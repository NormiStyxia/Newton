local GreenAssistConfig = {}

local function Clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Clone(child) end
    return result
end

local function IsArray(value)
    return type(value) == "table" and #value > 0
end

local function Merge(target, source)
    if type(source) ~= "table" then return target end
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" and not IsArray(value) then
            Merge(target[key], value)
        else
            target[key] = Clone(value)
        end
    end
    return target
end

local function Frames(folder, count)
    local frames = {}
    for index = 1, count do
        frames[index] = string.format("image/green_assistant/%s/frame_%02d.png", folder, index)
    end
    return frames
end

GreenAssistConfig.DEFAULTS = {
    fallbackAnimation = "idle",
    failureThreshold = 3,
    features = {
        roam = true,
        interaction = true,
        dialogue = true,
        failureAssist = true,
        takeover = true,
    },
    animations = {
        idle = {
            frames = Frames("idle", 16),
            fps = 8,
            loop = true,
            playbackSpeed = 1,
            anchor = { x = 0.5, y = 1 },
            frameOffset = { x = 0, y = 0 },
            scale = 1,
        },
        move = {
            frames = Frames("move", 16),
            fps = 10,
            loop = true,
            playbackSpeed = 1,
            anchor = { x = 0.5, y = 1 },
            frameOffset = { x = 0, y = 0 },
            scale = 1,
        },
        blink = {
            frames = Frames("blink", 16),
            fps = 12,
            loop = false,
            playbackSpeed = 1,
            anchor = { x = 0.5, y = 1 },
            frameOffset = { x = 0, y = 0 },
            scale = 1,
        },
    },
    behaviorAnimationMap = {
        IDLE = "idle",
        ROAM = "move",
        INTERACT = "idle",
        OBSERVE = "idle",
        DIALOGUE = "idle",
        OFFER = "idle",
        TAKEOVER = "idle",
        SUCCESS = "idle",
        DISABLED = "idle",
    },
    ui = {
        anchorX = 0,
        anchorY = 1,
        offsetX = 76,
        offsetY = -18,
        scale = 1,
        spriteHeight = 210,
        hitboxWidth = 112,
        hitboxHeight = 218,
    },
    roamArea = {
        relativeToAnchor = true,
        xMin = 42,
        xMax = 238,
        yMin = -118,
        yMax = -18,
    },
    roam = {
        enabled = true,
        minIdleTime = 4,
        maxIdleTime = 12,
        moveSpeed = 40,
        maxDistance = 120,
        arrivalDistance = 1.5,
    },
    blink = {
        enabled = true,
        animation = "blink",
        minInterval = 4.5,
        maxInterval = 10,
    },
    interaction = {
        duration = 1.8,
        consecutiveWindow = 1.2,
        pokeLines = { "在。", "怎么了？", "正在记录。", "……", "不要一直戳。" },
    },
    failureAssist = {
        observeDuration = 1.6,
        observeLines = { "我看到了。", "轨迹记下了。", "再试一次。" },
        offerText = "需要我接管吗？",
        declineText = "不用",
        acceptText = "交给你",
        successText = "好了。",
        unavailableText = "这关还没有可用的辅助轨迹。",
    },
    debug = {
        enabled = false,
    },
}

function GreenAssistConfig.Resolve(overrides)
    return Merge(Clone(GreenAssistConfig.DEFAULTS), overrides or {})
end

return GreenAssistConfig
