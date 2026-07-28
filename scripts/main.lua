local LevelData = require("migration.LevelData")
local CoordinateMapper = require("migration.CoordinateMapper")
local DesignSpace = require("migration.DesignSpace")
local Rules = require("migration.Rules")
local RuntimeFactory = require("migration.RuntimeFactory")
local Renderer2D = require("migration.Renderer")
local SynthAudio = require("migration.SynthAudio")

local CONFIG = {
    title = "牛顿看了想打人",
    pixelsPerMeter = 100,
    gravityAcceleration = 10,
    levelCount = 9,
    replaySampleMs = 1000 / 30,
}

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
local runtime_ = nil
---@type table|nil
local ground_ = nil
---@type table|nil
local apple_ = nil
---@type table|nil
local mapper_ = nil
local frame_ = nil
local levelIndex_ = 1
local rules_ = Rules.NewState()
local draggedApple_ = false
local activeCardId_ = nil
local activeCardStart_ = nil
local activeCardPointer_ = nil
local activeCardDragged_ = false
local activeCardDeploying_ = false
local primedCardId_ = nil
local cardParameterStart_ = nil
local cardPointerLast_ = nil
local cardPointerStillMs_ = 0
local cardCandidate_ = nil
local cardGestureDistance_ = 0
local launched_ = false
local goalContact_ = false
local goalContactMs_ = 0
local outsideMs_ = 0
local flightMs_ = 0
local status_ = "READY · 等待发射"
local isPaused_ = false
local bulletTimeActive_ = false
local bulletTimeAccumulator_ = 0
local bulletTimeStepOpen_ = false
local debugDraw_ = false
local success_ = false
local failed_ = false
local failureCount_ = 0
local replayActive_ = false
local replayTime_ = 0
local replayPaused_ = false
local replaySpeed_ = 1
local replayFinished_ = false
local replaySamples_ = {}
local replayEvents_ = {}
local replaySavedApple_ = nil
local replaySampleAccumulator_ = 0
local trail_ = {}
local sensorAngle_ = 0
local uiElapsed_ = 0
local anger_ = 0
local phaseTraversing_ = false
local stalledMs_ = 0
local channelStates_ = {}
local cardStates_ = {}
local cardDeckById_ = {}
local handOrder_ = {}
local cardBurns_ = {}
local burningCardIds_ = {}
local ruleDeployCount_ = 0
local ReevaluateButtons = nil
local InitializeMechanisms = nil
local RecordReplayEvent = nil
local StartReplay = nil
local StopReplay = nil

local function SetStatus(value)
    status_ = value
    print("[Migration] " .. value)
end

local function PlaySound(kind)
    if audio_ then audio_:Play(kind) end
end

local function LoadLevel(index)
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

local function InitializeCards()
    cardStates_ = {}
    cardDeckById_ = {}
    handOrder_ = {}
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

local function SetGravity()
    if not physicsWorld_ or not level_ then return end
    local base = level_.rules.initialGravity
    local gravity = Rules.GetGravity(rules_, base)
    physicsWorld_:SetGravity(Vector2(
        gravity.x * gravity.strength * CONFIG.gravityAcceleration,
        -gravity.y * gravity.strength * CONFIG.gravityAcceleration
    ))
    if apple_ and apple_.shape then
        apple_.shape.maskBits = rules_.phaseActive and (RuntimeFactory.MASK_ALL & ~RuntimeFactory.CATEGORY_PHASEABLE) or RuntimeFactory.MASK_ALL
        apple_.shape.restitution = apple_.baseRestitution * Rules.GetRestitutionMultiplier(rules_)
    end
    if runtime_ then
        local multiplier = Rules.GetRestitutionMultiplier(rules_)
        for _, object in ipairs(runtime_.ordered) do
            if object.type == "wall" and object.shape and object.baseRestitution then
                object.shape.restitution = object.baseRestitution * multiplier
            end
        end
    end
    if ReevaluateButtons then ReevaluateButtons() end
end

local function UpdateAngerFromRules()
    local persistent = next(rules_.activeFields) ~= nil or rules_.phaseActive
    if persistent then
        anger_ = math.min(96, 54 + ruleDeployCount_ * 10)
    else
        anger_ = math.min(68, failureCount_ * 18)
    end
end

local function SyncPhysicsUpdateEnabled()
    if not physicsWorld_ then return end
    if isPaused_ then
        physicsWorld_:SetUpdateEnabled(false)
        return
    end
    -- The Phaser scene does not slow simulation while a card is only being
    -- rearranged in the hand. Bullet time begins once it is primed, deployed,
    -- or resolving its burn animation.
    local bulletTime = activeCardDeploying_ or primedCardId_ ~= nil or #cardBurns_ > 0
    if not bulletTime then
        bulletTimeActive_ = false
        bulletTimeAccumulator_ = 0
        bulletTimeStepOpen_ = false
        physicsWorld_:SetUpdateEnabled(true)
        return
    end
    bulletTimeActive_ = true
end

local function UpdateBulletTime(dt)
    if not physicsWorld_ or isPaused_ or not bulletTimeActive_ then return end
    if bulletTimeStepOpen_ then
        bulletTimeStepOpen_ = false
        physicsWorld_:SetUpdateEnabled(false)
        return
    end
    bulletTimeAccumulator_ = bulletTimeAccumulator_ + dt
    if bulletTimeAccumulator_ >= 1 / 3 then
        bulletTimeAccumulator_ = bulletTimeAccumulator_ - 1 / 3
        bulletTimeStepOpen_ = true
        physicsWorld_:SetUpdateEnabled(true)
    else
        physicsWorld_:SetUpdateEnabled(false)
    end
end

local function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")
    physicsWorld_ = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld_:SetVelocityIterations(8)
    physicsWorld_:SetPositionIterations(10)
    physicsWorld_:SetContinuousPhysics(true)
    physicsWorld_:SetAutoClearForces(true)
    SetGravity()
end

local function SetupViewport()
    if not scene_ then return end
    local cameraNode = scene_:CreateChild("Camera")
    camera_ = cameraNode:CreateComponent("Camera")
    camera_:SetOrthographic(true)
    camera_:SetOrthoSize(DesignSpace.LAB.height / CONFIG.pixelsPerMeter)
    cameraNode.position = Vector3(0, 0, -10)
    viewport_ = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport_)
end

local function BuildLevel(index)
    level_ = LoadLevel(index)
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
    ground_ = RuntimeFactory.CreateGround(scene_, mapper_, LevelData.PLAYFIELD_GROUND_Y)
    runtime_ = RuntimeFactory.CreateLevelObjects({ scene = scene_, mapper = mapper_ }, level_)
    local launcher = LevelData.FindFirst(level_, "launcher")
    if not launcher then error("关卡缺少发射器") end
    local launcherRuntime = runtime_.byId[launcher.id]
    apple_ = RuntimeFactory.CreateApple(scene_, launcherRuntime)
    rules_ = Rules.NewState()
    InitializeCards()
    draggedApple_ = false
    activeCardId_ = nil
    primedCardId_ = nil
    isPaused_ = false
    activeCardStart_ = nil
    activeCardPointer_ = nil
    activeCardDragged_ = false
    activeCardDeploying_ = false
    cardParameterStart_ = nil
    cardPointerLast_ = nil
    cardPointerStillMs_ = 0
    cardCandidate_ = nil
    cardGestureDistance_ = 0
    bulletTimeActive_ = false
    bulletTimeAccumulator_ = 0
    bulletTimeStepOpen_ = false
    launched_ = false
    goalContact_ = false
    goalContactMs_ = 0
    outsideMs_ = 0
    flightMs_ = 0
    stalledMs_ = 0
    phaseTraversing_ = false
    success_ = false
    failed_ = false
    replayActive_ = false
    replayTime_ = 0
    replayPaused_ = false
    replaySpeed_ = 1
    replayFinished_ = false
    replaySamples_ = {}
    replayEvents_ = {}
    replaySavedApple_ = nil
    cardBurns_ = {}
    burningCardIds_ = {}
    ruleDeployCount_ = 0
    replaySampleAccumulator_ = 0
    trail_ = {}
    sensorAngle_ = 0
    uiElapsed_ = 0
    anger_ = 0
    if InitializeMechanisms then InitializeMechanisms() end
    SetGravity()
    SyncPhysicsUpdateEnabled()
    SetStatus(string.format("READY · 实验 %02d · %s", index, level_.name))
end

local function ResetExperiment(playResetSound)
    if not apple_ or not level_ then return end
    if playResetSound ~= false then PlaySound("reset") end
    rules_ = Rules.NewState()
    InitializeCards()
    isPaused_ = false
    bulletTimeActive_ = false
    bulletTimeAccumulator_ = 0
    bulletTimeStepOpen_ = false
    apple_.body.bodyType = BT_STATIC
    apple_.body.linearVelocity = Vector2(0, 0)
    apple_.body.angularVelocity = 0
    apple_.node:SetPosition2D(apple_.launcher.spawnWorldX, apple_.launcher.spawnWorldY)
    apple_.node:SetRotation2D(0)
    apple_.body.awake = true
    apple_.shape.trigger = false
    launched_ = false
    draggedApple_ = false
    activeCardId_ = nil
    primedCardId_ = nil
    activeCardStart_ = nil
    activeCardPointer_ = nil
    activeCardDragged_ = false
    activeCardDeploying_ = false
    cardParameterStart_ = nil
    cardPointerLast_ = nil
    cardPointerStillMs_ = 0
    cardCandidate_ = nil
    cardGestureDistance_ = 0
    goalContact_ = false
    goalContactMs_ = 0
    outsideMs_ = 0
    flightMs_ = 0
    stalledMs_ = 0
    phaseTraversing_ = false
    success_ = false
    failed_ = false
    replayActive_ = false
    replayTime_ = 0
    replayPaused_ = false
    replaySpeed_ = 1
    replayFinished_ = false
    replaySamples_ = {}
    replayEvents_ = {}
    replaySavedApple_ = nil
    cardBurns_ = {}
    burningCardIds_ = {}
    ruleDeployCount_ = 0
    replaySampleAccumulator_ = 0
    trail_ = {}
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
            end
        end
    end
    if InitializeMechanisms then InitializeMechanisms() end
    SetGravity()
    SyncPhysicsUpdateEnabled()
    SetStatus("READY · 等待发射")
end

local function DesignPointer()
    local mouse = input.mousePosition
    local x, y = design_:ScreenToLogical(mouse.x, mouse.y)
    return x, y
end

local function PointerInPlayfield(x, y)
    return x >= frame_.playfieldX + 18 and x <= frame_.playfieldX + frame_.playfieldWidth - 18
        and y >= frame_.playfieldY + 18 and y <= frame_.groundY - 18
end

local function PointerToWorld(x, y)
    return design_:LogicalToWorld(x, y)
end

local function AppleScreenPosition()
    local p = apple_.node.position2D
    return design_:WorldToLogical(p.x, p.y)
end

local function IsNearApple(x, y)
    local ax, ay = AppleScreenPosition()
    local dx, dy = x - ax, y - ay
    return dx * dx + dy * dy <= 46 * 46
end

local function UpdateAppleDrag(x, y)
    local launcher = apple_.launcher
    local lx, ly = design_:LevelToLogical(launcher.spawnLevelX, launcher.spawnLevelY)
    local dx, dy = x - lx, y - ly
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 98 then dx, dy = dx * 98 / length, dy * 98 / length end
    dx = math.max(dx, -76)
    dy = math.min(dy, 78)
    local wx, wy = PointerToWorld(lx + dx, ly + dy)
    apple_.node:SetPosition2D(wx, wy)
end

local function LaunchApple()
    draggedApple_ = false
    local launcher = apple_.launcher
    local applePos = apple_.node.position2D
    local dx = (applePos.x - launcher.spawnWorldX) * CONFIG.pixelsPerMeter
    local dy = -(applePos.y - launcher.spawnWorldY) * CONFIG.pixelsPerMeter
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 24 then ResetExperiment(false); return end
    local vx = -dx * 0.165
    local vy = -dy * 0.165
    apple_.body.bodyType = BT_DYNAMIC
    apple_.body.linearVelocity = Vector2(
        vx * 60 / CONFIG.pixelsPerMeter,
        -vy * 60 / CONFIG.pixelsPerMeter
    )
    apple_.body.angularVelocity = -vx * 0.006 * 60
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
    replaySampleAccumulator_ = 0
    SetGravity()
    SetStatus("FLIGHT · 规则已生效")
    PlaySound("launch")
end

local function IsAppleGoalPair(nodeA, nodeB)
    if not nodeA or not nodeB or not runtime_ then return false end
    local goal = LevelData.FindFirst(level_, "goal_sensor")
    if not goal then return false end
    return (nodeA.name == "Apple" and nodeB.name == goal.id) or (nodeB.name == "Apple" and nodeA.name == goal.id)
end

local function IsAppleNode(node)
    return node and node.name == "Apple"
end

local function DoorOpenVector(object)
    local distance = object.openDistance * mapper_.objectScale / CONFIG.pixelsPerMeter
    if object.openDirection == "UP" then return 0, distance end
    if object.openDirection == "DOWN" then return 0, -distance end
    if object.openDirection == "LEFT" then return -distance, 0 end
    return distance, 0
end

local function DoorBlockedByApple(object)
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

local function SetDoorTarget(object, open)
    object.targetOpen = open
    if not open then object.closeAt = flightMs_ + object.closeDelay end
end

local function ApplyDoorSignal(object, active)
    if object.response == "OPEN" then
        SetDoorTarget(object, active)
    elseif object.response == "CLOSE" then
        SetDoorTarget(object, not active)
    elseif active then
        SetDoorTarget(object, not object.targetOpen)
    end
end

local function EmitChannelSignal(channelId, active, sourceId)
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

local function EvaluateButton(object)
    local gravity = Rules.GetGravity(rules_, level_.rules.initialGravity)
    local conditionSatisfied = object.contactCount > 0 and gravity.strength >= object.gravityThreshold
    local activationEdge = not object.conditionSatisfied and conditionSatisfied
    local canActivate = flightMs_ - object.lastActivationAt >= object.debounceTime
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
        object.lastActivationAt = flightMs_
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

local function UpdateDoors(dt)
    if not runtime_ then return end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "door" then
            local target = object.targetOpen and 1 or 0
            local delta = dt * 1000 / math.max(1, object.duration)
            if object.openness < target then
                object.state = "OPENING"
                object.openness = math.min(target, object.openness + delta)
                if object.openness == 1 then object.state = "OPEN" end
            elseif object.openness > target and flightMs_ >= object.closeAt then
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

local function UpdateSpringExits()
    if not runtime_ or not apple_ then return end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "spring" and object.pendingExitVelocity then
            apple_.body.linearVelocity = object.pendingExitVelocity
            apple_.body.awake = true
            object.pendingExitVelocity = nil
        end
    end
end

local function IsInsidePhaseableWall(worldX, worldY)
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

local function UpdatePhaseTraversal()
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

local function ApplyDecision(id, mirrorAxis)
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
        apple_.body.linearVelocity = Vector2(v.x, v.y + 5.52)
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
    PlaySound("card")
    return true
end

local function ApplyCardResolution(id, candidate)
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
        RecordReplayEvent("CARD_PLAYED", id)
        UpdateAngerFromRules()
        SetStatus("RULE DEPLOYED · " .. definition.name)
        PlaySound("card")
        return true
    end
    return launched_ and ApplyDecision(id, candidate) or false
end

local function QueueCardResolution(id, x, y, candidate)
    burningCardIds_[id] = true
    cardBurns_[#cardBurns_ + 1] = {
        id = id,
        x = x,
        y = y,
        candidate = candidate,
        elapsed = 0,
        applyAt = 100,
        duration = 690,
        applied = false,
    }
    SetStatus("CARD RESOLVING · 燃烧")
end

local function CardEntries()
    local result = {}
    for _, id in ipairs(handOrder_) do
        local card = cardDeckById_[id]
        local state = cardStates_[card.cardId]
        if card.enabled and state and not state.consumed and (state.usageMode == "REUSABLE" or state.remainingUses > 0) then result[#result + 1] = card end
    end
    return result
end

local function CardPose(index, count)
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
    return entries[index], poses[index]
end

local function CardHomePose(id)
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
    for i, card in ipairs(entries) do
        if card.cardId == id then return poses[i] end
    end
    return nil
end

local function TryCardPress(x, y)
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
    for i, card in ipairs(entries) do
        local pose = poses[i]
        if pose and not burningCardIds_[card.cardId]
            and x >= pose.x - 72 and x <= pose.x + 72 and y >= pose.y - 101 and y <= pose.y + 101 then
            if primedCardId_ and primedCardId_ ~= card.cardId then primedCardId_ = nil end
            activeCardId_ = card.cardId
            activeCardStart_ = { x = x, y = y }
            activeCardPointer_ = { x = x, y = y }
            activeCardDragged_ = false
            activeCardDeploying_ = false
            cardParameterStart_ = nil
            cardPointerLast_ = { x = x, y = y }
            cardPointerStillMs_ = 0
            cardCandidate_ = nil
            cardGestureDistance_ = 0
            SetStatus("CARD · 按住拖动或再次点击预备")
            return true
        end
    end
    return false
end

local function ClearCardInteraction()
    activeCardStart_ = nil
    activeCardPointer_ = nil
    activeCardDragged_ = false
    activeCardDeploying_ = false
    cardParameterStart_ = nil
    cardPointerLast_ = nil
    cardPointerStillMs_ = 0
    cardCandidate_ = nil
    cardGestureDistance_ = 0
end

local function UpdateCardParameter(dt)
    if not activeCardId_ or not activeCardPointer_ or not activeCardDeploying_ then return end
    if activeCardId_ ~= "side-gravity" and activeCardId_ ~= "mirror-motion" then return end
    local pointer = activeCardPointer_
    if not PointerInPlayfield(pointer.x, pointer.y) then
        cardParameterStart_ = nil
        cardPointerStillMs_ = 0
        cardCandidate_ = nil
        cardGestureDistance_ = 0
        cardPointerLast_ = { x = pointer.x, y = pointer.y }
        return
    end
    if not cardParameterStart_ then
        local last = cardPointerLast_ or pointer
        local dx, dy = pointer.x - last.x, pointer.y - last.y
        if dx * dx + dy * dy <= 16 then cardPointerStillMs_ = cardPointerStillMs_ + dt * 1000 else cardPointerStillMs_ = 0 end
        cardPointerLast_ = { x = pointer.x, y = pointer.y }
        if cardPointerStillMs_ >= 140 then
            cardParameterStart_ = { x = pointer.x, y = pointer.y }
            cardCandidate_ = nil
            cardGestureDistance_ = 0
            SetStatus(activeCardId_ == "side-gravity" and "PARAMETER · 四向滑动选择重力" or "PARAMETER · 滑动选择镜像轴")
        end
        return
    end
    local dx, dy = pointer.x - cardParameterStart_.x, pointer.y - cardParameterStart_.y
    cardGestureDistance_ = math.sqrt(dx * dx + dy * dy)
    if cardGestureDistance_ < 24 then
        cardCandidate_ = nil
    elseif activeCardId_ == "side-gravity" then
        if math.abs(dx) >= math.abs(dy) then cardCandidate_ = dx >= 0 and "RIGHT" or "LEFT" else cardCandidate_ = dy >= 0 and "DOWN" or "UP" end
    else
        cardCandidate_ = math.abs(dx) >= math.abs(dy) and "HORIZONTAL" or "VERTICAL"
    end
end

local function ResolveActiveCard(x, y)
    local id = activeCardId_
    activeCardId_ = nil
    if not id then return end
    local candidate = cardCandidate_
    local gestureDistance = cardGestureDistance_
    local wasDragged = activeCardDragged_
    local wasDeploying = activeCardDeploying_
    if not wasDragged then
        if primedCardId_ == id then
            primedCardId_ = nil
            SetStatus(launched_ and "RUNNING · 实验进行中" or "READY · 等待发射")
        else
            primedCardId_ = id
            SetStatus("BULLET TIME · 0.05")
        end
        ClearCardInteraction()
        return
    end
    primedCardId_ = nil
    if not wasDeploying then
        local home = CardHomePose(id)
        if home and y >= home.y - 40 then
            local entries = CardEntries()
            local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
            local from, target = nil, 1
            local nearest = math.huge
            for i, card in ipairs(entries) do
                if card.cardId == id then from = i end
                local distance = math.abs(x - poses[i].x)
                if distance < nearest then nearest = distance; target = i end
            end
            if from and target and from ~= target then
                local sourceIndex = nil
                for i, cardId in ipairs(handOrder_) do if cardId == id then sourceIndex = i; break end end
                if sourceIndex then
                    table.remove(handOrder_, sourceIndex)
                    local targetId = entries[target] and entries[target].cardId
                    local insertAt = #handOrder_ + 1
                    if targetId then for i, cardId in ipairs(handOrder_) do if cardId == targetId then insertAt = i; break end end end
                    table.insert(handOrder_, insertAt, id)
                    SetStatus("CARD · 手牌顺序已调整")
                end
            end
        end
        ClearCardInteraction()
        return
    end
    if not PointerInPlayfield(x, y) then
        ClearCardInteraction()
        return
    end
    if id == "side-gravity" and (not candidate or gestureDistance < 48) then
        SetStatus("CARD · 横向引力需要明确的方向手势")
        ClearCardInteraction()
        return
    end
    if id == "mirror-motion" and (not candidate or gestureDistance < 48) then
        SetStatus("CARD · 运动镜像需要明确的方向手势")
        ClearCardInteraction()
        return
    end
    if Rules.CARDS[id].kind == "decision" and not launched_ then
        SetStatus("CARD · 当前没有已发射的实验对象")
        ClearCardInteraction()
        return
    end
    QueueCardResolution(id, x, y, candidate)
    ClearCardInteraction()
end

local function HandleReplayPointer(x, y)
    if not input:GetMouseButtonPress(MOUSEB_LEFT) then return end
    local cx, cy = frame_.playfieldX + frame_.playfieldWidth * .5, frame_.playfieldY + 34
    local function inButton(buttonX, width)
        return x >= buttonX - width * .5 and x <= buttonX + width * .5 and y >= cy - 17 and y <= cy + 17
    end
    if inButton(cx - 92, 44) then
        if replayFinished_ then
            replayTime_ = 0; replayFinished_ = false; replayPaused_ = false
        else
            replayPaused_ = not replayPaused_
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

local function HandlePointer()
    if not frame_ or not apple_ then return end
    local x, y = DesignPointer()
    if replayActive_ then HandleReplayPointer(x, y); return end
    local down = input:GetMouseButtonDown(MOUSEB_LEFT)
    local press = input:GetMouseButtonPress(MOUSEB_LEFT)
    local release = input:GetMouseButtonRelease(MOUSEB_LEFT)
    if success_ or failed_ then
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
        if x >= titleX + 255 and x <= titleX + 301 and y >= 23 and y <= 69 then
            BuildLevel(levelIndex_ - 1)
        elseif x >= titleX + 315 and x <= titleX + 361 and y >= 23 and y <= 69 then
            ResetExperiment()
        elseif x >= titleX + 375 and x <= titleX + 421 and y >= 23 and y <= 69 then
            isPaused_ = not isPaused_
        elseif x >= frame_.playfieldX + frame_.playfieldWidth - 100 and x <= frame_.playfieldX + frame_.playfieldWidth and math.abs(y - (frame_.cardHandY + 23)) < 48 then
            if Rules.Punch(rules_) then
                phaseTraversing_ = false
                SetGravity()
                UpdateAngerFromRules()
                RecordReplayEvent("NEWTON_PUNCH")
                SetStatus("NEWTON · 修正拳已出手")
                PlaySound("punch")
            end
        elseif not launched_ and IsNearApple(x, y) then
            draggedApple_ = true
        elseif not isPaused_ then
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
            if home and y < home.y - 40 then
                activeCardDeploying_ = true
                SetStatus("CARD DRAGGING · 子弹时间 0.05")
            end
        end
    end
    if release then
        if draggedApple_ then LaunchApple() end
        if activeCardId_ then ResolveActiveCard(x, y) end
    end
end

local function ResetGoal()
    goalContact_ = false
    goalContactMs_ = 0
    local goal = level_ and LevelData.FindFirst(level_, "goal_sensor") or nil
    local runtimeGoal = goal and runtime_ and runtime_.byId[goal.id] or nil
    if runtimeGoal then runtimeGoal.active = false; runtimeGoal.contactProgress = 0 end
end

local function RecordReplay(dt)
    if not launched_ or replayActive_ or not apple_ then return end
    replaySampleAccumulator_ = replaySampleAccumulator_ + dt * 1000
    if replaySampleAccumulator_ < CONFIG.replaySampleMs then return end
    replaySampleAccumulator_ = 0
    local p = apple_.node.position2D
    local v = apple_.body.linearVelocity
    replaySamples_[#replaySamples_ + 1] = {
        t = flightMs_,
        x = p.x,
        y = p.y,
        vx = v.x,
        vy = v.y,
        angle = apple_.node.rotation2D,
    }
end

local function CaptureReplayFinalSample()
    if not apple_ or #replaySamples_ == 0 then return end
    local last = replaySamples_[#replaySamples_]
    if last and math.abs((last.t or 0) - flightMs_) < .001 then return end
    local p, v = apple_.node.position2D, apple_.body.linearVelocity
    replaySamples_[#replaySamples_ + 1] = {
        t = flightMs_, x = p.x, y = p.y, vx = v.x, vy = v.y, angle = apple_.node.rotation2D,
    }
end

RecordReplayEvent = function(kind, cardId)
    if not launched_ or replayActive_ then return end
    local p = apple_.node.position2D
    replayEvents_[#replayEvents_ + 1] = { t = flightMs_, type = kind, cardId = cardId, x = p.x, y = p.y }
end

local function ReplayDuration()
    local last = replaySamples_[#replaySamples_]
    return last and last.t or 0
end

local function ReplayStateAt(time)
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
    if replayActive_ or #replaySamples_ < 2 or not apple_ then return end
    local p, v = apple_.node.position2D, apple_.body.linearVelocity
    replaySavedApple_ = {
        x = p.x, y = p.y, angle = apple_.node.rotation2D,
        bodyType = apple_.body.bodyType, vx = v.x, vy = v.y, angularVelocity = apple_.body.angularVelocity,
    }
    apple_.body.bodyType = BT_STATIC
    apple_.body.linearVelocity = Vector2(0, 0)
    apple_.body.angularVelocity = 0
    replayActive_ = true
    replayPaused_ = false
    replayFinished_ = false
    replayTime_ = 0
    SetStatus("REPLAY · 轨迹回放")
end

StopReplay = function()
    if not replayActive_ or not apple_ then return end
    local saved = replaySavedApple_
    replayActive_ = false
    replayPaused_ = false
    replayFinished_ = false
    replayTime_ = 0
    replaySavedApple_ = nil
    if saved then
        apple_.node:SetPosition2D(saved.x, saved.y)
        apple_.node:SetRotation2D(saved.angle)
        apple_.body.bodyType = saved.bodyType
        apple_.body.linearVelocity = Vector2(saved.vx, saved.vy)
        apple_.body.angularVelocity = saved.angularVelocity
        apple_.body.awake = true
    end
    if success_ then SetStatus("COMPLETE · 观察成功")
    elseif failed_ then SetStatus("FAILED · 实验未成立")
    else SetStatus(launched_ and "FLIGHT · 规则已生效" or "READY · 等待发射") end
end

local function UpdateReplay(dt)
    if not replayActive_ or replayPaused_ or replayFinished_ then return end
    replayTime_ = math.min(ReplayDuration(), replayTime_ + math.max(0, dt) * 1000 * replaySpeed_)
    if replayTime_ >= ReplayDuration() then
        replayFinished_ = true
        replayPaused_ = true
    end
end

local function UpdateExperiment(dt)
    if not launched_ or replayActive_ then return end
    flightMs_ = flightMs_ + dt * 1000
    RecordReplay(dt)
    UpdateSpringExits()
    UpdatePhaseTraversal()
    local p = apple_.node.position2D
    local screenX, screenY = design_:WorldToLogical(p.x, p.y)
    trail_[#trail_ + 1] = { x = screenX, y = screenY }
    if #trail_ > 70 then table.remove(trail_, 1) end
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
        local matterSpeed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y) * CONFIG.pixelsPerMeter / 60
        if goalContactMs_ >= requiredStayTime and matterSpeed <= 4.8 then
            CaptureReplayFinalSample()
            success_ = true
            launched_ = false
            apple_.body.bodyType = BT_STATIC
            apple_.shape.trigger = true
            SetStatus("COMPLETE · 观察成功")
            PlaySound("success")
        end
    else goalContactMs_ = 0 end
    if screenX < frame_.playfieldX - 120 or screenX > frame_.playfieldX + frame_.playfieldWidth + 120
        or screenY < frame_.playfieldY - 140 or screenY > frame_.playfieldY + frame_.playfieldHeight + 140 then
        CaptureReplayFinalSample()
        failed_ = true
        failureCount_ = failureCount_ + 1
        launched_ = false
        apple_.body.bodyType = BT_STATIC
        SetStatus("FAILED · 苹果离开实验区域")
    else
        local velocity = apple_.body.linearVelocity
        local matterSpeed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y) * CONFIG.pixelsPerMeter / 60
        stalledMs_ = matterSpeed < 0.1 and stalledMs_ + dt * 1000 or 0
        if stalledMs_ > 5200 then
            CaptureReplayFinalSample()
            failed_ = true
            failureCount_ = failureCount_ + 1
            launched_ = false
            apple_.body.bodyType = BT_STATIC
            SetStatus("FAILED · 苹果静止过久")
        end
    end
    if math.abs(p.x) > 7.5 or math.abs(p.y) > 5 then anger_ = math.min(100, anger_ + dt * 2) end
    UpdateDoors(dt)
end

local function DrawAim()
    if not draggedApple_ or not apple_ then return end
    local x, y = AppleScreenPosition()
    local lx, ly = design_:LevelToLogical(apple_.launcher.spawnLevelX, apple_.launcher.spawnLevelY)
    nvgStrokeColor(painter_.vg, nvgRGBA(168, 85, 73, 220)); nvgStrokeWidth(painter_.vg, 2)
    nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, lx, ly); nvgLineTo(painter_.vg, x, y); nvgStroke(painter_.vg)
    nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 130)); nvgStrokeWidth(painter_.vg, 1)
    nvgBeginPath(painter_.vg)
    for i = 0, 20 do
        local t = i / 20
        local px = lx + (x - lx) * t
        local py = ly + (y - ly) * t + 60 * t * t
        if i == 0 then nvgMoveTo(painter_.vg, px, py) else nvgLineTo(painter_.vg, px, py) end
    end
    nvgStroke(painter_.vg)
end

local function DrawLaunchHint()
    if launched_ or draggedApple_ or success_ or failed_ or not apple_ then return end
    local launcher = apple_.launcher
    local lx, ly = design_:LevelToLogical(launcher.spawnLevelX, launcher.spawnLevelY)
    local hintX, hintY = lx + 76, ly - 60
    painter_:RoundedRect(hintX - 78, hintY - 18, 156, 36, 0, Renderer2D.COLORS.panel, nil, nil, 232)
    painter_:Text(hintX, hintY - 7, "拖动苹果，松开发射", 14, Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local pulse = (math.sin(uiElapsed_ * math.pi * 2 / .9) + 1) * .5
    painter_:Circle(lx + 20 - pulse * 60, ly + 16 + pulse * 18, 5, Renderer2D.COLORS.primaryActive, nil, nil, math.floor(208 - pulse * 170))
end

local function DrawTrail()
    if #trail_ < 2 then return end
    nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 120)); nvgStrokeWidth(painter_.vg, 2)
    nvgBeginPath(painter_.vg)
    for i, p in ipairs(trail_) do if i == 1 then nvgMoveTo(painter_.vg, p.x, p.y) else nvgLineTo(painter_.vg, p.x, p.y) end end
    nvgStroke(painter_.vg)
end

local function DrawReplay()
    local state = ReplayStateAt(replayTime_)
    if not state then return end
    local samples = replaySamples_
    if #samples > 1 then
        nvgStrokeWidth(painter_.vg, 2)
        nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 64))
        nvgBeginPath(painter_.vg)
        for i, sample in ipairs(samples) do
            local x, y = design_:WorldToLogical(sample.x, sample.y)
            if i == 1 then nvgMoveTo(painter_.vg, x, y) else nvgLineTo(painter_.vg, x, y) end
        end
        nvgStroke(painter_.vg)
        nvgStrokeWidth(painter_.vg, 4)
        nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 204))
        nvgBeginPath(painter_.vg)
        for i, sample in ipairs(samples) do
            if sample.t > replayTime_ then break end
            local x, y = design_:WorldToLogical(sample.x, sample.y)
            if i == 1 then nvgMoveTo(painter_.vg, x, y) else nvgLineTo(painter_.vg, x, y) end
        end
        local currentX, currentY = design_:WorldToLogical(state.x, state.y)
        nvgLineTo(painter_.vg, currentX, currentY); nvgStroke(painter_.vg)
    end

    for _, event in ipairs(replayEvents_) do
        if event.t <= replayTime_ and (event.type == "CARD_PLAYED" or event.type == "NEWTON_PUNCH") then
            local x, y = design_:WorldToLogical(event.x, event.y)
            local card = event.cardId and Rules.CARDS[event.cardId] or nil
            local accent = card and card.accent or Renderer2D.COLORS.warning
            painter_:Circle(x, y, 15, Renderer2D.COLORS.panel, accent, 2, 245)
            painter_:Text(x, y - 7, card and card.symbol or "N", 13, card and Renderer2D.COLORS.text or Renderer2D.COLORS.warning, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
        end
    end

    local appleX, appleY = design_:WorldToLogical(state.x, state.y)
    painter_:Circle(appleX, appleY, 37, Renderer2D.COLORS.primaryActive, Renderer2D.COLORS.primaryActive, 2, 48)
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
end

local function DrawHUD()
    local f = frame_
    local titleX = f.workspaceX - 37
    painter_:Text(titleX + 36, 19, "牛顿看了想打人", 29, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(titleX + 36, 57, string.format("实验 %02d · %s", levelIndex_, level_.name or ""), 13, Renderer2D.COLORS.greenSecondary)
    painter_:RoundedRect(titleX + 255, 23, 46, 46, 5, Renderer2D.COLORS.dark, Renderer2D.COLORS.white, 2, 110)
    painter_:Text(titleX + 278, 32, "←", 27, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    painter_:RoundedRect(titleX + 315, 23, 46, 46, 5, Renderer2D.COLORS.dark, Renderer2D.COLORS.white, 2, 110)
    painter_:Text(titleX + 338, 32, "↻", 27, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    painter_:RoundedRect(titleX + 375, 23, 46, 46, 5, Renderer2D.COLORS.dark, Renderer2D.COLORS.white, 2, 110)
    painter_:Text(titleX + 398, 34, isPaused_ and "▶" or "Ⅱ", 21, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    painter_:Text(f.playfieldX + 180, 17, "当前实验状态", 12, Renderer2D.COLORS.secondary)
    painter_:Text(f.playfieldX + 180, 42, status_, 17, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(f.playfieldX + 585, 17, "当前场地规则", 12, Renderer2D.COLORS.secondary)
    local g = Rules.GetGravity(rules_, level_.rules.initialGravity)
    painter_:Text(f.playfieldX + 585, 42, string.format("(%d,%d) · %s", g.x, g.y, rules_.activeFields["feather-gravity"] and "轻羽" or "经典场地"), 17, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(f.playfieldX + 800, 18, level_.objective or "让苹果进入观察皿", 16, Renderer2D.COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(f.playfieldX + f.playfieldWidth - 290, 17, "关卡", 12, Renderer2D.COLORS.secondary)
    for i = 1, CONFIG.levelCount do
        local x = f.playfieldX + f.playfieldWidth - 290 + (i - 1) * 27
        painter_:Circle(x, 52, 10, i == levelIndex_ and Renderer2D.COLORS.greenStrong or Renderer2D.COLORS.panelSecondary, Renderer2D.COLORS.greenLight, 1)
        painter_:Text(x, 46, tostring(i), 10, i == levelIndex_ and Renderer2D.COLORS.white or Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
end

local function DrawCards()
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
    for i, card in ipairs(entries) do
        if not burningCardIds_[card.cardId] then
            local pose = poses[i]
            local def = Rules.CARDS[card.cardId]
            local active = activeCardId_ == card.cardId or primedCardId_ == card.cardId
            local field = def.kind == "field"
            local fill = card.cardId == "quantum-phase" and Renderer2D.COLORS.quantumSoft or (field and Renderer2D.COLORS.greenSecondary or Renderer2D.COLORS.instantSoft)
            local edge = card.cardId == "quantum-phase" and Renderer2D.COLORS.quantum or (field and Renderer2D.COLORS.greenStrong or Renderer2D.COLORS.instant)
            local cardX, cardY = pose.x, pose.y - (active and 18 or 0)
            if activeCardId_ == card.cardId and activeCardDragged_ and activeCardPointer_ then cardX, cardY = activeCardPointer_.x, activeCardPointer_.y end
            if activeCardId_ == card.cardId and cardParameterStart_ then cardX, cardY = cardParameterStart_.x, cardParameterStart_.y end
            nvgSave(painter_.vg); nvgTranslate(painter_.vg, cardX, cardY); nvgRotate(painter_.vg, math.rad(active and 0 or pose.angle))
            local cardState = cardStates_[card.cardId]
            local usage = cardState and cardState.usageMode or card.usageMode
            local remaining = cardState and cardState.remainingUses or card.count
            painter_:RoundedRect(-70, -96, 144, 202, 8, Renderer2D.COLORS.dark, nil, nil, 26)
            painter_:RoundedRect(-72, -101, 144, 202, 8, edge)
            painter_:RoundedRect(-66, -95, 132, 190, 6, fill)
            painter_:RoundedRect(-66, -95, 132, 24, 6, edge, nil, nil, 36)
            painter_:RoundedRect(-57, -37, 114, 88, 5, Renderer2D.COLORS.panel, edge, 1, 107)
            painter_:StrokeRect(-57, 59, 114, 0, edge, 1, 133)
            painter_:RoundedRect(-72, -101, 144, 202, 8, nil, active and Renderer2D.COLORS.primaryActive or edge, active and 3 or 2)
            painter_:Text(-58, -85, (field and "场地 · " or "决策 · ") .. (usage == "REUSABLE" and "可重复" or (tostring(remaining) .. " 次")), 9, edge)
            painter_:Text(0, -58, def.name, 16, field and Renderer2D.COLORS.text or Renderer2D.COLORS.body, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            painter_:Text(0, 8, def.symbol, 42, field and Renderer2D.COLORS.text or Renderer2D.COLORS.body, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
            painter_:TextBox(-51, 69, 102, def.description, 10, field and Renderer2D.COLORS.body or Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            painter_:RoundedRect(39, -94, 25, 20, 4, edge)
            painter_:Text(51, -91, usage == "REUSABLE" and "∞" or tostring(remaining), 10, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgRestore(painter_.vg)
        end
    end
    local cx = frame_.playfieldX + frame_.playfieldWidth - 58
    local cy = frame_.cardHandY + 23
    painter_:Circle(cx, cy, 40, Renderer2D.COLORS.dark, Renderer2D.COLORS.warningLow, 2, 240)
    painter_:Text(cx, cy - 16, "✊", 28, Renderer2D.COLORS.warningLow, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(cx, cy + 16, "修正拳", 10, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
end

local function DrawSelectorArrow(x, y, direction, active)
    local fill = active and Renderer2D.COLORS.greenLight or Renderer2D.COLORS.darkSecondary
    local alpha = active and 255 or 219
    nvgFillColor(painter_.vg, nvgRGBA(fill[1], fill[2], fill[3], alpha))
    if direction == "RIGHT" then
        nvgBeginPath(painter_.vg); nvgRect(painter_.vg, x - 22, y - 5, 24, 10); nvgFill(painter_.vg)
        nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, x + 2, y - 13); nvgLineTo(painter_.vg, x + 22, y); nvgLineTo(painter_.vg, x + 2, y + 13); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
    elseif direction == "LEFT" then
        nvgBeginPath(painter_.vg); nvgRect(painter_.vg, x - 2, y - 5, 24, 10); nvgFill(painter_.vg)
        nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, x - 2, y - 13); nvgLineTo(painter_.vg, x - 22, y); nvgLineTo(painter_.vg, x - 2, y + 13); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
    elseif direction == "UP" then
        nvgBeginPath(painter_.vg); nvgRect(painter_.vg, x - 5, y - 2, 10, 24); nvgFill(painter_.vg)
        nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, x - 13, y - 2); nvgLineTo(painter_.vg, x, y - 22); nvgLineTo(painter_.vg, x + 13, y - 2); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
    else
        nvgBeginPath(painter_.vg); nvgRect(painter_.vg, x - 5, y - 22, 10, 24); nvgFill(painter_.vg)
        nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, x - 13, y + 2); nvgLineTo(painter_.vg, x, y + 22); nvgLineTo(painter_.vg, x + 13, y + 2); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
    end
end

local function DrawCardParameterSelector()
    if not activeCardId_ or not cardParameterStart_ or not activeCardPointer_ then return end
    local anchor, pointer = cardParameterStart_, activeCardPointer_
    nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 61)); nvgStrokeWidth(painter_.vg, 2)
    nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, anchor.x, anchor.y); nvgLineTo(painter_.vg, pointer.x, pointer.y); nvgStroke(painter_.vg)
    painter_:Circle(anchor.x, anchor.y, 3.5, Renderer2D.COLORS.greenStrong, nil, nil, 184)
    if activeCardId_ == "side-gravity" then
        DrawSelectorArrow(anchor.x, anchor.y - 116, "UP", cardCandidate_ == "UP")
        DrawSelectorArrow(anchor.x - 98, anchor.y, "LEFT", cardCandidate_ == "LEFT")
        DrawSelectorArrow(anchor.x + 98, anchor.y, "RIGHT", cardCandidate_ == "RIGHT")
        DrawSelectorArrow(anchor.x, anchor.y + 116, "DOWN", cardCandidate_ == "DOWN")
    else
        local horizontal = cardCandidate_ == "HORIZONTAL"
        local vertical = cardCandidate_ == "VERTICAL"
        DrawSelectorArrow(anchor.x - 98, anchor.y, "LEFT", horizontal)
        DrawSelectorArrow(anchor.x - 98, anchor.y, "RIGHT", horizontal)
        DrawSelectorArrow(anchor.x + 98, anchor.y, "UP", vertical)
        DrawSelectorArrow(anchor.x + 98, anchor.y, "DOWN", vertical)
    end
end

local function DrawCardBurns()
    for _, burn in ipairs(cardBurns_) do
        local progress = math.max(0, math.min(1, burn.elapsed / burn.duration))
        local def = Rules.CARDS[burn.id]
        local edge = burn.id == "quantum-phase" and Renderer2D.COLORS.quantum or Renderer2D.COLORS.instant
        local top = burn.y - 101 + progress * 202
        local visibleHeight = math.max(0, 202 * (1 - progress))
        if visibleHeight > 1 then
            nvgSave(painter_.vg)
            nvgScissor(painter_.vg, burn.x - 72, top, 144, visibleHeight)
            painter_:RoundedRect(burn.x - 72, burn.y - 101, 144, 202, 8, Renderer2D.COLORS.instantSoft, edge, 2)
            painter_:Text(burn.x, burn.y - 58, def and def.name or burn.id, 16, Renderer2D.COLORS.body, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            painter_:Text(burn.x, burn.y + 8, def and def.symbol or "", 42, Renderer2D.COLORS.warningActive, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
            nvgRestore(painter_.vg)
            nvgStrokeColor(painter_.vg, nvgRGBA(198, 106, 88, math.floor(255 * (1 - progress))))
            nvgStrokeWidth(painter_.vg, 3); nvgBeginPath(painter_.vg)
            for i = 0, 12 do
                local x = burn.x - 68 + i * (136 / 12)
                local y = top + math.sin(i * 1.73) * 3.6 + math.sin(i * .67 + .8) * 2.2
                if i == 0 then nvgMoveTo(painter_.vg, x, y) else nvgLineTo(painter_.vg, x, y) end
            end
            nvgStroke(painter_.vg)
            for i = 1, 3 do
                local sparkProgress = math.max(0, (progress - (i - 1) * .2) / .8)
                if sparkProgress > 0 then
                    painter_:Circle(burn.x - 34 + i * 28, top - sparkProgress * 34, 3 - sparkProgress, Renderer2D.COLORS.warningActive, nil, nil, math.floor(200 * (1 - sparkProgress)))
                end
            end
        end
    end
end

local function DrawOverlay()
    if (activeCardId_ or primedCardId_ or #cardBurns_ > 0) and not isPaused_ and not success_ and not failed_ then
        painter_:RoundedRect(frame_.playfieldX + 8, frame_.playfieldY + 8, frame_.playfieldWidth - 16, frame_.playfieldHeight - 16, 5, Renderer2D.COLORS.greenSoft, Renderer2D.COLORS.primaryActive, 3, 46)
    end
    if isPaused_ then
        painter_:FillRect(frame_.playfieldX, frame_.playfieldY, frame_.playfieldWidth, frame_.playfieldHeight, { 0, 0, 0, 255 }, 66)
        painter_:Text(frame_.playfieldX + frame_.playfieldWidth - 24, frame_.playfieldY + 18, "实验暂停 · 规则卡可操作", 13, Renderer2D.COLORS.text, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    end
    if success_ or failed_ then
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
    SubscribeToEvent("PhysicsBeginContact2D", "HandleCollisionBegin")
    SubscribeToEvent("PhysicsEndContact2D", "HandleCollisionEnd")
    SubscribeToEvent(painter_.vg, "NanoVGRender", "HandleRender")
    print("[Migration] 1:1 design-space runtime started")
end

function Stop()
    if painter_ then painter_:Destroy(); painter_ = nil end
end

---@param _eventType string
---@param eventData UpdateEventData
function HandleUpdate(_eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")
    if audio_ then audio_:Update(dt) end
    uiElapsed_ = uiElapsed_ + dt
    sensorAngle_ = sensorAngle_ + dt * (goalContact_ and (math.pi * 2 / 7.2) or (math.pi * 2 / 10))
    for i = #cardBurns_, 1, -1 do
        local burn = cardBurns_[i]
        burn.elapsed = burn.elapsed + dt * 1000
        if not burn.applied and burn.elapsed >= burn.applyAt then
            burn.applied = ApplyCardResolution(burn.id, burn.candidate)
        end
        if burn.elapsed >= burn.duration then
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
    frame_ = design_:Frame()
    HandlePointer()
    UpdateCardParameter(dt)
    if input:GetKeyPress(KEY_R) then ResetExperiment() end
    if input:GetKeyPress(KEY_P) or input:GetKeyPress(KEY_SPACE) then
        isPaused_ = not isPaused_
    end
    if input:GetKeyPress(KEY_Z) then debugDraw_ = not debugDraw_ end
    if input:GetKeyPress(KEY_V) and #replaySamples_ > 1 then
        if replayActive_ then StopReplay() else StartReplay() end
    end
    if input:GetKeyPress(KEY_LEFT) and levelIndex_ > 1 then BuildLevel(levelIndex_ - 1) end
    if input:GetKeyPress(KEY_RIGHT) and levelIndex_ < CONFIG.levelCount then BuildLevel(levelIndex_ + 1) end
    SyncPhysicsUpdateEnabled()
    UpdateBulletTime(dt)
    if replayActive_ then
        UpdateReplay(dt)
    elseif not isPaused_ then
        UpdateExperiment(dt)
    end
    if debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
end

function HandleScreenMode()
    frame_ = design_:Frame()
end

---@param _eventType string
---@param eventData PhysicsBeginContact2DEventData
function HandleCollisionBegin(_eventType, eventData)
    local nodeA = eventData:GetPtr("NodeA")
    local nodeB = eventData:GetPtr("NodeB")
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
    if object.type == "spring" and object.enabled and object.channelEnabled and not object.spent and flightMs_ - object.triggeredAt >= object.cooldown then
        local v = apple_.body.linearVelocity
        local direction = object.direction
        local ix, iy = 0, 0
        if direction == "UP" then iy = 1 elseif direction == "DOWN" then iy = -1 elseif direction == "LEFT" then ix = -1 else ix = 1 end
        local impulse = object.impulseStrength * Rules.GetRestitutionMultiplier(rules_)
        object.pendingExitVelocity = Vector2(v.x + ix * impulse, v.y + iy * impulse)
        object.triggeredAt = flightMs_
        object.spent = object.oneShot
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
    painter_:DrawNewton(frame_, level_, anger_)
    painter_:DrawGround(frame_)
    if runtime_ then for _, object in ipairs(runtime_.ordered) do painter_:DrawObject(frame_, object, { sensorAngle = sensorAngle_, success = success_ }) end end
    if replayActive_ then
        DrawReplay()
    else
        DrawTrail()
        DrawAim()
        DrawLaunchHint()
        painter_:DrawApple(frame_, apple_)
    end
    DrawHUD()
    DrawCards()
    DrawCardParameterSelector()
    DrawCardBurns()
    DrawOverlay()
    painter_:Finish()
end
