local DraftCloudSync = {}
DraftCloudSync.__index = DraftCloudSync

DraftCloudSync.KEY = "workshop_drafts_v1"
DraftCloudSync.MAX_DRAFTS = 100
DraftCloudSync.MAX_TEXT_BYTES = 1024 * 1024

local function safeId(value)
    return type(value) == "string" and value:match("^[%w_-]+$") ~= nil
end

local function clone(self, value)
    return self.levelDocument.Clone(value)
end

local DRAFT_ONLY_ERRORS = {
    LAUNCHER_COUNT = true,
    GOAL_COUNT = true,
}

local function draftValidationError(report)
    for _, issue in ipairs(report.errors or {}) do
        if not DRAFT_ONLY_ERRORS[issue.code] then return issue end
    end
    return nil
end

function DraftCloudSync.New(options)
    assert(type(options) == "table" and options.levelDocument, "levelDocument is required")
    local self = setmetatable({}, DraftCloudSync)
    self.levelDocument = options.levelDocument
    self.json = options.json
    self.cloud = options.cloud or _G.clientCloud
    self.clock = options.clock or function() return os.time() end
    self.pending = {}
    self.syncing = false
    self.status = "offline"
    self.lastError = nil
    return self
end

function DraftCloudSync:IsAvailable()
    return self.cloud and type(self.cloud.Get) == "function" and type(self.cloud.Set) == "function"
end

function DraftCloudSync:_normalizeEnvelope(envelope, useCurrentTime)
    if type(envelope) ~= "table" or type(envelope.document) ~= "table" then
        return nil, "云草稿格式无效"
    end
    local levelId = envelope.levelId or envelope.document.levelId
    if not safeId(levelId) or envelope.document.levelId ~= levelId then
        return nil, "云草稿 levelId 无效"
    end
    local document = self.levelDocument.Normalize(envelope.document)
    local report = self.levelDocument.ValidateDetailed(document)
    local blockingIssue = draftValidationError(report)
    if blockingIssue then return nil, "云草稿校验失败：" .. blockingIssue.message end
    return {
        kind = "editor-draft",
        schemaVersion = document.schemaVersion,
        levelId = levelId,
        updatedAt = tonumber(envelope.updatedAt) or (useCurrentTime and self.clock() or 0),
        source = envelope.source or "custom",
        document = clone(self, document),
        viewState = type(envelope.viewState) == "table" and clone(self, envelope.viewState) or {},
    }, nil
end

function DraftCloudSync:_requestGet(callback)
    if not self:IsAvailable() then callback(false, "云草稿服务不可用"); return end
    self.cloud:Get(DraftCloudSync.KEY, {
        ok = function(values)
            local payload = values and values[DraftCloudSync.KEY] or nil
            callback(true, type(payload) == "table" and payload or { version = 1, drafts = {} })
        end,
        error = function(code, reason)
            callback(false, string.format("读取云草稿失败（%s）：%s", tostring(code), tostring(reason)))
        end,
        timeout = function() callback(false, "读取云草稿超时") end,
    })
end

function DraftCloudSync:_requestSet(payload, callback)
    if not self:IsAvailable() then callback(false, "云草稿服务不可用"); return end
    if self.json and type(self.json.encode) == "function" then
        local ok, text = pcall(self.json.encode, payload)
        if not ok then callback(false, "云草稿序列化失败：" .. tostring(text)); return end
        if type(text) == "string" and #text > DraftCloudSync.MAX_TEXT_BYTES then
            callback(false, "云草稿超过 1 MiB 限制")
            return
        end
    end
    self.cloud:Set(DraftCloudSync.KEY, payload, {
        ok = function() callback(true, nil) end,
        error = function(code, reason)
            callback(false, string.format("写入云草稿失败（%s）：%s", tostring(code), tostring(reason)))
        end,
        timeout = function() callback(false, "写入云草稿超时") end,
    })
end

function DraftCloudSync:_validDrafts(payload)
    local result = {}
    for _, envelope in pairs(type(payload) == "table" and payload.drafts or {}) do
        local normalized = self:_normalizeEnvelope(envelope, false)
        if normalized then result[normalized.levelId] = normalized end
    end
    return result
end

local function finishBatch(self, batch, ok, errorMessage)
    self.syncing = false
    self.status, self.lastError = ok and "ready" or "failed", errorMessage
    for _, operation in pairs(batch) do
        if operation.callback then pcall(operation.callback, ok, errorMessage) end
    end
    if next(self.pending) then self:_flush() end
end

function DraftCloudSync:_flush()
    if self.syncing or not next(self.pending) then return true end
    if not self:IsAvailable() then
        self.status, self.lastError = "offline", "云草稿服务不可用"
        return false, self.lastError
    end
    local batch = self.pending
    self.pending = {}
    self.syncing, self.status, self.lastError = true, "syncing", nil
    self:_requestGet(function(readOk, payloadOrError)
        if not readOk then finishBatch(self, batch, false, payloadOrError); return end
        local drafts = self:_validDrafts(payloadOrError)
        for levelId, operation in pairs(batch) do
            if operation.kind == "delete" then
                drafts[levelId] = nil
            else
                local remote = drafts[levelId]
                if remote and remote.updatedAt > operation.envelope.updatedAt then
                    finishBatch(self, batch, false, "云端存在更新的草稿版本")
                    return
                end
                drafts[levelId] = clone(self, operation.envelope)
            end
        end
        local count = 0
        for _ in pairs(drafts) do count = count + 1 end
        if count > DraftCloudSync.MAX_DRAFTS then
            finishBatch(self, batch, false, "云草稿数量超过 " .. tostring(DraftCloudSync.MAX_DRAFTS) .. " 个限制")
            return
        end
        self:_requestSet({ version = 1, drafts = drafts }, function(saved, errorMessage)
            finishBatch(self, batch, saved, errorMessage)
        end)
    end)
    return true, nil
end

function DraftCloudSync:Refresh(callback)
    if self.syncing then if callback then callback(false, "云草稿同步正在进行") end; return false end
    if not self:IsAvailable() then
        self.status, self.lastError = "offline", "云草稿服务不可用"
        if callback then callback(false, self.lastError) end
        return false
    end
    self.syncing, self.status, self.lastError = true, "loading", nil
    self:_requestGet(function(ok, payloadOrError)
        self.syncing = false
        if ok then
            self.status = "ready"
            if callback then callback(true, self:_validDrafts(payloadOrError)) end
        else
            self.status, self.lastError = "offline", payloadOrError
            if callback then callback(false, payloadOrError) end
        end
        if next(self.pending) then self:_flush() end
    end)
    return true
end

function DraftCloudSync:QueueSave(envelope, callback)
    if not self:IsAvailable() then return false, "云草稿服务不可用" end
    local normalized, errorMessage = self:_normalizeEnvelope(envelope, true)
    if not normalized then return false, errorMessage end
    self.pending[normalized.levelId] = { kind = "save", envelope = normalized, callback = callback }
    self:_flush()
    return true, nil
end

function DraftCloudSync:QueueDelete(levelId, callback)
    if not self:IsAvailable() then return false, "云草稿服务不可用" end
    if not safeId(levelId) then return false, "云草稿 levelId 无效" end
    self.pending[levelId] = { kind = "delete", callback = callback }
    self:_flush()
    return true, nil
end

function DraftCloudSync:GetStatus()
    return self.status, self.lastError
end

return DraftCloudSync
