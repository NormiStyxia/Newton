package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local Actions = require("game.input.SemanticActions")
local InteractionRouter = require("game.input.InteractionRouter")
local Selection = require("game.workshop.Selection")
local Dialogue = require("game.dialogue.DialogueController")

local animatedCard, clearedInteraction, clearedSelection = nil, 0, 0
local pauseCount, pauseClicks = 0, 0
local context
context = setmetatable({
    SemanticActions = Actions,
    Rules = {},
    ReplayMode = {},
    CONFIG = { levelCount = 9 },
    activeCardId_ = "side-gravity",
    primedCardId_ = nil,
    selectedCardId_ = "side-gravity",
    CurrentCardVisualPose = function() return { x = 10, y = 20 } end,
    PrimedCardPose = function() return nil end,
    AnimateCardToHome = function(id) animatedCard = id end,
    ClearCardInteraction = function() clearedInteraction = clearedInteraction + 1 end,
    ClearSelectedCard = function()
        clearedSelection = clearedSelection + 1
        context.selectedCardId_ = nil
    end,
    playUIClick = function() pauseClicks = pauseClicks + 1 end,
    ToggleTacticalPause = function() pauseCount = pauseCount + 1 end,
}, { __index = _G })
InteractionRouter.Install(context)

local cancelFrame = Actions.Attach({
    x = 0, y = 0, down = false, pressed = false, released = false,
}, { source = "mouse", cancelInteraction = true })
local cancel = Actions.Find(cancelFrame, Actions.CANCEL, "interaction")
expect(context.HandleCancelAction(cancel), "semantic cancel was not handled")
expect(context.activeCardId_ == nil and context.primedCardId_ == nil
    and animatedCard == "side-gravity" and clearedInteraction == 1 and clearedSelection == 1,
    "semantic cancel did not use the single card cancellation path")
expect(cancel.consumedBy == "CardInteraction", "cancel consumer was not recorded")

context.activeCardId_, context.selectedCardId_ = "side-gravity", "side-gravity"
context.frame_ = {
    workspaceX = 1000,
    playfieldX = 0, playfieldY = 0, playfieldWidth = 500, playfieldHeight = 500,
    cardHandY = 800,
}
context.apple_ = {}
context.isPaused_, context.launched_, context.replayActive_ = true, false, false
context.HandleGreenAssistantPointer = function() return false end
context.HandleHUDPointer = function() return false end
context.IsResultOverlayVisible = function() return false end
context.TryCardPress = function() return false end
context.SetHoveredCard = function() end
local touchBlank = Actions.Attach({
    x = 100, y = 100, down = true, pressed = true, released = false,
    insideStage = true, isTouch = true,
}, { source = "touch", pointerId = 9, directScroll = true })
context.HandlePointer(touchBlank)
local contextualCancel = touchBlank.actions[#touchBlank.actions]
expect(contextualCancel.action == Actions.CANCEL and contextualCancel.source == "touch"
    and contextualCancel.consumedBy == "CardInteraction",
    "touch blank press did not become a contextual semantic cancel")
expect(context.activeCardId_ == nil and context.selectedCardId_ == nil,
    "touch contextual cancel did not clear the active card interaction")
local ordinaryBlank = Actions.Attach({
    x = 100, y = 100, down = true, pressed = true, released = false,
    insideStage = true, isTouch = true,
}, { source = "touch", pointerId = 9, directScroll = true })
context.HandlePointer(ordinaryBlank)
expect(Actions.Find(ordinaryBlank, Actions.CANCEL, "interaction") == nil,
    "ordinary touch world press was globally reclassified as cancel")

local pauseFrame = Actions.Attach({
    x = 0, y = 0, down = false, pressed = false, released = false,
}, { source = "touch", pauseToggle = true, pausePointerId = 2 })
local pause = Actions.Find(pauseFrame, Actions.PAUSE_TOGGLE)
expect(context.HandlePauseAction(pause) and pauseCount == 1 and pauseClicks == 1,
    "touch pause action did not enter the shared tactical pause handler")
expect(pause.consumedBy == "TacticalPause", "pause consumer was not recorded")

local interaction = {
    ScreenToLevel = function(_, x, y) return x, y end,
    FindTopObject = function() return nil end,
}
local function selectionState(tool)
    return {
        canvasTool = tool,
        controls = { canvasTransform = { objectScale = 1 } },
        layout = { canvasViewport = { x = 0, y = 0, w = 500, h = 500 } },
        document = { objects = {} },
        selectedObject = nil,
        selectedObjectIds = {},
        selectedObjects = {},
        selectionCount = 0,
        readOnly = false,
        view = { panX = 0, panY = 0 },
    }
end

local mouseSelection = selectionState("pan")
local boxBegin = Actions.Attach({
    x = 10, y = 10, down = true, pressed = true, released = false, isTouch = false,
}, {
    source = "mouse", hover = true, modifiers = { ctrl = true }, boxSelect = true,
})
Selection.BeginCanvasGesture(mouseSelection, boxBegin, interaction)
expect(mouseSelection.transaction and mouseSelection.transaction.tool == "marquee"
    and Actions.Find(boxBegin, Actions.BOX_SELECT_BEGIN),
    "Ctrl+mouse did not enter the shared box-select transaction")

local boxMove = Actions.Attach({
    x = 12, y = 12, down = true, pressed = false, released = false, isTouch = false,
}, { source = "mouse", hover = true })
Selection.UpdateCanvasGesture(mouseSelection, boxMove, interaction)
expect(Actions.Find(boxMove, Actions.BOX_SELECT_UPDATE),
    "active box selection did not promote primary move to BOX_SELECT_UPDATE")

local boxEnd = Actions.Attach({
    x = 12, y = 12, down = false, pressed = false, released = true, isTouch = false,
}, { source = "mouse", hover = true })
Selection.EndCanvasGesture(mouseSelection, boxEnd)
expect(Actions.Find(boxEnd, Actions.BOX_SELECT_END),
    "active box selection did not promote primary release to BOX_SELECT_END")

local touchSelection = selectionState("marquee")
local touchBegin = Actions.Attach({
    x = 20, y = 20, down = true, pressed = true, released = false, isTouch = true,
}, { source = "touch", pointerId = 3, directScroll = true })
Selection.BeginCanvasGesture(touchSelection, touchBegin, interaction)
expect(touchSelection.transaction and touchSelection.transaction.tool == "marquee"
    and Actions.Find(touchBegin, Actions.BOX_SELECT_BEGIN),
    "touch box tool did not enter the shared box-select transaction")

local dialogueContext = setmetatable({ anger_ = 0 }, { __index = _G })
Dialogue.Install(dialogueContext)
dialogueContext.InitializeDialogue()
local dialogue = dialogueContext.dialogueController_
dialogue.maxScroll = 200
dialogue.scrollOffset = 0
dialogue:SetViewGeometry({
    viewport = { x = 0, y = 0, w = 200, h = 200 },
    track = { x = 190, y = 0, w = 10, h = 200 },
    thumb = { x = 190, y = 0, w = 10, h = 40 },
})
local dialogueWheel = Actions.Attach({
    x = 50, y = 50, down = false, pressed = false, released = false, isTouch = false,
}, { source = "mouse", hover = true, scrollY = -16 })
expect(dialogue:_HandleScrollbar(dialogueWheel) and dialogue.scrollOffset == 54,
    "dialogue wheel did not enter the shared scroll handler with its calibrated step")

dialogue.scrollOffset = 0
local dialogueTouchStart = Actions.Attach({
    x = 50, y = 80, down = true, pressed = true, released = false, isTouch = true,
}, { source = "touch", pointerId = 5, directScroll = true })
expect(dialogue:_HandleViewportScroll(dialogueTouchStart),
    "dialogue touch scroll did not capture its viewport")
local dialogueTouchMove = Actions.Attach({
    x = 50, y = 40, down = true, pressed = false, released = false, isTouch = true,
}, { source = "touch", pointerId = 5, directScroll = true })
expect(dialogue:_HandleViewportScroll(dialogueTouchMove) and dialogue.scrollOffset == 40,
    "dialogue touch drag did not enter the same scroll handler")

print(string.format('{"mode":"INPUT_SEMANTIC_ROUTING","checks":%d,"status":"pass"}', checks))
