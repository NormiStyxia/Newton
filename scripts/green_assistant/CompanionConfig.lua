local CompanionConfig = {}

local DEFAULTS = {
    moveSpeed = 64,
    idleMinDuration = 2,
    idleMaxDuration = 4,
    blinkMinInterval = 1.8,
    blinkMaxInterval = 4.5,
    minWalkDistance = 72,
    maxWalkDistance = 320,
    longWalkChance = 0.2,
    shortWalkChance = 0.25,
    arrivalDistance = 1.5,
    characterHalfWidth = 56,
    edgePadding = 12,
    cardSafeGap = 32,
    minimumZoneWidth = 180,
    dragThreshold = 10,
    dragHoldDuration = 0.35,
    dragBottomPadding = 2,
    settleDuration = 0.16,
    relocationExitDuration = 0.18,
    relocationHoldDuration = 0.06,
    relocationEnterDuration = 0.22,
    relocationSlatCount = 8,
    baselineBottomInset = 18,
    zoneLeftPadding = 0,
    zoneRightPadding = 18,
    emptyHandRightInset = 118,
}

local function Clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Clone(child) end
    return result
end

function CompanionConfig.Resolve(overrides)
    local result = Clone(DEFAULTS)
    for key, value in pairs(overrides or {}) do result[key] = Clone(value) end
    return result
end

CompanionConfig.DEFAULTS = DEFAULTS

return CompanionConfig
