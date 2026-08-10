package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local RuleArchiveOverlay = require("ui.RuleArchiveOverlay")
local Rules = require("game.gameplay.Rules")

local feedbackCount = 0
local archive = RuleArchiveOverlay.New({
    rules = Rules,
    cardWidth = 124,
    cardHeight = 202,
    onFeedback = function() feedbackCount = feedbackCount + 1 end,
})

local frame = { logicalWidth = 1880, logicalHeight = 840 }
expect(archive:GetCardCount() == 6, "archive must expose all six canonical rule cards")
expect(not archive:IsVisible(), "archive must start closed")
expect(archive:Open(), "closed archive should open")
expect(archive.phase == "opening", "open should begin the deal animation")

archive:Update(.7, -10000, -10000, frame)
expect(archive:IsOpen(), "deal animation should finish within the requested duration")

local layout = archive:ResolveLayout(frame)
expect(#layout.cards == 6, "layout must contain six card poses")
local expectedAngles = { -5, -3, -1, 1, 3, 5 }
for index, pose in ipairs(layout.cards) do
    expect(pose.angle == expectedAngles[index], "card fan angle must remain stable")
    local halfWidth = layout.cardWidth * .5
    local halfHeight = layout.cardHeight * .5
    expect(pose.x - halfWidth >= 0 and pose.x + halfWidth <= frame.logicalWidth,
        "card must remain horizontally visible")
    expect(pose.y - halfHeight >= 0 and pose.y + halfHeight <= frame.logicalHeight,
        "card must remain vertically visible")
    if index > 1 then expect(pose.x > layout.cards[index - 1].x, "cards must be ordered horizontally") end
end

local third = layout.cards[3]
archive:Update(.12, third.x, third.y, frame)
expect(archive.hoveredIndex == 3, "hover should resolve the visible card")
archive:HandlePointer({ pressed = true, x = third.x, y = third.y }, frame)
expect(archive.selectedIndex == 3, "clicking a card should open lightweight inspection")
expect(archive:IsOpen(), "card inspection must not close the archive")
expect(feedbackCount == 1, "card inspection should emit one feedback event")

archive:HandlePointer({ pressed = true, x = 20, y = 20 }, frame)
expect(archive.phase == "closing", "clicking blank overlay space should close the archive")
archive:Update(.5, 20, 20, frame)
expect(not archive:IsVisible(), "reverse collection animation should finish closed")
expect(feedbackCount == 2, "blank-space close should emit one feedback event")

expect(archive:Open(), "archive should reopen without rebuilding catalog state")
archive:Update(.14, -10000, -10000, frame)
local poseBeforeInterruptedClose = archive:_basePose(1, archive:ResolveLayout(frame))
expect(archive:Close(), "entry/escape close path should be available during opening")
local poseAfterInterruptedClose = archive:_basePose(1, archive:ResolveLayout(frame))
expect(math.abs(poseBeforeInterruptedClose.x - poseAfterInterruptedClose.x) < 1e-9
    and math.abs(poseBeforeInterruptedClose.y - poseAfterInterruptedClose.y) < 1e-9,
    "closing during deal animation must not snap cards to their final fan positions")
archive:Update(.5, -10000, -10000, frame)
expect(not archive:IsVisible(), "programmatic close should reset the overlay")

local compact = archive:ResolveLayout({ logicalWidth = 1280, logicalHeight = 720 })
expect(#compact.cards == 6, "compact landscape layout must keep all six cards")
for _, pose in ipairs(compact.cards) do
    local halfWidth = compact.cardWidth * .5
    local halfHeight = compact.cardHeight * .5
    expect(pose.x - halfWidth >= 0 and pose.x + halfWidth <= 1280,
        "compact layout must keep cards horizontally visible")
    expect(pose.y - halfHeight >= 0 and pose.y + halfHeight <= 720,
        "compact layout must keep cards vertically visible")
end

print(string.format("RULE_ARCHIVE_OVERLAY: %d checks passed", checks))
