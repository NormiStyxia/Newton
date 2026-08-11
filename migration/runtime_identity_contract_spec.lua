package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local LevelSession = require("game.level.LevelSession")
local Tutorial = require("game.tutorial.Controller")
local Dialogue = require("game.dialogue.DialogueController")
local DialogueData = require("game.dialogue.DialogueData")
local GreenAdapter = require("game.green_assistant.NewtonGreenAssistAdapter")
local ResultReport = require("ui.result_report")
local LevelPresentation = require("game.level.Presentation")
local Rules = require("game.gameplay.Rules")
local ReplayMode = require("game.replay.Mode")
local InteractionRouter = require("game.input.InteractionRouter")

local context = setmetatable({
    failureCountsByLevel_ = {},
    LEVEL_META = {},
    LEVEL_SCORE_PROFILES = {},
    DEFAULT_LEVEL_SCORE_PROFILE = "default",
    CONFIG = { levelCount = 9 },
}, { __index = _G })
LevelSession.Install(context)

local overlayContext = setmetatable({
    Rules = Rules,
    ReplayMode = ReplayMode,
    CONFIG = { levelCount = 9 },
}, { __index = _G })
InteractionRouter.Install(overlayContext)
local assistedLayout = overlayContext.ResolveAssistedResultLayout({
    playfieldX = 323,
    playfieldY = 112,
    playfieldWidth = 1500,
    playfieldHeight = 596,
})
expect(assistedLayout.panel.w == 620 and assistedLayout.panel.h == 210,
    "assisted result panel no longer matches the failure overlay footprint")
expect(assistedLayout.centerX == 1073 and assistedLayout.centerY == 410,
    "assisted result panel no longer shares the failure overlay center")
expect(assistedLayout.returnButton.x == 973 and assistedLayout.retryButton.x == 1173
    and assistedLayout.returnButton.y == 470 and assistedLayout.retryButton.y == 470,
    "assisted result buttons lost their symmetric compact spacing")

context.runtimeSession_ = { sourceKind = "custom", levelId = "level_02" }
context.level_ = { levelId = "level_02" }
expect(not context.IsOfficialRuntimeSession(), "custom session was treated as official")
expect(context.RuntimeLevelStateKey() == "custom:level_02",
    "custom state key collided with the official level ID")
context.runtimeSession_.sourceKind = "official"
expect(context.IsOfficialRuntimeSession(), "official session lost official identity")
expect(context.RuntimeLevelStateKey() == "level_02", "official state key changed")

Tutorial.Install(context)
context.InitializeTutorial()
context.runtimeSession_.sourceKind = "custom"
context.NotifyTutorialLevelReady("level_02")
context.NotifyTutorialDialogueMarker("level_02", "level02_feather_gravity_action")
expect(context.GetTutorialRenderModel().visible == false,
    "custom level inherited the official level_02 tutorial")
context.runtimeSession_.sourceKind = "official"
context.NotifyTutorialLevelReady("level_02")
context.NotifyTutorialDialogueMarker("level_02", "level02_feather_gravity_action")
expect(context.GetTutorialRenderModel().visible == true,
    "official level_02 tutorial was disabled by the identity guard")

context.anger_ = 0
context.playUIClick = function() end
Dialogue.Install(context)
context.InitializeDialogue()
context.runtimeSession_.sourceKind = "custom"
context.NotifyDialogueLevelReady("level_02")
expect(context.dialogueController_.currentLevelId == nil
    and not context.dialogueController_:IsActive(),
    "custom level inherited official dialogue")
context.runtimeSession_.sourceKind = "official"
context.NotifyDialogueLevelReady("level_02")
expect(context.dialogueController_.currentLevelId == "level_02"
    and context.dialogueController_:IsActive(),
    "official dialogue was disabled by the identity guard")

context.AppendDialogueMessages("level_02", {
    { speaker = "green", side = "left", displayName = "Green", text = "stale follow-up", style = "GREEN" },
})
expect(context.dialogueController_.log:MessageCount("level_02") > #DialogueData.Intro("level_02"),
    "re-entry setup did not create a previous-session follow-up")
context.NotifyDialogueLevelReady(nil)
context.NotifyTutorialLevelReady("level_02")
context.NotifyDialogueLevelReady("level_02")
expect(context.dialogueController_:IsActive()
    and context.dialogueController_.openMode == "intro"
    and context.dialogueController_.visibleCount == 0,
    "official level re-entry did not restart its communication intro")
expect(context.dialogueController_.log:MessageCount("level_02") == #DialogueData.Intro("level_02"),
    "official level re-entry retained stale follow-up messages from the previous session")
context.dialogueController_:RevealAll()
expect(context.GetTutorialRenderModel().visible == true,
    "re-entered communication did not replay the tutorial marker")

context.NotifyDialogueLevelReady("level_05")
local level05IntroCount = #DialogueData.Intro("level_05")
expect(level05IntroCount == 7
    and context.dialogueController_.log:MessageCount("level_05") == level05IntroCount,
    "level 05 intro dialogue was not initialized with seven messages")
context.dialogueController_:RevealAll()
context.dialogueController_:Close()
context.dialogueController_:_FinishClose()
expect(context.NotifyDialogueWallImpact("level_05"),
    "first real level 05 wall impact did not trigger dialogue")
expect(not context.dialogueController_:IsActive()
    and context.dialogueController_:HasUnread(),
    "closed communication did not stay closed with an unread wall-impact dot")
expect(context.dialogueController_.log:MessageCount("level_05") == level05IntroCount + 2,
    "wall-impact dialogue did not append exactly two messages")
expect(context.dialogueController_:OpenHistory()
    and context.dialogueController_.openMode == "history"
    and context.dialogueController_.visibleCount == level05IntroCount + 2
    and not context.dialogueController_:HasUnread(),
    "opening wall-impact history did not reveal and mark the queued messages read")
context.dialogueController_:Close()
context.dialogueController_:_FinishClose()
expect(not context.NotifyDialogueWallImpact("level_05")
    and context.dialogueController_.log:MessageCount("level_05") == level05IntroCount + 2,
    "repeated wall impact duplicated level 05 dialogue")
context.NotifyDialogueLevelReady(nil)
context.NotifyDialogueLevelReady("level_05")
context.dialogueController_:RevealAll()
context.dialogueController_:Close()
context.dialogueController_:_FinishClose()
expect(context.NotifyDialogueWallImpact("level_05")
    and context.dialogueController_.log:MessageCount("level_05") == level05IntroCount + 2
    and not context.dialogueController_:IsActive()
    and context.dialogueController_:HasUnread(),
    "level 05 re-entry did not reset the per-session first-wall observation")
context.NotifyDialogueLevelReady("level_04")
expect(not context.NotifyDialogueWallImpact("level_04"),
    "non-level-05 wall impact inherited level 05 dialogue")

context.level_, context.apple_ = {}, {}
context.replayBusinessMode_, context.assistDemoActive_ = ReplayMode.NONE, false
local adapter = GreenAdapter.New(context)
context.runtimeSession_.sourceKind = "custom"
expect(not adapter:canTakeover("level_02"),
    "custom level could load an official standard solution")
expect(adapter:getAssistReplay("level_02") == nil,
    "custom level directly fetched an official standard solution")
context.runtimeSession_.sourceKind = "official"
expect(adapter:canTakeover("level_02"),
    "official level lost its standard solution")
expect(adapter:getAssistReplay("level_02") ~= nil,
    "official level could not fetch its standard solution")

local progressWrites, officialStarts, catalogReturns = 0, 0, 0
local resultContext = setmetatable({
    LevelPresentation = LevelPresentation,
    Rules = Rules,
    ReplayMode = ReplayMode,
    CONFIG = { levelCount = 9 },
    runtimeSession_ = { sourceKind = "custom", levelId = "level_02" },
    level_ = {
        levelId = "level_02",
        name = "Custom copy",
        scoring = { metric = "ruleDeployCount", tiers = { { score = 100, maxInterventions = 1 } } },
    },
    levelIndex_ = 2,
    rules_ = Rules.NewState(),
    ruleDeployCount_ = 0,
    assistedClear_ = false,
    assistUsed_ = false,
    observation_ = "",
    anger_ = 0,
    success_ = true,
    replayMode_ = "none",
    replayBusinessMode_ = ReplayMode.NONE,
    experimentProgress_ = {
        UpdateReportSnapshot = function()
            progressWrites = progressWrites + 1
            return true
        end,
    },
}, { __index = _G })
resultContext.IsOfficialRuntimeSession = function()
    return resultContext.runtimeSession_.sourceKind == "official"
end
resultContext.RuntimeLevelStateKey = function()
    return resultContext.IsOfficialRuntimeSession() and resultContext.level_.levelId
        or "custom:" .. resultContext.level_.levelId
end
resultContext.playUIClick = function() end
resultContext.RequestStartLevel = function()
    officialStarts = officialStarts + 1
    return true
end
resultContext.RequestReturnToCatalog = function()
    catalogReturns = catalogReturns + 1
    return true
end
resultContext.ResetExperiment = function() end
resultContext.StartReplay = function() return false end
ResultReport.Install(resultContext)
resultContext.resultReportState_ = {
    sourceKind = "custom",
    levelId = "level_02",
    assistUsed = false,
    selectedSelfReview = "custom",
}
resultContext.BeginResultReportAction("next")
resultContext.UpdateResultReport(1)
expect(progressWrites == 0 and officialStarts == 0 and catalogReturns == 1,
    "custom victory wrote campaign progress or started the next official level")

resultContext.runtimeSession_.sourceKind = "official"
resultContext.resultReportState_ = {
    sourceKind = "official",
    levelId = "level_02",
    assistUsed = false,
    selectedSelfReview = "official",
}
resultContext.BeginResultReportAction("next")
resultContext.UpdateResultReport(1)
expect(progressWrites == 1 and officialStarts == 1,
    "official victory flow was disabled by the custom identity fix")

print(string.format('{"mode":"RUNTIME_IDENTITY","checks":%d,"status":"pass"}', checks))
