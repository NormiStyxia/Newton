-- level/LevelSession: private runtime functions installed into the App context.
local M = {}
local WallImpactShake = require("game.render.WallImpactShake")
local NewtonPunchShake = require("game.render.NewtonPunchShake")

---@param context GameContext
function M.Install(context)
    local LevelData = context.LevelData
    local LevelPresentation = context.LevelPresentation
    local DesignSpace = context.DesignSpace
    local Rules = context.Rules
    local PhysicsProfiles = context.PhysicsProfiles
    local CoordinateMapper = context.CoordinateMapper
    local SynthAudio = context.SynthAudio
    local RuntimeFactory = context.RuntimeFactory
    local MatterCalibration = context.MatterCalibration
    local PhaseWallEffects = context.PhaseWallEffects
    local CONFIG = context.CONFIG
    local LEVEL_META = context.LEVEL_META
    local LEVEL_SCORE_PROFILES = context.LEVEL_SCORE_PROFILES
    local DEFAULT_LEVEL_SCORE_PROFILE = context.DEFAULT_LEVEL_SCORE_PROFILE
    local experimentProgress_ = context.experimentProgress_
    local newtonPunchShake_ = context.newtonPunchShake_
    local _ENV = context

    function IsOfficialRuntimeSession()
        return runtimeSession_ ~= nil and runtimeSession_.sourceKind == "official"
    end

    function RuntimeLevelStateKey()
        local levelId = runtimeSession_ and runtimeSession_.levelId or level_ and level_.levelId or "unknown"
        if IsOfficialRuntimeSession() then return levelId end
        return "custom:" .. tostring(levelId)
    end

    function LoadLevelDefinition(index)
        index = math.max(1, math.min(CONFIG.levelCount, index))
        local resource = string.format("Data/Levels/level_%02d.json", index)
        local level, err = LevelData.Load(resource)
        if not level then error(err) end
        local meta = LEVEL_META[level.levelId]
        LevelPresentation.Apply(level, meta, LEVEL_SCORE_PROFILES, DEFAULT_LEVEL_SCORE_PROFILE)
        return level, index
    end
    function LoadLevel(index)
        local level, resolvedIndex = LoadLevelDefinition(index)
        levelIndex_ = resolvedIndex
        return level
    end
    function CreateScene()
        scene_ = Scene()
        scene_:CreateComponent("Octree")
        scene_:CreateComponent("DebugRenderer")
        physicsWorld_ = scene_:CreateComponent("PhysicsWorld2D")
        physicsWorld_:SetVelocityIterations(8)
        physicsWorld_:SetPositionIterations(10)
        -- Phaser Matter runs this scene with sleeping disabled. Leaving Box2D's
        -- default enabled makes low-speed slide/contact outcomes frame-dependent.
        physicsWorld_:SetAllowSleeping(false)
        -- Matter uses discrete contacts. Its 25 px/frame source speed cap keeps
        -- the apple within the fixtures' contact range without Box2D CCD.
        physicsWorld_:SetContinuousPhysics(physicsProfile_.continuousPhysics)
        physicsWorld_:SetAutoClearForces(true)
        SetGravity()
    end
    function SetupViewport()
        if not scene_ then return end
        local cameraNode = scene_:CreateChild("Camera")
        camera_ = cameraNode:CreateComponent("Camera")
        camera_:SetOrthographic(true)
        camera_:SetOrthoSize(DesignSpace.LAB.height / CONFIG.pixelsPerMeter)
        cameraNode.position = Vector3(0, 0, -10)
        viewport_ = Viewport:new(scene_, camera_)
        renderer:SetNumViewports(1)
        renderer:SetViewport(0, viewport_)
    end

    function ReleaseLevelRuntime()
        if assistSceneActive_ and context.AbortGreenAssistantTakeover then
            context.AbortGreenAssistantTakeover("leave-level")
        end
        if level_ and level_.physicsProbe then level_.physicsProbe:Stop({ apple = apple_ }) end
        if ClearResultReportState then ClearResultReportState() end
        if SetReplayMode then SetReplayMode("none") end
        WallImpactShake.ResetRuntime(runtime_)
        NewtonPunchShake.Reset(newtonPunchShake_)
        if scene_ then scene_:SetUpdateEnabled(false) end
        renderer:SetNumViewports(0)
        if audio_ then
            if context.audioManager_ then context.audioManager_:DetachSfx(audio_) end
            audio_.scene = nil
        end
        if scene_ then scene_:Dispose() end
        if runtimeSession_ then runtimeSession_.disposed = true end
        scene_, camera_, viewport_, physicsWorld_ = nil, nil, nil, nil
        runtime_, laboratoryBoundaries_, apple_, mapper_, audio_ = nil, nil, nil, nil, nil
        physicsProfile_, level_, runtimeSession_ = nil, nil, nil
        assistantInputLocked_, assistSceneActive_, assistDemoActive_ = false, false, false
        ClearCardInteraction()
        ClearSelectedCard()
        return true
    end

    function ResetSessionState(isFreshLevel)
        if ClearResultReportState then ClearResultReportState() end
        rules_ = Rules.NewState()
        InitializeCards()
        ClearSelectedCard()
        observation_ = level_.observation or ""
        draggedApple_, aimPreview_ = false, nil
        activeCardId_, primedCardId_ = nil, nil
        isPaused_, bulletTimeActive_ = false, false
        activeCardStart_, activeCardPointer_ = nil, nil
        activeCardDragged_, activeCardDeploying_ = false, false
        activeCardPressedAt_ = nil
        if isFreshLevel then activeCardPressPose_ = nil end
        cardParameterStart_, cardDeployEnteredMs_, cardLastMotionAtMs_ = nil, nil, nil
        cardPointerSamples_, cardCandidate_, cardGestureDistance_ = {}, nil, 0
        launched_, goalContact_, goalEntryRecorded_ = false, false, false
        goalContactMs_, outsideMs_, flightMs_, stalledMs_ = 0, 0, 0, 0
        goalContactEventSeen_, goalContactEndSeen_ = false, false
        goalContactConfirmed_, goalContactMissSteps_ = false, 0
        applePreSolveVelocity_ = nil
        appleSupportNormal_ = nil
        pendingMatterRestitutions_ = nil
        physicsStepTimeScale_ = nil
        goalPulseElapsedMs_, phaseTraversing_, phaseWallTraversal_ = nil, false, nil
        phasePreviousX_, phasePreviousY_ = nil, nil
        success_, failed_, absorbing_, absorbElapsedMs_ = false, false, false, 0
        assistedClear_ = false
        assistSceneActive_ = false
        assistDemoActive_ = false
        assistUsed_ = false
        level_.resultOverlayVisible = false
        SetReplayMode("none")
        replayTime_, replaySpeed_ = 0, 1
        replaySamples_, replayEvents_, replaySavedApple_ = {}, {}, nil
        replayNextSampleMs_, replayPreviousSample_ = 0, nil
        cardBurns_, cardBurnParticles_, burningCardIds_ = {}, {}, {}
        rulePulse_, ruleFlash_, ruleDeployCount_ = nil, nil, 0
        NewtonPunchShake.Reset(newtonPunchShake_)
        trail_, lastTrailAt_, anger_ = {}, 0, 0
        if isFreshLevel then sensorAngle_, uiElapsed_ = 0, 0 end
        RestoreAppleContactMaterial()
        if InitializeMechanisms then InitializeMechanisms() end
        SetGravity()
        -- SetGravity reevaluates buttons, so snap doors only after final targets settle.
        if SnapDoorsToTargets then SnapDoorsToTargets() end
        SyncPhysicsUpdateEnabled()
        SetStatus("READY · 等待发射")
        if context.ResetTutorialForLevel then context.ResetTutorialForLevel(level_.levelId) end
    end

    ---@param document table
    ---@param options table|nil
    ---@return table|nil session
    ---@return string|nil errorMessage
    function StartRuntimeSessionFromDocument(document, options)
        options = options or {}
        if scene_ or level_ then ReleaseLevelRuntime() end
        local normalized, migrations = LevelData.Normalize(document)
        local valid, errors = LevelData.Validate(normalized)
        if not valid then return nil, table.concat(errors, "；") end

        -- Runtime identity is granted by the launch path, never by level JSON.
        -- Unknown/legacy launch kinds are treated as custom by default.
        local sourceKind = options.sourceKind == "official" and "official" or "custom"
        level_ = normalized
        if options.levelIndex ~= nil then levelIndex_ = tonumber(options.levelIndex) or levelIndex_ end
        runtimeSession_ = {
            levelId = level_.levelId,
            levelIndex = sourceKind == "official" and levelIndex_ or nil,
            sourceKind = sourceKind,
            screen = options.screen or "game",
            originLevelId = sourceKind == "custom" and level_.originLevelId or nil,
            customLevelId = sourceKind == "custom" and level_.levelId or nil,
            migrations = migrations,
            disposed = false,
        }
        LevelPresentation.Apply(level_, sourceKind == "official" and LEVEL_META[level_.levelId] or nil,
            LEVEL_SCORE_PROFILES, DEFAULT_LEVEL_SCORE_PROFILE)
        physicsProfile_ = PhysicsProfiles.Resolve(level_.physicsProfile)
        failureCount_ = context.failureCountsByLevel_[RuntimeLevelStateKey()] or 0
        observation_ = level_.observation or ""
        mapper_ = CoordinateMapper.New({
            levelWidth = level_.playfield.width,
            levelHeight = level_.playfield.height,
            viewportWidth = DesignSpace.LAB.width,
            viewportHeight = DesignSpace.LAB.height,
            pixelsPerMeter = CONFIG.pixelsPerMeter,
        })
        CreateScene()
        audio_ = SynthAudio.New(scene_)
        if context.audioManager_ then context.audioManager_:AttachSfx(audio_) end
        SetupViewport()
        laboratoryBoundaries_ = RuntimeFactory.CreateLaboratoryBoundaries(
            scene_, mapper_, LevelData.PLAYFIELD_GROUND_Y, physicsProfile_.boundaries
        )
        runtime_ = RuntimeFactory.CreateLevelObjects({ scene = scene_, mapper = mapper_ }, level_)
        local launcher = LevelData.FindFirst(level_, "launcher")
        if not launcher then error("关卡缺少发射器") end
        local launcherRuntime = runtime_.byId[launcher.id]
        apple_ = RuntimeFactory.CreateApple(scene_, launcherRuntime)
        if options.enablePhysicsProbe ~= false then level_.physicsProbe = require("game.physics.Probe").New() end
        ResetSessionState(true)
        screen_ = runtimeSession_.screen
        RefreshHUDSummary()
        if IsOfficialRuntimeSession() and options.notifyAssistant ~= false then
            NotifyGreenAssistantLevelChanged(level_.levelId)
        else
            NotifyGreenAssistantLevelChanged(nil)
        end
        if context.NotifyTutorialLevelReady then context.NotifyTutorialLevelReady(level_.levelId) end
        if IsOfficialRuntimeSession() and options.notifyDialogue ~= false then
            context.NotifyDialogueLevelReady(level_.levelId)
        else
            context.NotifyDialogueLevelReady(nil)
        end
        return runtimeSession_, nil
    end

    function GetRuntimeSession()
        return runtimeSession_
    end

    function BuildLevel(index)
        local document, resolvedIndex = LoadLevelDefinition(index)
        levelIndex_ = resolvedIndex
        local session, errorMessage = StartRuntimeSessionFromDocument(document, {
            sourceKind = "official",
            screen = "game",
            levelIndex = resolvedIndex,
            enablePhysicsProbe = true,
            notifyAssistant = true,
            notifyDialogue = true,
        })
        if not session then error(errorMessage) end
        return session
    end
    function ResetExperiment(playResetSound)
        if not apple_ or not level_ then return end
        -- A manual refresh after launch ends the current attempt. Count it as
        -- a failure before the reset clears the transient experiment state.
        if launched_ and not assistDemoActive_ then
            CaptureReplayFinalSample()
            failed_ = true
            launched_ = false
            apple_.body.bodyType = BT_STATIC
            RegisterFailure("MANUAL_RESET")
        end
        if level_.physicsProbe then
            level_.physicsProbe:Stop({ apple = apple_ })
        end
        if playResetSound ~= false then PlaySound("reset") end
        apple_.body.bodyType = BT_STATIC
        apple_.body.linearVelocity = Vector2(0, 0)
        apple_.body.angularVelocity = 0
        apple_.node:SetPosition2D(apple_.launcher.spawnWorldX, apple_.launcher.spawnWorldY)
        apple_.node:SetRotation2D(0)
        apple_.body.awake = true
        apple_.body.linearDamping = MatterCalibration.Box2DLinearDamping(apple_.baseFrictionAir)
        apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping(apple_.baseFrictionAir)
        apple_.shape.restitution = MatterCalibration.APPLE_INITIAL_RESTITUTION
        apple_.shape.trigger = false
        if runtime_ then
            PhaseWallEffects.ResetRuntime(runtime_)
            WallImpactShake.ResetRuntime(runtime_)
            NewtonPunchShake.Reset(newtonPunchShake_)
            for _, object in ipairs(runtime_.ordered) do
                object.contactMs = 0
                if object.type == "goal_sensor" then
                    object.active = false
                    object.contactProgress = 0
                elseif object.type == "spring" then
                    object.spent = false
                    object.triggeredAt = -math.huge
                    object.pendingExitVelocity = nil
                    object.pulseElapsedMs = nil
                end
            end
        end
        ResetSessionState(false)
    end

    function RecordOfficialExperimentProgress(assisted, reportState)
        if assisted == true or not experimentProgress_ or not level_
            or not IsOfficialRuntimeSession() then
            return nil, nil
        end
        local scoreSummary = LevelPresentation.BuildResultSummary(level_.scoring, ruleDeployCount_)
        local reportSnapshot = BuildResultReportSnapshot and BuildResultReportSnapshot(reportState) or nil
        local progressRecord, progressError = experimentProgress_:Record(
            level_.levelId, scoreSummary and scoreSummary.score, reportSnapshot)
        if not progressRecord then
            print(string.format("[ExperimentProgress] record failed for %s: %s",
                tostring(level_.levelId), tostring(progressError)))
        elseif progressRecord.persistenceError then
            print(string.format("[ExperimentProgress] local save unavailable for %s: %s",
                tostring(level_.levelId), tostring(progressRecord.persistenceError)))
        elseif progressRecord.snapshotError then
            print(string.format("[ExperimentProgress] report snapshot skipped for %s: %s",
                tostring(level_.levelId), tostring(progressRecord.snapshotError)))
        end
        return progressRecord, progressError
    end

    function CompleteLevel(result)
        result = result or {}
        local assisted = result.assisted == true
        success_, failed_, absorbing_, launched_ = true, false, false, false
        assistedClear_ = assisted
        if level_ then
            level_.assistedClear = assisted
            level_.resultOverlayVisible = true
        end
        local reportState = nil
        if assisted then
            if ClearResultReportState then ClearResultReportState() end
            isPaused_ = true
        elseif GenerateResultReport then
            reportState = GenerateResultReport()
        end
        RecordOfficialExperimentProgress(assisted, reportState)
        if apple_ and apple_.body then
            apple_.body.bodyType = BT_STATIC
            apple_.body.linearVelocity = Vector2(0, 0)
            apple_.body.angularVelocity = 0
        end
        ClearCardInteraction()
        ClearSelectedCard()
        SyncPhysicsUpdateEnabled()
        SetStatus(assisted and "ASSISTED CLEAR · 辅助观测成立" or "CLEARED · 观测成立")
        if assisted then PlaySound("success") end
    end
end

return M
