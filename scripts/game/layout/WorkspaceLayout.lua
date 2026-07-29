local CardHandLayout = require("game.layout.CardHandLayout")
local CompanionConfig = require("green_assistant.CompanionConfig")

local WorkspaceLayout = {}

function WorkspaceLayout.Apply(frame, cardHandPoses, cardWidth, cardHeight, overrides)
    assert(type(frame) == "table", "layout frame is required")
    local config = CompanionConfig.Resolve(overrides)
    local bounds = CardHandLayout.Bounds(cardHandPoses, cardWidth, cardHeight)
    local left = frame.workspaceX + config.zoneLeftPadding
    local rightLimit = frame.logicalWidth - config.zoneRightPadding
    local right
    if bounds then
        right = math.min(rightLimit, bounds.left - config.cardSafeGap)
    else
        right = math.min(rightLimit, frame.playfieldX + frame.playfieldWidth - config.emptyHandRightInset)
    end
    local baselineY = frame.logicalHeight - config.baselineBottomInset
    local width = math.max(0, right - left)
    local companionZone = {
        left = left,
        right = right,
        top = baselineY - config.dragTopPadding,
        bottom = baselineY + config.dragBottomPadding,
        baselineY = baselineY,
        fallbackX = left + config.characterHalfWidth + config.edgePadding,
        walkingAllowed = width >= config.minimumZoneWidth,
        width = width,
    }
    frame.cardHandBounds = bounds
    frame.companionZone = companionZone
    return companionZone, bounds
end

return WorkspaceLayout
