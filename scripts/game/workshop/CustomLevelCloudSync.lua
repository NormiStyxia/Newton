local CustomLevelCloudSync = {}
CustomLevelCloudSync.__index = CustomLevelCloudSync

local KEY = "workshop_custom_levels_v1"
local MAX_LEVELS = 100
local MAX_TEXT_BYTES = 1024 * 1024

local function clone(self, value)
    return self.levelDocument.Clone(value)
end

local function makeEntityId(document, clock)
    local seed = tostring(clock()) .. "_" .. tostring(document.levelId or "level")
    local hash = 2166136261
    for index = 1, #seed do
        hash = (hash ~ string.byte(seed, index)) * 16777619 % 4294967296
    end
    return string.format("local_%08x_%08x", hash, #seed)
end

local function isValidEntityId(value)
    return type(value) == "string" and value:match("^[%w_-]+$") ~= nil
end

local function isValidRecord(record)
    return type(record) == "table"
        and isValidEntityId(record.entityId)
        and (record.deleted == true or type(record.document) == "table")
end

function CustomLevelCloudSync.New(options)
    assert(type(options) == "table", "options is required")
    assert(options.draftStore and options.levelDocument, "draftStore and levelDocument are required")
    local self = setmetatable({}, CustomLevelCloudSync)
    self.draftStore = options.draftStore
    self.levelDocument = options.levelDocument
    self.json = options.json
    self.cloud = options.cloud or _G.clientCloud
    self.clock = options.clock or function() return os.time() end
    self.onRemoteRecord = options.onRemoteRecord
    self.state = options.state or { version = 1, records = {}, status = "offline", lastError = nil }
    self.state.records = self.state.records or {}
    self.syncing = false
    return self
end

function CustomLevelCloudSync:_saveState()
    local ok, result = self.draftStore:SaveSyncState(self.state)
    if not ok then print("[WorkshopCloud] 本地同步状态保存失败：" .. tostring(result)) end
end

function CustomLevelCloudSync:_notifyChanged()
    self:_saveState()
end

function CustomLevelCloudSync:_ensureLocalRecord(document, envelope)
    local entityId = envelope and envelope.cloudEntityId
    if not isValidEntityId(entityId) then
        for candidateId, candidate in pairs(self.state.records) do
            if candidate.localLevelId == document.levelId and not candidate.deleted then
                entityId = candidateId
                break
            end
        end
    end
    if not isValidEntityId(entityId) then entityId = makeEntityId(document, self.clock) end
    local record = self.state.records[entityId]
    if not record then
        record = {
            entityId = entityId,
            localLevelId = document.levelId,
            localRevision = tonumber(envelope and envelope.localRevision) or 1,
            remoteRevision = tonumber(envelope and envelope.syncRevision) or 0,
            syncState = envelope and envelope.syncState or "pendingUpload",
            deleted = false,
        }
        self.state.records[entityId] = record
    else
        record.localLevelId = document.levelId
        record.deleted = false
    end
    record.document = clone(self, document)
    return record
end

function CustomLevelCloudSync:RegisterLocal(document, envelope)
    if type(document) ~= "table" then return nil, "自制实验数据为空" end
    local record = self:_ensureLocalRecord(document, envelope)
    self:_notifyChanged()
    return record
end

function CustomLevelCloudSync:PrepareLocal(document, envelope)
    if type(document) ~= "table" then return nil, "自制实验数据为空" end
    local report = self.levelDocument.ValidateDetailed(document)
    if not report.valid then return nil, "自制实验校验失败：" .. report.errors[1].message end
    local record = self:_ensureLocalRecord(document, envelope)
    record.localRevision = (record.localRevision or 0) + 1
    record.updatedAt = self.clock()
    record.document = clone(self, document)
    self:_notifyChanged()
    return record
end

function CustomLevelCloudSync:_requestGet(callback)
    if not self.cloud or type(self.cloud.Get) ~= "function" then
        callback(false, "云存档服务不可用")
        return
    end
    self.cloud:Get(KEY, {
        ok = function(values)
            local payload = values and values[KEY] or nil
            if type(payload) ~= "table" then payload = { version = 1, records = {} } end
            callback(true, payload)
        end,
        error = function(code, reason)
            callback(false, string.format("读取云存档失败（%s）：%s", tostring(code), tostring(reason)))
        end,
        timeout = function() callback(false, "读取云存档超时") end,
    })
end

function CustomLevelCloudSync:_requestSet(payload, callback)
    if not self.cloud or type(self.cloud.Set) ~= "function" then
        callback(false, "云存档服务不可用")
        return
    end
    if self.json and type(self.json.encode) == "function" then
        local ok, encoded = pcall(self.json.encode, payload)
        if ok and type(encoded) == "string" and #encoded > MAX_TEXT_BYTES then
            callback(false, "云存档超过 1 MiB 限制")
            return
        end
    end
    self.cloud:Set(KEY, payload, {
        ok = function() callback(true) end,
        error = function(code, reason)
            callback(false, string.format("写入云存档失败（%s）：%s", tostring(code), tostring(reason)))
        end,
        timeout = function() callback(false, "写入云存档超时") end,
    })
end

function CustomLevelCloudSync:_recordsForUpload()
    local result = {}
    local count = 0
    for _, record in pairs(self.state.records) do
        if count >= MAX_LEVELS then break end
        if isValidRecord(record) then
            result[#result + 1] = {
                entityId = record.entityId,
                localLevelId = record.localLevelId,
                localRevision = record.syncState == "conflict"
                    and record.remoteRevision or record.localRevision,
                remoteRevision = record.remoteRevision,
                updatedAt = record.updatedAt,
                deleted = record.deleted == true,
                document = record.deleted and nil or clone(self,
                    record.syncState == "conflict" and record.remoteDocument or record.document),
            }
            count = count + 1
        end
    end
    return result
end

function CustomLevelCloudSync:_mergeRemote(payload)
    local remoteRecords = type(payload.records) == "table" and payload.records or {}
    local changed = false
    for _, remote in pairs(remoteRecords) do
        if isValidRecord(remote) then
            local localRecord = self.state.records[remote.entityId]
            local remoteRevision = tonumber(remote.localRevision or remote.remoteRevision) or 0
            if not localRecord then
                localRecord = clone(self, remote)
                localRecord.remoteRevision = remoteRevision
                localRecord.localRevision = remoteRevision
                localRecord.syncState = remote.deleted and "deleted" or "remoteNewer"
                self.state.records[remote.entityId] = localRecord
                if not remote.deleted and self.onRemoteRecord then
                    pcall(self.onRemoteRecord, localRecord, "new")
                end
                changed = true
            elseif localRecord.syncState == "pendingUpload" or localRecord.syncState == "failed" then
                if remoteRevision > (tonumber(localRecord.remoteRevision) or 0) then
                    localRecord.remoteDocument = clone(self, remote.document)
                    localRecord.remoteRevision = remoteRevision
                    localRecord.syncState = "conflict"
                    if self.onRemoteRecord then pcall(self.onRemoteRecord, localRecord, "conflict") end
                    changed = true
                end
            elseif remoteRevision > (tonumber(localRecord.remoteRevision) or 0) then
                localRecord.document = clone(self, remote.document)
                localRecord.localLevelId = remote.localLevelId or localRecord.localLevelId
                localRecord.remoteRevision = remoteRevision
                localRecord.localRevision = remoteRevision
                localRecord.deleted = remote.deleted == true
                localRecord.syncState = remote.deleted and "deleted" or "remoteNewer"
                if self.onRemoteRecord then
                    pcall(self.onRemoteRecord, localRecord, remote.deleted and "delete" or "update")
                end
                changed = true
            end
        end
    end
    if changed then self:_notifyChanged() end
end

function CustomLevelCloudSync:Refresh(callback)
    if self.syncing then if callback then callback(false, "同步正在进行") end; return end
    self.syncing = true
    self.state.status, self.state.lastError = "loadingRemote", nil
    self:_requestGet(function(ok, payloadOrError)
        if not ok then
            self.syncing = false
            self.state.status, self.state.lastError = "offline", payloadOrError
            self:_notifyChanged()
            if callback then callback(false, payloadOrError) end
            return
        end
        self:_mergeRemote(payloadOrError)
        self.state.status = "ready"
        self.syncing = false
        self:_notifyChanged()
        if callback then callback(true, nil) end
    end)
end

function CustomLevelCloudSync:QueueSave(document)
    if self.syncing then return false, "同步正在进行" end
    local record, errorMessage = self:PrepareLocal(document)
    if not record then return false, errorMessage end
    self.state.status = "syncing"
    record.syncState = "pendingUpload"
    self.syncing = true
    self:_notifyChanged()
    self:_requestGet(function(ok, payloadOrError)
        if not ok then
            record.syncState = "failed"
            self.state.status, self.state.lastError = "offline", payloadOrError
            self.syncing = false
            self:_notifyChanged()
            return
        end
        self:_mergeRemote(payloadOrError)
        if record.syncState == "conflict" then
            self.state.status, self.state.lastError = "conflict", "云端已有更新版本，已保留本地版本"
            self.syncing = false
            self:_notifyChanged()
            return
        end
        self:_requestSet({ version = 1, records = self:_recordsForUpload() }, function(saved, reason)
            if saved then
                record.remoteRevision = record.localRevision
                record.syncState = "synced"
                self.state.status, self.state.lastError = "ready", nil
            else
                record.syncState = "failed"
                self.state.status, self.state.lastError = "failed", reason
            end
            self.syncing = false
            self:_notifyChanged()
        end)
    end)
    return true
end

function CustomLevelCloudSync:QueueDelete(entityId)
    if self.syncing then return false, "同步正在进行" end
    local record = self.state.records[entityId]
    if not record then return false, "云实验不存在" end
    record.deleted = true
    record.localRevision = (record.localRevision or 0) + 1
    record.syncState = "pendingDelete"
    self.syncing = true
    self.state.status, self.state.lastError = "syncing", nil
    self:_notifyChanged()
    self:_requestGet(function(readOk, payloadOrError)
        if not readOk then
            record.syncState = "failed"
            self.state.status, self.state.lastError = "offline", payloadOrError
            self.syncing = false
            self:_notifyChanged()
            return
        end
        self:_mergeRemote(payloadOrError)
        record.deleted = true
        record.syncState = "pendingDelete"
        self:_requestSet({ version = 1, records = self:_recordsForUpload() }, function(ok, reason)
            if ok then
                record.remoteRevision = record.localRevision
                record.syncState = "deleted"
                self.state.status, self.state.lastError = "ready", nil
            else
                record.syncState = "failed"
                self.state.status, self.state.lastError = "failed", reason
            end
            self.syncing = false
            self:_notifyChanged()
        end)
    end)
    return true
end

function CustomLevelCloudSync:FindEntityId(levelId)
    for entityId, record in pairs(self.state.records) do
        if record.localLevelId == levelId and not record.deleted then return entityId end
    end
    return nil
end

function CustomLevelCloudSync:GetState(entityId)
    local record = entityId and self.state.records[entityId]
    return record and clone(self, record) or nil
end

function CustomLevelCloudSync:GetStatus()
    return self.state.status, self.state.lastError
end

return CustomLevelCloudSync
