-- Domain-owned mutable state exposed through a private compatibility environment.
---@class GameContext
---@field State any
---@field LevelData any
---@field CoordinateMapper any
---@field DesignSpace any
---@field WorkspaceLayout any
---@field MatterCalibration any
---@field PhysicsProfiles any
---@field PhysicsProbe any
---@field Rules any
---@field RuntimeFactory any
---@field Renderer2D any
---@field SynthAudio any
---@field TrajectoryPrediction any
---@field ReplayTimeline any
---@field ReplayFeed any
---@field ReplayMode any
---@field PhaseWallEffects any
---@field CONFIG table
---@field CARD_DESIGN_WIDTH number
---@field CARD_DESIGN_HEIGHT number
---@field CARD_TEXT_SCALE number
---@field CARD_RENDER_WIDTH number
---@field CARD_RENDER_HEIGHT number
---@field GOAL_CONTACT_SKIN number
---@field LEVEL_META table
---@field design_ any
---@field debugDraw_ boolean
---@field failureCountsByLevel_ table<string, integer>
---@field assistantInputLocked_ boolean
---@field pointer_ table
---@field dialogueController_ table|nil
---@field InitializeDialogue fun()
---@field DestroyDialogue fun()
---@field NotifyDialogueLevelReady fun(levelId: string)
---@field UpdateDialogue fun(dt: number, pointerFrame: table): boolean
---@field DrawDialogueHistoryButton fun()
---@field DrawDialogueOverlay fun()
---@field resultReportState_ table|nil
local State = {}

local OWNERS = {}

local function own(domain, names)
    for _, name in ipairs(names) do OWNERS[name] = domain end
end

own("runtime", {
    "scene_", "camera_", "viewport_", "physicsWorld_", "level_", "physicsProfile_", "runtime_",
    "laboratoryBoundaries_", "apple_", "applePreSolveVelocity_", "pendingMatterRestitutions_", "physicsStepTimeScale_", "mapper_", "audio_", "levelIndex_",
})
own("layout", { "design_", "frame_", "painter_", "sensorAngle_", "debugDraw_" })
own("experiment", {
    "rules_", "draggedApple_", "aimPreview_", "launched_", "outsideMs_", "flightMs_", "status_",
    "isPaused_", "bulletTimeActive_", "success_", "failed_", "absorbing_", "absorbElapsedMs_",
    "assistedClear_", "failureCount_", "failureCountsByLevel_", "observation_", "uiElapsed_", "anger_",
    "phaseTraversing_", "phaseWallTraversal_", "stalledMs_", "trail_", "lastTrailAt_", "rulePulse_", "ruleFlash_",
    "ruleDeployCount_",
})
own("goal", {
    "goalContact_", "goalContactMs_", "goalEntryRecorded_", "goalPulseElapsedMs_",
    "goalContactEventSeen_", "goalContactEndSeen_", "goalContactConfirmed_", "goalContactMissSteps_",
})
own("mechanisms", { "channelStates_" })
own("input", { "pointer_", "hoveredLevelIndex_", "hoveredNavigation_", "punchHovered_" })
own("cards", {
    "activeCardId_", "activeCardStart_", "activeCardPointer_", "activeCardDragged_",
    "activeCardDeploying_", "activeCardPressedAt_", "activeCardPressPose_", "primedCardId_",
    "cardParameterStart_", "cardDeployEnteredMs_", "cardLastMotionAtMs_", "cardPointerSamples_",
    "cardCandidate_", "cardGestureDistance_", "hoveredCardId_", "cardHoverStates_", "cardStates_",
    "cardDeckById_", "handOrder_", "cardHomeMotions_", "cardHandReordering_", "cardBurns_",
    "cardBurnParticles_", "burningCardIds_",
})
own("replay", {
    "replayActive_", "replayTime_", "replayPaused_", "replaySpeed_", "replayFinished_",
    "replaySamples_", "replayEvents_", "replaySavedApple_", "replayMode_", "replayNextSampleMs_",
    "replayPreviousSample_", "replayBusinessMode_",
})
own("assistant", {
    "greenAssistant_", "greenAssistantAdapter_", "assistantInputLocked_", "assistSceneActive_",
    "assistDemoRunner_", "assistDemoGameAdapter_", "assistDemoView_", "assistDemoActive_", "assistUsed_",
})
own("report", {
    "resultReportState_", "resultReportClearCounts_", "resultReportHistory_", "resultReportNextId_",
    "resultReportAnimation_", "resultReportClosing_",
})

local function refreshModes(domains)
    local experiment = domains.experiment
    if experiment.failed_ then
        experiment.mode = "failed"
    elseif experiment.success_ then
        experiment.mode = "success"
    elseif experiment.absorbing_ then
        experiment.mode = "absorbing"
    elseif experiment.isPaused_ then
        experiment.mode = "paused"
    elseif experiment.launched_ then
        experiment.mode = "launched"
    elseif experiment.draggedApple_ then
        experiment.mode = "aiming"
    else
        experiment.mode = "ready"
    end

    local cards = domains.cards
    if next(cards.burningCardIds_ or {}) then
        cards.mode = "burning"
    elseif cards.primedCardId_ then
        cards.mode = "parameter"
    elseif cards.activeCardDeploying_ then
        cards.mode = "deploying"
    elseif cards.activeCardId_ then
        cards.mode = "pressed"
    else
        cards.mode = "idle"
    end

    domains.replay.mode = domains.replay.replayMode_ or "none"
    domains.replay.businessMode = domains.replay.replayBusinessMode_ or 0
end

---@return GameContext
function State.New(dependencies, constants)
    local domains = {
        runtime = {}, layout = {}, experiment = {}, goal = {}, mechanisms = {}, input = {}, cards = {}, replay = {},
        assistant = {}, report = {},
    }
    ---@type GameContext
    local context = {}
    setmetatable(context, {
        __index = function(_, key)
            local owner = OWNERS[key]
            if owner then
                local snapshot = rawget(context, "__snapshot")
                if snapshot then return snapshot[key] end
                return domains[owner][key]
            end
            local value = dependencies[key]
            if value ~= nil then return value end
            value = constants[key]
            if value ~= nil then return value end
            return _G[key]
        end,
        __newindex = function(target, key, value)
            local owner = OWNERS[key]
            if owner then
                if rawget(context, "__snapshot") then error("GameSnapshot is read-only: " .. key) end
                domains[owner][key] = value
                refreshModes(domains)
            else
                rawset(target, key, value)
            end
        end,
    })
    rawset(context, "domains", domains)

    context.scene_, context.camera_, context.viewport_, context.physicsWorld_ = nil, nil, nil, nil
    context.level_, context.physicsProfile_, context.runtime_, context.laboratoryBoundaries_ = nil, nil, nil, nil
    context.apple_, context.applePreSolveVelocity_, context.pendingMatterRestitutions_, context.physicsStepTimeScale_ = nil, nil, nil, nil
    context.mapper_, context.frame_, context.audio_ = nil, nil, nil
    context.levelIndex_ = 1
    context.design_ = dependencies.DesignSpace.New(constants.CONFIG.pixelsPerMeter)
    context.painter_ = nil
    context.rules_ = dependencies.Rules.NewState()
    context.draggedApple_, context.aimPreview_ = false, nil
    context.activeCardId_, context.activeCardStart_, context.activeCardPointer_ = nil, nil, nil
    context.activeCardDragged_, context.activeCardDeploying_ = false, false
    context.activeCardPressedAt_, context.activeCardPressPose_, context.primedCardId_ = nil, nil, nil
    context.cardParameterStart_, context.cardDeployEnteredMs_, context.cardLastMotionAtMs_ = nil, nil, nil
    context.cardPointerSamples_, context.cardCandidate_, context.cardGestureDistance_ = {}, nil, 0
    context.hoveredCardId_, context.cardHoverStates_ = nil, {}
    context.hoveredLevelIndex_, context.hoveredNavigation_, context.punchHovered_ = nil, nil, false
    context.pointer_ = { activeTouchId = nil, touchX = 0, touchY = 0, touchPressed = false, touchReleased = false }
    context.launched_, context.goalContact_, context.goalContactMs_, context.goalEntryRecorded_ = false, false, 0, false
    context.goalContactEventSeen_, context.goalContactEndSeen_ = false, false
    context.goalContactConfirmed_, context.goalContactMissSteps_ = false, 0
    context.goalPulseElapsedMs_, context.outsideMs_, context.flightMs_ = nil, 0, 0
    context.status_, context.isPaused_, context.bulletTimeActive_, context.debugDraw_ = "READY · 等待发射", false, false, false
    context.success_, context.failed_, context.absorbing_, context.absorbElapsedMs_ = false, false, false, 0
    context.assistedClear_ = false
    context.failureCount_, context.failureCountsByLevel_, context.observation_ = 0, {}, ""
    context.replayActive_, context.replayTime_, context.replayPaused_, context.replaySpeed_ = false, 0, false, 1
    context.replayFinished_, context.replaySamples_, context.replayEvents_, context.replaySavedApple_ = false, {}, {}, nil
    context.replayMode_, context.replayNextSampleMs_, context.replayPreviousSample_ = "none", 0, nil
    context.replayBusinessMode_ = dependencies.ReplayMode and dependencies.ReplayMode.NONE or 0
    context.greenAssistant_, context.greenAssistantAdapter_ = nil, nil
    context.assistDemoRunner_, context.assistDemoGameAdapter_, context.assistDemoView_ = nil, nil, nil
    context.assistantInputLocked_, context.assistSceneActive_ = false, false
    context.assistDemoActive_, context.assistUsed_ = false, false
    context.resultReportState_, context.resultReportClearCounts_, context.resultReportHistory_ = nil, {}, { einstein = {}, green = {} }
    context.resultReportNextId_, context.resultReportAnimation_, context.resultReportClosing_ = 0, 0, nil
    context.trail_, context.lastTrailAt_, context.sensorAngle_, context.uiElapsed_, context.anger_ = {}, 0, 0, 0, 0
    context.phaseTraversing_, context.phaseWallTraversal_, context.stalledMs_, context.channelStates_ = false, nil, 0, {}
    context.cardStates_, context.cardDeckById_, context.handOrder_ = {}, {}, {}
    context.cardHomeMotions_, context.cardHandReordering_ = {}, false
    context.cardBurns_, context.cardBurnParticles_, context.burningCardIds_ = {}, {}, {}
    context.rulePulse_, context.ruleFlash_, context.ruleDeployCount_ = nil, nil, 0
    refreshModes(domains)
    return context
end

function State.BeginGameSnapshot(context)
    assert(rawget(context, "__snapshot") == nil, "GameSnapshot is already active")
    local snapshot = { modes = {} }
    local domains = rawget(context, "domains")
    refreshModes(domains)
    for key, owner in pairs(OWNERS) do snapshot[key] = domains[owner][key] end
    for name, domain in pairs(domains) do snapshot.modes[name] = domain.mode end
    rawset(context, "__snapshot", snapshot)
    return snapshot
end

function State.EndGameSnapshot(context)
    rawset(context, "__snapshot", nil)
end

return State
