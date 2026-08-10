-- AppRuntime: private runtime functions installed into the App context.
local M = {}
local EinsteinObserver = require("game.render.EinsteinObserver")
local WallImpactShake = require("game.render.WallImpactShake")
local NewtonPunchShake = require("game.render.NewtonPunchShake")
local ResultReportConfig = require("ui.result_report_config")
local TutorialView = require("game.render.TutorialView")

local TITLE_BACKGROUND_FILL = { 248, 231, 206, 255 }
local CATALOG_BACKGROUND_FILL = { 247, 239, 211, 255 }
local NOW_PLAYING_COLOR = { 164, 139, 76, 255 }

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local WorkspaceLayout = context.WorkspaceLayout
    local MatterCalibration = context.MatterCalibration
    local Renderer2D = context.Renderer2D
    local ReplayMode = context.ReplayMode
    local PhaseWallEffects = context.PhaseWallEffects
    local State = context.State
    local CONFIG = context.CONFIG
    local CARD_RENDER_WIDTH = context.CARD_RENDER_WIDTH
    local CARD_RENDER_HEIGHT = context.CARD_RENDER_HEIGHT
    local navigationTransition_ = context.navigationTransition_
    local newtonPunchShake_ = context.newtonPunchShake_
    local lastValidPhysicsTimeStep = 1 / 60
    local frameScreen_ = nil
    local _ENV = context

    local function currentNavigationTransition()
        return context.navigationTransition_ or navigationTransition_
    end

    local function navigationIsBackward()
        local transition = currentNavigationTransition()
        if not transition then return false end
        if type(transition.IsBackward) == "function" then return transition:IsBackward() end
        return transition.state == "CATALOG_TO_TITLE" or transition.state == "TITLE_ENTERING"
    end

    local function usesMainStage()
        return screen_ == "title" or screen_ == "title_catalog_transition" or screen_ == "catalog"
            or screen_ == "game" or screen_ == "workshop_preview"
    end

    local function FrameForCurrentScreen()
        local frame = screen_ == "title"
            and context.design_:Frame(true, 1870, 841)
            or context.design_:Frame(usesMainStage())
        if screen_ == "title"
            or screen_ == "title_catalog_transition" and navigationIsBackward() then
            frame.backgroundFill = TITLE_BACKGROUND_FILL
        elseif screen_ == "catalog" or screen_ == "title_catalog_transition" then
            frame.backgroundFill = CATALOG_BACKGROUND_FILL
        end
        frameScreen_ = screen_
        return frame
    end

    local function ResolvePhysicsTimeStep(eventData)
        local timeStep = eventData:GetFloat("TimeStep")
        -- UrhoX can expose a zero PhysicsPre/PostStep delta on the first
        -- persistent 2D contact even though Box2D still advances the world.
        -- Reuse the latest positive step so damping and trajectory sampling
        -- remain tied to the step that actually drove the solver.
        if timeStep and timeStep > .000001 then
            lastValidPhysicsTimeStep = timeStep
        end
        return lastValidPhysicsTimeStep
    end
    local function StartGlobalBGM()
        return context.setMusicContext("academy", { showNowPlaying = false, fadeIn = 0.45 })
    end

    local function DrawGreenAssistantTopLayer(draw)
        if not painter_ or not painter_.vg then
            draw()
            return
        end
        -- The companion is a presentation-layer character. It may occupy the
        -- letterbox padding, so do not inherit the gameplay stage scissor.
        nvgSave(painter_.vg)
        nvgResetScissor(painter_.vg)
        draw()
        nvgRestore(painter_.vg)
    end

    local function BeginGameplayWorldShake(frame)
        nvgSave(painter_.vg)
        local shake = newtonPunchShake_
        local shakeX = shake and shake.visualShakeX or 0
        local shakeY = shake and shake.visualShakeY or 0
        local shakeRotation = shake and shake.visualShakeRotation or 0
        if shakeX == 0 and shakeY == 0 and shakeRotation == 0 then return end
        local pivotX = frame.playfieldX + frame.playfieldWidth * .5
        local pivotY = frame.playfieldY + frame.playfieldHeight * .5
        nvgTranslate(painter_.vg, pivotX + shakeX, pivotY + shakeY)
        nvgRotate(painter_.vg, shakeRotation)
        nvgTranslate(painter_.vg, -pivotX, -pivotY)
    end

    local function EndGameplayWorldShake()
        nvgRestore(painter_.vg)
    end

    function playBGM(path, options)
        return context.globalBGM_:playBGM(path, options)
    end

    function stopBGM()
        context.globalBGM_:stopBGM()
    end

    function setBGMVolume(volume)
        if context.audioManager_ then context.audioManager_:setBgmVolume(volume)
        else context.globalBGM_:setBGMVolume(volume) end
    end

    function setSFXVolume(volume)
        if context.audioManager_ then context.audioManager_:setSfxVolume(volume)
        elseif context.uiAudio_ then context.uiAudio_:setVolume(volume) end
    end

    function setBGMMuted(muted)
        if context.audioManager_ then context.audioManager_:setBgmMuted(muted)
        else context.globalBGM_:setBgmMuted(muted) end
    end

    function setSFXMuted(muted)
        if context.audioManager_ then context.audioManager_:setSfxMuted(muted)
        elseif context.uiAudio_ then context.uiAudio_:setMuted(muted) end
    end

    function setMusicContext(musicContext, options)
        if context.audioManager_ then return context.audioManager_:setMusicContext(musicContext, options) end
        return context.globalBGM_:setMusicContext(musicContext, options)
    end

    function enterPreview()
        return context.audioManager_ and context.audioManager_:enterPreview() or true
    end

    function nextTrack()
        if context.audioManager_ then return context.audioManager_:nextTrack() end
        return context.globalBGM_:nextTrack()
    end

    function previousTrack()
        if context.audioManager_ then return context.audioManager_:previousTrack() end
        return context.globalBGM_:previousTrack()
    end

    function selectTrack(trackId)
        if context.audioManager_ then return context.audioManager_:selectTrack(trackId) end
        return context.globalBGM_:selectTrack(trackId)
    end

    function getCurrentTrack()
        return context.audioManager_ and context.audioManager_:getCurrentTrack()
            or context.globalBGM_:getCurrentTrack()
    end

    function getCurrentTrackTitle()
        return context.audioManager_ and context.audioManager_:getCurrentTrackTitle()
            or context.globalBGM_:getCurrentTrackTitle()
    end

    function showNowPlaying(title)
        return context.audioManager_ and context.audioManager_:showNowPlaying(title)
            or context.globalBGM_:showNowPlaying(title)
    end

    function saveAudioSettings()
        return context.audioManager_ and context.audioManager_:saveAudioSettings() or false
    end

    function loadAudioSettings()
        return context.audioManager_ and context.audioManager_:loadAudioSettings() or false
    end

    function DrawNowPlaying(painter)
        if not painter or not painter.Text then return end
        local state = context.globalBGM_:getNowPlayingState()
        if not state then return end
        local frame = context.frame_ or {}
        local x = (frame.logicalWidth or 1870) * .5
        local y = 94 + (state.yOffset or 0)
        local color = { NOW_PLAYING_COLOR[1], NOW_PLAYING_COLOR[2], NOW_PLAYING_COLOR[3],
            math.floor(230 * state.alpha + .5) }
        painter:Text(x, y, "♫ " .. state.title, 17, color,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-body")
    end

    function playUIClick()
        if context.audioManager_ then context.audioManager_:playUIClick()
        elseif context.uiAudio_ then context.uiAudio_:PlayUIClick() end
    end

    function HandleFirstAudioGesture()
        StartGlobalBGM()
    end

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
        -- The catalog uses the same fixed 1880 x 840 stage as gameplay, so its
        -- authored artwork is centered on taller viewports from the first frame.
        screen_ = "title"
        frame_ = FrameForCurrentScreen()
        context.InitializeDialogue()
        context.InitializeTutorial()
        context.InitializeAssistDemo()
        InitializeTitleScreen()
        InitializeGreenAssistant()
        InitializeExperimentCatalog()
        renderer:SetNumViewports(0)
        RefreshWorkspaceLayout()
        SubscribeToEvent("Update", "HandleUpdate")
        SubscribeToEvent("ScreenMode", "HandleScreenMode")
        SubscribeToEvent("MouseButtonDown", "HandleFirstAudioGesture")
        SubscribeToEvent("TouchBegin", "HandleTouchBegin")
        SubscribeToEvent("TouchMove", "HandleTouchMove")
        SubscribeToEvent("TouchEnd", "HandleTouchEnd")
        SubscribeToEvent("TextInput", "HandleTextInput")
        SubscribeToEvent("PhysicsPreStep", "HandlePhysicsPreStep")
        SubscribeToEvent("PhysicsPostStep", "HandlePhysicsPostStep")
        SubscribeToEvent("PhysicsBeginContact2D", "HandleCollisionBegin")
        SubscribeToEvent("PhysicsUpdateContact2D", "HandleCollisionUpdate")
        SubscribeToEvent("PhysicsEndContact2D", "HandleCollisionEnd")
        SubscribeToEvent(painter_.vg, "NanoVGRender", "HandleRender")
        if context.globalBGM_:canStartWithoutGesture() then StartGlobalBGM() end
        print("[Migration] 1:1 design-space runtime started")
    end
    function Stop()
        context.globalBGM_:stopBGM()
        if context.uiAudio_ then context.uiAudio_:Dispose() end
        ShutdownLevelWorkshop()
        if scene_ or level_ then ReleaseLevelRuntime() end
        context.DestroyDialogue()
        context.DestroyTutorial()
        DestroyGreenAssistant()
        context.DestroyAssistDemo()
        if painter_ then painter_:Destroy(); painter_ = nil end
        UnsubscribeFromAllEvents()
    end

    ---@param _eventType string
    ---@param eventData UpdateEventData
    function HandleUpdate(_eventType, eventData)
        local dt = eventData:GetFloat("TimeStep")
        if context.audioManager_ then context.audioManager_:Update(dt)
        else context.globalBGM_:Update(dt) end
        frame_ = FrameForCurrentScreen()
        RefreshWorkspaceLayout()
        local pointerFrame = PointerState()
        if screen_ == "title_catalog_transition" then
            local destination = currentNavigationTransition():Update(dt)
            if destination then
                screen_ = destination
                if destination == "title" and FinalizeCatalogToTitleTransition then
                    FinalizeCatalogToTitleTransition()
                end
            end
            return
        end
        if screen_ == "title" then
            UpdateTitleScreen(dt, pointerFrame)
            return
        end
        if screen_ == "catalog" then
            UpdateExperimentCatalog(dt, pointerFrame)
            return
        end
        if screen_ == "workshop" then
            UpdateLevelWorkshop(dt, pointerFrame)
            return
        end
        if not level_ or not apple_ then return end
        local assistEscapeHandled = false
        if assistSceneActive_ and input:GetKeyPress(KEY_ESCAPE) then
            assistEscapeHandled = context.AbortGreenAssistantTakeover("escape") == true
        end
        local assistPointerHandled = false
        if assistSceneActive_ and not assistEscapeHandled and context.HandleAssistDemoPointer then
            assistPointerHandled = context.HandleAssistDemoPointer(pointerFrame)
        end
        RefreshHUDSummary()
        hudEscapeConsumed_ = false
        if not assistEscapeHandled and hudDropdown_ and input:GetKeyPress(KEY_ESCAPE) then
            hudDropdown_ = nil
            playUIClick()
            hudEscapeConsumed_ = true
        end
        local reportVisible = IsResultReportVisible and IsResultReportVisible()
        frame_.assistantBubbleAvoidRect = reportVisible and ResultReportConfig.ResolveRect(frame_) or nil
        local dialoguePointerConsumed = assistPointerHandled
        if not dialoguePointerConsumed then
            dialoguePointerConsumed = (reportVisible or context.assistantInputLocked_)
                and false or context.UpdateDialogue(dt, pointerFrame)
        end
        if audio_ then audio_:Update(dt) end
        uiElapsed_ = uiElapsed_ + dt
        UpdateRuleFeedback(dt)
        UpdatePhaseWallEffects(dt)
        if not isPaused_ and not replayActive_ then
            local visualDt = dt * CurrentPhysicsTimeScale()
            WallImpactShake.UpdateRuntime(runtime_, visualDt)
            NewtonPunchShake.Update(newtonPunchShake_, visualDt)
        end
        context.UpdateAssistDemo(dt)
        -- Sample once, then give the screen-space Companion first chance to
        -- apply a rigid drag before its animation/update and before rendering.
        local assistantPointerConsumed = dialoguePointerConsumed
        if not dialoguePointerConsumed then
            assistantPointerConsumed = HandleGreenAssistantPointer(pointerFrame.x, pointerFrame.y, pointerFrame)
        end
        UpdateGreenAssistant(dt)
        if UpdateResultReport then UpdateResultReport(dt) end
        if screen_ ~= "game" and screen_ ~= "workshop_preview" then return end
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
                ---@diagnostic disable-next-line: assign-type-mismatch
                setStatus = SetStatus,
            }
            -- Deliberately hard to trigger during a normal game, but independent
            -- of the disabled physics debug renderer so captures remain possible.
            local keyboardProbeRequested = not context.assistantInputLocked_
                and input:GetKeyDown(KEY_CTRL) and input:GetKeyDown(KEY_ALT) and input:GetKeyPress(KEY_T)
            -- Maker embeds the Web runtime in a cross-origin iframe where browser
            -- automation cannot always forward keyboard chords. Keep a deliberately
            -- middle-click as an equivalent diagnostics-only trigger. Normal
            -- gameplay uses left/right clicks and is therefore unaffected.
            local pointerProbeRequested = pointerFrame.insideStage ~= false
                and not context.assistantInputLocked_ and input:GetMouseButtonPress(MOUSEB_MIDDLE)
            if keyboardProbeRequested or pointerProbeRequested then
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
        if screen_ ~= "game" and screen_ ~= "workshop_preview" then return end
        if replayActive_ then
            SyncPhysicsUpdateEnabled()
            UpdateReplay(dt)
            if context.debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
            return
        end
        UpdateCardParameter(dt)
        if not context.assistantInputLocked_ and input:GetKeyPress(KEY_R) then ResetExperiment() end
        if pointerFrame.insideStage ~= false and not context.assistantInputLocked_
            and input:GetMouseButtonPress(MOUSEB_RIGHT) and (activeCardId_ or primedCardId_) then
            local id = activeCardId_ or primedCardId_
            local from = activeCardId_ and CurrentCardVisualPose(id) or PrimedCardPose(id)
            activeCardId_ = nil
            primedCardId_ = nil
            AnimateCardToHome(id, from, .18)
            ClearCardInteraction()
        end
        if not context.assistantInputLocked_ and not assistEscapeHandled and not hudEscapeConsumed_
            and input:GetKeyPress(KEY_ESCAPE) then
            if replayActive_ then StopReplay() else ToggleTacticalPause() end
        end
        EinsteinObserver.Update(runtime_, apple_, dt, isPaused_)
        SyncPhysicsUpdateEnabled()
        context.AdvanceAssistDemoSimulation(dt)
        if replayActive_ then
            UpdateReplay(dt)
        elseif not isPaused_ and absorbing_ then
            UpdateExperiment(dt)
        end
        -- Tutorial is a passive observer. Running it after gameplay means a
        -- same-frame field activation or victory is reflected before render.
        context.UpdateTutorial(dt)
        if context.debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
    end

    ---@param _eventType string
    ---@param eventData PhysicsPreStepEventData
    function HandlePhysicsPreStep(_eventType, eventData)
        -- The previous post-step support is the state that applies to this
        -- integration. Resolve damping before clearing it for this step's
        -- PhysicsUpdateContact2D callbacks.
        local frictionAir = CurrentAppleFrictionAir(appleSupportNormal_)
        -- PhysicsUpdateContact2D repopulates this during the upcoming solve.
        -- Clearing it every step avoids stale support after gravity changes or
        -- contacts that end without a usable manifold.
        appleSupportNormal_ = nil
        if not apple_ or not launched_ or replayActive_ or apple_.body.bodyType ~= BT_DYNAMIC then
            applePreSolveVelocity_ = nil
            pendingMatterRestitutions_ = nil
            physicsStepTimeScale_ = nil
            return
        end
        -- Phaser caps before Matter runs the next integration and collision pass.
        CapAppleSpeed()
        -- PlayScene.preparePhysicsStep snapshots body.velocity in Matter's
        -- beforeupdate hook. Collision callbacks must consume this exact value,
        -- before gravity integration and contact solving mutate the velocity.
        local velocity = apple_.body.linearVelocity
        applePreSolveVelocity_ = Vector2(velocity.x, velocity.y)
        pendingMatterRestitutions_ = nil
        local physicsTimeScale = CurrentPhysicsTimeScale()
        local physicsTimeStep = ResolvePhysicsTimeStep(eventData)
        physicsStepTimeScale_ = physicsTimeScale
        apple_.body.linearDamping = MatterCalibration.Box2DLinearDamping(
            frictionAir,
            physicsTimeScale,
            physicsTimeStep
        )
        apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping(
            frictionAir,
            physicsTimeScale,
            physicsTimeStep
        )
    end

    ---@param _eventType string
    ---@param eventData PhysicsPostStepEventData
    function HandlePhysicsPostStep(_eventType, eventData)
        if not launched_ or replayActive_ or isPaused_ then
            applePreSolveVelocity_ = nil
            pendingMatterRestitutions_ = nil
            physicsStepTimeScale_ = nil
            return
        end
        local physicsTimeScale = CurrentPhysicsStepScale()
        local physicsProbe = level_ and level_.physicsProbe or nil
        if physicsProbe and physicsProbe:IsActive() then
            ApplyPendingMatterRestitution()
            UpdateSpringExits()
            physicsProbe:AfterPhysicsStep({
                apple = apple_,
                pixelsPerMeter = CONFIG.pixelsPerMeter,
                matterVelocityToWorld = CONFIG.matterVelocityToWorld,
            }, ResolvePhysicsTimeStep(eventData))
            applePreSolveVelocity_ = nil
            physicsStepTimeScale_ = nil
            return
        end
        -- The original applies a spring's pre-solve exit velocity after Matter's
        -- collision resolution, then advances runtime mechanisms in physics time.
        -- Align Matter's time-scaled restitution threshold first. An active
        -- spring then intentionally replaces that result with its explicit
        -- pre-solve exit velocity, matching SpringObject.afterPhysicsStep.
        ApplyPendingMatterRestitution()
        ApplyAppleRollingResistance(ResolvePhysicsTimeStep(eventData))
        UpdateSpringExits()
        RefreshGoalContact()
        local simulationStep = ResolvePhysicsTimeStep(eventData) * physicsTimeScale
        UpdateExperiment(simulationStep)
        context.UpdateAssistDemoPhysicsStep(simulationStep)
        applePreSolveVelocity_ = nil
        physicsStepTimeScale_ = nil
    end
    function HandleScreenMode()
        frame_ = FrameForCurrentScreen()
        RefreshWorkspaceLayout()
        if screen_ == "workshop" then HandleWorkshopScreenMode() end
    end

    ---@param eventData PhysicsBeginContact2DEventData
    ---@param nodeA Node
    ---@param velocity Vector2
    local function ReadAppleContact(eventData, nodeA, velocity)
        ---@diagnostic disable-next-line: undefined-field
        local contacts = eventData["Contacts"]:GetBuffer()
        if not contacts then return nil, nil, nil, nil end
        local bestSpeed = -math.huge
        local bestNormalX, bestNormalY, bestContactX, bestContactY = nil, nil, nil, nil
        while not contacts.eof do
            local position = contacts:ReadVector2()
            local normal = contacts:ReadVector2()
            contacts:ReadFloat() -- separation
            -- Box2D points from fixture A to B; expose the surface normal that
            -- points from the wall toward the apple for both fixture orders.
            if IsAppleNode(nodeA) then normal = Vector2(-normal.x, -normal.y) end
            ---@type number
            local speed = math.abs(velocity.x * normal.x + velocity.y * normal.y)
            if speed > bestSpeed then
                bestSpeed = speed
                bestNormalX, bestNormalY = normal.x, normal.y
                bestContactX, bestContactY = position.x, position.y
            end
        end
        return bestNormalX, bestNormalY, bestContactX, bestContactY
    end

    ---@param _eventType string
    ---@param eventData PhysicsBeginContact2DEventData
    function HandleCollisionBegin(_eventType, eventData)
        local nodeA = eventData:GetPtr("NodeA")
        local nodeB = eventData:GetPtr("NodeB")
        local physicsProbe = level_ and level_.physicsProbe or nil
        if physicsProbe and physicsProbe:IsActive() then
            if IsAppleNode(nodeA) then physicsProbe:OnContactBegin(nodeB, applePreSolveVelocity_, { apple = apple_, matterVelocityToWorld = CONFIG.matterVelocityToWorld })
            elseif IsAppleNode(nodeB) then physicsProbe:OnContactBegin(nodeA, applePreSolveVelocity_, { apple = apple_, matterVelocityToWorld = CONFIG.matterVelocityToWorld }) end
            return
        end
        if ActivateGoalContact(nodeA, nodeB, true) then return end
        if not nodeA or not nodeB or not runtime_ or not IsAppleNode(nodeA) and not IsAppleNode(nodeB) then return end
        local other = IsAppleNode(nodeA) and nodeB or nodeA
        QueueMatterRestitutionAlignment(other)
        local object = runtime_.byId[other.name]
        if launched_ and not replayActive_ then PlaySound("impact") end
        if not object then return end
        if object.type == "wall" and object.collisionEnabled then
            local velocity = applePreSolveVelocity_ or apple_.body.linearVelocity
            local normalX, normalY, contactX, contactY = ReadAppleContact(eventData, nodeA, velocity)
            if normalX == nil or normalY == nil then
                -- BeginContact normally supplies a manifold. Keep a rotated-box
                -- geometric fallback rather than falling back to total speed.
                local normal = MatterContactNormal(object, velocity)
                normalX, normalY = normal.x, normal.y
                local position = apple_.node.position2D
                contactX, contactY = position.x, position.y
            end
            WallImpactShake.Trigger(object, velocity, Vector2(normalX, normalY),
                contactX, contactY, CurrentPhysicsStepScale())
        end
        if object.type == "wall" and object.phaseable then
            -- A charged apple skips this contact through its collision mask;
            -- uncharged impacts use the existing begin-contact event for ripples.
            local position = apple_.node.position2D
            PhaseWallEffects.TriggerImpact(object, position.x, position.y,
                applePreSolveVelocity_ or apple_.body.linearVelocity, 0.78)
        end
        if object.type == "spring" and object.enabled and object.channelEnabled and not object.spent
            and uiElapsed_ * 1000 - object.triggeredAt >= object.cooldown then
            -- The Phaser runtime captures body.velocity in beforeupdate and
            -- SpringObject consumes that exact pre-solve snapshot in
            -- collisionStart. Keep the same observable hook on UrhoX.
            local v = applePreSolveVelocity_ or apple_.body.linearVelocity
            local direction = object.direction
            local ix, iy = 0, 0
            if direction == "UP" then iy = 1 elseif direction == "DOWN" then iy = -1 elseif direction == "LEFT" then ix = -1 else ix = 1 end
            -- The experiment branch wires SpringObject.getSpringMultiplier to
            -- worldRule.restitutionMultiplier. Hooke therefore strengthens the
            -- explicit spring exit as well as ordinary contact restitution;
            -- Feather affects gravity only.
            local impulse = object.impulseStrength * Rules.GetRestitutionMultiplier(rules_)
                * CurrentMatterVelocityToWorld(CurrentPhysicsStepScale())
            object.pendingExitVelocity = Vector2(v.x + ix * impulse, v.y + iy * impulse)
            PlaySound("spring")
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
        if not apple_ or not nodeA or not nodeB
            or not IsAppleNode(nodeA) and not IsAppleNode(nodeB)
            or not eventData:GetBool("Enabled") then return end

        local gravity = physicsWorld_:GetGravity()
        local gravityLength = math.sqrt(gravity.x * gravity.x + gravity.y * gravity.y)
        if gravityLength <= .000001 then return end
        local antiGravityX, antiGravityY = -gravity.x / gravityLength, -gravity.y / gravityLength
        local contacts = eventData["Contacts"]:GetBuffer()
        while not contacts.eof do
            contacts:ReadVector2() -- position
            local normal = contacts:ReadVector2()
            contacts:ReadFloat() -- separation
            -- Box2D's manifold normal points from fixture A toward fixture B.
            -- Convert it to the surface normal that always points at the apple.
            if IsAppleNode(nodeA) then normal = Vector2(-normal.x, -normal.y) end
            local supportDot = normal.x * antiGravityX + normal.y * antiGravityY
            local currentDot = appleSupportNormal_ and
                (appleSupportNormal_.x * antiGravityX + appleSupportNormal_.y * antiGravityY) or -math.huge
            if supportDot >= MatterCalibration.APPLE_SUPPORT_DOT_MIN and supportDot > currentDot then
                appleSupportNormal_ = Vector2(normal.x, normal.y)
            end
        end
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
        if DeactivateGoalContact(nodeA, nodeB) then
            -- Contact callbacks can arrive before the final solver transform is
            -- synchronized. PhysicsPostStep applies the one-step debounce and
            -- is the only place that may reset the continuous stay timer.
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
        if not painter_ or not frame_ then return end
        local mainStageActive = usesMainStage()
        if frame_.mainStageActive ~= mainStageActive or frameScreen_ ~= screen_ then
            frame_ = FrameForCurrentScreen()
            RefreshWorkspaceLayout()
        end
        if screen_ == "workshop" then
            local ok, err = pcall(function()
                painter_:Begin(frame_)
                DrawLevelWorkshop()
                DrawNowPlaying(painter_)
                painter_:Finish()
            end)
            if not ok then error(err) end
            return
        end
        if screen_ == "title_catalog_transition" then
            local ok, err = pcall(function()
                painter_:Begin(frame_)
                local designWidth = frame_.stageWidth or frame_.logicalWidth
                local transition = currentNavigationTransition()
                local titleOffset, catalogOffset = transition:GetRootOffsets(designWidth)
                DrawExperimentCatalog({ rootOffsetX = catalogOffset, transition = transition })
                DrawTitleScreen({ rootOffsetX = titleOffset, transition = transition })
                DrawNowPlaying(painter_)
                painter_:Finish()
            end)
            if not ok then error(err) end
            return
        end
        State.BeginGameSnapshot(context)
        local ok, err = pcall(function()
            painter_:Begin(frame_)
            if screen_ == "catalog" then
                DrawExperimentCatalog()
                DrawNowPlaying(painter_)
                painter_:Finish()
                return
            end
            if screen_ == "title" then
                DrawTitleScreen()
                DrawNowPlaying(painter_)
                painter_:Finish()
                return
            end
            if not level_ then
                DrawNowPlaying(painter_)
                painter_:Finish()
                return
            end
            painter_:DrawBackground(frame_)
            BeginGameplayWorldShake(frame_)
            painter_:DrawGameplayWallArt(frame_)
            EndGameplayWorldShake()
            painter_:DrawNewton(frame_, level_, anger_, observation_, uiElapsed_)
            -- Shake only the authored Gameplay world. HUD, Newton's panel,
            -- cards and modal overlays remain in the fixed stage transform.
            BeginGameplayWorldShake(frame_)
            painter_:DrawGround(frame_)
            local goalPulseProgress = goalPulseElapsedMs_ and math.max(0, math.min(1, goalPulseElapsedMs_ / 460)) or nil
            if runtime_ then for _, object in ipairs(runtime_.ordered) do painter_:DrawObject(frame_, object, { sensorAngle = sensorAngle_, success = success_ and not replayActive_, goalPulseProgress = goalPulseProgress, replayActive = replayActive_ }, context.design_, mapper_) end end
            if not replayActive_ then
                DrawTrail()
                DrawCardPrediction()
                DrawAim()
                DrawLaunchHint()
                local absorbProgress = absorbing_ and math.max(0, math.min(1, absorbElapsedMs_ / 520)) or 0
                painter_:DrawApple(frame_, apple_, 1 - absorbProgress * .65, 1 - absorbProgress * .65, context.design_)
                DrawVelocityArrow()
                DrawPlayfieldOverlay()
            end
            EndGameplayWorldShake()
            -- Pause is a fixed modal layer, even if it is opened during the
            -- short-lived world impact response.
            DrawPauseShade()
            painter_:DrawGameplayFrameChrome(frame_)
            BeginGameplayWorldShake(frame_)
            painter_:DrawGameplayDecor(frame_)
            EndGameplayWorldShake()
            DrawHUD()
            context.DrawDialogueHistoryButton()
            DrawCards(nil, 71.999, true)
            DrawPauseStatus()
            if not replayActive_ then DrawRulePulse() end
            DrawCardParameterSelector()
            DrawCards(72, nil, false)
            DrawSelectedCardDetail()
            DrawCardBurns()
            DrawCardBurnParticles()
            DrawRuleFlash()
            if replayActive_ then DrawReplay() end
            context.DrawAssistDemo()
            DrawHUDDropdown()
            context.DrawDialogueOverlay()
            TutorialView.Draw(painter_, frame_, context)
            DrawResultOverlay()
            DrawGreenAssistantTopLayer(DrawGreenAssistant)
            DrawGreenAssistantTopLayer(context.DrawGreenAssistantOverlay)
            DrawNowPlaying(painter_)
            painter_:Finish()
        end)
        State.EndGameSnapshot(context)
        if not ok then error(err) end
    end
end

return M
