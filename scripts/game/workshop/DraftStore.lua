local DraftStore = {}
local Numeric = require("game.workshop.Numeric")
DraftStore.__index = DraftStore

local ROOT = "level-workshop"
local DRAFT_DIR = ROOT .. "/drafts"
local LEVEL_DIR = ROOT .. "/levels"
local SYNC_PATH = ROOT .. "/sync.json"

local function safeId(levelId)
    return type(levelId) == "string" and levelId:match("^[%w_-]+$") ~= nil
end

local function closeFile(file)
    if file.Close then file:Close() elseif file.Dispose then file:Dispose() end
end

function DraftStore.CreateLocalAdapter()
    if _G.GetPlatform and GetPlatform() == "Web" then return nil end
    if not (_G.File and _G.fileSystem and _G.FILE_READ and _G.FILE_WRITE) then return nil end
    local adapter = { kind = "local-slot-best-effort" }
    function adapter:createDir(path) return fileSystem:CreateDir(path) end
    function adapter:exists(path) return fileSystem:FileExists(path) end
    function adapter:delete(path) return fileSystem:Delete(path) end
    function adapter:rename(source, destination) return fileSystem:Rename(source, destination) end
    function adapter:list(path, filter) return fileSystem:ScanDir(path .. "/", filter, SCAN_FILES, false) end
    function adapter:write(path, text)
        local file = File(path, FILE_WRITE)
        if not file or not file:IsOpen() then return false end
        local ok, written = pcall(file.WriteString, file, text)
        closeFile(file)
        return ok and written == true
    end
    function adapter:read(path)
        if not fileSystem:FileExists(path) then return nil end
        local file = File(path, FILE_READ)
        if not file or not file:IsOpen() then return nil end
        local text = file:ReadString()
        closeFile(file)
        return text
    end
    return adapter
end

---@param options table
---@return table
function DraftStore.New(options)
    assert(type(options) == "table" and options.clone, "clone is required")
    local self = setmetatable({}, DraftStore)
    self.clone = options.clone
    self.json = options.json
    self.adapter = options.adapter
    self.clock = options.clock or function() return os.time() end
    self.memoryDrafts = {}
    self.memoryBackups = {}
    self.memoryLevels = {}
    self.memorySync = nil
    if self.adapter then
        pcall(function()
            self.adapter:createDir(ROOT)
            self.adapter:createDir(DRAFT_DIR)
            self.adapter:createDir(LEVEL_DIR)
        end)
    end
    return self
end

local function draftPath(levelId) return DRAFT_DIR .. "/" .. levelId .. ".json" end
local function levelPath(levelId) return LEVEL_DIR .. "/" .. levelId .. ".json" end

local function encode(self, value)
    if not self.json or type(self.json.encode) ~= "function" then return nil, "JSON 编码器不可用" end
    local ok, text = pcall(self.json.encode, value)
    if not ok or type(text) ~= "string" then return nil, tostring(text) end
    return text, nil
end

local function decode(self, text)
    if not self.json or type(self.json.decode) ~= "function" then return nil, "JSON 解码器不可用" end
    local ok, value = pcall(self.json.decode, text)
    if not ok or type(value) ~= "table" then return nil, tostring(value) end
    return value, nil
end

local function writeAtomic(self, path, value)
    if not self.adapter then return false, "本地持久化不可用" end
    local text, encodeError = encode(self, value)
    if not text then return false, encodeError end
    local temporary, backup = path .. ".tmp", path .. ".bak"
    local ok, errorMessage = pcall(function()
        assert(self.adapter:write(temporary, text), "临时槽位写入失败")
        if self.adapter:exists(path) then
            if self.adapter:exists(backup) then self.adapter:delete(backup) end
            assert(self.adapter:rename(path, backup), "旧槽位备份失败")
        end
        assert(self.adapter:rename(temporary, path), "临时槽位提交失败")
    end)
    if ok then return true, nil end
    pcall(function()
        if self.adapter:exists(temporary) then self.adapter:delete(temporary) end
        if not self.adapter:exists(path) and self.adapter:exists(backup) then
            self.adapter:rename(backup, path)
        end
    end)
    return false, tostring(errorMessage)
end

local function readEnvelope(self, path)
    if not self.adapter then return nil, "本地持久化不可用" end
    local ok, text = pcall(self.adapter.read, self.adapter, path)
    if not ok or not text then return nil, ok and "槽位不存在" or tostring(text) end
    return decode(self, text)
end

local function deleteSlotFiles(self, path)
    if not self.adapter then return true, nil end
    local errors = {}
    for _, suffix in ipairs({ "", ".bak", ".tmp" }) do
        local candidate = path .. suffix
        local existsOk, exists = pcall(self.adapter.exists, self.adapter, candidate)
        if not existsOk then
            errors[#errors + 1] = candidate .. " 状态检查失败：" .. tostring(exists)
        elseif exists then
            local deleteOk, deleted = pcall(self.adapter.delete, self.adapter, candidate)
            if not deleteOk or deleted ~= true then
                errors[#errors + 1] = candidate .. " 删除失败：" .. tostring(deleted)
            end
        end
    end
    if #errors > 0 then return false, table.concat(errors, "；") end
    return true, nil
end

function DraftStore:SaveDraft(levelId, document, viewState, source)
    if not safeId(levelId) then return false, "levelId 格式无效" end
    local previous = self.memoryDrafts[levelId]
    if previous then self.memoryBackups[levelId] = self.clone(previous) end
    local snapshot = Numeric.NormalizeDocument(self.clone(document))
    local envelope = {
        kind = "editor-draft",
        schemaVersion = document.schemaVersion,
        levelId = levelId,
        updatedAt = self.clock(),
        source = source or "custom",
        document = snapshot,
        viewState = self.clone(viewState or {}),
    }
    self.memoryDrafts[levelId] = self.clone(envelope)
    local persisted, persistenceError = writeAtomic(self, draftPath(levelId), envelope)
    return true, { memory = true, persisted = persisted, error = persistenceError, updatedAt = envelope.updatedAt }
end

function DraftStore:LoadDraft(levelId)
    if not safeId(levelId) then return nil, "levelId 格式无效" end
    if self.memoryDrafts[levelId] then return self.clone(self.memoryDrafts[levelId]), nil end
    local envelope, errorMessage = readEnvelope(self, draftPath(levelId))
    if not envelope or envelope.kind ~= "editor-draft" or type(envelope.document) ~= "table" then
        local backup, backupError = readEnvelope(self, draftPath(levelId) .. ".bak")
        if backup and backup.kind == "editor-draft" and type(backup.document) == "table" then
            envelope = backup
        else
            return nil, backupError or errorMessage or "草稿格式无效"
        end
    end
    self.memoryDrafts[levelId] = self.clone(envelope)
    return self.clone(envelope), nil
end

function DraftStore:RestoreDraft(envelope)
    local levelId = type(envelope) == "table" and envelope.levelId or nil
    if not safeId(levelId) or envelope.kind ~= "editor-draft" or type(envelope.document) ~= "table"
        or envelope.document.levelId ~= levelId then
        return false, "云草稿格式无效"
    end
    local existing = self:LoadDraft(levelId)
    if existing and (tonumber(existing.updatedAt) or 0) >= (tonumber(envelope.updatedAt) or 0) then
        return true, { restored = false, newerLocal = true, updatedAt = existing.updatedAt }
    end
    if existing then self.memoryBackups[levelId] = self.clone(existing) end
    local restored = {
        kind = "editor-draft",
        schemaVersion = envelope.document.schemaVersion,
        levelId = levelId,
        updatedAt = tonumber(envelope.updatedAt) or self.clock(),
        source = envelope.source or "custom",
        document = Numeric.NormalizeDocument(self.clone(envelope.document)),
        viewState = self.clone(type(envelope.viewState) == "table" and envelope.viewState or {}),
    }
    self.memoryDrafts[levelId] = self.clone(restored)
    local persisted, persistenceError = writeAtomic(self, draftPath(levelId), restored)
    return true, {
        restored = true, memory = true, persisted = persisted,
        error = persistenceError, updatedAt = restored.updatedAt,
    }
end

function DraftStore:DeleteDraft(levelId)
    if not safeId(levelId) then return false, "levelId 格式无效" end
    local deleted, errorMessage = deleteSlotFiles(self, draftPath(levelId))
    if not deleted then return false, errorMessage end
    self.memoryDrafts[levelId], self.memoryBackups[levelId] = nil, nil
    return true, nil
end

function DraftStore:ListDrafts()
    local byId = {}
    for levelId, envelope in pairs(self.memoryDrafts) do
        byId[levelId] = { levelId = levelId, updatedAt = envelope.updatedAt, source = envelope.source }
    end
    if self.adapter then
        local ok, names = pcall(self.adapter.list, self.adapter, DRAFT_DIR, "*.json")
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do
                local levelId = name:match("^([%w_-]+)%.json$")
                if levelId and not byId[levelId] then
                    local envelope = readEnvelope(self, draftPath(levelId))
                    if envelope then byId[levelId] = { levelId = levelId, updatedAt = envelope.updatedAt, source = envelope.source } end
                end
            end
        end
    end
    local result = {}
    for _, metadata in pairs(byId) do result[#result + 1] = metadata end
    table.sort(result, function(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end)
    return result
end

function DraftStore:LoadSyncState()
    if self.memorySync then return self.clone(self.memorySync), nil end
    local envelope, errorMessage = readEnvelope(self, SYNC_PATH)
    if envelope and type(envelope) == "table" then
        self.memorySync = self.clone(envelope)
        return self.clone(envelope), nil
    end
    if errorMessage == "本地持久化不可用" then return {}, errorMessage end
    self.memorySync = {}
    return {}, nil
end

function DraftStore:SaveSyncState(syncState)
    if type(syncState) ~= "table" then return false, "同步状态格式无效" end
    self.memorySync = self.clone(syncState)
    local persisted, persistenceError = writeAtomic(self, SYNC_PATH, syncState)
    return true, { memory = true, persisted = persisted, error = persistenceError }
end

function DraftStore:SaveCustom(document, syncMetadata)
    local levelId = document and document.levelId
    if not safeId(levelId) then return false, "levelId 格式无效" end
    local snapshot = Numeric.NormalizeDocument(self.clone(document))
    local envelope = {
        kind = "custom-level",
        schemaVersion = document.schemaVersion,
        levelId = levelId,
        updatedAt = self.clock(),
        document = snapshot,
    }
    if type(syncMetadata) == "table" then
        envelope.cloudEntityId = syncMetadata.cloudEntityId
        envelope.syncRevision = syncMetadata.syncRevision
        envelope.syncState = syncMetadata.syncState
    end
    self.memoryLevels[levelId] = self.clone(envelope)
    local persisted, persistenceError = writeAtomic(self, levelPath(levelId), envelope)
    return true, { memory = true, persisted = persisted, error = persistenceError, updatedAt = envelope.updatedAt }
end

function DraftStore:LoadCustomLevels()
    local byId = {}
    for levelId, envelope in pairs(self.memoryLevels) do byId[levelId] = self.clone(envelope) end
    if self.adapter then
        local ok, names = pcall(self.adapter.list, self.adapter, LEVEL_DIR, "*.json")
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do
                local levelId = name:match("^([%w_-]+)%.json$")
                if levelId and not byId[levelId] then
                    local envelope = readEnvelope(self, levelPath(levelId))
                    if not envelope or envelope.kind ~= "custom-level" or type(envelope.document) ~= "table" then
                        envelope = readEnvelope(self, levelPath(levelId) .. ".bak")
                    end
                    if envelope and envelope.kind == "custom-level" and type(envelope.document) == "table" then
                        byId[levelId] = envelope
                    end
                end
            end
        end
    end
    local result = {}
    for _, envelope in pairs(byId) do result[#result + 1] = self.clone(envelope) end
    table.sort(result, function(a, b) return a.levelId < b.levelId end)
    return result
end

function DraftStore:DeleteCustom(levelId)
    if not safeId(levelId) then return false, "levelId 格式无效" end
    local levelDeleted, levelError = deleteSlotFiles(self, levelPath(levelId))
    local draftDeleted, draftError = deleteSlotFiles(self, draftPath(levelId))
    if not levelDeleted or not draftDeleted then
        local errors = {}
        if levelError then errors[#errors + 1] = levelError end
        if draftError then errors[#errors + 1] = draftError end
        return false, table.concat(errors, "；")
    end
    self.memoryLevels[levelId] = nil
    self.memoryDrafts[levelId], self.memoryBackups[levelId] = nil, nil
    return true, nil
end

function DraftStore:PersistenceKind()
    return self.adapter and (self.adapter.kind or "local-slot") or "memory-only"
end

return DraftStore
