local Inspector = {}

local CARD_ORDER = {
    "feather-gravity", "side-gravity", "hooke-bounce",
    "up-impulse", "mirror-motion", "quantum-phase",
}

local function defaultScoring()
    return {
        profileId = "custom",
        metric = "ruleDeployCount",
        tiers = {
            { score = 100, maxInterventions = 1, title = "精准实验", description = "不超过 1 次有效干预" },
            { score = 80, maxInterventions = 3, title = "有效实验", description = "不超过 3 次有效干预" },
            { score = 60, title = "观测成立", description = "完成关卡目标" },
        },
    }
end

function Inspector.EnsureCustomFields(document)
    if type(document.author) ~= "string" then document.author = "" end
    if type(document.description) ~= "string" then document.description = "" end
    if type(document.metadata) ~= "table" then document.metadata = {} end
    if type(document.scoring) ~= "table" or type(document.scoring.tiers) ~= "table" then
        document.scoring = defaultScoring()
    end
end

local function addField(fields, key, label, kind, value, setter, options)
    options = options or {}
    fields[#fields + 1] = {
        key = key, label = label, kind = kind, value = value, set = setter,
        editable = options.editable, options = options.options, maxLength = options.maxLength,
    }
end

local function section(fields, key, label)
    fields[#fields + 1] = { key = "section_" .. key, label = label, kind = "section", editable = false }
end

local function cardEntry(document, cardId)
    for _, card in ipairs(document.cardDeck.cards) do
        if card.cardId == cardId then return card end
    end
    return nil
end

local function ensureCard(document, cardId)
    local card = cardEntry(document, cardId)
    if card then return card end
    card = { cardId = cardId, count = 1, order = #document.cardDeck.cards, enabled = false, usageMode = "SINGLE_USE" }
    document.cardDeck.cards[#document.cardDeck.cards + 1] = card
    return card
end

local function objectFields(fields, current, LevelDocument, typeLabels)
    local object = current.selectedObject
    local canEdit = not current.readOnly
    section(fields, "object", "对象")
    addField(fields, "object.id", "对象 ID", "readonly", object.id, nil, { editable = false })
    addField(fields, "object.type", "类型", "readonly", typeLabels[object.type] or object.type, nil,
        { editable = false })
    addField(fields, "object.name", "名称", "text", object.name,
        function(value) object.name = value end, { editable = canEdit, maxLength = LevelDocument.LIMITS.maxNameLength })
    section(fields, "transform", "变换")
    for _, definition in ipairs({
        { "x", "X" }, { "y", "Y" }, { "width", "宽度" }, { "height", "高度" }, { "rotation", "角度" },
    }) do
        local key, label = definition[1], definition[2]
        addField(fields, "transform." .. key, label, "number", object.transform[key],
            function(value) object.transform[key] = value end, { editable = canEdit })
    end
    section(fields, "properties", "机制参数")
    local props = object.properties
    local function property(key, label, kind, options)
        addField(fields, "properties." .. key, label, kind, props[key],
            function(value) props[key] = value end,
            { editable = canEdit, options = options, maxLength = LevelDocument.LIMITS.maxTextLength })
    end
    if object.type == "wall" then
        property("collisionEnabled", "启用碰撞", "boolean")
        property("isPhaseable", "可相位穿透", "boolean")
    elseif object.type == "launcher" then
        property("appleSpawnOffsetX", "出生偏移 X", "number")
        property("appleSpawnOffsetY", "出生偏移 Y", "number")
    elseif object.type == "goal_sensor" then
        addField(fields, "properties.requiredStayTime", "停留时间", "readonly", 1000, nil, { editable = false })
    elseif object.type == "spring" then
        property("direction", "方向", "enum", { "UP", "RIGHT", "DOWN", "LEFT" })
        property("impulseStrength", "冲量强度", "number")
        property("cooldown", "冷却 ms", "number")
        property("oneShot", "单次触发", "boolean")
        property("enabled", "初始启用", "boolean")
        property("enabledChannel", "启用通道", "text")
    elseif object.type == "button" then
        property("mode", "模式", "enum", { "HOLD", "TOGGLE" })
        property("gravityThreshold", "重力阈值", "number")
        property("channelId", "通道 ID", "text")
        property("initialState", "初始状态", "boolean")
        property("debounceTime", "防抖 ms", "number")
    elseif object.type == "door" then
        property("channelId", "通道 ID", "text")
        property("response", "响应", "enum", { "OPEN", "CLOSE", "TOGGLE" })
        property("initialState", "初始状态", "enum", { "CLOSED", "OPEN" })
        property("openDirection", "开启方向", "enum", { "UP", "RIGHT", "DOWN", "LEFT" })
        property("openDistance", "开启距离", "number")
        property("duration", "运动时长 ms", "number")
        property("closeDelay", "关闭延迟 ms", "number")
        property("antiCrush", "防夹", "boolean")
    end
end

local function levelFields(fields, current, LevelDocument, Rules)
    local document = current.document
    local canEdit = not current.readOnly
    section(fields, "level", "关卡")
    addField(fields, "level.id", "levelId", "readonly", document.levelId, nil, { editable = false })
    addField(fields, "level.name", "名称", "text", document.name,
        function(value) document.name = value end,
        { editable = canEdit, maxLength = LevelDocument.LIMITS.maxNameLength })
    addField(fields, "level.author", "作者", "text", document.author or "",
        function(value) document.author = value end,
        { editable = canEdit, maxLength = LevelDocument.LIMITS.maxAuthorLength })
    addField(fields, "level.description", "简介", "text", document.description or "",
        function(value) document.description = value end,
        { editable = canEdit, maxLength = LevelDocument.LIMITS.maxDescriptionLength })
    section(fields, "world", "场地与重力")
    addField(fields, "playfield.width", "场地宽度", "number", document.playfield.width,
        function(value) document.playfield.width = value end, { editable = canEdit })
    addField(fields, "playfield.height", "场地高度", "number", document.playfield.height,
        function(value) document.playfield.height = value end, { editable = canEdit })
    for _, definition in ipairs({ { "x", "重力 X" }, { "y", "重力 Y" }, { "strength", "重力强度" } }) do
        local key, label = definition[1], definition[2]
        addField(fields, "gravity." .. key, label, "number", document.rules.initialGravity[key],
            function(value) document.rules.initialGravity[key] = value end, { editable = canEdit })
    end
    section(fields, "cards", "规则卡配置")
    for _, cardId in ipairs(CARD_ORDER) do
        local definition = Rules.CARDS[cardId]
        local card = cardEntry(document, cardId)
        local label = definition and definition.short or cardId
        addField(fields, "card." .. cardId .. ".enabled", label .. " 启用", "boolean",
            card and card.enabled == true or false,
            function(value) ensureCard(document, cardId).enabled = value end, { editable = canEdit })
        addField(fields, "card." .. cardId .. ".count", label .. " 次数", "number", card and card.count or 0,
            function(value) ensureCard(document, cardId).count = value end, { editable = canEdit })
        addField(fields, "card." .. cardId .. ".usage", label .. " 用法", "enum",
            card and card.usageMode or "SINGLE_USE",
            function(value) ensureCard(document, cardId).usageMode = value end,
            { editable = canEdit, options = { "SINGLE_USE", "REUSABLE" } })
    end
    section(fields, "scoring", "评分条件")
    local scoring = document.scoring
    if type(scoring) ~= "table" or type(scoring.tiers) ~= "table" then
        addField(fields, "scoring.source", "评分来源", "readonly", "正式关卡配置", nil, { editable = false })
    else
        for index, tier in ipairs(scoring.tiers) do
            addField(fields, "score." .. index, "第 " .. index .. " 档分数", "number", tier.score,
                function(value) tier.score = value end, { editable = canEdit })
            addField(fields, "score.limit." .. index, "第 " .. index .. " 档干预上限", "number",
                tier.maxInterventions or -1,
                function(value) tier.maxInterventions = value < 0 and nil or value end, { editable = canEdit })
        end
    end
end

function Inspector.Build(current, LevelDocument, Rules, typeLabels)
    local fields = {}
    if not current.document then return fields end
    if current.selectedObject then
        objectFields(fields, current, LevelDocument, typeLabels)
    else
        levelFields(fields, current, LevelDocument, Rules)
    end
    return fields
end

return Inspector
