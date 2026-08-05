local LevelDocument = require("game.level.LevelDocument")

local LevelData = {}

LevelData.SCHEMA_VERSION = LevelDocument.SCHEMA_VERSION
LevelData.PLAYFIELD_GROUND_Y = LevelDocument.PLAYFIELD_GROUND_Y

---@param level table
---@return boolean valid
---@return string[] errors
---@return string[] warnings
function LevelData.Validate(level)
    return LevelDocument.Validate(level)
end

LevelData.ValidateDetailed = LevelDocument.ValidateDetailed
LevelData.Normalize = LevelDocument.Normalize
LevelData.Clone = LevelDocument.Clone

---@param resourcePath string
---@return table|nil level
---@return string|nil errorMessage
function LevelData.Load(resourcePath)
    if not cache:Exists(resourcePath) then
        return nil, "关卡资源不存在：" .. resourcePath
    end

    local file = cache:GetFile(resourcePath)
    if not file or not file:IsOpen() then
        return nil, "无法打开关卡资源：" .. resourcePath
    end
    local content = file:ReadString()
    file:Dispose()

    local ok, decoded = pcall(cjson.decode, content)
    if not ok or type(decoded) ~= "table" then
        return nil, "关卡 JSON 解析失败：" .. tostring(decoded)
    end

    local normalized = LevelDocument.Normalize(decoded)
    local valid, errors = LevelData.Validate(normalized)
    if not valid then
        return nil, table.concat(errors, "；")
    end
    return normalized, nil
end

---@param content string
---@return table|nil level
---@return string|nil errorMessage
function LevelData.Decode(content)
    if type(content) ~= "string" or content == "" then return nil, "关卡 JSON 文本为空" end
    local ok, decoded = pcall(cjson.decode, content)
    if not ok or type(decoded) ~= "table" then return nil, "关卡 JSON 解析失败：" .. tostring(decoded) end
    local normalized = LevelDocument.Normalize(decoded)
    local valid, errors = LevelDocument.Validate(normalized)
    if not valid then return nil, table.concat(errors, "；") end
    return normalized, nil
end

---@param level table
---@param objectType string
---@return table|nil
function LevelData.FindFirst(level, objectType)
    for _, object in ipairs(level.objects) do
        if object.type == objectType then return object end
    end
    return nil
end

return LevelData
