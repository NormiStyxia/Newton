-- Domain-owned mutable state exposed through a private compatibility environment.
---@class GameContext
---@field State any
---@field LevelData any
---@field LevelDocument any
---@field LevelPresentation any
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
---@field GlobalBGM any
---@field AudioManager any
---@field TrajectoryPrediction any
---@field ReplayTimeline any
---@field ReplayFeed any
---@field ReplayMode any
---@field PhaseWallEffects any
---@field ExperimentProgress any
---@field CatalogTransition any
---@field CONFIG table
---@field CARD_DESIGN_WIDTH number
---@field CARD_DESIGN_HEIGHT number
---@field CARD_TEXT_SCALE number
---@field CARD_RENDER_WIDTH number
---@field CARD_RENDER_HEIGHT number
---@field GOAL_CONTACT_SKIN number
---@field LEVEL_META table
---@field LEVEL_SCORE_PROFILES table
---@field DEFAULT_LEVEL_SCORE_PROFILE string
---@field design_ any
---@field debugDraw_ boolean
---@field failureCountsByLevel_ table<string, integer>
---@field assistantInputLocked_ boolean
---@field assistSceneActive_ boolean
---@field assistDemoActive_ boolean
---@field assistUsed_ boolean
---@field pointer_ table
---@field dialogueController_ table|nil
---@field InitializeDialogue fun()
---@field DestroyDialogue fun()
---@field NotifyDialogueLevelReady fun(levelId: string)
---@field UpdateDialogue fun(dt: number, pointerFrame: table): boolean
---@field DrawDialogueHistoryButton fun()
---@field DrawDialogueOverlay fun()
---@field InitializeAssistDemo fun()
---@field DestroyAssistDemo fun()
---@field StartAssistDemo fun(solution: table): boolean, string|nil
---@field UpdateAssistDemo fun(dt: number)
---@field UpdateAssistDemoPhysicsStep fun(dt: number)
---@field AdvanceAssistDemoSimulation fun(dt: number): integer
---@field DrawAssistDemo fun()
---@field GetAssistDemoState fun(): string
---@field GetAssistDemoError fun(): string|nil
---@field IsAssistDemoFinished fun(): boolean
---@field FinishAssistDemo fun(): boolean
---@field AbortAssistDemo fun(reason: string|nil): boolean
---@field AbortGreenAssistantTakeover fun(reason: string|nil): boolean
---@field DrawGreenAssistantOverlay fun()
---@field ExecuteCardPlay fun(id: string, candidate: string|nil, x: number, y: number): boolean
---@field resultReportState_ table|nil
---@field screen_ "title"|"title_catalog_transition"|"catalog"|"game"|"workshop"|"workshop_preview"
---@field titleState_ table
---@field navigationTransition_ table
---@field runtimeSession_ table|nil
---@field catalogState_ table
---@field experimentProgress_ table
---@field globalBGM_ GlobalBGM
---@field uiAudio_ SynthAudio
---@field audioManager_ AudioManager
---@field playUIClick fun()
---@field playBGM fun(path: string, options?: BGMOptions): boolean
---@field stopBGM fun()
---@field setBGMVolume fun(volume: number)
---@field setSFXVolume fun(volume: number)
---@field setBGMMuted fun(muted: boolean)
---@field setSFXMuted fun(muted: boolean)
---@field setMusicContext fun(context: string, options?: table): boolean
---@field enterPreview fun(): boolean
---@field nextTrack fun(): boolean
---@field previousTrack fun(): boolean
---@field selectTrack fun(trackId: string): boolean
---@field getCurrentTrack fun(): table|nil
---@field getCurrentTrackTitle fun(): string
---@field showNowPlaying fun(title: string): boolean
---@field saveAudioSettings fun(): boolean
---@field loadAudioSettings fun(): boolean
---@field RecordOfficialExperimentProgress fun(assisted: boolean|nil, reportState: table|nil): table|nil, string|nil
---@field workshopState_ table
---@field hudRuleSummary_ string
---@field hudRuleList_ table
---@field hudObjectiveText_ string
---@field hudExpectedScore_ integer|nil
---@field hudInterventionCount_ integer
---@field hudDropdown_ string|nil
---@field hudEscapeConsumed_ boolean
local State = {}

local OWNERS = {}

local function own(domain, names)
    for _, name in ipairs(names) do OWNERS[name] = domain end
end

own("runtime", {
    "scene_", "camera_", "viewport_", "physicsWorld_", "level_", "physicsProfile_", "runtime_", "runtimeSession_",
    "laboratoryBoundaries_", "apple_", "applePreSolveVelocity_", "appleSupportNormal_", "pendingMatterRestitutions_", "physicsStepTimeScale_", "mapper_", "audio_", "levelIndex_",
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
own("input", { "pointer_", "hoveredNavigation_", "punchHovered_" })
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
own("navigation", {
    "screen_", "navigationTransition_", "catalogState_", "hudRuleSummary_", "hudRuleList_", "hudObjectiveText_",
    "hudExpectedScore_", "hudInterventionCount_", "hudDropdown_", "hudEscapeConsumed_",
})
own("progress", { "experimentProgress_" })
own("appAudio", { "audioManager_", "globalBGM_", "uiAudio_" })
own("workshop", { "workshopState_" })

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
        assistant = {}, report = {}, navigation = {}, progress = {}, appAudio = {}, workshop = {},
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
    context.level_, context.physicsProfile_, context.runtime_, context.runtimeSession_, context.laboratoryBoundaries_ = nil, nil, nil, nil, nil
    context.apple_, context.applePreSolveVelocity_, context.appleSupportNormal_ = nil, nil, nil
    context.pendingMatterRestitutions_, context.physicsStepTimeScale_ = nil, nil
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
    context.hoveredNavigation_, context.punchHovered_ = nil, false
    context.pointer_ = {
        activeTouchId = nil,
        pauseTouchId = nil,
        touchX = 0,
        touchY = 0,
        touchPressed = false,
        touchReleased = false,
        stagePointerCaptured = nil,
    }
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
    context.screen_ = "title"
    local catalogTransition = dependencies.CatalogTransition
        or require("ui.ExperimentCatalogTransition")
    context.navigationTransition_ = catalogTransition.NewEntrance()
    context.titleState_ = {
        selectedIndex = 1,
        focusIndex = 1,
        hoverIndex = nil,
        pressedIndex = nil,
        hoverCharacter = nil,
        selectionProgress = { 1, 0, 0, 0 },
        settingsOpen = false,
        settingsDrag = nil,
        settingsDismissPointerCaptured = false,
        -- Legacy aliases remain for old UI callers; AudioManager owns the
        -- canonical BGM/SFX values and the two independent mute flags.
        musicVolume = .4,
        soundVolume = .55,
        bgmVolume = .4,
        sfxVolume = .55,
        bgmMuted = false,
        sfxMuted = false,
        muted = false,
        academyIdCardCharacter = nil,
        academyIdCardElapsed = 0,
        profileMode = "TITLE_IDLE",
        profileElapsed = 0,
        profileCharacterId = nil,
        profileSketchElapsed = 0,
        profileBackHover = false,
        profileBackHoverProgress = 0,
        profileBackPressed = false,
    }
    context.experimentProgress_ = dependencies.ExperimentProgress.New({ json = cjson })
    if dependencies.AudioManager then
        context.audioManager_ = dependencies.AudioManager.New({
            bgm = dependencies.GlobalBGM and dependencies.GlobalBGM.New() or nil,
            uiAudio = dependencies.SynthAudio and dependencies.SynthAudio.New() or nil,
            json = dependencies.json or _G.cjson,
        })
        context.globalBGM_ = context.audioManager_.bgm
        context.uiAudio_ = context.audioManager_.uiAudio
    else
        context.audioManager_ = nil
        context.globalBGM_ = dependencies.GlobalBGM and dependencies.GlobalBGM.New() or nil
        context.uiAudio_ = dependencies.SynthAudio and dependencies.SynthAudio.New() or nil
    end
    if context.audioManager_ then
        context.titleState_.bgmVolume = context.audioManager_.bgmVolume
        context.titleState_.sfxVolume = context.audioManager_.sfxVolume
        context.titleState_.musicVolume = context.titleState_.bgmVolume
        context.titleState_.soundVolume = context.titleState_.sfxVolume
        context.titleState_.bgmMuted = context.audioManager_.bgmMuted
        context.titleState_.sfxMuted = context.audioManager_.sfxMuted
        context.titleState_.muted = context.titleState_.bgmMuted and context.titleState_.sfxMuted
    end
    context.catalogState_ = {
        selectedIndex = 1,
        levels = {},
        scroll = 0,
        scrollMax = 0,
        dragStartY = nil,
        dragStartScroll = 0,
        toast = nil,
        toastTime = 0,
        hoverTooltip = nil,
        reportSnapshot = nil,
        reportSnapshotAnimation = 0,
        reportSnapshotClosing = false,
        headerBackPressed = false,
    }
    context.workshopState_ = {
        initialized = false,
        returnScreen = "catalog",
        elapsed = 0,
        autoSaveDelay = 1.0,
        autoSaveDue = nil,
        lastDraftSaveAt = nil,
        repository = nil,
        history = nil,
        draftStore = nil,
        persistenceKind = "memory-only",
        entries = {},
        initializationErrors = {},
        supportedTypes = {},
        entryId = nil,
        metadata = nil,
        document = nil,
        readOnly = true,
        dirty = false,
        selectedObjectId = nil,
        selectedObject = nil,
        view = {
            zoom = 1, panX = 0, panY = 0,
            showGrid = true, snap = true, gridSize = 10, angleSnap = 15,
            fileScroll = 0, inspectorScroll = 0, drawerMode = "files",
        },
        layoutConfig = {},
        layout = nil,
        controls = {},
        inspectorFields = {},
        validation = { valid = false, errors = {}, warnings = {} },
        canUndo = false,
        canRedo = false,
        transaction = nil,
        touchScroll = nil,
        textEdit = nil,
        modal = nil,
        previewSnapshot = nil,
        status = "关卡工坊尚未打开",
        toast = nil,
        toastTime = 0,
    }
    context.hudRuleSummary_, context.hudRuleList_ = "经典场地", {}
    context.hudObjectiveText_, context.hudExpectedScore_, context.hudInterventionCount_ = "", nil, 0
    context.hudDropdown_, context.hudEscapeConsumed_ = nil, false
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
