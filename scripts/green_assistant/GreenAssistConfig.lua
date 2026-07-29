local CompanionConfig = require("green_assistant.CompanionConfig")
local CompanionDefaults = CompanionConfig.DEFAULTS

local GreenAssistConfig = {}

GreenAssistConfig.QUALITY_PROFILES = {
    A_MASTER_LINEAR = { variant = "master_1080", generateMipmaps = false },
    B_RUNTIME_LINEAR = { variant = "runtime_512", generateMipmaps = false },
    C_RUNTIME_MIPMAP = { variant = "runtime_512", generateMipmaps = true },
    D_MASTER_MIPMAP = { variant = "master_1080", generateMipmaps = true },
}

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
    qualityPreset = "C_RUNTIME_MIPMAP",
    fallbackAnimation = "idle_base",
    failureThreshold = 3,
    features = {
        roam = true,
        interaction = true,
        dialogue = true,
        failureAssist = true,
        takeover = true,
    },
    animations = {
        idle_base = {
            assetClip = "idle",
            frames = Frames("idle", 16),
            fps = 8,
            loop = true,
            playbackSpeed = 1,
            anchor = { x = 0.5, y = 1 },
            frameOffset = { x = 0, y = 0 },
            scale = 1,
        },
        idle = {
            assetClip = "idle",
            frames = Frames("idle", 16),
            fps = 8,
            loop = true,
            playbackSpeed = 1,
            anchor = { x = 0.5, y = 1 },
            frameOffset = { x = 0, y = 0 },
            scale = 1,
        },
        move = {
            assetClip = "move",
            frames = Frames("move", 16),
            fps = 10,
            loop = true,
            playbackSpeed = 1,
            anchor = { x = 0.5, y = 1 },
            frameOffset = { x = 0, y = 0 },
            scale = 1,
        },
        walk = {
            assetClip = "move",
            frames = Frames("move", 16),
            fps = 10,
            loop = true,
            playbackSpeed = 1,
            anchor = { x = 0.5, y = 1 },
            frameOffset = { x = 0, y = 0 },
            scale = 1,
        },
        blink = {
            assetClip = "blink",
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
        IDLE = "idle_base",
        WALK = "walk",
        ROAM = "walk",
        DRAG = "drag",
        INTERACT = "idle_base",
        OBSERVE = "idle_base",
        DIALOGUE = "idle_base",
        OFFER = "idle_base",
        TAKEOVER = "idle_base",
        SUCCESS = "idle_base",
        DISABLED = "idle_base",
    },
    assets = {
        enabled = true,
        -- A/D use master_1080. B/C use runtime_512.  Keep this independent
        -- from render.generateMipmaps so all four quality variants are testable.
        variant = "runtime_512",
        activeVariant = nil,
    },
    render = {
        -- false = A/B linear; true = C/D linear + mipmap.
        generateMipmaps = false,
    },
    ui = {
        anchorX = 0,
        anchorY = 1,
        offsetX = 76,
        offsetY = -18,
        scale = 1,
        sourceFacing = "LEFT",
        spriteHeight = 210,
        hitboxWidth = 112,
        hitboxHeight = 218,
    },
    companion = CompanionConfig.Resolve(),
    roamArea = {
        relativeToAnchor = true,
        xMin = 42,
        xMax = 238,
        yMin = -118,
        yMax = -18,
    },
    roam = {
        enabled = true,
        minIdleTime = CompanionDefaults.idleMinDuration,
        maxIdleTime = CompanionDefaults.idleMaxDuration,
        moveSpeed = CompanionDefaults.moveSpeed,
        maxDistance = CompanionDefaults.maxWalkDistance,
        arrivalDistance = CompanionDefaults.arrivalDistance,
    },
    blink = {
        enabled = true,
        animation = "blink",
        minInterval = CompanionDefaults.blinkMinInterval,
        maxInterval = CompanionDefaults.blinkMaxInterval,
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
    local resolved = Merge(Clone(GreenAssistConfig.DEFAULTS), overrides or {})
    local qualityPreset = resolved.qualityPreset
    if qualityPreset ~= false then
        local quality = GreenAssistConfig.QUALITY_PROFILES[qualityPreset]
        assert(quality, "unknown GreenAssistant quality preset: " .. tostring(qualityPreset))
        resolved.assets.variant = quality.variant
        resolved.render.generateMipmaps = quality.generateMipmaps
    end
    local companion = resolved.companion
    local legacyRoam = overrides and overrides.roam or nil
    if legacyRoam then
        if legacyRoam.minIdleTime ~= nil then companion.idleMinDuration = resolved.roam.minIdleTime end
        if legacyRoam.maxIdleTime ~= nil then companion.idleMaxDuration = resolved.roam.maxIdleTime end
        if legacyRoam.moveSpeed ~= nil then companion.moveSpeed = resolved.roam.moveSpeed end
        if legacyRoam.maxDistance ~= nil then companion.maxWalkDistance = resolved.roam.maxDistance end
        if legacyRoam.arrivalDistance ~= nil then companion.arrivalDistance = resolved.roam.arrivalDistance end
    else
        resolved.roam.minIdleTime = companion.idleMinDuration
        resolved.roam.maxIdleTime = companion.idleMaxDuration
        resolved.roam.moveSpeed = companion.moveSpeed
        resolved.roam.maxDistance = companion.maxWalkDistance
        resolved.roam.arrivalDistance = companion.arrivalDistance
    end
    local legacyBlink = overrides and overrides.blink or nil
    if legacyBlink then
        if legacyBlink.minInterval ~= nil then companion.blinkMinInterval = resolved.blink.minInterval end
        if legacyBlink.maxInterval ~= nil then companion.blinkMaxInterval = resolved.blink.maxInterval end
    else
        resolved.blink.minInterval = companion.blinkMinInterval
        resolved.blink.maxInterval = companion.blinkMaxInterval
    end
    return resolved
end

return GreenAssistConfig
