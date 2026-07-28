local LevelData = require("migration.LevelData")
local CoordinateMapper = require("migration.CoordinateMapper")
local DesignSpace = require("migration.DesignSpace")
local MatterCalibration = require("migration.MatterCalibration")
local PhysicsProfiles = require("migration.PhysicsProfiles")
local Rules = require("migration.Rules")
local RuntimeFactory = require("migration.RuntimeFactory")
local Renderer2D = require("migration.Renderer")
local SynthAudio = require("migration.SynthAudio")
local TrajectoryPrediction = require("migration.TrajectoryPrediction")

local CONFIG = {
    title = "牛顿看了想打人",
    pixelsPerMeter = 100,
    matterFramesPerSecond = 60,
    bulletTimeScale = 0.05,
    levelCount = 9,
    replaySampleMs = 1000 / 30,
}

-- Phaser draws card contents in a 124 px design container, then scales the
-- whole container to 144 px. The Maker card geometry is already expanded to
-- that final size, so text needs this factor explicitly.
local CARD_TEXT_SCALE = 144 / 124

-- Matter stores velocity in pixels per 60 Hz frame, while Box2D uses metres
-- per second. These constants keep the migrated runtime on the source scale.
CONFIG.matterVelocityToWorld = CONFIG.matterFramesPerSecond / CONFIG.pixelsPerMeter
CONFIG.maxAppleSpeed = 25 * CONFIG.matterVelocityToWorld

local LEVEL_META = {
    level_01 = { name = "第一颗苹果", objective = "让苹果进入观察皿", observation = "先观察抛物线，再谈万有引力。" },
    level_02 = { name = "羽毛般落下", objective = "用轻羽引力越过矮台", observation = "减弱重力，轨迹会被拉得更长。" },
    level_03 = { name = "世界向右落", objective = "利用横向引力，再让世界归位", observation = "苹果记得已经获得的速度。" },
    level_04 = { name = "半空中的推手", objective = "在挡板前施加向上冲量", observation = "一次恰当的冲量胜过持续用力。" },
    level_05 = { name = "让世界归位", objective = "越墙后用牛顿拳恢复经典物理", observation = "重置规则，不重置结果。" },
    level_06 = { name = "墙不存在", objective = "在薄墙前开启量子隧穿", observation = "这不是穿墙，只是暂时不承认墙。" },
    level_07 = { name = "镜中的抛物线", objective = "反转水平速度，回到左侧观察皿", observation = "镜像改变方向，却不抹去速度。" },
    level_08 = { name = "胡克的台阶", objective = "借高弹性平台完成二次起跳", observation = "反弹越漂亮，牛顿的眉头越紧。" },
    level_09 = { name = "两条路", objective = "穿墙或折返，寻找自己的解法", observation = "同一个终点不要求同一条证明。" },
}

---@type Scene|nil
local scene_ = nil
---@type Camera|nil
local camera_ = nil
---@type Viewport|nil
local viewport_ = nil
---@type PhysicsWorld2D|nil
local physicsWorld_ = nil
---@type DesignSpace
local design_ = DesignSpace.New()
---@type Renderer2D|nil
local painter_ = nil
---@type SynthAudio|nil
local audio_ = nil
---@type table|nil
local level_ = nil
---@type table|nil
local physicsProfile_ = nil
---@type table|nil
local runtime_ = nil
---@type table|nil
local laboratoryBoundaries_ = nil
---@type table|nil
local apple_ = nil
---@type Vector2|nil
local applePreSolveVelocity_ = nil
---@type table|nil
local mapper_ = nil
local frame_ = nil
local levelIndex_ = 1
local rules_ = Rules.NewState()
local draggedApple_ = false
local aimPreview_ = nil
local activeCardId_ = nil
local activeCardStart_ = nil
local activeCardPointer_ = nil
local activeCardDragged_ = false
local activeCardDeploying_ = false
local activeCardPressedAt_ = nil
local activeCardPressPose_ = nil
local primedCardId_ = nil
local cardParameterStart_ = nil
local cardDeployEnteredMs_ = nil
local cardLastMotionAtMs_ = nil
local cardPointerSamples_ = {}
local cardCandidate_ = nil
local cardGestureDistance_ = 0
local hoveredCardId_ = nil
local cardHoverStates_ = {}
local hoveredLevelIndex_ = nil
local hoveredNavigation_ = nil
local punchHovered_ = false
local pointer_ = {
    activeTouchId = nil,
    touchX = 0,
    touchY = 0,
    touchPressed = false,
    touchReleased = false,
}
local launched_ = false
local goalContact_ = false
local goalContactMs_ = 0
local goalPulseElapsedMs_ = nil
local outsideMs_ = 0
local flightMs_ = 0
local status_ = "READY · 等待发射"
local isPaused_ = false
local bulletTimeActive_ = false
local debugDraw_ = false
local success_ = false
local failed_ = false
local absorbing_ = false
local absorbElapsedMs_ = 0
local failureCount_ = 0
local failureCountsByLevel_ = {}
local observation_ = ""
local replayActive_ = false
local replayTime_ = 0
local replayPaused_ = false
local replaySpeed_ = 1
local replayFinished_ = false
local replaySamples_ = {}
local replayEvents_ = {}
local replaySavedApple_ = nil
-- Replay mode is the sole owner of the replay UI, input and frozen physics
-- lifecycle. The derived booleans remain only for the existing draw helpers.
local replayMode_ = "none"
local replayNextSampleMs_ = 0
local replayPreviousSample_ = nil
local trail_ = {}
local lastTrailAt_ = 0
local sensorAngle_ = 0
local uiElapsed_ = 0
local anger_ = 0
local phaseTraversing_ = false
local stalledMs_ = 0
local channelStates_ = {}
local cardStates_ = {}
local cardDeckById_ = {}
local handOrder_ = {}
local cardHomeMotions_ = {}
local cardHandReordering_ = false
local cardBurns_ = {}
local cardBurnParticles_ = {}
local burningCardIds_ = {}
local rulePulse_ = nil
local ruleFlash_ = nil
local ruleDeployCount_ = 0
local ReevaluateButtons = nil
local InitializeMechanisms = nil
local RecordReplayEvent = nil
local StartReplay = nil
local StopReplay = nil

-- Lua limits one chunk to 200 locals. This entry script already has a large
-- state surface, so helper functions deliberately live in its script environment
-- while mutable runtime state remains file-local above.
function SetStatus(value)
    status_ = value
    print("[Migration] " .. value)
end

---@param mode "none"|"playing"|"paused"|"finished"
function SetReplayMode(mode)
    assert(mode == "none" or mode == "playing" or mode == "paused" or mode == "finished",
        "unknown replay mode: " .. tostring(mode))
    replayMode_ = mode
    replayActive_ = mode ~= "none"
    replayPaused_ = mode == "paused" or mode == "finished"
    replayFinished_ = mode == "finished"
end

function ReplayLog(event)
    print(string.format(
        "[Replay] %s mode=%s samples=%d duration=%.3f",
        event,
        replayMode_,
        #replaySamples_,
        (#replaySamples_ > 0 and (replaySamples_[#replaySamples_].t or 0) or 0) / 1000
    ))
end

function PlaySound(kind)
    if audio_ then audio_:Play(kind) end
end

function RuleFeedbackText(id, candidate)
    if id == "feather-gravity" then return "场地重力强度已减弱，当前重力方向保持不变。" end
    if id == "side-gravity" then
        local labels = { LEFT = "左", RIGHT = "右", UP = "上", DOWN = "下" }
        return "场地重力已改为向" .. (labels[candidate] or "当前") .. "，动态物体速度保持不变。"
    end
    if id == "hooke-bounce" then return "苹果与普通墙体的弹性响应已提高。" end
    if id == "up-impulse" then return "向上冲量已叠加到苹果当前速度。" end
    if id == "mirror-motion" then
        return (candidate == "HORIZONTAL" and "水平" or "垂直") .. "速度已镜像，另一轴速度保持不变。"
    end
    return "苹果获得一次相位充能，下一次可穿过玻璃相位墙。"
end

function RuleFlashSymbol(id, candidate)
    local sideSymbols = { LEFT = "←", RIGHT = "→", UP = "↑", DOWN = "↓" }
    if id == "feather-gravity" then return "g½" end
    if id == "side-gravity" then return sideSymbols[candidate] or "↓" end
    if id == "hooke-bounce" then return "↗" end
    if id == "up-impulse" then return "↑" end
    if id == "mirror-motion" then return candidate == "VERTICAL" and "↕" or "↔" end
    return "∞"
end

function StartRuleFeedback(id, candidate, accent)
    observation_ = RuleFeedbackText(id, candidate)
    rulePulse_ = { elapsed = 0, duration = .22, color = accent or Renderer2D.COLORS.primaryActive }
    ruleFlash_ = {
        elapsed = 0,
        duration = .48,
        symbol = RuleFlashSymbol(id, candidate),
        color = id == "quantum-phase" and Renderer2D.COLORS.quantum or Renderer2D.COLORS.primaryActive,
    }
end

function UpdateRuleFeedback(dt)
    if rulePulse_ then
        rulePulse_.elapsed = rulePulse_.elapsed + dt
        if rulePulse_.elapsed >= rulePulse_.duration then rulePulse_ = nil end
    end
    if ruleFlash_ then
        ruleFlash_.elapsed = ruleFlash_.elapsed + dt
        if ruleFlash_.elapsed >= ruleFlash_.duration then ruleFlash_ = nil end
    end
end

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

function InitializeCards()
    cardStates_ = {}
    cardDeckById_ = {}
    handOrder_ = {}
    hoveredCardId_ = nil
    cardHoverStates_ = {}
    cardHomeMotions_ = {}
    cardHandReordering_ = false
    if not level_ or not level_.cardDeck then return end
    local ordered = {}
    for _, card in ipairs(level_.cardDeck.cards or {}) do
        ordered[#ordered + 1] = card
        cardStates_[card.cardId] = {
            remainingUses = math.max(0, card.count or 0),
            usageMode = card.usageMode or "SINGLE_USE",
            consumed = false,
        }
        cardDeckById_[card.cardId] = card
    end
    table.sort(ordered, function(a, b) return (a.order or 0) < (b.order or 0) end)
    for _, card in ipairs(ordered) do handOrder_[#handOrder_ + 1] = card.cardId end
end

function CurrentPhysicsTimeScale()
    if level_ and level_.physicsProbe and level_.physicsProbe:IsActive() then
        return level_.physicsProbe:GetTimeScale()
    end
    return bulletTimeActive_ and CONFIG.bulletTimeScale or 1
end

-- Matter reports velocity in pixels per 60 Hz frame, independent of its
-- current delta. Box2D stores physical metres per second, so a Matter value
-- occupies only timeScale of that physical velocity while bullet time is on.
function CurrentMatterVelocityToWorld()
    return CONFIG.matterVelocityToWorld * CurrentPhysicsTimeScale()
end

function CurrentMatterSpeedFromWorld(velocity)
    return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y) / CurrentMatterVelocityToWorld()
end

function ApplyAppleCardMaterial()
    if not apple_ or not apple_.shape then return end
    apple_.shape.restitution = MatterCalibration.CardRestitution(Rules.GetRestitutionMultiplier(rules_))
end

function RestoreAppleContactMaterial()
    if not apple_ or not apple_.shape then return end
    if math.abs(apple_.shape.friction - MatterCalibration.APPLE_FRICTION) > .0001 then
        apple_.shape.friction = MatterCalibration.APPLE_FRICTION
        if apple_.body and apple_.body.bodyType == BT_DYNAMIC then apple_.body.awake = true end
    end
end

function SetGravity()
    if not physicsWorld_ or not level_ or not physicsProfile_ then return end
    local base = level_.rules.initialGravity
    local gravity = Rules.GetGravity(rules_, base)
    if level_.physicsProbe and level_.physicsProbe:IsActive() then
        gravity = { x = 0, y = 1, strength = 1 }
    end
    local timeScale = CurrentPhysicsTimeScale()
    physicsWorld_:SetGravity(Vector2(
        gravity.x * gravity.strength * physicsProfile_.gravityAcceleration * timeScale * timeScale,
        -gravity.y * gravity.strength * physicsProfile_.gravityAcceleration * timeScale * timeScale
    ))
    if apple_ and apple_.shape then
        apple_.shape.maskBits = rules_.phaseActive and (RuntimeFactory.MASK_ALL & ~RuntimeFactory.CATEGORY_PHASEABLE) or RuntimeFactory.MASK_ALL
    end
    if ReevaluateButtons then ReevaluateButtons() end
end

---@param active boolean
function SetBulletTimeActive(active)
    if bulletTimeActive_ == active then return end
    local previousScale = CurrentPhysicsTimeScale()
    bulletTimeActive_ = active
    local nextScale = CurrentPhysicsTimeScale()
    if apple_ and apple_.body and apple_.body.bodyType == BT_DYNAMIC then
        local velocity = apple_.body.linearVelocity
        local scaleRatio = nextScale / previousScale
        apple_.body.linearVelocity = Vector2(velocity.x * scaleRatio, velocity.y * scaleRatio)
        apple_.body.angularVelocity = apple_.body.angularVelocity * scaleRatio
        apple_.body.linearDamping = MatterCalibration.Box2DLinearDamping(apple_.baseFrictionAir, nextScale)
        apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping(apple_.baseFrictionAir, nextScale)
        apple_.body.awake = true
    end
    SetGravity()
end

function UpdateAngerFromRules()
    local persistent = next(rules_.activeFields) ~= nil or rules_.phaseActive
    if persistent then
        anger_ = math.min(96, 54 + ruleDeployCount_ * 10)
    else
        anger_ = math.min(68, failureCount_ * 18)
    end
end

function SyncPhysicsUpdateEnabled()
    if not physicsWorld_ then return end
    if replayActive_ or isPaused_ then
        SetBulletTimeActive(false)
        physicsWorld_:SetUpdateEnabled(false)
        return
    end
    -- The Phaser scene does not slow simulation while a card is only being
    -- rearranged in the hand. Bullet time begins once it is primed, deployed,
    -- or resolving its burn animation.
    local bulletTime = activeCardDeploying_ or primedCardId_ ~= nil or #cardBurns_ > 0
    SetBulletTimeActive(bulletTime)
    physicsWorld_:SetUpdateEnabled(true)
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
    physicsWorld_:SetContinuousPhysics(true)
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

function BuildLevel(index)
    level_ = LoadLevel(index)
    physicsProfile_ = PhysicsProfiles.Resolve(level_.physicsProfile)
    failureCount_ = failureCountsByLevel_[level_.levelId] or 0
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
    RuntimeFactory.CreateViewportBackground(scene_)
    laboratoryBoundaries_ = RuntimeFactory.CreateLaboratoryBoundaries(
        scene_, mapper_, LevelData.PLAYFIELD_GROUND_Y, physicsProfile_.boundaries
    )
    runtime_ = RuntimeFactory.CreateLevelObjects({ scene = scene_, mapper = mapper_ }, level_)
    local launcher = LevelData.FindFirst(level_, "launcher")
    if not launcher then error("关卡缺少发射器") end
    local launcherRuntime = runtime_.byId[launcher.id]
    apple_ = RuntimeFactory.CreateApple(scene_, launcherRuntime)
    rules_ = Rules.NewState()
    level_.physicsProbe = require("migration.PhysicsProbe").New()
    InitializeCards()
    draggedApple_ = false
    aimPreview_ = nil
    activeCardId_ = nil
    primedCardId_ = nil
    isPaused_ = false
    activeCardStart_ = nil
    activeCardPointer_ = nil
    activeCardDragged_ = false
    activeCardDeploying_ = false
    activeCardPressedAt_ = nil
    activeCardPressPose_ = nil
    cardParameterStart_ = nil
    cardDeployEnteredMs_ = nil
    cardLastMotionAtMs_ = nil
    cardPointerSamples_ = {}
    cardCandidate_ = nil
    cardGestureDistance_ = 0
    bulletTimeActive_ = false
    launched_ = false
    goalContact_ = false
    goalContactMs_ = 0
    goalPulseElapsedMs_ = nil
    outsideMs_ = 0
    flightMs_ = 0
    stalledMs_ = 0
    phaseTraversing_ = false
    success_ = false
    failed_ = false
    level_.resultOverlayVisible = false
    absorbing_ = false
    absorbElapsedMs_ = 0
    SetReplayMode("none")
    replayTime_ = 0
    replaySpeed_ = 1
    replaySamples_ = {}
    replayEvents_ = {}
    replaySavedApple_ = nil
    cardBurns_ = {}
    cardBurnParticles_ = {}
    burningCardIds_ = {}
    rulePulse_ = nil
    ruleFlash_ = nil
    ruleDeployCount_ = 0
    replayNextSampleMs_ = 0
    replayPreviousSample_ = nil
    RestoreAppleContactMaterial()
    trail_ = {}
    lastTrailAt_ = 0
    sensorAngle_ = 0
    uiElapsed_ = 0
    anger_ = 0
    if InitializeMechanisms then InitializeMechanisms() end
    SetGravity()
    SyncPhysicsUpdateEnabled()
    SetStatus("READY · 等待发射")
end

function ResetExperiment(playResetSound)
    if not apple_ or not level_ then return end
    if level_.physicsProbe then
        level_.physicsProbe:Stop({ apple = apple_ })
    end
    if playResetSound ~= false then PlaySound("reset") end
    rules_ = Rules.NewState()
    InitializeCards()
    observation_ = level_.observation or ""
    isPaused_ = false
    bulletTimeActive_ = false
    apple_.body.bodyType = BT_STATIC
    apple_.body.linearVelocity = Vector2(0, 0)
    apple_.body.angularVelocity = 0
    apple_.node:SetPosition2D(apple_.launcher.spawnWorldX, apple_.launcher.spawnWorldY)
    apple_.node:SetRotation2D(0)
    apple_.body.awake = true
    apple_.body.linearDamping = MatterCalibration.Box2DLinearDamping(apple_.baseFrictionAir)
    apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping(apple_.baseFrictionAir)
    apple_.shape.restitution = MatterCalibration.APPLE_INITIAL_RESTITUTION
    applePreSolveVelocity_ = nil
    apple_.shape.trigger = false
    RestoreAppleContactMaterial()
    launched_ = false
    draggedApple_ = false
    aimPreview_ = nil
    activeCardId_ = nil
    primedCardId_ = nil
    activeCardStart_ = nil
    activeCardPointer_ = nil
    activeCardDragged_ = false
    activeCardDeploying_ = false
    activeCardPressedAt_ = nil
    cardParameterStart_ = nil
    cardDeployEnteredMs_ = nil
    cardLastMotionAtMs_ = nil
    cardPointerSamples_ = {}
    cardCandidate_ = nil
    cardGestureDistance_ = 0
    goalContact_ = false
    goalContactMs_ = 0
    goalPulseElapsedMs_ = nil
    outsideMs_ = 0
    flightMs_ = 0
    stalledMs_ = 0
    phaseTraversing_ = false
    success_ = false
    failed_ = false
    level_.resultOverlayVisible = false
    absorbing_ = false
    absorbElapsedMs_ = 0
    SetReplayMode("none")
    replayTime_ = 0
    replaySpeed_ = 1
    replaySamples_ = {}
    replayEvents_ = {}
    replaySavedApple_ = nil
    cardBurns_ = {}
    cardBurnParticles_ = {}
    burningCardIds_ = {}
    rulePulse_ = nil
    ruleFlash_ = nil
    ruleDeployCount_ = 0
    replayNextSampleMs_ = 0
    replayPreviousSample_ = nil
    trail_ = {}
    lastTrailAt_ = 0
    anger_ = 0
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
    if InitializeMechanisms then InitializeMechanisms() end
    SetGravity()
    SyncPhysicsUpdateEnabled()
    SetStatus("READY · 等待发射")
end

function DesignPointer(screenX, screenY)
    if screenX == nil or screenY == nil then
        local mouse = input.mousePosition
        screenX, screenY = mouse.x, mouse.y
    end
    local x, y = design_:ScreenToLogical(screenX, screenY)
    return x, y
end

-- Touch events carry physical screen coordinates, the same coordinate space as
-- input.mousePosition. A single active touch keeps a gesture from triggering
-- more than one game action on mobile devices.
function PointerState()
    if pointer_.activeTouchId ~= nil or pointer_.touchPressed or pointer_.touchReleased then
        local x, y = DesignPointer(pointer_.touchX, pointer_.touchY)
        local down = pointer_.activeTouchId ~= nil
        local press = pointer_.touchPressed
        local release = pointer_.touchReleased
        pointer_.touchPressed = false
        pointer_.touchReleased = false
        return x, y, down, press, release
    end
    local x, y = DesignPointer()
    return x, y,
        input:GetMouseButtonDown(MOUSEB_LEFT),
        input:GetMouseButtonPress(MOUSEB_LEFT),
        input:GetMouseButtonRelease(MOUSEB_LEFT)
end

function PointerInPlayfield(x, y)
    return x >= frame_.playfieldX + 18 and x <= frame_.playfieldX + frame_.playfieldWidth - 18
        and y >= frame_.playfieldY + 18 and y <= frame_.groundY - 18
end

function PointerToWorld(x, y)
    return design_:LogicalToWorld(x, y)
end

function AppleScreenPosition()
    local p = apple_.node.position2D
    return design_:WorldToLogical(p.x, p.y)
end

function IsNearApple(x, y)
    local ax, ay = AppleScreenPosition()
    local dx, dy = x - ax, y - ay
    return dx * dx + dy * dy <= 46 * 46
end

function UpdateAppleDrag(x, y)
    local launcher = apple_.launcher
    local lx, ly = design_:LevelToLogical(launcher.spawnLevelX, launcher.spawnLevelY)
    local dx, dy = x - lx, y - ly
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 98 then dx, dy = dx * 98 / length, dy * 98 / length end
    dx = math.max(dx, -76)
    dy = math.min(dy, 78)
    aimPreview_ = { x = lx + dx, y = ly + dy, launcherX = lx, launcherY = ly }
    local wx, wy = PointerToWorld(lx + dx, ly + dy)
    apple_.node:SetPosition2D(wx, wy)
end

function LaunchApple()
    draggedApple_ = false
    local launcher = apple_.launcher
    local applePos = apple_.node.position2D
    local dx, dy
    if aimPreview_ then
        dx = aimPreview_.x - aimPreview_.launcherX
        dy = aimPreview_.y - aimPreview_.launcherY
    else
        dx = (applePos.x - launcher.spawnWorldX) * CONFIG.pixelsPerMeter
        dy = -(applePos.y - launcher.spawnWorldY) * CONFIG.pixelsPerMeter
    end
    local length = math.sqrt(dx * dx + dy * dy)
    aimPreview_ = nil
    if length < 24 then ResetExperiment(false); return end
    local vx = -dx * 0.165
    local vy = -dy * 0.165
    local timeScale = CurrentPhysicsTimeScale()
    apple_.body.bodyType = BT_DYNAMIC
    -- Matter restores the material captured by setStatic(false), so a card
    -- played while the apple is still mounted does not survive launch.
    apple_.shape.restitution = MatterCalibration.APPLE_INITIAL_RESTITUTION
    apple_.body.linearVelocity = Vector2(
        vx * 60 / CONFIG.pixelsPerMeter * timeScale,
        -vy * 60 / CONFIG.pixelsPerMeter * timeScale
    )
    apple_.body.angularVelocity = -vx * 0.006 * 60 * timeScale
    apple_.body.linearDamping = MatterCalibration.Box2DLinearDamping(apple_.baseFrictionAir, timeScale)
    apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping(apple_.baseFrictionAir, timeScale)
    apple_.body.awake = true
    Rules.Launch(rules_)
    launched_ = true
    replaySamples_ = {
        {
            t = 0,
            x = applePos.x,
            y = applePos.y,
            vx = apple_.body.linearVelocity.x,
            vy = apple_.body.linearVelocity.y,
            angle = apple_.node.rotation2D,
        },
    }
    replayEvents_ = {}
    replayNextSampleMs_ = CONFIG.replaySampleMs
    replayPreviousSample_ = replaySamples_[1]
    SetGravity()
    SetStatus("FLIGHT · 规则已生效")
    PlaySound("launch")
end

function CancelAppleDrag()
    if not draggedApple_ or launched_ or not apple_ then return end
    draggedApple_ = false
    aimPreview_ = nil
    apple_.node:SetPosition2D(apple_.launcher.spawnWorldX, apple_.launcher.spawnWorldY)
end

function ToggleTacticalPause()
    if success_ or failed_ or absorbing_ then return end
    if not isPaused_ then CancelAppleDrag() end
    isPaused_ = not isPaused_
    if isPaused_ then
        SetStatus("TACTICAL PAUSE 路 规则卡仍可操作")
    else
        SetStatus(launched_ and "RUNNING 路 实验进行中" or "READY 路 等待发射")
    end
end

function IsAppleGoalPair(nodeA, nodeB)
    if not nodeA or not nodeB or not runtime_ then return false end
    local goal = LevelData.FindFirst(level_, "goal_sensor")
    if not goal then return false end
    return (nodeA.name == "Apple" and nodeB.name == goal.id) or (nodeB.name == "Apple" and nodeA.name == goal.id)
end

function IsAppleNode(node)
    return node and node.name == "Apple"
end

function DoorOpenVector(object)
    local distance = object.openDistance * mapper_.objectScale / CONFIG.pixelsPerMeter
    if object.openDirection == "UP" then return 0, distance end
    if object.openDirection == "DOWN" then return 0, -distance end
    if object.openDirection == "LEFT" then return -distance, 0 end
    return distance, 0
end

function DoorBlockedByApple(object)
    if not apple_ then return false end
    local openX, openY = DoorOpenVector(object)
    local position = apple_.node.position2D
    local radius = apple_.radius or 0
    local minX = math.min(object.worldX, object.worldX + openX) - object.worldWidth * 0.5 - radius
    local maxX = math.max(object.worldX, object.worldX + openX) + object.worldWidth * 0.5 + radius
    local minY = math.min(object.worldY, object.worldY + openY) - object.worldHeight * 0.5 - radius
    local maxY = math.max(object.worldY, object.worldY + openY) + object.worldHeight * 0.5 + radius
    return position.x >= minX and position.x <= maxX and position.y >= minY and position.y <= maxY
end

function SetDoorTarget(object, open)
    object.targetOpen = open
    if not open then object.closeAt = uiElapsed_ * 1000 + object.closeDelay end
end

function ApplyDoorSignal(object, active)
    if object.response == "OPEN" then
        SetDoorTarget(object, active)
    elseif object.response == "CLOSE" then
        SetDoorTarget(object, not active)
    elseif active then
        SetDoorTarget(object, not object.targetOpen)
    end
end

function EmitChannelSignal(channelId, active, sourceId)
    if not channelId or channelId == "" then return end
    channelStates_[channelId] = { active = active, sourceId = sourceId }
    if not runtime_ then return end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "door" and object.channelId == channelId then
            ApplyDoorSignal(object, active)
        elseif object.type == "spring" and object.enabledChannel == channelId then
            object.channelEnabled = active
        end
    end
end

function EvaluateButton(object)
    local gravityMultiplier = Rules.GetGravityMultiplier(rules_, level_.rules.initialGravity)
    local conditionSatisfied = object.contactCount > 0 and gravityMultiplier >= object.gravityThreshold
    local activationEdge = not object.conditionSatisfied and conditionSatisfied
    local canActivate = uiElapsed_ * 1000 - object.lastActivationAt >= object.debounceTime
    local nextActive = object.active
    if object.mode == "HOLD" then
        nextActive = conditionSatisfied
    elseif activationEdge and canActivate then
        nextActive = not object.active
    end
    object.conditionSatisfied = conditionSatisfied
    local outputChanged = nextActive ~= object.active
    object.active = nextActive
    if (activationEdge and canActivate) or (object.mode == "HOLD" and outputChanged and nextActive) then
        object.lastActivationAt = uiElapsed_ * 1000
    end
    if outputChanged then EmitChannelSignal(object.channelId, object.active, object.id) end
end

ReevaluateButtons = function()
    if not runtime_ or not level_ then return end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "button" then EvaluateButton(object) end
    end
end

InitializeMechanisms = function()
    channelStates_ = {}
    if not runtime_ then return end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "button" then
            object.active = object.data.properties and object.data.properties.initialState == true or false
            object.contactCount = 0
            object.conditionSatisfied = false
            object.lastActivationAt = -math.huge
        elseif object.type == "door" then
            object.targetOpen = object.data.properties and object.data.properties.initialState == "OPEN" or false
            object.openness = object.targetOpen and 1 or 0
            object.state = object.targetOpen and "OPEN" or "CLOSED"
            object.closeAt = 0
        elseif object.type == "spring" then
            object.channelEnabled = true
        end
    end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "button" then EmitChannelSignal(object.channelId, object.active, object.id) end
    end
end

function UpdateDoors(dt)
    if not runtime_ then return end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "door" then
            local target = object.targetOpen and 1 or 0
            local delta = dt * 1000 / math.max(1, object.duration)
            if object.openness < target then
                object.state = "OPENING"
                object.openness = math.min(target, object.openness + delta)
                if object.openness == 1 then object.state = "OPEN" end
            elseif object.openness > target and uiElapsed_ * 1000 >= object.closeAt then
                if not object.antiCrush or not DoorBlockedByApple(object) then
                    object.state = "CLOSING"
                    object.openness = math.max(target, object.openness - delta)
                    if object.openness == 0 then object.state = "CLOSED" end
                end
            end
            local ox, oy = DoorOpenVector(object)
            object.node:SetPosition2D(object.worldX + ox * object.openness, object.worldY + oy * object.openness)
        end
    end
end

function UpdateSpringExits()
    if not runtime_ or not apple_ then return end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "spring" and object.pendingExitVelocity then
            apple_.body.linearVelocity = object.pendingExitVelocity
            apple_.body.awake = true
            object.pendingExitVelocity = nil
        end
    end
end

function UpdateSpringVisuals(dt)
    if not runtime_ then return end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "spring" and object.pulseElapsedMs ~= nil then
            object.pulseElapsedMs = object.pulseElapsedMs + math.max(0, dt) * 1000
            if object.pulseElapsedMs >= 140 then object.pulseElapsedMs = nil end
        end
    end
end

function CapAppleSpeed()
    if not launched_ or not apple_ or apple_.body.bodyType ~= BT_DYNAMIC then return end
    local velocity = apple_.body.linearVelocity
    local speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
    local maxSpeed = CONFIG.maxAppleSpeed * CurrentPhysicsTimeScale()
    if speed <= maxSpeed then return end
    local scale = maxSpeed / speed
    apple_.body.linearVelocity = Vector2(velocity.x * scale, velocity.y * scale)
    apple_.body.awake = true
end

function IsInsidePhaseableWall(worldX, worldY)
    if not runtime_ then return false end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "wall" and object.phaseable then
            local rotation = math.rad(object.node.rotation2D)
            local dx, dy = worldX - object.worldX, worldY - object.worldY
            local localX = math.cos(rotation) * dx + math.sin(rotation) * dy
            local localY = -math.sin(rotation) * dx + math.cos(rotation) * dy
            if math.abs(localX) <= object.worldWidth * 0.5 and math.abs(localY) <= object.worldHeight * 0.5 then return true end
        end
    end
    return false
end

function UpdatePhaseTraversal()
    if not apple_ or not rules_.phaseActive then return end
    local position = apple_.node.position2D
    if IsInsidePhaseableWall(position.x, position.y) then
        phaseTraversing_ = true
    elseif phaseTraversing_ then
        phaseTraversing_ = false
        Rules.EndPhase(rules_)
        SetGravity()
        UpdateAngerFromRules()
        SetStatus("PHASE · 相位穿墙已消耗")
    end
end

function ApplyDecision(id, mirrorAxis)
    if id == "mirror-motion" then
        if not mirrorAxis then
            SetStatus("CARD · 运动镜像需要明确的方向手势")
            return false
        end
    end
    local cardState = cardStates_[id]
    local reusable = cardState and cardState.usageMode == "REUSABLE"
    if not Rules.UseDecision(rules_, id, reusable) then return false end
    if id == "up-impulse" then
        local v = apple_.body.linearVelocity
        apple_.body.linearVelocity = Vector2(v.x, v.y + 5.52 * CurrentPhysicsTimeScale())
    elseif id == "mirror-motion" then
        local v = apple_.body.linearVelocity
        if mirrorAxis == "HORIZONTAL" then
            apple_.body.linearVelocity = Vector2(-v.x, v.y)
            rules_.mirrorAxis = "HORIZONTAL"
        else
            apple_.body.linearVelocity = Vector2(v.x, -v.y)
            rules_.mirrorAxis = "VERTICAL"
        end
    elseif id == "quantum-phase" then
        phaseTraversing_ = false
        SetGravity()
    end
    ruleDeployCount_ = ruleDeployCount_ + 1
    RecordReplayEvent("CARD_PLAYED", id)
    UpdateAngerFromRules()
    SetStatus("RULE DEPLOYED · " .. (Rules.CARDS[id] and Rules.CARDS[id].name or id))
    StartRuleFeedback(id, mirrorAxis, Rules.CARDS[id] and Rules.CARDS[id].accent)
    PlaySound("card")
    return true
end

function ApplyCardResolution(id, candidate)
    local definition = Rules.CARDS[id]
    if not definition then return false end
    if definition.kind == "field" then
        if id == "side-gravity" then
            if candidate == "LEFT" then rules_.sideGravity = { x = -1, y = 0 }
            elseif candidate == "RIGHT" then rules_.sideGravity = { x = 1, y = 0 }
            elseif candidate == "UP" then rules_.sideGravity = { x = 0, y = -1 }
            elseif candidate == "DOWN" then rules_.sideGravity = { x = 0, y = 1 }
            else return false end
        end
        Rules.DeployField(rules_, id)
        ruleDeployCount_ = ruleDeployCount_ + 1
        SetGravity()
        ApplyAppleCardMaterial()
        RecordReplayEvent("CARD_PLAYED", id)
        UpdateAngerFromRules()
        SetStatus("RULE DEPLOYED · " .. definition.name)
        StartRuleFeedback(id, candidate, definition.accent)
        PlaySound("card")
        return true
    end
    local applied = launched_ and ApplyDecision(id, candidate) or false
    if applied then ApplyAppleCardMaterial() end
    return applied
end

function BurnProgress(burn)
    local animationElapsed = math.max(0, burn.elapsed - burn.delay)
    local linear = math.max(0, math.min(1, animationElapsed / burn.duration))
    return 1 - math.cos(linear * math.pi * .5)
end

function BurnNoise(seed, salt)
    return .5 + .5 * math.sin(seed * 12.9898 + salt * 78.233)
end

function EmitBurnParticles(burn, burst)
    local idSeed = 0
    for index = 1, #burn.id do idSeed = idSeed + string.byte(burn.id, index) * index end
    for index = 0, 4 do
        local seed = idSeed + burst * 17 + index * 7
        local ash = index >= 3
        local leftRight = BurnNoise(seed, 1) * 2 - 1
        local vertical = BurnNoise(seed, 2) * 2 - 1
        cardBurnParticles_[#cardBurnParticles_ + 1] = {
            x = burn.x + leftRight * 68,
            y = burn.y - 101 + BurnProgress(burn) * 202 + vertical * 4,
            dx = (BurnNoise(seed, 3) * 2 - 1) * 24,
            dy = -(42 + BurnNoise(seed, 4) * (ash and 46 or 76)),
            radius = ash and (2 + math.floor(BurnNoise(seed, 5) * 3)) or (2 + math.floor(BurnNoise(seed, 5) * 2)),
            alpha = ash and .65 or .96,
            color = ash and Renderer2D.COLORS.ash or (index % 2 == 0 and Renderer2D.COLORS.burnEdge or Renderer2D.COLORS.spark),
            scaleTarget = ash and .45 or .15,
            delay = 10 + math.floor(BurnNoise(seed, 6) * 81),
            duration = 260 + math.floor(BurnNoise(seed, 7) * 261),
            elapsed = 0,
        }
    end
end

function QueueCardResolution(id, x, y, candidate, pose)
    burningCardIds_[id] = true
    cardBurns_[#cardBurns_ + 1] = {
        id = id,
        x = x,
        y = y,
        candidate = candidate,
        elapsed = 0,
        applyAt = 100,
        delay = 55,
        duration = 690,
        totalDuration = 745,
        emittedBursts = 0,
        applied = false,
        startScale = (pose and pose.scale) or 1.05,
        startAngle = (pose and pose.angle) or 0,
    }
    SetStatus("CARD RESOLVING · 燃烧")
end

function CardEntries()
    local result = {}
    for _, id in ipairs(handOrder_) do
        local card = cardDeckById_[id]
        local state = cardStates_[card.cardId]
        if card.enabled and state and not state.consumed and (state.usageMode == "REUSABLE" or state.remainingUses > 0) then result[#result + 1] = card end
    end
    return result
end

function CardPose(index, count)
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
    return entries[index], poses[index]
end

function CardHomePose(id)
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
    for i, card in ipairs(entries) do
        if card.cardId == id then return poses[i] end
    end
    return nil
end

-- Phaser leaves a dragged card under the pointer while the rest of the hand
-- moves to its new slots over 160 ms. Keep the target layout in handOrder_,
-- and retain only the transient visual interpolation here.
function CardDisplayedPose(id, pose)
    local motion = cardHomeMotions_[id]
    if not motion then
        return { x = pose.x, y = pose.y, angle = pose.angle, depth = pose.depth, scale = 1 }
    end
    local t = motion.duration > 0 and math.min(1, motion.elapsed / motion.duration) or 1
    local eased = 1 - (1 - t) ^ 3
    return {
        x = motion.fromX + (motion.toX - motion.fromX) * eased,
        y = motion.fromY + (motion.toY - motion.fromY) * eased,
        angle = motion.fromAngle + (motion.toAngle - motion.fromAngle) * eased,
        depth = pose.depth,
        scale = motion.fromScale + (motion.toScale - motion.fromScale) * eased,
    }
end

-- Every card-facing system must agree on the same transient pose. In
-- particular, a primed card is not at its nominal hand slot: Phaser lifts it
-- by 10 px, scales it to 1.04 and raises it above the hand before hit testing.
function CardVisualPose(id, pose)
    local displayed = CardDisplayedPose(id, pose)
    local visual = {
        x = displayed.x,
        y = displayed.y,
        angle = displayed.angle,
        depth = displayed.depth,
        scale = displayed.scale or 1,
    }
    if activeCardId_ == id then
        visual.depth = 73
        local pressProgress = activeCardPressedAt_ and math.max(0, math.min(1, (uiElapsed_ - activeCardPressedAt_) / .09)) or 1
        local pressEase = 1 - (1 - pressProgress) ^ 3
        local pressPose = activeCardPressPose_ or visual
        visual.angle = (pressPose.angle or 0) * (1 - pressEase)
        visual.scale = (pressPose.scale or 1) + (1.05 - (pressPose.scale or 1)) * pressEase
        if cardParameterStart_ then
            visual.x, visual.y = cardParameterStart_.x, cardParameterStart_.y
        elseif activeCardDragged_ and activeCardPointer_ then
            visual.x, visual.y = activeCardPointer_.x, activeCardPointer_.y
        else
            -- POINTER_DOWN preserves the card's rendered pose. A direct
            -- touch therefore scales in place; only a prior hover carries
            -- Phaser's 18 px lift into the press.
            visual.x, visual.y = pressPose.x, pressPose.y
        end
        if activeCardDragged_ then visual.angle = 0; visual.scale = 1.05 end
        return visual
    end
    if primedCardId_ == id then
        visual.y = visual.y - 10
        visual.angle = 0
        visual.depth = 73
        visual.scale = visual.scale * 1.04
        return visual
    end
    local hoverState = cardHoverStates_[id]
    local hoverProgress = hoverState and hoverState.value or 0
    if hoverProgress > .001 then
        visual.y = visual.y - 18 * hoverProgress
        visual.angle = 0
        visual.depth = 72
        visual.scale = visual.scale * (1 + hoverProgress * .05)
    end
    return visual
end

function CurrentCardVisualPose(id)
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
    for index, card in ipairs(entries) do
        if card.cardId == id and poses[index] then return CardVisualPose(id, poses[index]) end
    end
    return nil
end

function PrimedCardPose(id)
    local home = CardHomePose(id)
    if not home then return nil end
    return { x = home.x, y = home.y - 10, angle = 0, depth = 73, scale = 1.04 }
end

function UpdateCardHomeMotions(dt)
    for id, motion in pairs(cardHomeMotions_) do
        motion.elapsed = motion.elapsed + dt
        if motion.elapsed >= motion.duration then cardHomeMotions_[id] = nil end
    end
end

function AnimateCardToHome(id, from, duration)
    local home = CardHomePose(id)
    if not home or not from then return end
    cardHomeMotions_[id] = {
        fromX = from.x,
        fromY = from.y,
        fromAngle = from.angle or 0,
        fromScale = from.scale or 1,
        toX = home.x,
        toY = home.y,
        toAngle = home.angle,
        toScale = 1,
        elapsed = 0,
        duration = duration,
    }
end

---@param id string
---@param targetIndex integer
---@return boolean
function MoveCardToHandSlot(id, targetIndex)
    local entries = CardEntries()
    local currentIndex = nil
    local currentPoses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
    local displayed = {}
    for i, card in ipairs(entries) do
        local pose = currentPoses[i]
        if card.cardId == id then currentIndex = i end
        if pose then displayed[card.cardId] = CardDisplayedPose(card.cardId, pose) end
    end
    if not currentIndex or currentIndex == targetIndex then return false end

    targetIndex = math.max(1, math.min(#entries, targetIndex))
    local desired = {}
    for i, card in ipairs(entries) do desired[i] = card.cardId end
    table.remove(desired, currentIndex)
    table.insert(desired, targetIndex, id)

    -- handOrder_ also retains cards that may no longer be drawable. Rewrite
    -- only the active entries so those hidden cards preserve their positions.
    local available = {}
    for _, card in ipairs(entries) do available[card.cardId] = true end
    local nextDesired = 1
    for index, cardId in ipairs(handOrder_) do
        if available[cardId] then
            handOrder_[index] = desired[nextDesired]
            nextDesired = nextDesired + 1
        end
    end

    local reordered = CardEntries()
    local targetPoses = Rules.CardHand(#reordered, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
    for i, card in ipairs(reordered) do
        if card.cardId ~= id then
            local from = displayed[card.cardId] or targetPoses[i]
            local target = targetPoses[i]
            if from and target then
                cardHomeMotions_[card.cardId] = {
                    fromX = from.x,
                    fromY = from.y,
                    fromAngle = from.angle,
                    fromScale = from.scale or 1,
                    toX = target.x,
                    toY = target.y,
                    toAngle = target.angle,
                    toScale = 1,
                    elapsed = 0,
                    duration = .16,
                }
            end
        end
    end
    return true
end

function UpdateCardHoverStates(dt)
    for _, card in ipairs(CardEntries()) do
        local state = cardHoverStates_[card.cardId]
        if state then
            state.elapsed = math.min(state.duration, state.elapsed + dt)
            local t = state.duration > 0 and state.elapsed / state.duration or 1
            local eased = 1 - (1 - t) ^ 3
            state.value = state.from + (state.target - state.from) * eased
        end
    end
end

function SetHoveredCard(id)
    if hoveredCardId_ == id then return end
    hoveredCardId_ = id
    for _, card in ipairs(CardEntries()) do
        local state = cardHoverStates_[card.cardId] or { value = 0, from = 0, target = 0, elapsed = 0, duration = .11 }
        local target = card.cardId == id and 1 or 0
        if state.target ~= target then
            state.from = state.value
            state.target = target
            state.elapsed = 0
            state.duration = .11
        end
        cardHoverStates_[card.cardId] = state
    end
end

function CardHoverProgress(id)
    local state = cardHoverStates_[id]
    return state and state.value or 0
end

function FindTopCardAt(x, y)
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
    local found, foundDepth, foundIndex = nil, -math.huge, -math.huge
    for i, card in ipairs(entries) do
        local pose = CardVisualPose(card.cardId, poses[i])
        if pose and not burningCardIds_[card.cardId] then
            local radians = math.rad(-pose.angle)
            local dx, dy = x - pose.x, y - pose.y
            local scale = pose.scale or 1
            local localX = (math.cos(radians) * dx - math.sin(radians) * dy) / scale
            local localY = (math.sin(radians) * dx + math.cos(radians) * dy) / scale
            if math.abs(localX) <= 72 and math.abs(localY) <= 101
                and (pose.depth > foundDepth or (pose.depth == foundDepth and i > foundIndex)) then
                found, foundDepth, foundIndex = card, pose.depth, i
            end
        end
    end
    return found
end

function UpdateHoverState(x, y)
    hoveredNavigation_ = nil
    hoveredLevelIndex_ = nil
    punchHovered_ = false
    if replayActive_ or success_ or failed_ then
        SetHoveredCard(nil)
        return
    end

    local titleX = frame_.workspaceX - 37
    if x >= titleX + 255 and x <= titleX + 301 and y >= 23 and y <= 69 then
        hoveredNavigation_ = "back"
    elseif x >= titleX + 315 and x <= titleX + 361 and y >= 23 and y <= 69 then
        hoveredNavigation_ = "reset"
    elseif not isPaused_ and x >= titleX + 375 and x <= titleX + 421 and y >= 23 and y <= 69 then
        hoveredNavigation_ = "pause"
    end

    local tabStartX = frame_.playfieldX + frame_.playfieldWidth - 290
    for index = 1, CONFIG.levelCount do
        local dx, dy = x - (tabStartX + (index - 1) * 27), y - 46
        if dx * dx + dy * dy <= 10 * 10 then
            hoveredLevelIndex_ = index
            break
        end
    end

    local punchX, punchY = frame_.playfieldX + frame_.playfieldWidth - 58, frame_.cardHandY + 23
    punchHovered_ = x >= punchX - 40 and x <= punchX + 40 and y >= punchY - 40 and y <= punchY + 40
    if activeCardId_ or primedCardId_ or #cardBurns_ > 0 or isPaused_ then
        SetHoveredCard(nil)
    else
        local card = FindTopCardAt(x, y)
        SetHoveredCard(card and card.cardId or nil)
    end
end

function TryCardPress(x, y)
    local card = FindTopCardAt(x, y)
    if not card then return false end
    local pressPose = CurrentCardVisualPose(card.cardId)
    if primedCardId_ and primedCardId_ ~= card.cardId then
        local previous = primedCardId_
        primedCardId_ = nil
        AnimateCardToHome(previous, PrimedCardPose(previous), .12)
    end
    activeCardId_ = card.cardId
    activeCardStart_ = { x = x, y = y }
    activeCardPointer_ = { x = x, y = y }
    activeCardDragged_ = false
    activeCardDeploying_ = false
    activeCardPressedAt_ = uiElapsed_
    activeCardPressPose_ = pressPose
    cardHandReordering_ = false
    cardParameterStart_ = nil
    cardDeployEnteredMs_ = nil
    cardLastMotionAtMs_ = nil
    cardPointerSamples_ = {}
    cardCandidate_ = nil
    cardGestureDistance_ = 0
    SetHoveredCard(nil)
    SetStatus("CARD · 按住拖动或再次点击预备")
    return true
end

function ClearCardInteraction()
    activeCardStart_ = nil
    activeCardPointer_ = nil
    activeCardDragged_ = false
    activeCardDeploying_ = false
    activeCardPressedAt_ = nil
    activeCardPressPose_ = nil
    cardHandReordering_ = false
    cardParameterStart_ = nil
    cardDeployEnteredMs_ = nil
    cardLastMotionAtMs_ = nil
    cardPointerSamples_ = {}
    cardCandidate_ = nil
    cardGestureDistance_ = 0
end

function UpdateCardParameter(dt)
    if not activeCardId_ or not activeCardPointer_ or not activeCardDeploying_ then return end
    if activeCardId_ ~= "side-gravity" and activeCardId_ ~= "mirror-motion" then return end
    local pointer = activeCardPointer_
    -- Before settling, Phaser requires the pointer to be in the playfield.
    -- Once the anchor exists, POINTER_UP_OUTSIDE still resolves from that
    -- fixed anchor; releasing outside must not destroy an already valid gesture.
    if not cardParameterStart_ and not PointerInPlayfield(pointer.x, pointer.y) then
        cardParameterStart_ = nil
        cardDeployEnteredMs_ = nil
        cardLastMotionAtMs_ = nil
        cardPointerSamples_ = {}
        cardCandidate_ = nil
        cardGestureDistance_ = 0
        return
    end
    if not cardParameterStart_ then
        local now = uiElapsed_ * 1000
        if not cardDeployEnteredMs_ then
            cardDeployEnteredMs_ = now
            cardLastMotionAtMs_ = now
            cardPointerSamples_ = { { x = pointer.x, y = pointer.y, at = now } }
            return
        end
        local previous = cardPointerSamples_[#cardPointerSamples_]
        local elapsed = math.max(1, now - previous.at)
        local stepX, stepY = pointer.x - previous.x, pointer.y - previous.y
        if math.sqrt(stepX * stepX + stepY * stepY) / elapsed > .08 then cardLastMotionAtMs_ = now end
        cardPointerSamples_[#cardPointerSamples_ + 1] = { x = pointer.x, y = pointer.y, at = now }
        local cutoff = now - 140
        while #cardPointerSamples_ > 2 and cardPointerSamples_[2].at < cutoff do table.remove(cardPointerSamples_, 1) end
        local recentDistance = 0
        for i = 2, #cardPointerSamples_ do
            local from, to = cardPointerSamples_[i - 1], cardPointerSamples_[i]
            local dx, dy = to.x - from.x, to.y - from.y
            recentDistance = recentDistance + math.sqrt(dx * dx + dy * dy)
        end
        local sampleSpan = now - cardPointerSamples_[1].at
        if now - cardDeployEnteredMs_ >= 100 and sampleSpan >= 112
            and recentDistance <= 8 and now - cardLastMotionAtMs_ >= 150 then
            cardParameterStart_ = { x = pointer.x, y = pointer.y }
            cardCandidate_ = nil
            cardGestureDistance_ = 0
            SetStatus(activeCardId_ == "side-gravity" and "PARAMETER · 四向滑动选择重力" or "PARAMETER · 滑动选择镜像轴")
        end
        return
    end
    local dx, dy = pointer.x - cardParameterStart_.x, pointer.y - cardParameterStart_.y
    cardGestureDistance_ = math.sqrt(dx * dx + dy * dy)
    if cardGestureDistance_ < 28 then
        cardCandidate_ = nil
    elseif activeCardId_ == "side-gravity" then
        local horizontal = cardCandidate_ and math.abs(math.abs(dx) - math.abs(dy)) < 8
            and (cardCandidate_ == "LEFT" or cardCandidate_ == "RIGHT") or math.abs(dx) >= math.abs(dy)
        if horizontal then cardCandidate_ = dx >= 0 and "RIGHT" or "LEFT" else cardCandidate_ = dy >= 0 and "DOWN" or "UP" end
    else
        if not (cardCandidate_ and math.abs(math.abs(dx) - math.abs(dy)) < 8) then
            cardCandidate_ = math.abs(dx) >= math.abs(dy) and "HORIZONTAL" or "VERTICAL"
        end
    end
end

function ResolveActiveCard(x, y)
    local id = activeCardId_
    if not id then return end
    local candidate = cardCandidate_
    local gestureDistance = cardGestureDistance_
    local wasDragged = activeCardDragged_
    local wasDeploying = activeCardDeploying_
    if not wasDragged then
        -- Phaser's primed transition starts from the nominal slot, not an
        -- interrupted hand-reorder tween.
        cardHomeMotions_[id] = nil
        if primedCardId_ == id then
            local from = PrimedCardPose(id)
            primedCardId_ = nil
            activeCardId_ = nil
            AnimateCardToHome(id, from, .12)
            SetStatus(launched_ and "RUNNING · 实验进行中" or "READY · 等待发射")
        else
            activeCardId_ = nil
            primedCardId_ = id
            SetStatus("BULLET TIME · 0.05")
        end
        ClearCardInteraction()
        return
    end
    primedCardId_ = nil
    if not wasDeploying then
        local from = CurrentCardVisualPose(id)
        activeCardId_ = nil
        AnimateCardToHome(id, from, cardHandReordering_ and .12 or .18)
        ClearCardInteraction()
        return
    end
    local needsParameter = id == "side-gravity" or id == "mirror-motion"
    local deployment = needsParameter and cardParameterStart_ or { x = x, y = y }
    if not deployment or not PointerInPlayfield(deployment.x, deployment.y) then
        local from = CurrentCardVisualPose(id)
        activeCardId_ = nil
        AnimateCardToHome(id, from, .18)
        ClearCardInteraction()
        return
    end
    if id == "side-gravity" and (not candidate or gestureDistance < 48) then
        SetStatus("CARD · 横向引力需要明确的方向手势")
        local from = CurrentCardVisualPose(id)
        activeCardId_ = nil
        AnimateCardToHome(id, from, .18)
        ClearCardInteraction()
        return
    end
    if id == "mirror-motion" and (not candidate or gestureDistance < 48) then
        SetStatus("CARD · 运动镜像需要明确的方向手势")
        local from = CurrentCardVisualPose(id)
        activeCardId_ = nil
        AnimateCardToHome(id, from, .18)
        ClearCardInteraction()
        return
    end
    if Rules.CARDS[id].kind == "decision" and not launched_ then
        SetStatus("CARD · 当前没有已发射的实验对象")
        local from = CurrentCardVisualPose(id)
        activeCardId_ = nil
        AnimateCardToHome(id, from, .18)
        ClearCardInteraction()
        return
    end
    local burnPose = CurrentCardVisualPose(id)
    activeCardId_ = nil
    QueueCardResolution(id, deployment.x, deployment.y, candidate, burnPose)
    ClearCardInteraction()
end

function IsResultOverlayVisible()
    return level_ and level_.resultOverlayVisible == true
end

function HandleReplayPointer(x, y, press)
    if not press then return end
    local cx, cy = frame_.playfieldX + frame_.playfieldWidth * .5, frame_.playfieldY + 34
    if replayFinished_ then
        local endX = frame_.playfieldX + frame_.playfieldWidth - 190
        local endY = frame_.playfieldY + frame_.playfieldHeight - 54
        local function inEndButton(offsetX, width)
            return x >= endX + offsetX - width * .5 and x <= endX + offsetX + width * .5
                and y >= endY - 17 and y <= endY + 17
        end
        if inEndButton(38, 92) then
            replayTime_ = 0
            SetReplayMode("playing")
            ReplayLog("restart")
            return
        elseif inEndButton(137, 84) then
            StopReplay()
            return
        end
    end
    local function inButton(buttonX, width)
        return x >= buttonX - width * .5 and x <= buttonX + width * .5 and y >= cy - 17 and y <= cy + 17
    end
    if inButton(cx - 92, 44) then
        if replayFinished_ then
            replayTime_ = 0
            SetReplayMode("playing")
            ReplayLog("restart")
        else
            SetReplayMode(replayMode_ == "paused" and "playing" or "paused")
            ReplayLog(replayMode_ == "paused" and "pause" or "resume")
        end
    elseif inButton(cx - 27, 58) then
        replaySpeed_ = .5
    elseif inButton(cx + 37, 58) then
        replaySpeed_ = 1
    elseif inButton(cx + 101, 58) then
        replaySpeed_ = 2
    elseif inButton(cx + 238, 78) then
        StopReplay()
    end
end

function HandlePointer()
    if not frame_ or not apple_ then return end
    local x, y, down, press, release = PointerState()
    UpdateHoverState(x, y)
    if replayActive_ then HandleReplayPointer(x, y, press); return end
    if IsResultOverlayVisible() then
        if press then
            local cx, cy = frame_.playfieldX + frame_.playfieldWidth * .5, frame_.playfieldY + frame_.playfieldHeight * .5
            local function inOverlayButton(buttonX, buttonY)
                return x >= buttonX - 73 and x <= buttonX + 73 and y >= buttonY - 23 and y <= buttonY + 23
            end
            if failed_ and inOverlayButton(cx, cy + 60) then
                ResetExperiment()
            elseif success_ then
                if inOverlayButton(cx - 160, cy + 65) then
                    BuildLevel(levelIndex_ < CONFIG.levelCount and levelIndex_ + 1 or 1)
                elseif inOverlayButton(cx, cy + 65) then
                    StartReplay()
                elseif inOverlayButton(cx + 160, cy + 65) then
                    ResetExperiment()
                end
            end
        end
        return
    end
    if press then
        local titleX = frame_.workspaceX - 37
        local tabStartX = frame_.playfieldX + frame_.playfieldWidth - 290
        for index = 1, CONFIG.levelCount do
            local tabX = tabStartX + (index - 1) * 27
            local dx, dy = x - tabX, y - 46
            if dx * dx + dy * dy <= 10 * 10 then
                BuildLevel(index)
                return
            end
        end
        if x >= titleX + 255 and x <= titleX + 301 and y >= 23 and y <= 69 then
            -- Phaser's back action falls back to restarting this level when
            -- browser history is unavailable, which is the Maker runtime case.
            ResetExperiment()
        elseif x >= titleX + 315 and x <= titleX + 361 and y >= 23 and y <= 69 then
            ResetExperiment()
        elseif x >= titleX + 375 and x <= titleX + 421 and y >= 23 and y <= 69 then
            ToggleTacticalPause()
        elseif x >= frame_.playfieldX + frame_.playfieldWidth - 98 and x <= frame_.playfieldX + frame_.playfieldWidth - 18
            and y >= frame_.cardHandY - 17 and y <= frame_.cardHandY + 63 then
            if Rules.Punch(rules_) then
                phaseTraversing_ = false
                SetGravity()
                ApplyAppleCardMaterial()
                UpdateAngerFromRules()
                RecordReplayEvent("NEWTON_PUNCH")
                SetStatus("NEWTON · 修正拳已出手")
                PlaySound("punch")
            end
        elseif not isPaused_ and not launched_ and IsNearApple(x, y) then
            draggedApple_ = true
        else
            TryCardPress(x, y)
        end
    end
    if down and draggedApple_ and not launched_ then UpdateAppleDrag(x, y) end
    if down and activeCardId_ and activeCardStart_ then
        local dx, dy = x - activeCardStart_.x, y - activeCardStart_.y
        if dx * dx + dy * dy >= 12 * 12 then activeCardDragged_ = true end
        activeCardPointer_ = { x = x, y = y }
        if activeCardDragged_ and not activeCardDeploying_ then
            local home = CardHomePose(activeCardId_)
            if home and y >= home.y - 40 then
                if not cardHandReordering_ then
                    cardHandReordering_ = true
                    SetStatus("HAND · 调整卡牌顺序")
                end
                local entries = CardEntries()
                local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
                local target, nearest = 1, math.huge
                for i, pose in ipairs(poses) do
                    local distance = math.abs(x - pose.x)
                    if distance < nearest then target, nearest = i, distance end
                end
                MoveCardToHandSlot(activeCardId_, target)
            elseif home then
                activeCardDeploying_ = true
                cardHandReordering_ = false
                SetStatus("CARD DRAGGING · 子弹时间 0.05")
            end
        end
    end
    if release then
        if draggedApple_ then LaunchApple() end
        if activeCardId_ then ResolveActiveCard(x, y) end
    end
end

function ResetGoal()
    goalContact_ = false
    goalContactMs_ = 0
    local goal = level_ and LevelData.FindFirst(level_, "goal_sensor") or nil
    local runtimeGoal = goal and runtime_ and runtime_.byId[goal.id] or nil
    if runtimeGoal then runtimeGoal.active = false; runtimeGoal.contactProgress = 0 end
end

function RecordReplay(dt)
    if not launched_ or replayActive_ or not apple_ then return end
    local p = apple_.node.position2D
    local v = apple_.body.linearVelocity
    local current = {
        t = flightMs_,
        x = p.x,
        y = p.y,
        vx = v.x,
        vy = v.y,
        angle = apple_.node.rotation2D,
    }
    local previous = replayPreviousSample_ or current
    local simulationDelta = math.max(0, dt * 1000)
    local frameStart = flightMs_ - simulationDelta
    while replayNextSampleMs_ <= flightMs_ + .0001 do
        local progress = simulationDelta > 0 and math.max(0, math.min(1, (replayNextSampleMs_ - frameStart) / simulationDelta)) or 1
        local deltaAngle = ((current.angle - previous.angle + 540) % 360) - 180
        replaySamples_[#replaySamples_ + 1] = {
            t = replayNextSampleMs_,
            x = previous.x + (current.x - previous.x) * progress,
            y = previous.y + (current.y - previous.y) * progress,
            vx = previous.vx + (current.vx - previous.vx) * progress,
            vy = previous.vy + (current.vy - previous.vy) * progress,
            angle = previous.angle + deltaAngle * progress,
        }
        replayNextSampleMs_ = replayNextSampleMs_ + CONFIG.replaySampleMs
    end
    replayPreviousSample_ = current
end

function CaptureReplayFinalSample()
    if not apple_ or #replaySamples_ == 0 then return end
    local last = replaySamples_[#replaySamples_]
    ---@type number
    local terminalTime = flightMs_
    if last and math.abs((last.t or 0) - terminalTime) < .001 then
        -- A successful launch normally has many samples. Keep the rare
        -- zero-duration terminal record replayable instead of leaving the
        -- success modal wired to a no-op button.
        if #replaySamples_ > 1 then return end
        terminalTime = (last.t or 0) + CONFIG.replaySampleMs
    end
    local p, v = apple_.node.position2D, apple_.body.linearVelocity
    replaySamples_[#replaySamples_ + 1] = {
        t = terminalTime, x = p.x, y = p.y, vx = v.x, vy = v.y, angle = apple_.node.rotation2D,
    }
    replayPreviousSample_ = replaySamples_[#replaySamples_]
end

RecordReplayEvent = function(kind, cardId)
    if not launched_ or replayActive_ then return end
    local p = apple_.node.position2D
    replayEvents_[#replayEvents_ + 1] = { t = flightMs_, type = kind, cardId = cardId, x = p.x, y = p.y }
end

function ReplayDuration()
    local last = replaySamples_[#replaySamples_]
    return last and last.t or 0
end

function CanReplay()
    return #replaySamples_ >= 2 and ReplayDuration() > 0
end

function ReplayStateAt(time)
    if #replaySamples_ == 0 then return nil end
    if #replaySamples_ == 1 or time <= replaySamples_[1].t then return replaySamples_[1] end
    for i = 2, #replaySamples_ do
        local before, after = replaySamples_[i - 1], replaySamples_[i]
        if time <= after.t then
            local span = math.max(.001, after.t - before.t)
            local progress = math.max(0, math.min(1, (time - before.t) / span))
            local deltaAngle = ((after.angle - before.angle + 540) % 360) - 180
            return {
                x = before.x + (after.x - before.x) * progress,
                y = before.y + (after.y - before.y) * progress,
                vx = before.vx + (after.vx - before.vx) * progress,
                vy = before.vy + (after.vy - before.vy) * progress,
                angle = before.angle + deltaAngle * progress,
            }
        end
    end
    return replaySamples_[#replaySamples_]
end

StartReplay = function()
    if replayActive_ or not apple_ or not (success_ or failed_) then return false end
    CaptureReplayFinalSample()
    if not CanReplay() then
        -- Phaser only constructs a replay from a real recorded timeline. A
        -- fabricated 33 ms record finishes on the next frame and looks frozen.
        SetStatus("REPLAY · 轨迹记录不足")
        ReplayLog("rejected")
        return false
    end
    local p, v = apple_.node.position2D, apple_.body.linearVelocity
    replaySavedApple_ = {
        x = p.x, y = p.y, angle = apple_.node.rotation2D,
        bodyType = apple_.body.bodyType, vx = v.x, vy = v.y, angularVelocity = apple_.body.angularVelocity,
    }
    level_.resultOverlayVisible = false
    SetReplayMode("playing")
    absorbing_ = false
    absorbElapsedMs_ = 0
    ResetGoal()
    isPaused_ = false
    SetBulletTimeActive(false)
    replayTime_ = 0
    replaySpeed_ = 1
    ClearCardInteraction()
    apple_.body.bodyType = BT_STATIC
    apple_.body.linearVelocity = Vector2(0, 0)
    apple_.body.angularVelocity = 0
    RestoreAppleContactMaterial()
    SyncPhysicsUpdateEnabled()
    SetStatus("REPLAY · 轨迹回放")
    ReplayLog("start")
    return true
end

StopReplay = function()
    if not replayActive_ or not apple_ then return end
    local saved = replaySavedApple_
    SetReplayMode("none")
    replayTime_ = 0
    replaySavedApple_ = nil
    isPaused_ = false
    if saved then
        apple_.node:SetPosition2D(saved.x, saved.y)
        apple_.node:SetRotation2D(saved.angle)
        apple_.body.bodyType = saved.bodyType
        apple_.body.linearVelocity = Vector2(saved.vx, saved.vy)
        apple_.body.angularVelocity = saved.angularVelocity
        apple_.body.awake = true
    end
    RestoreAppleContactMaterial()
    SyncPhysicsUpdateEnabled()
    level_.resultOverlayVisible = success_ or failed_
    if success_ then SetStatus("CLEARED · 观测成立")
    elseif failed_ then SetStatus("FAILED · 实验未成立")
    else SetStatus(launched_ and "FLIGHT · 规则已生效" or "READY · 等待发射") end
    ReplayLog("exit")
end

function UpdateReplay(dt)
    if replayMode_ ~= "playing" then return end
    replayTime_ = math.min(ReplayDuration(), replayTime_ + math.max(0, dt) * 1000 * replaySpeed_)
    if replayTime_ >= ReplayDuration() then
        SetReplayMode("finished")
        ReplayLog("finished")
    end
end

function RegisterFailure()
    failureCount_ = failureCount_ + 1
    if level_ then failureCountsByLevel_[level_.levelId] = failureCount_ end
    observation_ = "轨迹停止。重置后再次发射。"
    if level_ then level_.resultOverlayVisible = true end
    SetStatus("FAILED · 实验未成立")
end

function UpdateExperiment(dt)
    if replayActive_ then return end
    if absorbing_ then
        if goalPulseElapsedMs_ ~= nil then
            goalPulseElapsedMs_ = goalPulseElapsedMs_ + math.max(0, dt) * 1000
            if goalPulseElapsedMs_ >= 460 then goalPulseElapsedMs_ = nil end
        end
        absorbElapsedMs_ = math.min(520, absorbElapsedMs_ + math.max(0, dt) * 1000)
        if absorbElapsedMs_ >= 520 then
            absorbing_ = false
            success_ = true
            if level_ then level_.resultOverlayVisible = true end
            SetStatus("CLEARED · 观测成立")
        end
        return
    end
    if not launched_ then return end
    flightMs_ = flightMs_ + dt * 1000
    RecordReplay(dt)
    UpdatePhaseTraversal()
    local p = apple_.node.position2D
    local screenX, screenY = design_:WorldToLogical(p.x, p.y)
    if flightMs_ - lastTrailAt_ > 55 then
        trail_[#trail_ + 1] = { x = screenX, y = screenY }
        if #trail_ > 18 then table.remove(trail_, 1) end
        lastTrailAt_ = flightMs_
    end
    if goalContact_ then
        goalContactMs_ = goalContactMs_ + dt * 1000
        local goal = LevelData.FindFirst(level_, "goal_sensor")
        local runtimeGoal = goal and runtime_.byId[goal.id] or nil
        local requiredStayTime = runtimeGoal and runtimeGoal.requiredStayTime or 700
        if runtimeGoal then
            runtimeGoal.contactMs = goalContactMs_
            runtimeGoal.contactProgress = math.max(0, math.min(1, goalContactMs_ / requiredStayTime))
            runtimeGoal.active = true
        end
        local velocity = apple_.body.linearVelocity
        local matterSpeed = CurrentMatterSpeedFromWorld(velocity)
        if goalContactMs_ >= requiredStayTime and matterSpeed <= 4.8 then
            CaptureReplayFinalSample()
            absorbing_ = true
            absorbElapsedMs_ = 0
            goalPulseElapsedMs_ = 0
            launched_ = false
            apple_.body.bodyType = BT_STATIC
            apple_.body.linearVelocity = Vector2(0, 0)
            apple_.shape.trigger = true
            activeCardId_ = nil
            primedCardId_ = nil
            ClearCardInteraction()
            observation_ = "苹果已在爱因斯坦观察窗内稳定停留。"
            SetStatus("CLEARED · 观察成立")
            PlaySound("success")
        end
    else goalContactMs_ = 0 end
    if screenX < frame_.playfieldX - 120 or screenX > frame_.playfieldX + frame_.playfieldWidth + 120
        or screenY < frame_.playfieldY - 140 or screenY > frame_.playfieldY + frame_.playfieldHeight + 140 then
        CaptureReplayFinalSample()
        failed_ = true
        launched_ = false
        apple_.body.bodyType = BT_STATIC
        RegisterFailure()
    else
        local velocity = apple_.body.linearVelocity
        local matterSpeed = CurrentMatterSpeedFromWorld(velocity)
        stalledMs_ = matterSpeed < 0.1 and stalledMs_ + dt * 1000 or 0
        if stalledMs_ > 5200 then
            CaptureReplayFinalSample()
            failed_ = true
            launched_ = false
            apple_.body.bodyType = BT_STATIC
            RegisterFailure()
        end
    end
    if math.abs(p.x) > 7.5 or math.abs(p.y) > 5 then anger_ = math.min(100, anger_ + dt * 2) end
    UpdateDoors(dt)
end

function DrawPrediction(direction, alpha, x, y, velocityX, velocityY)
    if not apple_ or not level_ then return end
    if x == nil or y == nil then x, y = AppleScreenPosition() end
    if velocityX == nil or velocityY == nil then
        local velocity = apple_.body.linearVelocity
        local conversion = CurrentMatterVelocityToWorld()
        velocityX = velocity.x / conversion
        velocityY = -velocity.y / conversion
    end
    local gravity = Rules.GetGravity(rules_, level_.rules.initialGravity)
    local gravityX, gravityY = gravity.x * gravity.strength, gravity.y * gravity.strength
    if direction then
        gravityX, gravityY = 0, 0
        if direction == "LEFT" then gravityX = -gravity.strength
        elseif direction == "RIGHT" then gravityX = gravity.strength
        elseif direction == "UP" then gravityY = -gravity.strength
        else gravityY = gravity.strength end
    end
    local points = TrajectoryPrediction.PredictFreeFlight({
        x = x,
        y = y,
        velocityX = velocityX,
        velocityY = velocityY,
        gravityX = gravityX,
        gravityY = gravityY,
        frictionAir = MatterCalibration.APPLE_FRICTION_AIR,
        forceScale = 0.001,
        maxSpeed = 25,
        steps = 30,
        sampleEvery = 3,
    })
    for _, point in ipairs(points) do
        if point.x < frame_.playfieldX or point.x > frame_.playfieldX + frame_.playfieldWidth
            or point.y < frame_.playfieldY or point.y > frame_.playfieldY + frame_.playfieldHeight then break end
        local pointAlpha = math.max(0.18, math.min(alpha, alpha - point.frame / 75))
        painter_:Circle(point.x, point.y, point.frame % 6 == 0 and 3.5 or 2, Renderer2D.COLORS.primary, nil, nil, math.floor(pointAlpha * 255))
    end
end

function DrawAim()
    if not draggedApple_ or not aimPreview_ then return end
    local x, y = aimPreview_.x, aimPreview_.y
    local lx, ly = aimPreview_.launcherX, aimPreview_.launcherY
    nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 224)); nvgStrokeWidth(painter_.vg, 6)
    nvgBeginPath(painter_.vg)
    nvgMoveTo(painter_.vg, lx - 18, ly + 4)
    nvgLineTo(painter_.vg, x, y)
    nvgLineTo(painter_.vg, lx + 18, ly + 4)
    nvgStroke(painter_.vg)
    DrawPrediction(nil, 0.55, x, y, -(x - lx) * .165, -(y - ly) * .165)
end

function DrawCardPrediction()
    if not activeCardId_ or not cardParameterStart_ or not cardCandidate_ then return end
    local x, y = AppleScreenPosition()
    if activeCardId_ == "side-gravity" then
        DrawPrediction(cardCandidate_, 0.88, x, y)
    elseif activeCardId_ == "mirror-motion" then
        local velocity = apple_.body.linearVelocity
        local conversion = CurrentMatterVelocityToWorld()
        local vx = velocity.x / conversion
        local vy = -velocity.y / conversion
        if cardCandidate_ == "HORIZONTAL" then vx = -vx else vy = -vy end
        DrawPrediction(nil, 0.88, x, y, vx, vy)
    end
end

function DrawLaunchHint()
    if launched_ or draggedApple_ or absorbing_ or success_ or failed_ or not apple_ then return end
    local launcher = apple_.launcher
    local lx, ly = design_:LevelToLogical(launcher.spawnLevelX, launcher.spawnLevelY)
    local hintX, hintY = lx + 76, ly - 60
    painter_:RoundedRect(hintX - 78, hintY - 18, 156, 36, 0, Renderer2D.COLORS.panel, nil, nil, 232)
    painter_:Text(hintX, hintY - 7, "拖动苹果，松开发射", 14, Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local pulse = (math.sin(uiElapsed_ * math.pi * 2 / .9) + 1) * .5
    painter_:Circle(lx + 20 - pulse * 60, ly + 16 + pulse * 18, 5, Renderer2D.COLORS.primaryActive, nil, nil, math.floor(208 - pulse * 170))
end

function DrawTrail()
    for i, point in ipairs(trail_) do
        local progress = i / #trail_
        painter_:Circle(point.x, point.y, 1.5 + progress * 3, Renderer2D.COLORS.primary, nil, nil, math.floor(progress * .32 * 255))
    end
end

function DrawVelocityArrow()
    if not apple_ then return end
    local x, y = AppleScreenPosition()
    local velocity = apple_.body.linearVelocity
    local conversion = CurrentMatterVelocityToWorld()
    local vx = velocity.x / conversion
    local vy = -velocity.y / conversion
    local length = math.min(58, math.sqrt(vx * vx + vy * vy) * 3.4)
    if length < 8 then return end
    local angle = math.atan(vy, vx)
    local endX, endY = x + math.cos(angle) * length, y + math.sin(angle) * length
    nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 184)); nvgStrokeWidth(painter_.vg, 3)
    nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, x, y); nvgLineTo(painter_.vg, endX, endY); nvgStroke(painter_.vg)
    nvgFillColor(painter_.vg, nvgRGBA(95, 143, 104, 204)); nvgBeginPath(painter_.vg)
    nvgMoveTo(painter_.vg, endX, endY)
    nvgLineTo(painter_.vg, endX - math.cos(angle - .55) * 10, endY - math.sin(angle - .55) * 10)
    nvgLineTo(painter_.vg, endX - math.cos(angle + .55) * 10, endY - math.sin(angle + .55) * 10)
    nvgClosePath(painter_.vg); nvgFill(painter_.vg)
end

function DrawRulePulse()
    if not rulePulse_ then return end
    local progress = math.max(0, math.min(1, rulePulse_.elapsed / rulePulse_.duration))
    painter_:FillRect(
        frame_.playfieldX,
        frame_.playfieldY,
        frame_.playfieldWidth,
        frame_.playfieldHeight,
        rulePulse_.color,
        math.floor((1 - progress) * .13 * 255)
    )
end

function DrawRuleFlash()
    if not ruleFlash_ or not apple_ then return end
    local progress = math.max(0, math.min(1, ruleFlash_.elapsed / ruleFlash_.duration))
    local x, y = AppleScreenPosition()
    local scale = 1 + progress * .2
    painter_:Text(
        x,
        y - 18 - progress * 72,
        ruleFlash_.symbol,
        50 * scale,
        ruleFlash_.color,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE,
        "maker-display",
        math.floor((1 - progress) * 255)
    )
end

function DrawReplay()
    local state = ReplayStateAt(replayTime_)
    if not state then return end
    local samples = {}
    for _, sample in ipairs(replaySamples_) do
        if sample.t > replayTime_ + .001 then break end
        samples[#samples + 1] = sample
    end
    local lastSample = samples[#samples]
    if not lastSample or math.abs(lastSample.t - replayTime_) > .001 then
        samples[#samples + 1] = {
            t = replayTime_, x = state.x, y = state.y,
            vx = state.vx, vy = state.vy, angle = state.angle,
        }
    end
    if #samples > 0 then
        for i = 2, #samples do
            local from, to = samples[i - 1], samples[i]
            local fromX, fromY = design_:WorldToLogical(from.x, from.y)
            local toX, toY = design_:WorldToLogical(to.x, to.y)
            local recent = replayTime_ - to.t <= 1300
            nvgStrokeWidth(painter_.vg, recent and 4 or 2)
            nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, recent and 204 or 64))
            nvgBeginPath(painter_.vg)
            nvgMoveTo(painter_.vg, fromX, fromY)
            nvgLineTo(painter_.vg, toX, toY)
            nvgStroke(painter_.vg)
        end

        local startX, startY = design_:WorldToLogical(samples[1].x, samples[1].y)
        painter_:Circle(startX, startY, 10, nil, Renderer2D.COLORS.darkPrimary, 3, 209)

        local traversed, nextArrow = 0, 110
        for i = 2, #samples do
            local from, to = samples[i - 1], samples[i]
            local fromX, fromY = design_:WorldToLogical(from.x, from.y)
            local toX, toY = design_:WorldToLogical(to.x, to.y)
            local dx, dy = toX - fromX, toY - fromY
            local length = math.sqrt(dx * dx + dy * dy)
            if length >= .001 then
                while traversed + length >= nextArrow do
                    local progress = (nextArrow - traversed) / length
                    local x, y = fromX + dx * progress, fromY + dy * progress
                    local ux, uy = dx / length, dy / length
                    local normalX, normalY = -uy, ux
                    local arrowTime = from.t + (to.t - from.t) * progress
                    local recent = replayTime_ - arrowTime <= 1300
                    nvgFillColor(painter_.vg, nvgRGBA(82, 117, 93, recent and 209 or 117))
                    nvgBeginPath(painter_.vg)
                    nvgMoveTo(painter_.vg, x + ux * 8, y + uy * 8)
                    nvgLineTo(painter_.vg, x - ux * 5 + normalX * 5, y - uy * 5 + normalY * 5)
                    nvgLineTo(painter_.vg, x - ux * 5 - normalX * 5, y - uy * 5 - normalY * 5)
                    nvgClosePath(painter_.vg)
                    nvgFill(painter_.vg)
                    nextArrow = nextArrow + 110
                end
                traversed = traversed + length
            end
        end

        if replayFinished_ then
            local finishSample = samples[#samples]
            local endX, endY = design_:WorldToLogical(finishSample.x, finishSample.y)
            painter_:Circle(endX, endY, 7, Renderer2D.COLORS.darkPrimary, nil, nil, 230)
            nvgStrokeColor(painter_.vg, nvgRGBA(47, 73, 56, 230))
            nvgStrokeWidth(painter_.vg, 2)
            nvgBeginPath(painter_.vg)
            nvgMoveTo(painter_.vg, endX + 10, endY + 9)
            nvgLineTo(painter_.vg, endX + 10, endY - 18)
            nvgStroke(painter_.vg)
            nvgFillColor(painter_.vg, nvgRGBA(117, 180, 110, 242))
            nvgBeginPath(painter_.vg)
            nvgMoveTo(painter_.vg, endX + 10, endY - 18)
            nvgLineTo(painter_.vg, endX + 31, endY - 12)
            nvgLineTo(painter_.vg, endX + 10, endY - 6)
            nvgClosePath(painter_.vg)
            nvgFill(painter_.vg)
        end
    end

    local sequence = 0
    for _, event in ipairs(replayEvents_) do
        if event.type == "CARD_PLAYED" or event.type == "NEWTON_PUNCH" then
            sequence = sequence + 1
        end
        if event.t <= replayTime_ and (event.type == "CARD_PLAYED" or event.type == "NEWTON_PUNCH") then
            local x, y = design_:WorldToLogical(event.x, event.y)
            local card = event.cardId and Rules.CARDS[event.cardId] or nil
            local accent = card and card.accent or Renderer2D.COLORS.warning
            painter_:Circle(x, y, 15, Renderer2D.COLORS.panel, accent, 2, 245)
            painter_:Text(x, y - 7, card and card.symbol or "N", 13, card and Renderer2D.COLORS.text or Renderer2D.COLORS.warning, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            painter_:Circle(x + 11, y - 11, 8, Renderer2D.COLORS.dark, nil, nil, 255)
            painter_:Text(x + 11, y - 15, tostring(sequence), 9, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
        end
    end

    local appleX, appleY = design_:WorldToLogical(state.x, state.y)
    painter_:Circle(appleX, appleY, 37, Renderer2D.COLORS.primaryActive, nil, nil, 48)
    painter_:Circle(appleX, appleY, 37, nil, Renderer2D.COLORS.primaryActive, 2, 122)
    painter_:Image(painter_.images.apple, appleX, appleY, 64, 64, 1, math.rad(state.angle or 0))

    local cx, cy = frame_.playfieldX + frame_.playfieldWidth * .5, frame_.playfieldY + 34
    painter_:RoundedRect(cx - 289, cy - 27, 578, 54, 5, Renderer2D.COLORS.dark, Renderer2D.COLORS.greenLight, 1, 240)
    painter_:Text(cx - 272, cy - 9, "实验回放", 14, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(cx - 272, cy + 10, string.format("%.2f / %.2f s", replayTime_ / 1000, ReplayDuration() / 1000), 10, Renderer2D.COLORS.greenSecondary)
    local function replayButton(x, width, label, active)
        painter_:RoundedRect(x - width * .5, cy - 17, width, 34, 4, active and Renderer2D.COLORS.greenStrong or Renderer2D.COLORS.darkSecondary, Renderer2D.COLORS.greenLight, 1, active and 255 or 168)
        painter_:Text(x, cy - 7, label, 12, active and Renderer2D.COLORS.white or Renderer2D.COLORS.greenSecondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
    end
    replayButton(cx - 92, 44, replayPaused_ and "▶" or "Ⅱ", not replayPaused_)
    replayButton(cx - 27, 58, "0.5×", replaySpeed_ == .5)
    replayButton(cx + 37, 58, "1×", replaySpeed_ == 1)
    replayButton(cx + 101, 58, "2×", replaySpeed_ == 2)
    replayButton(cx + 238, 78, "退出", false)

    local feedX, feedY = frame_.playfieldX + 18, frame_.playfieldY + frame_.playfieldHeight - 166
    painter_:RoundedRect(feedX, feedY, 310, 148, 3, Renderer2D.COLORS.dark, Renderer2D.COLORS.greenLight, 1, 232)
    painter_:Text(feedX + 14, feedY + 11, replayFinished_ and "本次规则使用顺序" or "REPLAY · 规则记录", 13, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    local visible = {}
    for _, event in ipairs(replayEvents_) do if event.t <= replayTime_ then visible[#visible + 1] = event end end
    local start = math.max(1, #visible - 2)
    if #visible == 0 then painter_:Text(feedX + 14, feedY + 57, "未使用规则卡", 13, Renderer2D.COLORS.greenSecondary) end
    for i = start, #visible do
        local event = visible[i]
        local row = i - start
        local card = event.cardId and Rules.CARDS[event.cardId] or nil
        local accent = card and card.accent or Renderer2D.COLORS.warning
        local label = card and card.name or (event.type == "NEWTON_PUNCH" and "修正拳" or "苹果进入观察窗")
        painter_:Circle(feedX + 22, feedY + 52 + row * 34, 11, accent, nil, nil, 235)
        painter_:Text(feedX + 22, feedY + 45 + row * 34, card and card.symbol or "N", 10, Renderer2D.COLORS.dark, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
        painter_:Text(feedX + 42, feedY + 42 + row * 34, label, 13, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
        painter_:Text(feedX + 42, feedY + 58 + row * 34, event.t <= replayTime_ and "已执行" or "等待中", 10, Renderer2D.COLORS.greenSecondary)
    end
    if replayFinished_ then
        local endX = frame_.playfieldX + frame_.playfieldWidth - 190
        local endY = frame_.playfieldY + frame_.playfieldHeight - 54
        painter_:RoundedRect(endX - 175, endY - 24, 350, 48, 4, Renderer2D.COLORS.panel, Renderer2D.COLORS.primaryActive, 2, 245)
        painter_:Text(endX - 160, endY - 7, "回放完成", 13, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
        local function endButton(x, width, label)
            painter_:RoundedRect(x - width * .5, endY - 17, width, 34, 4, Renderer2D.COLORS.darkSecondary, Renderer2D.COLORS.greenLight, 1, 168)
            painter_:Text(x, endY - 7, label, 12, Renderer2D.COLORS.greenSecondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
        end
        endButton(endX + 38, 92, "再次播放")
        endButton(endX + 137, 84, "退出回放")
    end
end

function DrawHUD()
    local f = frame_
    local titleX = f.workspaceX - 37
    painter_:Text(titleX + 36, 19, "牛顿看了想打人", 29, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(titleX + 36, 57, string.format("实验 %02d · %s", levelIndex_, level_.name or ""), 13, Renderer2D.COLORS.greenSecondary)
    local function DrawNavigationButton(x, symbol, key, symbolY, size)
        local hovered = hoveredNavigation_ == key
        painter_:FillRect(x, 23, 46, 46, hovered and Renderer2D.COLORS.darkSecondary or Renderer2D.COLORS.dark, hovered and 255 or 107)
        painter_:StrokeRect(x, 23, 46, 46, hovered and Renderer2D.COLORS.greenLight or Renderer2D.COLORS.background, 2, hovered and 230 or 115)
        painter_:Text(x + 23, symbolY, symbol, size, Renderer2D.COLORS.background, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
    DrawNavigationButton(titleX + 255, "←", "back", 32, 27)
    DrawNavigationButton(titleX + 315, "↻", "reset", 32, 27)
    DrawNavigationButton(titleX + 375, isPaused_ and "▶" or "Ⅱ", "pause", 34, 21)
    painter_:Text(f.playfieldX + 180, 17, "当前实验状态", 12, Renderer2D.COLORS.secondary)
    painter_:Text(f.playfieldX + 180, 42, status_, 17, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(f.playfieldX + 585, 17, "当前场地规则", 12, Renderer2D.COLORS.secondary)
    local g = Rules.GetGravity(rules_, level_.rules.initialGravity)
    painter_:Text(f.playfieldX + 585, 42, string.format("(%d,%d) · %s", g.x, g.y, rules_.activeFields["feather-gravity"] and "轻羽" or "经典场地"), 17, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(f.playfieldX + 800, 18, level_.objective or "让苹果进入观察皿", 16, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(f.playfieldX + f.playfieldWidth - 290, 17, "关卡", 12, Renderer2D.COLORS.secondary)
    for i = 1, CONFIG.levelCount do
        local x = f.playfieldX + f.playfieldWidth - 290 + (i - 1) * 27
        local scale = hoveredLevelIndex_ == i and 1.14 or 1
        painter_:Circle(x, 46, 10 * scale, i == levelIndex_ and Renderer2D.COLORS.greenStrong or Renderer2D.COLORS.panelSecondary, i == levelIndex_ and Renderer2D.COLORS.primaryActive or Renderer2D.COLORS.greenLight, 1)
        painter_:Text(x, 46, tostring(i), 10 * scale, i == levelIndex_ and Renderer2D.COLORS.white or Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end
end

function CardUseLabel(usage, remaining)
    return usage == "REUSABLE" and "可重复" or (tostring(remaining) .. " 次")
end

function CardBadgeText(id, usage, remaining)
    if burningCardIds_[id] then return "燃烧" end
    if activeCardId_ == id then
        if cardHandReordering_ then return "排序" end
        if activeCardDeploying_ then
            local needsParameter = id == "side-gravity" or id == "mirror-motion"
            if not needsParameter then
                return activeCardPointer_ and PointerInPlayfield(activeCardPointer_.x, activeCardPointer_.y) and "可部署" or "移入场地"
            end
            if cardParameterStart_ then
                if cardGestureDistance_ >= 48 then return "松手确认" end
                return cardCandidate_ and "继续滑动" or "滑动选方向"
            end
            if activeCardPointer_ and PointerInPlayfield(activeCardPointer_.x, activeCardPointer_.y) then return "停稳后选方向" end
            return cardDeployEnteredMs_ and "移回场地" or "移入场地"
        end
    end
    if primedCardId_ == id then return "0.05" end
    return usage == "REUSABLE" and "∞" or tostring(remaining)
end

function DrawCardBadge(value, edge)
    local size = 10 * CARD_TEXT_SCALE
    local horizontalPadding = 5 * CARD_TEXT_SCALE
    nvgFontFace(painter_.vg, "maker-body")
    nvgFontSize(painter_.vg, size)
    local width = math.max(25, nvgTextBounds(painter_.vg, 0, 0, value) + horizontalPadding * 2)
    local right = 51 * CARD_TEXT_SCALE
    painter_:RoundedRect(right - width, -94, width, 20, 4, edge)
    painter_:Text(right - width * .5, -91, value, size, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
end

function DrawCardSurface(id, def, card, cardState, badgeText, active, hovered)
    local field = def.kind == "field"
    local usage = cardState and cardState.usageMode or card.usageMode
    local remaining = cardState and cardState.remainingUses or card.count
    local fill = id == "quantum-phase" and (hovered and Renderer2D.COLORS.quantumCardSurfaceHover or Renderer2D.COLORS.quantumSoft)
        or (field and (hovered and Renderer2D.COLORS.fieldCardSurfaceHover or Renderer2D.COLORS.fieldCardSurface)
            or (hovered and Renderer2D.COLORS.decisionCardSurfaceHover or Renderer2D.COLORS.decisionCardSurface))
    local edge = id == "quantum-phase" and Renderer2D.COLORS.quantum or (field and Renderer2D.COLORS.fieldCardBorder or Renderer2D.COLORS.decisionCardBorder)
    local titleColor = field and Renderer2D.COLORS.text or Renderer2D.COLORS.decisionCardText
    local bodyColor = field and Renderer2D.COLORS.body or Renderer2D.COLORS.decisionCardBody
    painter_:RoundedRect(-70, -96, 144, 202, 8, Renderer2D.COLORS.dark, nil, nil, hovered and 41 or 26)
    painter_:RoundedRect(-72, -101, 144, 202, 8, edge)
    painter_:RoundedRect(-66, -95, 132, 190, 6, fill)
    painter_:RoundedRect(-66, -95, 132, 24, 6, edge, nil, nil, 36)
    painter_:RoundedRect(-57, -37, 114, 88, 5, Renderer2D.COLORS.panel, edge, 1, 107)
    painter_:StrokeRect(-57, 59, 114, 0, edge, 1, 133)
    painter_:RoundedRect(-72, -101, 144, 202, 8, nil, active and Renderer2D.COLORS.primaryActive or edge, active and 3 or 2)
    painter_:Text(-58, -85, (field and "场地 · " or "决策 · ") .. CardUseLabel(usage, remaining), 9 * CARD_TEXT_SCALE, edge)
    painter_:Text(0, -58, def.name, 16 * CARD_TEXT_SCALE, titleColor, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(0, 8, def.symbol, 42 * CARD_TEXT_SCALE, titleColor, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
    painter_:TextBox(-51 * CARD_TEXT_SCALE, 69, 102 * CARD_TEXT_SCALE, def.description, 10 * CARD_TEXT_SCALE, bodyColor, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    DrawCardBadge(badgeText or CardBadgeText(id, usage, remaining), edge)
end

function DrawCards()
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
    local drawEntries = {}
    for i, card in ipairs(entries) do
        if not burningCardIds_[card.cardId] then
            local pose = CardVisualPose(card.cardId, poses[i])
            drawEntries[#drawEntries + 1] = {
                card = card,
                pose = pose,
                index = i,
                depth = pose.depth,
            }
        end
    end
    table.sort(drawEntries, function(a, b)
        if a.depth == b.depth then return a.index < b.index end
        return a.depth < b.depth
    end)
    for _, entry in ipairs(drawEntries) do
            local card, pose = entry.card, entry.pose
            local active = activeCardId_ == card.cardId
            local primed = primedCardId_ == card.cardId
            local hovered = hoveredCardId_ == card.cardId and not active and not primed
            nvgSave(painter_.vg); nvgTranslate(painter_.vg, pose.x, pose.y); nvgRotate(painter_.vg, math.rad(pose.angle)); nvgScale(painter_.vg, pose.scale or 1, pose.scale or 1)
            local cardState = cardStates_[card.cardId]
            local usage = cardState and cardState.usageMode or card.usageMode
            local remaining = cardState and cardState.remainingUses or card.count
            local faceActive = primed or (active and activeCardDeploying_)
            DrawCardSurface(card.cardId, Rules.CARDS[card.cardId], card, cardState, CardBadgeText(card.cardId, usage, remaining), faceActive, hovered)
            nvgRestore(painter_.vg)
    end
    local cx = frame_.playfieldX + frame_.playfieldWidth - 58
    local cy = frame_.cardHandY + 23
    -- Phaser-equivalent ability face with the original fist.svg path rendered
    -- directly by NanoVG rather than a fallback glyph or geometry substitute.
    painter_:Circle(cx, cy, 42, Renderer2D.COLORS.background)
    local punchReady = Rules.CanPunch(rules_) and not success_ and not failed_ and not replayActive_
    local punchAlpha = punchReady and 255 or math.floor(255 * .62)
    local punchColor = punchReady and Renderer2D.COLORS.warningActive or Renderer2D.COLORS.warning
    painter_:Circle(cx + 2, cy + 3, 40, Renderer2D.COLORS.darkPrimary, nil, nil, math.floor(punchAlpha * .12))
    painter_:Circle(cx, cy, 35, punchReady and punchHovered_ and Renderer2D.COLORS.warningSoft or Renderer2D.COLORS.playfield, nil, nil, punchAlpha)
    painter_:Circle(cx, cy, 37.5, nil, Renderer2D.COLORS.warningLow, 5, math.floor(punchAlpha * .42))
    if anger_ > 0 then
        local progress = math.max(0, math.min(1, anger_ / 100))
        nvgStrokeColor(painter_.vg, nvgRGBA(Renderer2D.COLORS.warningActive[1], Renderer2D.COLORS.warningActive[2], Renderer2D.COLORS.warningActive[3], math.floor(punchAlpha * (punchReady and 1 or .72))))
        nvgStrokeWidth(painter_.vg, 5)
        nvgBeginPath(painter_.vg)
        nvgArc(painter_.vg, cx, cy, 37.5, -math.pi * .5, -math.pi * .5 + math.pi * 2 * progress, NVG_CW)
        nvgStroke(painter_.vg)
    end
    painter_:Circle(cx, cy, 32, nil, punchReady and Renderer2D.COLORS.warningActive or Renderer2D.COLORS.warningLow, punchReady and 2 or 1, punchAlpha)
    painter_:DrawFist(cx, cy - 5, 46, punchColor, punchAlpha)
    local punchStatus = punchReady and "可修正" or (rules_.punchUsed and "已使用" or "未就绪")
    painter_:Text(cx, cy + 42, punchStatus, 10, punchColor, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display", punchAlpha)
end

function DrawSelectorArrow(x, y, direction, active, alpha)
    local function fillArrow(drawX, drawY, color, opacity, shaftWidth, headHalf, extent)
        nvgFillColor(painter_.vg, nvgRGBA(color[1], color[2], color[3], math.floor(opacity * 255)))
        local shaftLength = extent + 2
        if direction == "RIGHT" then
            nvgBeginPath(painter_.vg); nvgRect(painter_.vg, drawX - extent, drawY - shaftWidth * .5, shaftLength, shaftWidth); nvgFill(painter_.vg)
            nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, drawX + 2, drawY - headHalf); nvgLineTo(painter_.vg, drawX + extent, drawY); nvgLineTo(painter_.vg, drawX + 2, drawY + headHalf); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
        elseif direction == "LEFT" then
            nvgBeginPath(painter_.vg); nvgRect(painter_.vg, drawX - 2, drawY - shaftWidth * .5, shaftLength, shaftWidth); nvgFill(painter_.vg)
            nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, drawX - 2, drawY - headHalf); nvgLineTo(painter_.vg, drawX - extent, drawY); nvgLineTo(painter_.vg, drawX - 2, drawY + headHalf); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
        elseif direction == "UP" then
            nvgBeginPath(painter_.vg); nvgRect(painter_.vg, drawX - shaftWidth * .5, drawY - 2, shaftWidth, shaftLength); nvgFill(painter_.vg)
            nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, drawX - headHalf, drawY - 2); nvgLineTo(painter_.vg, drawX, drawY - extent); nvgLineTo(painter_.vg, drawX + headHalf, drawY - 2); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
        else
            nvgBeginPath(painter_.vg); nvgRect(painter_.vg, drawX - shaftWidth * .5, drawY - extent, shaftWidth, shaftLength); nvgFill(painter_.vg)
            nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, drawX - headHalf, drawY + 2); nvgLineTo(painter_.vg, drawX, drawY + extent); nvgLineTo(painter_.vg, drawX + headHalf, drawY + 2); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
        end
    end
    if active then fillArrow(x + 2, y + 2, Renderer2D.COLORS.darkPrimary, .38, 10, 13, 22) end
    fillArrow(x, y, active and Renderer2D.COLORS.greenLight or Renderer2D.COLORS.darkSecondary, alpha, active and 10 or 9, active and 13 or 12, active and 22 or 20)
end

function DrawCardParameterSelector()
    if not activeCardId_ or not cardParameterStart_ or not activeCardPointer_ then return end
    local anchor, pointer = cardParameterStart_, activeCardPointer_
    nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 61)); nvgStrokeWidth(painter_.vg, 2)
    nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, anchor.x, anchor.y); nvgLineTo(painter_.vg, pointer.x, pointer.y); nvgStroke(painter_.vg)
    painter_:Circle(anchor.x, anchor.y, 3.5, Renderer2D.COLORS.greenStrong, nil, nil, 184)
    local function clamp(value, minimum, maximum)
        return math.max(minimum, math.min(maximum, value))
    end
    local function position(offsetX, offsetY)
        return clamp(anchor.x + offsetX, 30, frame_.logicalWidth - 30), clamp(anchor.y + offsetY, 30, frame_.logicalHeight - 30)
    end
    if activeCardId_ == "side-gravity" then
        local hasCandidate = cardCandidate_ ~= nil
        local upX, upY = position(0, -116)
        local leftX, leftY = position(-98, 0)
        local rightX, rightY = position(98, 0)
        local downX, downY = position(0, 116)
        DrawSelectorArrow(upX, upY, "UP", cardCandidate_ == "UP", cardCandidate_ == "UP" and 1 or (hasCandidate and .58 or .86))
        DrawSelectorArrow(leftX, leftY, "LEFT", cardCandidate_ == "LEFT", cardCandidate_ == "LEFT" and 1 or (hasCandidate and .58 or .86))
        DrawSelectorArrow(rightX, rightY, "RIGHT", cardCandidate_ == "RIGHT", cardCandidate_ == "RIGHT" and 1 or (hasCandidate and .58 or .86))
        DrawSelectorArrow(downX, downY, "DOWN", cardCandidate_ == "DOWN", cardCandidate_ == "DOWN" and 1 or (hasCandidate and .58 or .86))
    else
        local horizontal = cardCandidate_ == "HORIZONTAL"
        local vertical = cardCandidate_ == "VERTICAL"
        local hasCandidate = horizontal or vertical
        local horizontalX, horizontalY = position(-98, 0)
        local verticalX, verticalY = position(98, 0)
        DrawSelectorArrow(horizontalX, horizontalY, "LEFT", horizontal, horizontal and 1 or (hasCandidate and .58 or .86))
        DrawSelectorArrow(horizontalX, horizontalY, "RIGHT", horizontal, horizontal and 1 or (hasCandidate and .58 or .86))
        DrawSelectorArrow(verticalX, verticalY, "UP", vertical, vertical and 1 or (hasCandidate and .58 or .86))
        DrawSelectorArrow(verticalX, verticalY, "DOWN", vertical, vertical and 1 or (hasCandidate and .58 or .86))
    end
end

function DrawCardBurns()
    for _, burn in ipairs(cardBurns_) do
        local progress = BurnProgress(burn)
        local def = Rules.CARDS[burn.id]
        local card = cardDeckById_[burn.id]
        local cardState = cardStates_[burn.id]
        local top = burn.y - 101 + progress * 202
        local visibleHeight = math.max(0, 202 * (1 - progress))
        local edgePoints = {}
        for i = 0, 12 do
            local x = burn.x - 68 + i * (136 / 12)
            local y = top + math.sin(i * 1.73) * 3.6 + math.sin(i * .67 + .8) * 2.2
            edgePoints[i + 1] = { x = x, y = math.min(burn.y + 101, y) }
        end
        if visibleHeight > 1 and def and card then
            local shakeProgress = math.max(0, math.min(1, burn.elapsed / 70))
            local shakeEase = 1 - (1 - shakeProgress) ^ 3
            local targetAngle = BurnNoise(#burn.id, 8) * 1.6 - .8
            local angle = (burn.startAngle or 0) + (targetAngle - (burn.startAngle or 0)) * shakeEase
            local scale = (burn.startScale or 1.05) + (1.02 - (burn.startScale or 1.05)) * shakeEase
            local clipPoints = { { x = burn.x - 72, y = edgePoints[1].y } }
            for _, point in ipairs(edgePoints) do clipPoints[#clipPoints + 1] = point end
            clipPoints[#clipPoints + 1] = { x = burn.x + 72, y = edgePoints[#edgePoints].y }

            -- NanoVG only clips rectangular regions. Consecutive strips along
            -- the source's 13-point edge reproduce the GeometryMask silhouette
            -- instead of retaining the previous rectangular burn cutoff.
            for index = 1, #clipPoints - 1 do
                local left, right = clipPoints[index], clipPoints[index + 1]
                local width = math.max(1, right.x - left.x + 1)
                local height = math.max(0, burn.y + 101 - left.y)
                if height > 0 then
                    nvgSave(painter_.vg)
                    nvgScissor(painter_.vg, left.x, left.y, width, height)
                    nvgTranslate(painter_.vg, burn.x, burn.y)
                    nvgRotate(painter_.vg, math.rad(angle))
                    nvgScale(painter_.vg, scale, scale)
                    DrawCardSurface(burn.id, def, card, cardState, "燃烧", true, false)
                    nvgRestore(painter_.vg)
                end
            end
        end
        if progress > .04 then
            local function drawBurnEdge(color, width, alpha, offset)
                nvgStrokeColor(painter_.vg, nvgRGBA(color[1], color[2], color[3], math.floor(alpha * 255)))
                nvgStrokeWidth(painter_.vg, width)
                nvgBeginPath(painter_.vg)
                for index, point in ipairs(edgePoints) do
                    if index == 1 then nvgMoveTo(painter_.vg, point.x, point.y + offset) else nvgLineTo(painter_.vg, point.x, point.y + offset) end
                end
                nvgStroke(painter_.vg)
            end
            drawBurnEdge(Renderer2D.COLORS.ash, 4, .46, 2)
            drawBurnEdge(Renderer2D.COLORS.burnEdge, 5, .38, 0)
            drawBurnEdge(Renderer2D.COLORS.burnCore, 2, .96, -1)
            nvgFillColor(painter_.vg, nvgRGBA(Renderer2D.COLORS.burnCore[1], Renderer2D.COLORS.burnCore[2], Renderer2D.COLORS.burnCore[3], math.floor(.54 * 255)))
            for index = 3, #edgePoints - 1, 3 do
                local point = edgePoints[index]
                local flameHeight = 4 + ((index - 1) * 3) % 5
                nvgBeginPath(painter_.vg)
                nvgMoveTo(painter_.vg, point.x - 3, point.y)
                nvgLineTo(painter_.vg, point.x, point.y - flameHeight)
                nvgLineTo(painter_.vg, point.x + 3, point.y)
                nvgClosePath(painter_.vg)
                nvgFill(painter_.vg)
            end
        end
    end
end

function DrawCardBurnParticles()
    for _, particle in ipairs(cardBurnParticles_) do
        local elapsed = particle.elapsed - particle.delay
        if elapsed >= 0 then
            local progress = math.max(0, math.min(1, elapsed / particle.duration))
            local eased = 1 - (1 - progress) ^ 3
            local radius = particle.radius * (1 + (particle.scaleTarget - 1) * eased)
            painter_:Circle(
                particle.x + particle.dx * eased,
                particle.y + particle.dy * eased,
                radius,
                particle.color,
                nil,
                nil,
                math.floor(particle.alpha * 255 * (1 - progress))
            )
        end
    end
end

function DrawPlayfieldOverlay()
    if replayMode_ ~= "none" then return end
    if (activeCardId_ or primedCardId_ or #cardBurns_ > 0) and not isPaused_ and not success_ and not failed_ then
        painter_:RoundedRect(frame_.playfieldX + 8, frame_.playfieldY + 8, frame_.playfieldWidth - 16, frame_.playfieldHeight - 16, 5, Renderer2D.COLORS.greenSoft, nil, nil, 46)
        painter_:RoundedRect(frame_.playfieldX + 8, frame_.playfieldY + 8, frame_.playfieldWidth - 16, frame_.playfieldHeight - 16, 5, nil, Renderer2D.COLORS.primaryActive, 3, 179)
    end
    if isPaused_ then
        painter_:FillRect(frame_.playfieldX, frame_.playfieldY, frame_.playfieldWidth, frame_.playfieldHeight, { 0, 0, 0, 255 }, 66)
        painter_:Text(frame_.playfieldX + frame_.playfieldWidth - 24, frame_.playfieldY + 18, "实验暂停 · 规则卡可操作", 13, Renderer2D.COLORS.text, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    end
end

function DrawResultOverlay()
    if replayMode_ ~= "none" then return end
    if IsResultOverlayVisible() then
        painter_:FillRect(0, 0, frame_.logicalWidth, frame_.logicalHeight, Renderer2D.COLORS.background, 199)
        local cx, cy = frame_.playfieldX + frame_.playfieldWidth * .5, frame_.playfieldY + frame_.playfieldHeight * .5
        local function overlayButton(x, y, label, secondary)
            painter_:RoundedRect(x - 73, y - 23, 146, 46, 4, secondary and Renderer2D.COLORS.panelSecondary or Renderer2D.COLORS.greenStrong, secondary and Renderer2D.COLORS.dark or Renderer2D.COLORS.primaryActive, 2)
            painter_:Text(x, y - 8, label, 16, secondary and Renderer2D.COLORS.text or Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
        end
        if success_ then
            painter_:RoundedRect(cx - 345, cy - 115, 690, 230, 4, Renderer2D.COLORS.panel, Renderer2D.COLORS.primaryActive, 2)
            painter_:Text(cx, cy - 75, "观测成立", 42, Renderer2D.COLORS.text, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            painter_:Text(cx, cy - 6, (level_.name or "实验") .. " · 苹果已稳定进入观察窗", 16, Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            overlayButton(cx - 160, cy + 65, levelIndex_ < CONFIG.levelCount and "下一实验" or "重新观测", false)
            overlayButton(cx, cy + 65, "查看实验回放", true)
            overlayButton(cx + 160, cy + 65, "再次尝试", true)
        else
            painter_:RoundedRect(cx - 310, cy - 105, 620, 210, 4, Renderer2D.COLORS.panel, Renderer2D.COLORS.warning, 2)
            painter_:Text(cx, cy - 67, "实验未成立", 38, Renderer2D.COLORS.warning, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            painter_:Text(cx, cy - 5, string.format("第 %d 次偏离记录", failureCount_), 16, Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            overlayButton(cx, cy + 60, "重新布置", false)
        end
    end
end

function Start()
    graphics.windowTitle = CONFIG.title
    painter_ = Renderer2D.New()
    frame_ = design_:Frame()
    BuildLevel(1)
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    SubscribeToEvent("PhysicsPreStep", "HandlePhysicsPreStep")
    SubscribeToEvent("PhysicsPostStep", "HandlePhysicsPostStep")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleCollisionBegin")
    SubscribeToEvent("PhysicsEndContact2D", "HandleCollisionEnd")
    SubscribeToEvent(painter_.vg, "NanoVGRender", "HandleRender")
    print("[Migration] 1:1 design-space runtime started")
end

function Stop()
    if level_ and level_.physicsProbe then level_.physicsProbe:Stop({ apple = apple_ }) end
    if painter_ then painter_:Destroy(); painter_ = nil end
end

---@param _eventType string
---@param eventData UpdateEventData
function HandleUpdate(_eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")
    if audio_ then audio_:Update(dt) end
    uiElapsed_ = uiElapsed_ + dt
    UpdateRuleFeedback(dt)
    frame_ = design_:Frame()
    -- Replay owns the input/update frame. Do not let cards, reset shortcuts,
    -- or normal completion updates mutate the suspended experiment.
    if replayActive_ then
        HandlePointer()
        if input:GetKeyPress(KEY_ESCAPE) then StopReplay() end
        SyncPhysicsUpdateEnabled()
        if replayActive_ then UpdateReplay(dt) end
        if debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
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
        if debugDraw_ and input:GetKeyPress(KEY_T) then physicsProbe:Start(probeContext) end
        if physicsProbe:IsActive() then
            local probeResult = physicsProbe:Update(probeContext)
            SyncPhysicsUpdateEnabled()
            if probeResult == "finished" then ResetExperiment(false) end
            if debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
            return
        end
    end
    UpdateCardHomeMotions(dt)
    UpdateCardHoverStates(dt)
    UpdateSpringVisuals(dt)
    sensorAngle_ = sensorAngle_ + dt * (goalContact_ and (math.pi * 2 / 7.2) or (math.pi * 2 / 10))
    for i = #cardBurns_, 1, -1 do
        local burn = cardBurns_[i]
        burn.elapsed = burn.elapsed + dt * 1000
        local thresholds = { .2, .5, .78 }
        local progress = BurnProgress(burn)
        while burn.emittedBursts < #thresholds and progress >= thresholds[burn.emittedBursts + 1] do
            burn.emittedBursts = burn.emittedBursts + 1
            EmitBurnParticles(burn, burn.emittedBursts)
        end
        if not burn.applied and burn.elapsed >= burn.applyAt then
            burn.applied = ApplyCardResolution(burn.id, burn.candidate)
        end
        if burn.elapsed >= burn.totalDuration then
            if burn.applied then
                local cardState = cardStates_[burn.id]
                if cardState and cardState.usageMode ~= "REUSABLE" then
                    cardState.remainingUses = math.max(0, cardState.remainingUses - 1)
                    cardState.consumed = cardState.remainingUses == 0
                end
            end
            burningCardIds_[burn.id] = nil
            table.remove(cardBurns_, i)
        end
    end
    for i = #cardBurnParticles_, 1, -1 do
        local particle = cardBurnParticles_[i]
        particle.elapsed = particle.elapsed + dt * 1000
        if particle.elapsed >= particle.delay + particle.duration then table.remove(cardBurnParticles_, i) end
    end
    HandlePointer()
    if replayActive_ then
        SyncPhysicsUpdateEnabled()
        UpdateReplay(dt)
        if debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
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
    if debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
end

---@param _eventType string
---@param eventData PhysicsPreStepEventData
function HandlePhysicsPreStep(_eventType, eventData)
    if not apple_ or not launched_ or replayActive_ or apple_.body.bodyType ~= BT_DYNAMIC then
        applePreSolveVelocity_ = nil
        return
    end
    -- Phaser caps before Matter runs the next integration and collision pass.
    CapAppleSpeed()
    apple_.body.linearDamping = MatterCalibration.Box2DLinearDamping(
        apple_.baseFrictionAir,
        CurrentPhysicsTimeScale(),
        eventData:GetFloat("TimeStep")
    )
    apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping(
        apple_.baseFrictionAir,
        CurrentPhysicsTimeScale(),
        eventData:GetFloat("TimeStep")
    )
    local velocity = apple_.body.linearVelocity
    applePreSolveVelocity_ = Vector2(velocity.x, velocity.y)
end

---@param _eventType string
---@param eventData PhysicsPostStepEventData
function HandlePhysicsPostStep(_eventType, eventData)
    if not launched_ or replayActive_ or isPaused_ then return end
    local physicsProbe = level_ and level_.physicsProbe or nil
    if physicsProbe and physicsProbe:IsActive() then
        UpdateSpringExits()
        physicsProbe:AfterPhysicsStep({
            apple = apple_,
            pixelsPerMeter = CONFIG.pixelsPerMeter,
            matterVelocityToWorld = CONFIG.matterVelocityToWorld,
        }, eventData:GetFloat("TimeStep"))
        return
    end
    -- The original applies a spring's pre-solve exit velocity after Matter's
    -- collision resolution, then advances runtime mechanisms in physics time.
    UpdateSpringExits()
    UpdateExperiment(eventData:GetFloat("TimeStep") * CurrentPhysicsTimeScale())
end

function HandleScreenMode()
    frame_ = design_:Frame()
end

---@param _eventType string
---@param eventData TouchBeginEventData
function HandleTouchBegin(_eventType, eventData)
    if pointer_.activeTouchId ~= nil then return end
    pointer_.activeTouchId = eventData:GetInt("TouchID")
    pointer_.touchX = eventData:GetInt("X")
    pointer_.touchY = eventData:GetInt("Y")
    pointer_.touchPressed = true
end

---@param _eventType string
---@param eventData TouchMoveEventData
function HandleTouchMove(_eventType, eventData)
    if eventData:GetInt("TouchID") ~= pointer_.activeTouchId then return end
    pointer_.touchX = eventData:GetInt("X")
    pointer_.touchY = eventData:GetInt("Y")
end

---@param _eventType string
---@param eventData TouchEndEventData
function HandleTouchEnd(_eventType, eventData)
    if eventData:GetInt("TouchID") ~= pointer_.activeTouchId then return end
    pointer_.touchX = eventData:GetInt("X")
    pointer_.touchY = eventData:GetInt("Y")
    pointer_.activeTouchId = nil
    pointer_.touchReleased = true
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
    if IsAppleGoalPair(nodeA, nodeB) then
        goalContact_ = true
        local goal = LevelData.FindFirst(level_, "goal_sensor")
        local runtimeGoal = goal and runtime_.byId[goal.id] or nil
        if runtimeGoal then runtimeGoal.active = true end
        RecordReplayEvent("GOAL_ENTER")
        SetStatus("OBSERVE · 苹果进入观察窗")
        return
    end
    if not nodeA or not nodeB or not runtime_ or not IsAppleNode(nodeA) and not IsAppleNode(nodeB) then return end
    local other = IsAppleNode(nodeA) and nodeB or nodeA
    local object = runtime_.byId[other.name]
    if launched_ and not replayActive_ then PlaySound("impact") end
    if not object then return end
    if object.type == "spring" and object.enabled and object.channelEnabled and not object.spent
        and uiElapsed_ * 1000 - object.triggeredAt >= object.cooldown then
        local v = applePreSolveVelocity_ or apple_.body.linearVelocity
        local direction = object.direction
        local ix, iy = 0, 0
        if direction == "UP" then iy = 1 elseif direction == "DOWN" then iy = -1 elseif direction == "LEFT" then ix = -1 else ix = 1 end
        local impulse = object.impulseStrength * Rules.GetRestitutionMultiplier(rules_)
            * CurrentMatterVelocityToWorld()
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
        local goal = LevelData.FindFirst(level_, "goal_sensor")
        local runtimeGoal = goal and runtime_.byId[goal.id] or nil
        if runtimeGoal then runtimeGoal.active = false; runtimeGoal.contactProgress = 0 end
        ResetGoal()
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
    painter_:Begin(frame_)
    painter_:DrawBackground(frame_)
    painter_:DrawNewton(frame_, level_, anger_, observation_)
    painter_:DrawGround(frame_)
    local goalPulseProgress = goalPulseElapsedMs_ and math.max(0, math.min(1, goalPulseElapsedMs_ / 460)) or nil
    if runtime_ then for _, object in ipairs(runtime_.ordered) do painter_:DrawObject(frame_, object, { sensorAngle = sensorAngle_, success = success_ and not replayActive_, goalPulseProgress = goalPulseProgress }) end end
    if replayActive_ then
        DrawReplay()
    else
        DrawTrail()
        DrawAim()
        DrawCardPrediction()
        DrawLaunchHint()
        local absorbProgress = absorbing_ and math.max(0, math.min(1, absorbElapsedMs_ / 520)) or 0
        painter_:DrawApple(frame_, apple_, 1 - absorbProgress * .65, 1 - absorbProgress * .65)
        DrawVelocityArrow()
        DrawRulePulse()
        DrawPlayfieldOverlay()
    end
    DrawHUD()
    DrawCards()
    DrawCardParameterSelector()
    DrawCardBurns()
    DrawCardBurnParticles()
    DrawRuleFlash()
    DrawResultOverlay()
    painter_:Finish()
end
