local Repository = {}
local Numeric = require("game.workshop.Numeric")
Repository.__index = Repository

local function clone(levelDocument, value)
    return levelDocument.Clone(value)
end

local function entryId(sourceKind, levelId)
    return sourceKind .. ":" .. levelId
end

local function copyMetadata(entry)
    return {
        entryId = entry.entryId,
        levelId = entry.levelId,
        name = entry.name,
        sourceKind = entry.sourceKind,
        readOnly = entry.readOnly,
        updatedAt = entry.updatedAt,
        officialIndex = entry.officialIndex,
    }
end

local function validateDocument(levelDocument, document, normalizeTransform)
    local normalized = levelDocument.Normalize(document)
    if normalizeTransform then Numeric.NormalizeDocument(normalized) end
    local valid, errors = levelDocument.Validate(normalized)
    if not valid then return nil, table.concat(errors, "；") end
    return normalized, nil
end

---@param options table
---@return table
function Repository.New(options)
    assert(type(options) == "table" and options.LevelDocument, "LevelDocument is required")
    local self = setmetatable({}, Repository)
    self.LevelDocument = options.LevelDocument
    self.official = {}
    self.custom = {}
    self.officialOrder = {}
    self.customOrder = {}
    self.nextCustomIndex = 1
    return self
end

---@param count integer
---@param loader fun(index: integer): table
---@return string[] errors
function Repository:InitializeOfficial(count, loader)
    self.official, self.officialOrder = {}, {}
    local errors = {}
    for index = 1, count do
        local ok, documentOrError = pcall(loader, index)
        if ok and type(documentOrError) == "table" then
            local normalized, errorMessage = validateDocument(self.LevelDocument, documentOrError, false)
            if normalized then
                local id = entryId("official", normalized.levelId)
                local entry = {
                    entryId = id,
                    levelId = normalized.levelId,
                    name = normalized.name,
                    sourceKind = "official",
                    readOnly = true,
                    officialIndex = index,
                    document = clone(self.LevelDocument, normalized),
                }
                self.official[id] = entry
                self.officialOrder[#self.officialOrder + 1] = id
            else
                errors[#errors + 1] = string.format("level_%02d：%s", index, errorMessage)
            end
        else
            errors[#errors + 1] = string.format("level_%02d：%s", index, tostring(documentOrError))
        end
    end
    return errors
end

function Repository:List()
    local result = {}
    for _, id in ipairs(self.officialOrder) do result[#result + 1] = copyMetadata(self.official[id]) end
    for _, id in ipairs(self.customOrder) do result[#result + 1] = copyMetadata(self.custom[id]) end
    return result
end

function Repository:GetEntry(id)
    local entry = self.official[id] or self.custom[id]
    return entry and copyMetadata(entry) or nil
end

function Repository:Open(id)
    local entry = self.official[id] or self.custom[id]
    if not entry then return nil, "关卡不存在：" .. tostring(id) end
    return clone(self.LevelDocument, entry.document), copyMetadata(entry)
end

function Repository:FindByLevelId(levelId)
    return self.official[entryId("official", levelId)] or self.custom[entryId("custom", levelId)]
end

function Repository:NextCustomLevelId()
    while true do
        local levelId = string.format("custom_%03d", self.nextCustomIndex)
        self.nextCustomIndex = self.nextCustomIndex + 1
        if not self:FindByLevelId(levelId) then return levelId end
    end
end

local function trackCustomIndex(self, levelId)
    local suffix = levelId:match("^custom_(%d+)$")
    if suffix then self.nextCustomIndex = math.max(self.nextCustomIndex, tonumber(suffix) + 1) end
end

function Repository:RestoreCustom(document, updatedAt, options)
    local normalizeTransform = not options or options.normalizeTransform ~= false
    local normalized, errorMessage = validateDocument(self.LevelDocument, document, normalizeTransform)
    if not normalized then return nil, errorMessage end
    if self:FindByLevelId(normalized.levelId) then return nil, "levelId 已存在：" .. normalized.levelId end
    local id = entryId("custom", normalized.levelId)
    local entry = {
        entryId = id,
        levelId = normalized.levelId,
        name = normalized.name,
        sourceKind = "custom",
        readOnly = false,
        updatedAt = updatedAt,
        document = clone(self.LevelDocument, normalized),
    }
    self.custom[id] = entry
    self.customOrder[#self.customOrder + 1] = id
    trackCustomIndex(self, normalized.levelId)
    return copyMetadata(entry), nil
end

function Repository:CreateCustom(name)
    local levelId = self:NextCustomLevelId()
    local document = self.LevelDocument.New(levelId, name)
    local metadata, errorMessage = self:RestoreCustom(document)
    if not metadata then return nil, errorMessage end
    return self:Open(metadata.entryId)
end

function Repository:CopyAsCustom(sourceEntryId, name)
    local source, errorMessage = self:Open(sourceEntryId)
    if not source then return nil, errorMessage end
    source.levelId = self:NextCustomLevelId()
    source.name = name or ((source.name or "未命名实验") .. " 副本")
    local metadata, restoreError = self:RestoreCustom(source)
    if not metadata then return nil, restoreError end
    return self:Open(metadata.entryId)
end

function Repository:ImportAsCustom(document, name)
    local normalized, errorMessage = validateDocument(self.LevelDocument, document, true)
    if not normalized then return nil, errorMessage end
    normalized.levelId = self:NextCustomLevelId()
    if name and name ~= "" then normalized.name = name end
    local metadata, restoreError = self:RestoreCustom(normalized)
    if not metadata then return nil, restoreError end
    return self:Open(metadata.entryId)
end

function Repository:ReplaceCustom(id, document, updatedAt)
    local entry = self.custom[id]
    if not entry then
        if self.official[id] then return false, "官方关卡为只读" end
        return false, "自定义关卡不存在"
    end
    local normalized, errorMessage = validateDocument(self.LevelDocument, document, true)
    if not normalized then return false, errorMessage end
    if normalized.levelId ~= entry.levelId then return false, "不能修改自定义关卡的 levelId" end
    entry.document = clone(self.LevelDocument, normalized)
    entry.name = normalized.name
    entry.updatedAt = updatedAt
    return true, nil
end

function Repository:RenameCustom(id, name)
    local entry = self.custom[id]
    if not entry then return false, self.official[id] and "官方关卡为只读" or "自定义关卡不存在" end
    local document = clone(self.LevelDocument, entry.document)
    document.name = name
    return self:ReplaceCustom(id, document, entry.updatedAt)
end

function Repository:DeleteCustom(id)
    if self.official[id] then return false, "官方关卡为只读" end
    if not self.custom[id] then return false, "自定义关卡不存在" end
    self.custom[id] = nil
    for index, candidate in ipairs(self.customOrder) do
        if candidate == id then table.remove(self.customOrder, index); break end
    end
    return true, nil
end

function Repository:NextObjectId(document, objectType)
    local prefix = tostring(objectType or "object"):gsub("[^%w_-]", "_")
    local used = {}
    for _, object in ipairs(document.objects or {}) do used[object.id] = true end
    local index = 1
    while used[string.format("%s_%03d", prefix, index)] do index = index + 1 end
    return string.format("%s_%03d", prefix, index)
end

return Repository
