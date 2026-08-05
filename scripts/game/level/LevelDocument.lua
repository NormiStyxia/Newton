local PhysicsProfiles = require("game.physics.Profiles")
local Rules = require("game.gameplay.Rules")

local LevelDocument = {}

LevelDocument.SCHEMA_VERSION = 1
LevelDocument.PLAYFIELD_GROUND_Y = 580
LevelDocument.REQUIRED_GOAL_STAY_TIME_MS = 1000

LevelDocument.LIMITS = {
    maxObjects = 500,
    maxCards = 32,
    maxScoringTiers = 10,
    maxIdLength = 64,
    maxNameLength = 96,
    maxAuthorLength = 64,
    maxDescriptionLength = 2000,
    maxTextLength = 20000,
    maxTreeDepth = 16,
    maxTreeNodes = 20000,
    maxPlayfieldSize = 10000,
    maxObjectSize = 10000,
}

local BOUNDARY_EPSILON = 1e-6
local FORBIDDEN_REFERENCE_KEYS = {
    asset = true, assetpath = true, material = true, model = true,
    path = true, resource = true, resourcepath = true, script = true,
    texture = true, uri = true, url = true,
}

local function IsSupportedType(objectType)
    return objectType == "wall"
        or objectType == "launcher"
        or objectType == "goal_sensor"
        or objectType == "spring"
        or objectType == "button"
        or objectType == "door"
end

local DIRECTION_VALUES = { UP = true, DOWN = true, LEFT = true, RIGHT = true }
local USAGE_MODES = { REUSABLE = true, SINGLE_USE = true }
local BUTTON_MODES = { HOLD = true, TOGGLE = true }
local DOOR_RESPONSES = { OPEN = true, CLOSE = true, TOGGLE = true }
local DOOR_STATES = { OPEN = true, CLOSED = true }

local DEFAULT_NAMES = {
    wall = "墙体",
    launcher = "苹果发射器",
    goal_sensor = "观察皿",
    spring = "弹簧",
    button = "按钮",
    door = "机关门",
}

local DEFAULT_TRANSFORMS = {
    wall = { width = 190, height = 20 },
    launcher = { width = 110, height = 96 },
    goal_sensor = { width = 180, height = 160 },
    spring = { width = 110, height = 34 },
    button = { width = 100, height = 28 },
    door = { width = 70, height = 210 },
}

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function IsInteger(value)
    return IsFiniteNumber(value) and value == math.floor(value)
end

local function DeepClone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[DeepClone(key, seen)] = DeepClone(child, seen)
    end
    return copy
end

local function SetDefault(target, key, value)
    if target[key] == nil then target[key] = DeepClone(value) end
end

local function NormalizeProperties(object, migrations)
    object.properties = type(object.properties) == "table" and object.properties or {}
    local props = object.properties

    local function discard(key)
        if props[key] == nil then return end
        props[key] = nil
        migrations[#migrations + 1] = tostring(object.id or object.type or "object") .. ".properties." .. key
    end

    if object.type == "wall" then
        discard("friction")
        discard("restitution")
        SetDefault(props, "collisionEnabled", true)
        SetDefault(props, "isPhaseable", false)
    elseif object.type == "launcher" then
        discard("launchAngle")
        discard("launchPower")
        SetDefault(props, "appleSpawnOffsetX", 0)
        SetDefault(props, "appleSpawnOffsetY", 0)
    elseif object.type == "goal_sensor" then
        discard("targetTag")
        if props.requiredStayTime ~= LevelDocument.REQUIRED_GOAL_STAY_TIME_MS then
            migrations[#migrations + 1] = tostring(object.id or "goal_sensor") .. ".properties.requiredStayTime"
        end
        props.requiredStayTime = LevelDocument.REQUIRED_GOAL_STAY_TIME_MS
    elseif object.type == "spring" then
        SetDefault(props, "direction", "UP")
        SetDefault(props, "impulseStrength", 10)
        SetDefault(props, "cooldown", 500)
        SetDefault(props, "oneShot", false)
        SetDefault(props, "enabled", true)
        SetDefault(props, "enabledChannel", "")
    elseif object.type == "button" then
        discard("activationType")
        SetDefault(props, "mode", "HOLD")
        SetDefault(props, "gravityThreshold", 1)
        SetDefault(props, "channelId", "route_A")
        SetDefault(props, "initialState", false)
        SetDefault(props, "debounceTime", 180)
    elseif object.type == "door" then
        SetDefault(props, "channelId", "route_A")
        SetDefault(props, "response", "OPEN")
        SetDefault(props, "initialState", "CLOSED")
        SetDefault(props, "openDirection", "UP")
        SetDefault(props, "openDistance", 190)
        SetDefault(props, "duration", 420)
        SetDefault(props, "closeDelay", 180)
        SetDefault(props, "antiCrush", true)
    end
end

---@param source table
---@return table document
---@return string[] migrations
function LevelDocument.Normalize(source)
    local document = DeepClone(source)
    local migrations = {}
    document._editor = nil
    if type(document.objects) == "table" then
        for _, object in ipairs(document.objects) do
            if type(object) == "table" then NormalizeProperties(object, migrations) end
        end
    end
    if type(document.cardDeck) == "table" and type(document.cardDeck.cards) == "table" then
        for _, card in ipairs(document.cardDeck.cards) do
            if type(card) == "table" then SetDefault(card, "usageMode", "SINGLE_USE") end
        end
    end
    return document, migrations
end

---@param value any
---@return table
function LevelDocument.Clone(value)
    return DeepClone(value)
end

local function AddIssue(report, severity, code, path, message)
    local issue = { severity = severity, code = code, path = path, message = message }
    report[severity == "error" and "errors" or "warnings"][#report[severity == "error" and "errors" or "warnings"] + 1] = issue
end

local function Error(report, code, path, message)
    AddIssue(report, "error", code, path, message)
end

local function Warning(report, code, path, message)
    AddIssue(report, "warning", code, path, message)
end

local function ValidateString(report, value, path, label, maxLength, allowEmpty)
    if type(value) ~= "string" then
        Error(report, "TYPE_STRING", path, label .. "必须是字符串")
        return false
    end
    if not allowEmpty and value == "" then
        Error(report, "STRING_EMPTY", path, label .. "不能为空")
        return false
    end
    if #value > maxLength then
        Error(report, "STRING_TOO_LONG", path, label .. "长度不能超过 " .. tostring(maxLength))
        return false
    end
    return true
end

local function ValidateBoolean(report, value, path, label)
    if type(value) ~= "boolean" then Error(report, "TYPE_BOOLEAN", path, label .. "必须是布尔值") end
end

local function ValidateNumberRange(report, value, path, label, minimum, maximum, integer)
    if not IsFiniteNumber(value) then
        Error(report, "TYPE_NUMBER", path, label .. "必须是有限数值")
        return false
    end
    if integer and not IsInteger(value) then
        Error(report, "TYPE_INTEGER", path, label .. "必须是整数")
        return false
    end
    if value < minimum or value > maximum then
        Error(report, "NUMBER_RANGE", path,
            string.format("%s必须位于 %s 到 %s 之间", label, tostring(minimum), tostring(maximum)))
        return false
    end
    return true
end

local function ValidateEnum(report, value, values, path, label)
    if type(value) ~= "string" or not values[value] then
        Error(report, "ENUM", path, label .. "取值无效：" .. tostring(value))
        return false
    end
    return true
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

local function ValidateSafeTree(report, root)
    local nodeCount = 0
    local active = {}
    local function visit(value, path, depth)
        nodeCount = nodeCount + 1
        if nodeCount > LevelDocument.LIMITS.maxTreeNodes then
            Error(report, "TREE_SIZE", path, "JSON 节点数量超过安全限制")
            return false
        end
        if depth > LevelDocument.LIMITS.maxTreeDepth then
            Error(report, "TREE_DEPTH", path, "JSON 嵌套层级超过安全限制")
            return false
        end
        local valueType = type(value)
        if valueType == "string" then
            if #value > LevelDocument.LIMITS.maxTextLength then
                Error(report, "TEXT_SIZE", path, "文本长度超过安全限制")
            end
        elseif valueType == "number" then
            if not IsFiniteNumber(value) then Error(report, "NON_FINITE", path, "数值必须是有限值") end
        elseif valueType == "table" then
            if active[value] then
                Error(report, "CYCLE", path, "关卡数据不能包含循环引用")
                return false
            end
            active[value] = true
            for key, child in pairs(value) do
                local keyType = type(key)
                if keyType ~= "string" and keyType ~= "number" then
                    Error(report, "KEY_TYPE", path, "JSON 键只能是字符串或数字")
                else
                    if keyType == "string" and FORBIDDEN_REFERENCE_KEYS[key:lower()] then
                        Error(report, "RESOURCE_REFERENCE", path .. "." .. key,
                            "关卡 JSON 不允许引用任意项目资源或脚本")
                    end
                    visit(child, path .. "." .. tostring(key), depth + 1)
                end
            end
            active[value] = nil
        elseif valueType ~= "boolean" and valueType ~= "nil" then
            Error(report, "VALUE_TYPE", path, "关卡数据包含 JSON 不支持的值类型")
        end
        return true
    end
    visit(root, "$", 0)
end

local function ValidateTransform(report, object, index, playfield)
    local prefix = "objects[" .. tostring(index) .. "].transform"
    local transform = object.transform
    if type(transform) ~= "table" then
        Error(report, "TRANSFORM", prefix, "transform 必须是对象")
        return
    end
    local validX = ValidateNumberRange(report, transform.x, prefix .. ".x", "x", -LevelDocument.LIMITS.maxPlayfieldSize, LevelDocument.LIMITS.maxPlayfieldSize, false)
    local validY = ValidateNumberRange(report, transform.y, prefix .. ".y", "y", -LevelDocument.LIMITS.maxPlayfieldSize, LevelDocument.LIMITS.maxPlayfieldSize, false)
    local validWidth = ValidateNumberRange(report, transform.width, prefix .. ".width", "width", 0.1, LevelDocument.LIMITS.maxObjectSize, false)
    local validHeight = ValidateNumberRange(report, transform.height, prefix .. ".height", "height", 0.1, LevelDocument.LIMITS.maxObjectSize, false)
    local validRotation = ValidateNumberRange(report, transform.rotation, prefix .. ".rotation", "rotation", -360000, 360000, false)
    if not (validX and validY and validWidth and validHeight and validRotation) or type(playfield) ~= "table" then return end
    if not IsFiniteNumber(playfield.width) or not IsFiniteNumber(playfield.height) then return end

    local extents = RotatedHalfExtents(transform)
    if transform.x - extents.x < -BOUNDARY_EPSILON
        or transform.x + extents.x > playfield.width + BOUNDARY_EPSILON
        or transform.y - extents.y < -BOUNDARY_EPSILON
        or transform.y + extents.y > LevelDocument.PLAYFIELD_GROUND_Y + BOUNDARY_EPSILON then
        Error(report, "OUT_OF_BOUNDS", prefix, tostring(object.id or index) .. " 超出可运行关卡边界")
    end
end

local function ValidateChannel(report, value, path, allowEmpty)
    if not ValidateString(report, value, path, "channelId", LevelDocument.LIMITS.maxIdLength, allowEmpty) then return end
    if value ~= "" and not value:match("^[%w_-]+$") then
        Error(report, "CHANNEL_FORMAT", path, "channelId 只能包含字母、数字、下划线和连字符")
    end
end

local function ValidateProperties(report, object, index, playfield)
    local prefix = "objects[" .. tostring(index) .. "].properties"
    local props = object.properties
    if type(props) ~= "table" then
        Error(report, "PROPERTIES", prefix, "properties 必须是对象")
        return
    end
    if object.type == "wall" then
        ValidateBoolean(report, props.collisionEnabled, prefix .. ".collisionEnabled", "collisionEnabled")
        ValidateBoolean(report, props.isPhaseable, prefix .. ".isPhaseable", "isPhaseable")
    elseif object.type == "launcher" then
        local maxSize = LevelDocument.LIMITS.maxPlayfieldSize
        ValidateNumberRange(report, props.appleSpawnOffsetX, prefix .. ".appleSpawnOffsetX", "appleSpawnOffsetX", -maxSize, maxSize, false)
        ValidateNumberRange(report, props.appleSpawnOffsetY, prefix .. ".appleSpawnOffsetY", "appleSpawnOffsetY", -maxSize, maxSize, false)
        local transform = object.transform
        if type(transform) == "table" and IsFiniteNumber(transform.x) and IsFiniteNumber(transform.y)
            and IsFiniteNumber(props.appleSpawnOffsetX) and IsFiniteNumber(props.appleSpawnOffsetY)
            and type(playfield) == "table" and IsFiniteNumber(playfield.width) then
            local spawnX = transform.x + props.appleSpawnOffsetX
            local spawnY = transform.y + props.appleSpawnOffsetY
            if spawnX < 0 or spawnX > playfield.width or spawnY < 0 or spawnY > LevelDocument.PLAYFIELD_GROUND_Y then
                Error(report, "SPAWN_BOUNDS", prefix, "苹果出生点超出可运行关卡边界")
            end
        end
    elseif object.type == "goal_sensor" then
        if props.requiredStayTime ~= LevelDocument.REQUIRED_GOAL_STAY_TIME_MS then
            Error(report, "GOAL_STAY_TIME", prefix .. ".requiredStayTime", "requiredStayTime 必须为 1000ms")
        end
    elseif object.type == "spring" then
        ValidateEnum(report, props.direction, DIRECTION_VALUES, prefix .. ".direction", "direction")
        ValidateNumberRange(report, props.impulseStrength, prefix .. ".impulseStrength", "impulseStrength", 0.01, 100, false)
        ValidateNumberRange(report, props.cooldown, prefix .. ".cooldown", "cooldown", 0, 60000, false)
        ValidateBoolean(report, props.oneShot, prefix .. ".oneShot", "oneShot")
        ValidateBoolean(report, props.enabled, prefix .. ".enabled", "enabled")
        ValidateChannel(report, props.enabledChannel, prefix .. ".enabledChannel", true)
    elseif object.type == "button" then
        ValidateEnum(report, props.mode, BUTTON_MODES, prefix .. ".mode", "mode")
        ValidateNumberRange(report, props.gravityThreshold, prefix .. ".gravityThreshold", "gravityThreshold", 0, 100, false)
        ValidateChannel(report, props.channelId, prefix .. ".channelId", false)
        ValidateBoolean(report, props.initialState, prefix .. ".initialState", "initialState")
        ValidateNumberRange(report, props.debounceTime, prefix .. ".debounceTime", "debounceTime", 0, 60000, false)
    elseif object.type == "door" then
        ValidateChannel(report, props.channelId, prefix .. ".channelId", false)
        ValidateEnum(report, props.response, DOOR_RESPONSES, prefix .. ".response", "response")
        ValidateEnum(report, props.initialState, DOOR_STATES, prefix .. ".initialState", "initialState")
        ValidateEnum(report, props.openDirection, DIRECTION_VALUES, prefix .. ".openDirection", "openDirection")
        ValidateNumberRange(report, props.openDistance, prefix .. ".openDistance", "openDistance", 0, LevelDocument.LIMITS.maxObjectSize, false)
        ValidateNumberRange(report, props.duration, prefix .. ".duration", "duration", 1, 60000, false)
        ValidateNumberRange(report, props.closeDelay, prefix .. ".closeDelay", "closeDelay", 0, 60000, false)
        ValidateBoolean(report, props.antiCrush, prefix .. ".antiCrush", "antiCrush")
    end
end

local function ValidateCards(report, cardDeck)
    if type(cardDeck) ~= "table" or type(cardDeck.cards) ~= "table" then
        Error(report, "CARD_DECK", "cardDeck.cards", "cardDeck.cards 必须是数组")
        return
    end
    if #cardDeck.cards > LevelDocument.LIMITS.maxCards then
        Error(report, "CARD_LIMIT", "cardDeck.cards", "卡牌数量超过安全限制")
    end
    local ids = {}
    for index, card in ipairs(cardDeck.cards) do
        local prefix = "cardDeck.cards[" .. tostring(index) .. "]"
        if type(card) ~= "table" then
            Error(report, "CARD", prefix, "卡牌条目必须是对象")
        else
            if type(card.cardId) ~= "string" or not Rules.CARDS[card.cardId] then
                Error(report, "CARD_ID", prefix .. ".cardId", "未知卡牌：" .. tostring(card.cardId))
            elseif ids[card.cardId] then
                Error(report, "CARD_DUPLICATE", prefix .. ".cardId", "卡牌重复：" .. card.cardId)
            else
                ids[card.cardId] = true
            end
            ValidateNumberRange(report, card.count, prefix .. ".count", "count", 0, 99, true)
            ValidateNumberRange(report, card.order, prefix .. ".order", "order", 0, 1000, true)
            ValidateBoolean(report, card.enabled, prefix .. ".enabled", "enabled")
            ValidateEnum(report, card.usageMode, USAGE_MODES, prefix .. ".usageMode", "usageMode")
            if card.enabled == true and card.count == 0 then
                Warning(report, "CARD_ZERO_COUNT", prefix .. ".count", "已启用卡牌的 count 为 0")
            end
        end
    end
end

local function ValidateRules(report, rules)
    if type(rules) ~= "table" or type(rules.initialGravity) ~= "table" then
        Error(report, "GRAVITY", "rules.initialGravity", "初始重力参数缺失")
        return
    end
    local gravity = rules.initialGravity
    local validX = ValidateNumberRange(report, gravity.x, "rules.initialGravity.x", "x", -1, 1, false)
    local validY = ValidateNumberRange(report, gravity.y, "rules.initialGravity.y", "y", -1, 1, false)
    ValidateNumberRange(report, gravity.strength, "rules.initialGravity.strength", "strength", 0, 10, false)
    if validX and validY and math.abs(gravity.x) < 1e-9 and math.abs(gravity.y) < 1e-9 then
        Error(report, "GRAVITY_DIRECTION", "rules.initialGravity", "初始重力方向不能为零向量")
    end
end

local function ValidateScoring(report, scoring)
    if scoring == nil then return end
    if type(scoring) ~= "table" then
        Error(report, "SCORING", "scoring", "scoring 必须是对象")
        return
    end
    if scoring.profileId ~= nil then
        ValidateString(report, scoring.profileId, "scoring.profileId", "profileId",
            LevelDocument.LIMITS.maxIdLength, true)
    end
    if scoring.metric ~= "ruleDeployCount" then
        Error(report, "SCORING_METRIC", "scoring.metric", "当前仅支持 ruleDeployCount 评分指标")
    end
    if type(scoring.tiers) ~= "table" then
        Error(report, "SCORING_TIERS", "scoring.tiers", "scoring.tiers 必须是数组")
        return
    end
    if #scoring.tiers == 0 or #scoring.tiers > LevelDocument.LIMITS.maxScoringTiers then
        Error(report, "SCORING_TIER_LIMIT", "scoring.tiers",
            "评分档位数量必须位于 1 到 " .. tostring(LevelDocument.LIMITS.maxScoringTiers) .. " 之间")
    end
    local previousLimit = -1
    for index, tier in ipairs(scoring.tiers) do
        local prefix = "scoring.tiers[" .. tostring(index) .. "]"
        if type(tier) ~= "table" then
            Error(report, "SCORING_TIER", prefix, "评分档位必须是对象")
        else
            ValidateNumberRange(report, tier.score, prefix .. ".score", "score", 0, 100, true)
            if tier.maxInterventions ~= nil then
                if ValidateNumberRange(report, tier.maxInterventions, prefix .. ".maxInterventions",
                    "maxInterventions", 0, 999, true) and tier.maxInterventions <= previousLimit then
                    Error(report, "SCORING_ORDER", prefix .. ".maxInterventions", "干预上限必须严格递增")
                end
                previousLimit = tier.maxInterventions
            elseif index ~= #scoring.tiers then
                Error(report, "SCORING_FALLBACK", prefix .. ".maxInterventions", "无上限评分档位只能位于最后")
            end
            if tier.title ~= nil then
                ValidateString(report, tier.title, prefix .. ".title", "title",
                    LevelDocument.LIMITS.maxNameLength, true)
            end
            if tier.description ~= nil then
                ValidateString(report, tier.description, prefix .. ".description", "description",
                    LevelDocument.LIMITS.maxDescriptionLength, true)
            end
        end
    end
end

---@param level table
---@return table report
function LevelDocument.ValidateDetailed(level)
    local report = { valid = false, errors = {}, warnings = {} }
    if type(level) ~= "table" then
        Error(report, "ROOT", "$", "关卡根节点必须是对象")
        return report
    end
    ValidateSafeTree(report, level)
    if level.schemaVersion ~= LevelDocument.SCHEMA_VERSION then
        Error(report, "SCHEMA_VERSION", "schemaVersion", "仅支持 schemaVersion " .. tostring(LevelDocument.SCHEMA_VERSION))
    end
    if ValidateString(report, level.levelId, "levelId", "levelId", LevelDocument.LIMITS.maxIdLength, false)
        and not level.levelId:match("^[%w_-]+$") then
        Error(report, "LEVEL_ID_FORMAT", "levelId", "levelId 只能包含字母、数字、下划线和连字符")
    end
    ValidateString(report, level.name, "name", "关卡名称", LevelDocument.LIMITS.maxNameLength, false)
    if level.author ~= nil then ValidateString(report, level.author, "author", "作者", LevelDocument.LIMITS.maxAuthorLength, true) end
    if level.description ~= nil then ValidateString(report, level.description, "description", "简介", LevelDocument.LIMITS.maxDescriptionLength, true) end
    if level.metadata ~= nil and type(level.metadata) ~= "table" then Error(report, "METADATA", "metadata", "metadata 必须是对象") end
    if level.physicsProfile ~= nil and not PhysicsProfiles.IsKnown(level.physicsProfile) then
        Error(report, "PHYSICS_PROFILE", "physicsProfile", "physicsProfile 无效：" .. tostring(level.physicsProfile))
    end

    local playfield = level.playfield
    if type(playfield) ~= "table" then
        Error(report, "PLAYFIELD", "playfield", "playfield 必须是对象")
    else
        ValidateNumberRange(report, playfield.width, "playfield.width", "playfield.width", 1, LevelDocument.LIMITS.maxPlayfieldSize, false)
        ValidateNumberRange(report, playfield.height, "playfield.height", "playfield.height", LevelDocument.PLAYFIELD_GROUND_Y, LevelDocument.LIMITS.maxPlayfieldSize, false)
    end

    if type(level.objects) ~= "table" then
        Error(report, "OBJECTS", "objects", "objects 必须是数组")
    else
        if #level.objects > LevelDocument.LIMITS.maxObjects then
            Error(report, "OBJECT_LIMIT", "objects", "对象数量超过安全限制")
        end
        local ids = {}
        local launcherCount, goalCount = 0, 0
        for index, object in ipairs(level.objects) do
            local prefix = "objects[" .. tostring(index) .. "]"
            if type(object) ~= "table" then
                Error(report, "OBJECT", prefix, "对象条目必须是对象")
            else
                if ValidateString(report, object.id, prefix .. ".id", "对象 ID", LevelDocument.LIMITS.maxIdLength, false) then
                    if not object.id:match("^[%w_-]+$") then
                        Error(report, "OBJECT_ID_FORMAT", prefix .. ".id", "对象 ID 格式无效")
                    elseif ids[object.id] then
                        Error(report, "OBJECT_ID_DUPLICATE", prefix .. ".id", "ID 重复：" .. object.id)
                    else
                        ids[object.id] = true
                    end
                end
                ValidateString(report, object.name, prefix .. ".name", "对象名称", LevelDocument.LIMITS.maxNameLength, false)
                if not IsSupportedType(object.type) then
                    Error(report, "OBJECT_TYPE", prefix .. ".type", "对象类型无效：" .. tostring(object.type))
                else
                    if object.type == "launcher" then launcherCount = launcherCount + 1 end
                    if object.type == "goal_sensor" then goalCount = goalCount + 1 end
                end
                ValidateTransform(report, object, index, playfield)
                ValidateProperties(report, object, index, playfield)
            end
        end
        if launcherCount ~= 1 then Error(report, "LAUNCHER_COUNT", "objects", "关卡必须且只能包含一个发射器") end
        if goalCount ~= 1 then Error(report, "GOAL_COUNT", "objects", "关卡必须且只能包含一个目标 Sensor") end
    end

    ValidateCards(report, level.cardDeck)
    ValidateRules(report, level.rules)
    ValidateScoring(report, level.scoring)
    report.valid = #report.errors == 0
    return report
end

---@param level table
---@return boolean valid
---@return string[] errors
---@return string[] warnings
function LevelDocument.Validate(level)
    local report = LevelDocument.ValidateDetailed(level)
    local errors, warnings = {}, {}
    for _, issue in ipairs(report.errors) do errors[#errors + 1] = issue.path .. "：" .. issue.message end
    for _, issue in ipairs(report.warnings) do warnings[#warnings + 1] = issue.path .. "：" .. issue.message end
    return report.valid, errors, warnings
end

---@param objectType string
---@param id string
---@param x number
---@param y number
---@return table
function LevelDocument.NewObject(objectType, id, x, y)
    assert(IsSupportedType(objectType), "unsupported object type: " .. tostring(objectType))
    local size = DEFAULT_TRANSFORMS[objectType]
    ---@cast size table
    local object = {
        id = id,
        type = objectType,
        name = DEFAULT_NAMES[objectType],
        transform = { x = x, y = y, width = size.width, height = size.height, rotation = 0 },
        properties = {},
    }
    local normalized = LevelDocument.Normalize({ objects = { object } })
    return normalized.objects[1]
end

---@param levelId string
---@param name string|nil
---@return table
function LevelDocument.New(levelId, name)
    local document = {
        schemaVersion = LevelDocument.SCHEMA_VERSION,
        levelId = levelId,
        name = name or "未命名实验",
        author = "",
        description = "",
        playfield = { width = 1400, height = 700 },
        objects = {},
        cardDeck = { cards = {} },
        rules = { initialGravity = { x = 0, y = 1, strength = 1 } },
        metadata = {},
    }
    document.objects[1] = LevelDocument.NewObject("launcher", "launcher_main", 140, 467)
    document.objects[2] = LevelDocument.NewObject("goal_sensor", "goal_main", 1100, 490)
    return document
end

function LevelDocument.IsSupportedType(objectType)
    return IsSupportedType(objectType)
end

function LevelDocument.SupportedTypes()
    return { "wall", "launcher", "goal_sensor", "spring", "button", "door" }
end

return LevelDocument
