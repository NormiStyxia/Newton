package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local Actions = require("game.input.SemanticActions")

local mouse = Actions.Attach({
    x = 120, y = 80, down = true, pressed = true, released = false,
    insideStage = true, isTouch = false,
}, {
    source = "mouse",
    hover = true,
    modifiers = { ctrl = true },
    cancelInteraction = true,
    cancelRaw = "mouse.right",
    cancelNavigation = true,
    scrollY = -1,
    boxSelect = true,
})
expect(Actions.Find(mouse, Actions.PRIMARY_PRESS) ~= nil, "mouse primary press was not semantic")
expect(Actions.Find(mouse, Actions.CANCEL, "interaction") ~= nil,
    "right mouse did not map to interaction cancel")
expect(Actions.Find(mouse, Actions.CANCEL, "navigation") ~= nil,
    "keyboard Escape did not map to navigation cancel")
expect(Actions.Find(mouse, Actions.BOX_SELECT_BEGIN) ~= nil,
    "Ctrl+mouse press did not map to box-select begin")
expect(Actions.SupportsHover(mouse), "mouse hover capability was lost")
local wheel = Actions.Find(mouse, Actions.SCROLL)
local _, wheelDelta = Actions.ScrollDelta(wheel, 48, 1)
expect(wheelDelta == 48, "wheel delta did not normalize through the semantic scroll step")

local cancel = Actions.Find(mouse, Actions.CANCEL, "interaction")
expect(Actions.Consume(cancel, "CardInteraction")
    and Actions.Find(mouse, Actions.CANCEL, "interaction") == nil,
    "consumed cancel action remained dispatchable")

local touchPress = Actions.Attach({
    x = 20, y = 80, down = true, pressed = true, released = false,
    insideStage = true, isTouch = true,
}, {
    source = "touch", pointerId = 7, directScroll = true,
})
expect(Actions.Find(touchPress, Actions.PRIMARY_PRESS).pointerId == 7,
    "touch primary pointer identity was lost")
expect(not Actions.SupportsHover(touchPress), "touch acquired a fake hover capability")
expect(Actions.Find(touchPress, Actions.SCROLL) == nil,
    "touch primary input became scroll before a scrollable region opted in")

local targets = {
    { id = "list", rect = { x = 0, y = 0, w = 100, h = 100 }, value = 0, maximum = 200 },
}
local gesture, result = Actions.UpdateDirectScroll(nil, touchPress, targets, 8)
expect(gesture and result.consume and result.action == nil,
    "scrollable touch press was not deferred for gesture arbitration")

local touchMove = Actions.Attach({
    x = 20, y = 40, down = true, pressed = false, released = false,
    insideStage = true, isTouch = true,
}, {
    source = "touch", pointerId = 7, directScroll = true,
})
gesture, result = Actions.UpdateDirectScroll(gesture, touchMove, targets, 8)
expect(gesture and result.action and result.action.action == Actions.SCROLL
    and result.action.deltaY == 40 and result.value == 40,
    "touch drag did not become a logical semantic scroll")

local touchRelease = Actions.Attach({
    x = 20, y = 40, down = false, pressed = false, released = true,
    insideStage = true, isTouch = true,
}, {
    source = "touch", pointerId = 7, directScroll = true,
})
gesture, result = Actions.UpdateDirectScroll(gesture, touchRelease, targets, 8)
expect(gesture == nil and result.consume and not result.tap,
    "completed touch scroll leaked into primary click handling")

local pauseFrame = Actions.Attach({
    x = 10, y = 10, down = true, pressed = false, released = false,
    insideStage = true, isTouch = true,
}, {
    source = "touch", pointerId = 1, directScroll = true,
    pauseToggle = true, pausePointerId = 2,
})
local pause = Actions.Find(pauseFrame, Actions.PAUSE_TOGGLE)
expect(pause and pause.pointerId == 2 and pause.source == "touch",
    "multi-touch pause did not map to PAUSE_TOGGLE")

print(string.format('{"mode":"INPUT_SEMANTIC_ACTIONS","checks":%d,"status":"pass"}', checks))
