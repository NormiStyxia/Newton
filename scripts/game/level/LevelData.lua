local PhysicsProfiles = require("game.physics.Profiles")

local LevelData = {}

LevelData.SCHEMA_VERSION = 1
LevelData.PLAYFIELD_GROUND_Y = 580

---@type table<string, boolean>
local SUPPORTED_TYPES = {
    wall = true,
    launcher = true,
    goal_sensor = true,
    spring = true,
    button = true,
    door = true,
}

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function AddError(errors, message)
    errors[#errors + 1] = message
end

local function RotatedHalfExtents(transform)
    local radians = math.rad(transform.rotation)
    local cosValue = math.abs(math.cos(radians))
    local sinValue = math.abs(math.sin(radians))
    return {
        x = cosValue * transform.width * 0.5 + sinValue * transform.height * 0.5,
        y = sinValue * transform.width * 0.5 + cosValue * transform.height * 0.5,
    }
end

---@param level table
---@return boolean valid
---@return string[] errors
function LevelData.Validate(level)
    local errors = {}
    if type(level) ~= "table" then
        return false, { "关卡根节点必须是对象" }
    end

    if level.schemaVersion ~= LevelData.SCHEMA_VERSION then
        AddError(errors, "仅支持 schemaVersion " .. tostring(LevelData.SCHEMA_VERSION))
    end
    if type(level.levelId) ~= "string" or not level.levelId:match("^[%w_-]+$") then
        AddError(errors, "levelId 格式无效")
    end
    if level.physicsProfile ~= nil and not PhysicsProfiles.IsKnown(level.physicsProfile) then
        AddError(errors, "physicsProfile 无效：" .. tostring(level.physicsProfile))
    end
    if type(level.playfield) ~= "table"
        or not IsFiniteNumber(level.playfield.width)
        or not IsFiniteNumber(level.playfield.height)
        or level.playfield.width <= 0
        or level.playfield.height <= 0 then
        AddError(errors, "playfield.width/height 必须是正数")
    end
    if type(level.objects) ~= "table" then
        AddError(errors, "objects 必须是数组")
        return false, errors
    end
    if type(level.cardDeck) ~= "table" or type(level.cardDeck.cards) ~= "table" then
        AddError(errors, "cardDeck.cards 必须是数组")
    end

    local ids = {}
    local launcherCount = 0
    local goalCount = 0
    for index, object in ipairs(level.objects) do
        local prefix = "objects[" .. tostring(index) .. "]"
        if type(object) ~= "table" then
            AddError(errors, prefix .. " 必须是对象")
        else
            if type(object.id) ~= "string" or object.id == "" then
                AddError(errors, prefix .. ".id 不能为空")
            elseif ids[object.id] then
                AddError(errors, "ID 重复：" .. object.id)
            else
                ids[object.id] = true
            end

            if not SUPPORTED_TYPES[object.type] then
                AddError(errors, prefix .. ".type 无效：" .. tostring(object.type))
            elseif object.type == "launcher" then
                launcherCount = launcherCount + 1
            elseif object.type == "goal_sensor" then
                goalCount = goalCount + 1
            end

            local transform = object.transform
            if type(transform) ~= "table" then
                AddError(errors, prefix .. ".transform 必须是对象")
            else
                local numeric = {
                    { "x", transform.x },
                    { "y", transform.y },
                    { "width", transform.width },
                    { "height", transform.height },
                    { "rotation", transform.rotation },
                }
                for _, entry in ipairs(numeric) do
                    if not IsFiniteNumber(entry[2]) then
                        AddError(errors, prefix .. ".transform." .. entry[1] .. " 必须是有限数值")
                        break
                    end
                end
                if IsFiniteNumber(transform.width) and IsFiniteNumber(transform.height) then
                    if transform.width <= 0 or transform.height <= 0 then
                        AddError(errors, prefix .. " 尺寸必须大于 0")
                    elseif type(level.playfield) == "table"
                        and IsFiniteNumber(level.playfield.width)
                        and IsFiniteNumber(level.playfield.height)
                        and IsFiniteNumber(transform.x)
                        and IsFiniteNumber(transform.y)
                        and IsFiniteNumber(transform.rotation) then
                        local extents = RotatedHalfExtents(transform)
                        if transform.x - extents.x < 0
                            or transform.x + extents.x > level.playfield.width
                            or transform.y - extents.y < 0
                            or transform.y + extents.y > LevelData.PLAYFIELD_GROUND_Y then
                            AddError(errors, tostring(object.id) .. " 超出关卡边界")
                        end
                    end
                end
            end
            if type(object.properties) ~= "table" then
                AddError(errors, prefix .. ".properties 必须是对象")
            end
        end
    end

    if launcherCount == 0 then AddError(errors, "关卡缺少发射器") end
    if goalCount == 0 then AddError(errors, "关卡缺少目标 Sensor") end
    if type(level.rules) ~= "table" or type(level.rules.initialGravity) ~= "table" then
        AddError(errors, "初始重力参数缺失")
    else
        local gravity = level.rules.initialGravity
        if not IsFiniteNumber(gravity.x)
            or not IsFiniteNumber(gravity.y)
            or not IsFiniteNumber(gravity.strength) then
            AddError(errors, "初始重力参数无效")
        end
    end

    return #errors == 0, errors
end

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

    local valid, errors = LevelData.Validate(decoded)
    if not valid then
        return nil, table.concat(errors, "；")
    end
    return decoded, nil
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
