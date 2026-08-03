-- level/LevelSession: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local LevelData = context.LevelData
    local DesignSpace = context.DesignSpace
    local Rules = context.Rules
    local PhysicsProfiles = context.PhysicsProfiles
    local CoordinateMapper = context.CoordinateMapper
    local SynthAudio = context.SynthAudio
    local RuntimeFactory = context.RuntimeFactory
    local MatterCalibration = context.MatterCalibration
    local CONFIG = context.CONFIG
    local LEVEL_META = context.LEVEL_META
    local _ENV = context
    function LoadLevel(index)
        index = math.max(1, math.min(CONFIG.levelCount, index))
        local resource = string.format("Data/Levels/level_%02d.json", index)
        local level, err = LevelData.Load(resource)
        if not level then error(err) end
        local meta = LEVEL_META[level.levelId]
        if meta then
            level.name = meta.name
            level.objective = meta.objective
            level.observation = meta.observation
        end
        levelIndex_ = index
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
        renderer:SetViewport(0, viewport_)
    end

    function ResetSessionState(isFreshLevel)
        rules_ = Rules.NewState()
        InitializeCards()
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
        pendingMatterRestitutions_ = nil
        physicsStepTimeScale_ = nil
        goalPulseElapsedMs_, phaseTraversing_ = nil, false
        success_, failed_, absorbing_, absorbElapsedMs_ = false, false, false, 0
        assistedClear_ = false
        assistSceneActive_ = false
        level_.resultOverlayVisible = false
        SetReplayMode("none")
        replayTime_, replaySpeed_ = 0, 1
        replaySamples_, replayEvents_, replaySavedApple_ = {}, {}, nil
        replayNextSampleMs_, replayPreviousSample_ = 0, nil
        cardBurns_, cardBurnParticles_, burningCardIds_ = {}, {}, {}
        rulePulse_, ruleFlash_, ruleDeployCount_ = nil, nil, 0
        trail_, lastTrailAt_, anger_ = {}, 0, 0
        if isFreshLevel then sensorAngle_, uiElapsed_ = 0, 0 end
        RestoreAppleContactMaterial()
        if InitializeMechanisms then InitializeMechanisms() end
        SetGravity()
        SyncPhysicsUpdateEnabled()
        SetStatus("READY · 等待发射")
    end

    function BuildLevel(index)
        level_ = LoadLevel(index)
        physicsProfile_ = PhysicsProfiles.Resolve(level_.physicsProfile)
        failureCount_ = context.failureCountsByLevel_[level_.levelId] or 0
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
        SetupViewport()
        laboratoryBoundaries_ = RuntimeFactory.CreateLaboratoryBoundaries(
            scene_, mapper_, LevelData.PLAYFIELD_GROUND_Y, physicsProfile_.boundaries
        )
        runtime_ = RuntimeFactory.CreateLevelObjects({ scene = scene_, mapper = mapper_ }, level_)
        local launcher = LevelData.FindFirst(level_, "launcher")
        if not launcher then error("关卡缺少发射器") end
        local launcherRuntime = runtime_.byId[launcher.id]
        apple_ = RuntimeFactory.CreateApple(scene_, launcherRuntime)
        level_.physicsProbe = require("game.physics.Probe").New()
        ResetSessionState(true)
        NotifyGreenAssistantLevelChanged(level_.levelId)
        context.NotifyDialogueLevelReady(level_.levelId)
    end
    function ResetExperiment(playResetSound)
        if not apple_ or not level_ then return end
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

    function CompleteLevel(result)
        result = result or {}
        local assisted = result.assisted == true
        success_, failed_, absorbing_, launched_ = true, false, false, false
        assistedClear_ = assisted
        if level_ then
            level_.assistedClear = assisted
            level_.resultOverlayVisible = true
        end
        if apple_ and apple_.body then
            apple_.body.bodyType = BT_STATIC
            apple_.body.linearVelocity = Vector2(0, 0)
            apple_.body.angularVelocity = 0
        end
        ClearCardInteraction()
        SyncPhysicsUpdateEnabled()
        SetStatus(assisted and "ASSISTED CLEAR · 辅助观测成立" or "CLEARED · 观测成立")
        if assisted then PlaySound("success") end
    end
end

return M
