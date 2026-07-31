-- AppRuntime: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local WorkspaceLayout = context.WorkspaceLayout
    local MatterCalibration = context.MatterCalibration
    local Renderer2D = context.Renderer2D
    local ReplayMode = context.ReplayMode
    local State = context.State
    local CONFIG = context.CONFIG
    local CARD_RENDER_WIDTH = context.CARD_RENDER_WIDTH
    local CARD_RENDER_HEIGHT = context.CARD_RENDER_HEIGHT
    local _ENV = context
    function RefreshWorkspaceLayout()
        if not frame_ then return end
        local entries = CardEntries and CardEntries() or {}
        local poses = Rules.CardHand(#entries,
            frame_.playfieldX + frame_.playfieldWidth * 0.5,
            frame_.cardHandY,
            frame_.playfieldWidth)
        WorkspaceLayout.Apply(frame_, poses, CARD_RENDER_WIDTH, CARD_RENDER_HEIGHT)
    end

    function Start()
        graphics.windowTitle = CONFIG.title
        painter_ = Renderer2D.New()
        frame_ = context.design_:Frame()
        InitializeGreenAssistant()
        BuildLevel(1)
        RefreshWorkspaceLayout()
        SubscribeToEvent("Update", "HandleUpdate")
        SubscribeToEvent("ScreenMode", "HandleScreenMode")
        SubscribeToEvent("TouchBegin", "HandleTouchBegin")
        SubscribeToEvent("TouchMove", "HandleTouchMove")
        SubscribeToEvent("TouchEnd", "HandleTouchEnd")
        SubscribeToEvent("PhysicsPreStep", "HandlePhysicsPreStep")
        SubscribeToEvent("PhysicsPostStep", "HandlePhysicsPostStep")
        SubscribeToEvent("PhysicsBeginContact2D", "HandleCollisionBegin")
        SubscribeToEvent("PhysicsUpdateContact2D", "HandleCollisionUpdate")
        SubscribeToEvent("PhysicsEndContact2D", "HandleCollisionEnd")
        SubscribeToEvent(painter_.vg, "NanoVGRender", "HandleRender")
        print("[Migration] 1:1 design-space runtime started")
    end
    function Stop()
        if level_ and level_.physicsProbe then level_.physicsProbe:Stop({ apple = apple_ }) end
        DestroyGreenAssistant()
        if painter_ then painter_:Destroy(); painter_ = nil end
    end

    ---@param _eventType string
    ---@param eventData UpdateEventData
    function HandleUpdate(_eventType, eventData)
        local dt = eventData:GetFloat("TimeStep")
        if audio_ then audio_:Update(dt) end
        uiElapsed_ = uiElapsed_ + dt
        UpdateRuleFeedback(dt)
        frame_ = context.design_:Frame()
        RefreshWorkspaceLayout()
        -- Sample once, then give the screen-space Companion first chance to
        -- apply a rigid drag before its animation/update and before rendering.
        local pointerFrame = PointerState()
        local assistantPointerConsumed = HandleGreenAssistantPointer(pointerFrame.x, pointerFrame.y, pointerFrame)
        UpdateGreenAssistant(dt)
        -- Replay owns the input/update frame. Do not let cards, reset shortcuts,
        -- or normal completion updates mutate the suspended experiment.
        if replayActive_ then
            HandlePointer(pointerFrame, assistantPointerConsumed)
            if replayBusinessMode_ == ReplayMode.PLAYER_REPLAY and input:GetKeyPress(KEY_ESCAPE) then StopReplay() end
            SyncPhysicsUpdateEnabled()
            if replayActive_ then UpdateReplay(dt) end
            if context.debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
            return
        end
        local physicsProbe = level_ and level_.physicsProbe or nil
        if physicsProbe then
            local probeContext = {
                scene = scene_,
                mapper = mapper_,
                apple = apple_,
                physicsWorld = physicsWorld_,
                pixelsPerMeter = CONFIG.pixelsPerMeter,
                matterVelocityToWorld = CONFIG.matterVelocityToWorld,
                applyGravity = SetGravity,
                setLaunched = function(value) launched_ = value end,
                setStatus = SetStatus,
            }
            -- Deliberately hard to trigger during a normal game, but independent
            -- of the disabled physics debug renderer so captures remain possible.
            if input:GetKeyDown(KEY_CTRL) and input:GetKeyDown(KEY_ALT) and input:GetKeyPress(KEY_T) then
                physicsProbe:Start(probeContext)
            end
            if physicsProbe:IsActive() then
                local probeResult = physicsProbe:Update(probeContext)
                SyncPhysicsUpdateEnabled()
                if probeResult == "finished" then ResetExperiment(false) end
                if context.debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
                return
            end
        end
        UpdateCardAnimations(dt)
        UpdateSpringVisuals(dt)
        sensorAngle_ = sensorAngle_ + dt * (goalContact_ and (math.pi * 2 / 7.2) or (math.pi * 2 / 10))
        HandlePointer(pointerFrame, assistantPointerConsumed)
        if replayActive_ then
            SyncPhysicsUpdateEnabled()
            UpdateReplay(dt)
            if context.debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
            return
        end
        UpdateCardParameter(dt)
        if input:GetKeyPress(KEY_R) then ResetExperiment() end
        if input:GetMouseButtonPress(MOUSEB_RIGHT) and (activeCardId_ or primedCardId_) then
            local id = activeCardId_ or primedCardId_
            local from = activeCardId_ and CurrentCardVisualPose(id) or PrimedCardPose(id)
            activeCardId_ = nil
            primedCardId_ = nil
            AnimateCardToHome(id, from, .18)
            ClearCardInteraction()
        end
        if input:GetKeyPress(KEY_ESCAPE) then
            if replayActive_ then StopReplay() else ToggleTacticalPause() end
        end
        SyncPhysicsUpdateEnabled()
        if replayActive_ then
            UpdateReplay(dt)
        elseif not isPaused_ and absorbing_ then
            UpdateExperiment(dt)
        end
        if context.debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
    end

    ---@param _eventType string
    ---@param eventData PhysicsPreStepEventData
    function HandlePhysicsPreStep(_eventType, eventData)
        if not apple_ or not launched_ or replayActive_ or apple_.body.bodyType ~= BT_DYNAMIC then
            physicsStepTimeScale_ = nil
            return
        end
        -- Phaser caps before Matter runs the next integration and collision pass.
        CapAppleSpeed()
        local physicsTimeScale = CurrentPhysicsTimeScale()
        physicsStepTimeScale_ = physicsTimeScale
        apple_.body.linearDamping = MatterCalibration.Box2DLinearDamping(
            apple_.baseFrictionAir,
            physicsTimeScale,
            eventData:GetFloat("TimeStep")
        )
        apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping(
            apple_.baseFrictionAir,
            physicsTimeScale,
            eventData:GetFloat("TimeStep")
        )
    end

    ---@param _eventType string
    ---@param eventData PhysicsPostStepEventData
    function HandlePhysicsPostStep(_eventType, eventData)
        if not launched_ or replayActive_ or isPaused_ then
            physicsStepTimeScale_ = nil
            return
        end
        local physicsTimeScale = CurrentPhysicsStepScale()
        local physicsProbe = level_ and level_.physicsProbe or nil
        if physicsProbe and physicsProbe:IsActive() then
            UpdateSpringExits()
            physicsProbe:AfterPhysicsStep({
                apple = apple_,
                pixelsPerMeter = CONFIG.pixelsPerMeter,
                matterVelocityToWorld = CONFIG.matterVelocityToWorld,
            }, eventData:GetFloat("TimeStep"))
            physicsStepTimeScale_ = nil
            return
        end
        -- The original applies a spring's pre-solve exit velocity after Matter's
        -- collision resolution, then advances runtime mechanisms in physics time.
        UpdateSpringExits()
        RefreshGoalContact()
        UpdateExperiment(eventData:GetFloat("TimeStep") * physicsTimeScale)
        physicsStepTimeScale_ = nil
    end
    function HandleScreenMode()
        frame_ = context.design_:Frame()
        RefreshWorkspaceLayout()
    end

    ---@param _eventType string
    ---@param eventData TouchBeginEventData
    function HandleCollisionBegin(_eventType, eventData)
        local nodeA = eventData:GetPtr("NodeA")
        local nodeB = eventData:GetPtr("NodeB")
        local physicsProbe = level_ and level_.physicsProbe or nil
        if physicsProbe and physicsProbe:IsActive() then
            if IsAppleNode(nodeA) then physicsProbe:OnContactBegin(nodeB, apple_.body.linearVelocity, { apple = apple_, matterVelocityToWorld = CONFIG.matterVelocityToWorld })
            elseif IsAppleNode(nodeB) then physicsProbe:OnContactBegin(nodeA, apple_.body.linearVelocity, { apple = apple_, matterVelocityToWorld = CONFIG.matterVelocityToWorld }) end
            return
        end
        if ActivateGoalContact(nodeA, nodeB, true) then return end
        if not nodeA or not nodeB or not runtime_ or not IsAppleNode(nodeA) and not IsAppleNode(nodeB) then return end
        local other = IsAppleNode(nodeA) and nodeB or nodeA
        local object = runtime_.byId[other.name]
        if launched_ and not replayActive_ then PlaySound("impact") end
        if not object then return end
        if object.type == "spring" and object.enabled and object.channelEnabled and not object.spent
            and uiElapsed_ * 1000 - object.triggeredAt >= object.cooldown then
            -- Matter fires collisionStart after Body.update has integrated this
            -- step and before Solver resolves it. UrhoX emits this callback at
            -- the equivalent contact phase, so snapshot the current velocity
            -- here instead of the prior PhysicsPreStep velocity.
            local collisionVelocity = apple_.body.linearVelocity
            local v = Vector2(collisionVelocity.x, collisionVelocity.y)
            local direction = object.direction
            local ix, iy = 0, 0
            if direction == "UP" then iy = 1 elseif direction == "DOWN" then iy = -1 elseif direction == "LEFT" then ix = -1 else ix = 1 end
            -- SpringObject scales its exit impulse by the source gravity
            -- multiplier. Hooke changes restitution only; Feather changes this
            -- impulse together with gravity.
            local impulse = object.impulseStrength * Rules.GetGravityMultiplier(rules_, level_.rules.initialGravity)
                * CurrentMatterVelocityToWorld(CurrentPhysicsStepScale())
            object.pendingExitVelocity = Vector2(v.x + ix * impulse, v.y + iy * impulse)
            object.triggeredAt = uiElapsed_ * 1000
            object.spent = object.oneShot
            object.pulseElapsedMs = 0
        elseif object.type == "button" then
            object.contactCount = object.contactCount + 1
            EvaluateButton(object)
        end
    end

    ---@param _eventType string
    ---@param eventData PhysicsUpdateContact2DEventData
    function HandleCollisionUpdate(_eventType, eventData)
        local nodeA = eventData:GetPtr("NodeA")
        local nodeB = eventData:GetPtr("NodeB")
        local physicsProbe = level_ and level_.physicsProbe or nil
        if physicsProbe and physicsProbe:IsActive() then return end
        ActivateGoalContact(nodeA, nodeB, false)
    end

    ---@param _eventType string
    ---@param eventData PhysicsEndContact2DEventData
    function HandleCollisionEnd(_eventType, eventData)
        local nodeA = eventData:GetPtr("NodeA")
        local nodeB = eventData:GetPtr("NodeB")
        local physicsProbe = level_ and level_.physicsProbe or nil
        if physicsProbe and physicsProbe:IsActive() then
            if IsAppleNode(nodeA) then physicsProbe:OnContactEnd(nodeB)
            elseif IsAppleNode(nodeB) then physicsProbe:OnContactEnd(nodeA) end
            return
        end
        if IsAppleGoalPair(nodeA, nodeB) then
            -- Contact callbacks can arrive before the final solver transform is
            -- synchronized. PhysicsPostStep owns the circle-vs-rotated-box test
            -- and is the only place that may reset the continuous stay timer.
            return
        end
        if not nodeA or not nodeB or not runtime_ or not IsAppleNode(nodeA) and not IsAppleNode(nodeB) then return end
        local other = IsAppleNode(nodeA) and nodeB or nodeA
        local object = runtime_.byId[other.name]
        if object and object.type == "button" then
            object.contactCount = math.max(0, object.contactCount - 1)
            EvaluateButton(object)
        end
    end
    function HandleRender()
        if not painter_ or not frame_ or not level_ then return end
        State.BeginGameSnapshot(context)
        local ok, err = pcall(function()
            painter_:Begin(frame_)
            painter_:DrawBackground(frame_)
            painter_:DrawNewton(frame_, level_, anger_, observation_)
            painter_:DrawGround(frame_)
            local goalPulseProgress = goalPulseElapsedMs_ and math.max(0, math.min(1, goalPulseElapsedMs_ / 460)) or nil
            if runtime_ then for _, object in ipairs(runtime_.ordered) do painter_:DrawObject(frame_, object, { sensorAngle = sensorAngle_, success = success_ and not replayActive_, goalPulseProgress = goalPulseProgress }, context.design_, mapper_) end end
            if not replayActive_ then
                DrawTrail()
                DrawCardPrediction()
                DrawAim()
                DrawLaunchHint()
                local absorbProgress = absorbing_ and math.max(0, math.min(1, absorbElapsedMs_ / 520)) or 0
                painter_:DrawApple(frame_, apple_, 1 - absorbProgress * .65, 1 - absorbProgress * .65, context.design_)
                DrawVelocityArrow()
                DrawPlayfieldOverlay()
                DrawPauseShade()
            end
            DrawHUD()
            DrawCards(nil, 71.999, true)
            DrawPauseStatus()
            if not replayActive_ then DrawRulePulse() end
            DrawCardParameterSelector()
            DrawCards(72, nil, false)
            DrawCardBurns()
            DrawCardBurnParticles()
            DrawRuleFlash()
            if replayActive_ then DrawReplay() end
            DrawResultOverlay()
            DrawGreenAssistant()
            painter_:Finish()
        end)
        State.EndGameSnapshot(context)
        if not ok then error(err) end
    end
end

return M
