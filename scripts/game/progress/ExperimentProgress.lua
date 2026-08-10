local ExperimentProgress = {}
ExperimentProgress.__index = ExperimentProgress

local ROOT = "experiment-progress"
local PROGRESS_PATH = ROOT .. "/official-experiments.json"
local CLOUD_KEY = "official_experiment_progress_v1"
local CLOUD_MAX_TEXT_BYTES = 1024 * 1024
local SCHEMA_VERSION = 2
local VALID_SCORES = { [60] = true, [80] = true, [100] = true }
local SNAPSHOT_SCHEMA_VERSION = 1
local MAX_RULES = 12

local function closeFile(file)
    if file.Close then file:Close() elseif file.Dispose then file:Dispose() end
end

local function createLocalAdapter()
    if _G.GetPlatform and GetPlatform() == "Web" then return nil end
    if not (_G.File and _G.fileSystem and _G.FILE_READ and _G.FILE_WRITE) then return nil end
    local adapter = { kind = "local-slot-best-effort" }
    function adapter:createDir(path) return fileSystem:CreateDir(path) end
    function adapter:exists(path) return fileSystem:FileExists(path) end
    function adapter:delete(path) return fileSystem:Delete(path) end
    function adapter:rename(source, destination) return fileSystem:Rename(source, destination) end
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

local function validLevelId(levelId)
    return type(levelId) == "string" and levelId:match("^[%w_-]+$") ~= nil
end

local function validScore(value)
    value = tonumber(value)
    return value and VALID_SCORES[value] and value or nil
end

local function cleanText(value, fallback)
    if type(value) ~= "string" or value == "" then return fallback end
    return value
end

local function cloneStringList(values)
    local result = {}
    if type(values) ~= "table" then return result end
    for _, value in ipairs(values) do
        if type(value) == "string" and value ~= "" then
            result[#result + 1] = value
            if #result >= MAX_RULES then break end
        end
    end
    return result
end

local function cloneSnapshot(snapshot)
    if type(snapshot) ~= "table" or not validLevelId(snapshot.levelId) then return nil end
    local score = validScore(snapshot.score)
    if not score then return nil end
    local clearedAt = math.max(0, math.floor(tonumber(snapshot.clearedAt) or 0))
    return {
        schemaVersion = SNAPSHOT_SCHEMA_VERSION,
        levelId = snapshot.levelId,
        experimentNumber = math.max(1, math.floor(tonumber(snapshot.experimentNumber) or 1)),
        experimentName = cleanText(snapshot.experimentName, "未命名实验"),
        title = cleanText(snapshot.title, "观测成立"),
        clearedAt = clearedAt,
        score = score,
        maxScore = math.max(score, math.floor(tonumber(snapshot.maxScore) or 100)),
        ratingLabel = cleanText(snapshot.ratingLabel, "观测成立"),
        interventionCount = math.max(0, math.floor(tonumber(snapshot.interventionCount) or 0)),
        summaryText = cleanText(snapshot.summaryText, "实验结果已归档"),
        resultDescription = cleanText(snapshot.resultDescription, "实验结果已归档"),
        selectedSelfReview = cleanText(snapshot.selectedSelfReview, nil),
        newtonReview = cleanText(snapshot.newtonReview, "暂无评语。"),
        einsteinReview = cleanText(snapshot.einsteinReview, "暂无评语。"),
        greenReview = cleanText(snapshot.greenReview, "暂无评语。"),
        anger = math.max(0, math.min(100, math.floor(tonumber(snapshot.anger) or 0))),
        newtonDangerAccent = snapshot.newtonDangerAccent == true,
        usedRules = cloneStringList(snapshot.usedRules),
    }
end

local function cloneRecord(record)
    if type(record) ~= "table" then
        return { completed = false, bestScore = nil, lastReportSnapshot = nil }
    end
    local bestScore = validScore(record.bestScore)
    return {
        completed = record.completed == true or bestScore ~= nil,
        bestScore = bestScore,
        lastReportSnapshot = cloneSnapshot(record.lastReportSnapshot),
    }
end

local function shouldReplaceSnapshot(current, candidate)
    if not candidate then return false end
    if not current then return true end
    if candidate.score ~= current.score then return candidate.score > current.score end
    return candidate.clearedAt > current.clearedAt
end

local function mergeRecord(localRecord, remoteRecord)
    local merged = cloneRecord(localRecord)
    local remote = cloneRecord(remoteRecord)
    local changed = false

    if remote.completed and not merged.completed then
        merged.completed = true
        changed = true
    end
    if remote.bestScore and (not merged.bestScore or remote.bestScore > merged.bestScore) then
        merged.bestScore = remote.bestScore
        merged.completed = true
        changed = true
    end
    if shouldReplaceSnapshot(merged.lastReportSnapshot, remote.lastReportSnapshot) then
        merged.lastReportSnapshot = remote.lastReportSnapshot
        merged.completed = true
        if not merged.bestScore or remote.lastReportSnapshot.score > merged.bestScore then
            merged.bestScore = remote.lastReportSnapshot.score
        end
        changed = true
    end
    return merged, changed
end

local function encode(self, value)
    if not self.json or type(self.json.encode) ~= "function" then return nil, "JSON encoder unavailable" end
    local ok, text = pcall(self.json.encode, value)
    if not ok or type(text) ~= "string" then return nil, tostring(text) end
    return text, nil
end

local function decode(self, text)
    if not self.json or type(self.json.decode) ~= "function" then return nil, "JSON decoder unavailable" end
    local ok, value = pcall(self.json.decode, text)
    if not ok or type(value) ~= "table" then return nil, tostring(value) end
    return value, nil
end

local function readEnvelope(self, path)
    if not self.adapter then return nil, "local persistence unavailable" end
    local ok, text = pcall(self.adapter.read, self.adapter, path)
    if not ok or not text then return nil, ok and "slot missing" or tostring(text) end
    return decode(self, text)
end

local function localEnvelope(self)
    local experiments = {}
    for levelId, record in pairs(self.records) do
        if validLevelId(levelId) then experiments[levelId] = cloneRecord(record) end
    end
    return {
        kind = "experiment-progress",
        schemaVersion = SCHEMA_VERSION,
        experiments = experiments,
    }
end

local function writeAtomic(self)
    if not self.adapter then return false, "local persistence unavailable" end
    local text, encodeError = encode(self, localEnvelope(self))
    if not text then return false, encodeError end

    local temporary, backup = PROGRESS_PATH .. ".tmp", PROGRESS_PATH .. ".bak"
    local ok, errorMessage = pcall(function()
        assert(self.adapter:write(temporary, text), "temporary write failed")
        if self.adapter:exists(PROGRESS_PATH) then
            if self.adapter:exists(backup) then self.adapter:delete(backup) end
            assert(self.adapter:rename(PROGRESS_PATH, backup), "backup rotation failed")
        end
        assert(self.adapter:rename(temporary, PROGRESS_PATH), "commit rename failed")
    end)
    if ok then return true, nil end
    pcall(function()
        if self.adapter:exists(temporary) then self.adapter:delete(temporary) end
        if not self.adapter:exists(PROGRESS_PATH) and self.adapter:exists(backup) then
            self.adapter:rename(backup, PROGRESS_PATH)
        end
    end)
    return false, tostring(errorMessage)
end

function ExperimentProgress.New(options)
    local self = setmetatable({}, ExperimentProgress)
    self.json = options and options.json
    self.adapter = options and options.adapter or createLocalAdapter()
    self.cloud = options and options.cloud or _G.clientCloud
    self.records = {}
    self.pendingFeedback = nil
    self.cloudSyncing = false
    self.cloudUploadPending = false
    self.cloudStatus = "offline"
    self.cloudLastError = nil
    if self.adapter then pcall(self.adapter.createDir, self.adapter, ROOT) end
    self:Load()
    return self
end

function ExperimentProgress:Load()
    local envelope = readEnvelope(self, PROGRESS_PATH)
    if (not envelope or envelope.kind ~= "experiment-progress") then
        envelope = readEnvelope(self, PROGRESS_PATH .. ".bak")
    end
    if type(envelope) ~= "table" or type(envelope.experiments) ~= "table" then return false end
    for levelId, record in pairs(envelope.experiments) do
        if validLevelId(levelId) then self.records[levelId] = cloneRecord(record) end
    end
    return true
end

function ExperimentProgress:IsCloudAvailable()
    return self.cloud and type(self.cloud.Get) == "function" and type(self.cloud.Set) == "function"
end

function ExperimentProgress:_requestCloudGet(callback)
    if not self:IsCloudAvailable() then callback(false, "官方实验云存档服务不可用"); return end
    self.cloud:Get(CLOUD_KEY, {
        ok = function(values)
            local payload = values and values[CLOUD_KEY] or nil
            if type(payload) ~= "table" then payload = { schemaVersion = SCHEMA_VERSION, experiments = {} } end
            callback(true, payload)
        end,
        error = function(code, reason)
            callback(false, string.format("读取官方实验云存档失败（%s）：%s", tostring(code), tostring(reason)))
        end,
        timeout = function() callback(false, "读取官方实验云存档超时") end,
    })
end

function ExperimentProgress:_requestCloudSet(payload, callback)
    if not self:IsCloudAvailable() then callback(false, "官方实验云存档服务不可用"); return end
    local text, encodeError = encode(self, payload)
    if not text then callback(false, "官方实验云存档序列化失败：" .. tostring(encodeError)); return end
    if #text > CLOUD_MAX_TEXT_BYTES then
        callback(false, "官方实验云存档超过 1 MiB 限制")
        return
    end
    self.cloud:Set(CLOUD_KEY, payload, {
        ok = function() callback(true, nil) end,
        error = function(code, reason)
            callback(false, string.format("写入官方实验云存档失败（%s）：%s", tostring(code), tostring(reason)))
        end,
        timeout = function() callback(false, "写入官方实验云存档超时") end,
    })
end

function ExperimentProgress:_mergeCloudEnvelope(payload)
    local remoteRecords = type(payload) == "table" and payload.experiments or nil
    if type(remoteRecords) ~= "table" then return false end
    local changed = false
    for levelId, remoteRecord in pairs(remoteRecords) do
        if validLevelId(levelId) and type(remoteRecord) == "table" then
            local merged, recordChanged = mergeRecord(self.records[levelId], remoteRecord)
            if recordChanged then
                self.records[levelId] = merged
                changed = true
            end
        end
    end
    return changed
end

function ExperimentProgress:_finishCloudSync(ok, errorMessage, callback)
    self.cloudSyncing = false
    self.cloudStatus = ok and "ready" or "failed"
    self.cloudLastError = errorMessage
    if ok then
        print("[ExperimentProgressCloud] 官方实验进度、分数和报告已同步")
    else
        self.cloudUploadPending = true
        print("[ExperimentProgressCloud] 同步失败：" .. tostring(errorMessage))
    end
    if callback then callback(ok, errorMessage) end
    if ok and self.cloudUploadPending then self:_flushCloudUpload() end
end

function ExperimentProgress:_syncCloud(callback)
    self.cloudSyncing = true
    self.cloudStatus = "syncing"
    self.cloudLastError = nil
    self.cloudUploadPending = false
    self:_requestCloudGet(function(readOk, payloadOrError)
        if not readOk then
            self:_finishCloudSync(false, payloadOrError, callback)
            return
        end
        local changed = self:_mergeCloudEnvelope(payloadOrError)
        if changed then
            local persisted, persistenceError = writeAtomic(self)
            if not persisted and self.adapter then
                print("[ExperimentProgressCloud] 合并后的本地缓存保存失败：" .. tostring(persistenceError))
            end
        end
        self:_requestCloudSet(localEnvelope(self), function(saved, saveError)
            self:_finishCloudSync(saved, saveError, callback)
        end)
    end)
end

function ExperimentProgress:_flushCloudUpload()
    if self.cloudSyncing or not self.cloudUploadPending then return end
    if not self:IsCloudAvailable() then
        self.cloudStatus = "offline"
        self.cloudLastError = "官方实验云存档服务不可用"
        return
    end
    self:_syncCloud(nil)
end

function ExperimentProgress:RefreshCloud(callback)
    if self.cloudSyncing then
        if callback then callback(false, "官方实验云同步正在进行") end
        return false
    end
    if not self:IsCloudAvailable() then
        self.cloudStatus = "offline"
        self.cloudLastError = "官方实验云存档服务不可用"
        if callback then callback(false, self.cloudLastError) end
        return false
    end
    self.cloudUploadPending = true
    self.cloudStatus = "loading"
    print("[ExperimentProgressCloud] 开始合并官方实验云存档")
    self:_syncCloud(callback)
    return true
end

function ExperimentProgress:QueueCloudUpload()
    self.cloudUploadPending = true
    self:_flushCloudUpload()
    return self:IsCloudAvailable()
end

function ExperimentProgress:GetCloudStatus()
    return self.cloudStatus, self.cloudLastError
end

function ExperimentProgress:Get(levelId)
    return cloneRecord(self.records[levelId])
end

function ExperimentProgress:GetReportSnapshot(levelId)
    if not validLevelId(levelId) then return nil end
    return cloneSnapshot(self.records[levelId] and self.records[levelId].lastReportSnapshot)
end

function ExperimentProgress:HasReportSnapshot(levelId)
    return validLevelId(levelId)
        and self.records[levelId] ~= nil
        and self.records[levelId].lastReportSnapshot ~= nil
end

function ExperimentProgress:Record(levelId, score, reportSnapshot)
    if not validLevelId(levelId) then return nil, "invalid level id" end
    local previous = cloneRecord(self.records[levelId])
    local newScore = validScore(score)
    local snapshot = reportSnapshot ~= nil and cloneSnapshot(reportSnapshot) or nil
    local snapshotError = reportSnapshot ~= nil and not snapshot and "invalid report snapshot" or nil
    local nextRecord = cloneRecord(previous)
    nextRecord.completed = true
    if newScore and (not nextRecord.bestScore or newScore > nextRecord.bestScore) then
        nextRecord.bestScore = newScore
    end
    local previousSnapshot = previous.lastReportSnapshot
    -- Keep the highest-scoring report; a same-score clear replaces it with the latest details.
    local snapshotUpdated = snapshot ~= nil
        and (not previousSnapshot or snapshot.score >= previousSnapshot.score)
    if snapshotUpdated then nextRecord.lastReportSnapshot = snapshot end

    local firstCompletion = previous.completed ~= true
    local bestImproved = nextRecord.bestScore ~= previous.bestScore
    self.records[levelId] = nextRecord

    local persisted, persistenceError = true, nil
    if firstCompletion or bestImproved or snapshotUpdated then
        persisted, persistenceError = writeAtomic(self)
    end
    if firstCompletion or bestImproved then
        self.pendingFeedback = {
            levelId = levelId,
            firstCompletion = firstCompletion,
            bestImproved = bestImproved,
            previousScore = previous.bestScore,
            bestScore = nextRecord.bestScore,
        }
    end
    if firstCompletion or bestImproved or snapshotUpdated then self:QueueCloudUpload() end
    return {
        completed = true,
        firstCompletion = firstCompletion,
        bestImproved = bestImproved,
        bestScore = nextRecord.bestScore,
        snapshotUpdated = snapshotUpdated,
        snapshotError = snapshotError,
        persisted = persisted,
        persistenceError = persistenceError,
    }, nil
end

function ExperimentProgress:UpdateReportSnapshot(levelId, reportSnapshot)
    if not validLevelId(levelId) then return false, "invalid level id" end
    local snapshot = cloneSnapshot(reportSnapshot)
    if not snapshot or snapshot.levelId ~= levelId then return false, "invalid report snapshot" end
    local record = cloneRecord(self.records[levelId])
    if not record.completed then return false, "experiment is not completed" end
    local previousSnapshot = record.lastReportSnapshot
    if previousSnapshot and snapshot.score < previousSnapshot.score then return true, nil end
    record.lastReportSnapshot = snapshot
    self.records[levelId] = record
    local persisted, persistenceError = writeAtomic(self)
    self:QueueCloudUpload()
    return persisted, persistenceError
end

function ExperimentProgress:ConsumeFeedback()
    local feedback = self.pendingFeedback
    self.pendingFeedback = nil
    return feedback
end

function ExperimentProgress:ClearPendingFeedback()
    self.pendingFeedback = nil
end

function ExperimentProgress:PersistenceKind()
    return self.adapter and (self.adapter.kind or "local-slot") or "memory-only"
end

return ExperimentProgress
