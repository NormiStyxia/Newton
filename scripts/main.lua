local LevelData = require("migration.LevelData")
local CoordinateMapper = require("migration.CoordinateMapper")
local DesignSpace = require("migration.DesignSpace")
local Rules = require("migration.Rules")
local RuntimeFactory = require("migration.RuntimeFactory")
local Renderer2D = require("migration.Renderer")

local CONFIG = {
    title = "牛顿看了想打人",
    pixelsPerMeter = 100,
    gravityAcceleration = 10,
    levelCount = 9,
    replaySampleMs = 50,
    goalStayMs = 700,
    failOutsideMs = 700,
    maxFlightMs = 30000,
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
local launched_ = false
local goalContact_ = false
local goalContactMs_ = 0
local outsideMs_ = 0
local flightMs_ = 0
local status_ = "READY · 等待发射"
local isPaused_ = false
local isEditor_ = false
local debugDraw_ = false
local success_ = false
local failed_ = false
local replayActive_ = false
local replayTime_ = 0
local replaySamples_ = {}
local replaySampleAccumulator_ = 0
local trail_ = {}
local sensorAngle_ = 0
local anger_ = 0
local lastPointerDown_ = false
local editorSelection_ = nil
local editorHistory_ = {}
local editorFuture_ = {}

local function SetStatus(value)
    status_ = value
    print("[Migration] " .. value)
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
    SetupViewport()
    RuntimeFactory.CreateViewportBackground(scene_)
    ground_ = RuntimeFactory.CreateGround(scene_, mapper_, LevelData.PLAYFIELD_GROUND_Y)
    runtime_ = RuntimeFactory.CreateLevelObjects({ scene = scene_, mapper = mapper_ }, level_)
    local launcher = LevelData.FindFirst(level_, "launcher")
    if not launcher then error("关卡缺少发射器") end
    local launcherRuntime = runtime_.byId[launcher.id]
    apple_ = RuntimeFactory.CreateApple(scene_, launcherRuntime)
    rules_ = Rules.NewState()
    draggedApple_ = false
    activeCardId_ = nil
    launched_ = false
    goalContact_ = false
    goalContactMs_ = 0
    outsideMs_ = 0
    flightMs_ = 0
    success_ = false
    failed_ = false
    replayActive_ = false
    replayTime_ = 0
    replaySamples_ = {}
    replaySampleAccumulator_ = 0
    trail_ = {}
    sensorAngle_ = 0
    anger_ = 0
    editorSelection_ = nil
    editorHistory_ = {}
    editorFuture_ = {}
    SetGravity()
    SetStatus(string.format("READY · 实验 %02d · %s", index, level_.name))
end

local function ResetExperiment()
    if not apple_ or not level_ then return end
    rules_ = Rules.NewState()
    apple_.body.bodyType = BT_STATIC
    apple_.body.linearVelocity = Vector2(0, 0)
    apple_.body.angularVelocity = 0
    apple_.node:SetPosition2D(apple_.launcher.spawnWorldX, apple_.launcher.spawnWorldY)
    apple_.node:SetRotation2D(0)
    apple_.body.awake = true
    launched_ = false
    draggedApple_ = false
    activeCardId_ = nil
    goalContact_ = false
    goalContactMs_ = 0
    outsideMs_ = 0
    flightMs_ = 0
    success_ = false
    failed_ = false
    replayActive_ = false
    replayTime_ = 0
    replaySamples_ = {}
    replaySampleAccumulator_ = 0
    trail_ = {}
    anger_ = 0
    if runtime_ then
        for _, object in ipairs(runtime_.ordered) do
            object.active = object.data.properties and object.data.properties.initialState == true or false
            object.contactMs = 0
            object.spent = false
            object.openness = object.data.properties and object.data.properties.initialState == "OPEN" and 1 or 0
            object.targetOpen = object.openness == 1
        end
    end
    SetGravity()
    SetStatus("READY · 等待发射")
end

local function DesignPointer()
    local mouse = input.mousePosition
    local x, y = design_:ScreenToLogical(mouse.x, mouse.y)
    return x, y
end

local function PointerInPlayfield(x, y)
    return x >= frame_.playfieldX and x <= frame_.playfieldX + frame_.playfieldWidth
        and y >= frame_.playfieldY and y <= frame_.playfieldY + frame_.playfieldHeight
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
    if length < 24 then ResetExperiment(); return end
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
    SetGravity()
    SetStatus("FLIGHT · 规则已生效")
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

local function UpdateDoors(dt)
    if not runtime_ then return end
    for _, object in ipairs(runtime_.ordered) do
        if object.type == "door" then
            local props = object.data.properties or {}
            local target = object.targetOpen and 1 or 0
            local duration = math.max(1, props.duration or 300)
            local delta = dt * 1000 / duration
            if object.openness < target then object.openness = math.min(target, object.openness + delta)
            elseif object.openness > target then object.openness = math.max(target, object.openness - delta) end
            local direction = props.openDirection or "UP"
            local ox, oy = 0, 0
            if direction == "UP" then oy = -(props.openDistance or 100) * mapper_.objectScale / CONFIG.pixelsPerMeter
            elseif direction == "DOWN" then oy = (props.openDistance or 100) * mapper_.objectScale / CONFIG.pixelsPerMeter
            elseif direction == "LEFT" then ox = -(props.openDistance or 100) * mapper_.objectScale / CONFIG.pixelsPerMeter
            else ox = (props.openDistance or 100) * mapper_.objectScale / CONFIG.pixelsPerMeter end
            object.node:SetPosition2D(object.worldX + ox * object.openness, object.worldY + oy * object.openness)
        end
    end
end

local function ApplyDecision(id, pointerX, pointerY)
    if not Rules.UseDecision(rules_, id) then return false end
    if id == "up-impulse" then
        local v = apple_.body.linearVelocity
        apple_.body.linearVelocity = Vector2(v.x, v.y + 4.2)
    elseif id == "mirror-motion" then
        local v = apple_.body.linearVelocity
        if math.abs(pointerX - activeCardStart_.x) >= math.abs(pointerY - activeCardStart_.y) then
            apple_.body.linearVelocity = Vector2(-v.x, v.y)
            rules_.mirrorAxis = "HORIZONTAL"
        else
            apple_.body.linearVelocity = Vector2(v.x, -v.y)
            rules_.mirrorAxis = "VERTICAL"
        end
    elseif id == "quantum-phase" then
        SetGravity()
    end
    anger_ = math.min(100, anger_ + 10)
    SetStatus("CARD · " .. (Rules.CARDS[id] and Rules.CARDS[id].name or id))
    return true
end

local function CardEntries()
    local result = {}
    for _, card in ipairs(level_.cardDeck.cards or {}) do
        if card.enabled and card.count > 0 then result[#result + 1] = card end
    end
    table.sort(result, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return result
end

local function CardPose(index, count)
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
    return entries[index], poses[index]
end

local function TryCardPress(x, y)
    local entries = CardEntries()
    local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
    for i, card in ipairs(entries) do
        local pose = poses[i]
        if pose and x >= pose.x - 72 and x <= pose.x + 72 and y >= pose.y - 101 and y <= pose.y + 101 then
            activeCardId_ = card.cardId
            activeCardStart_ = { x = x, y = y }
            SetStatus("CARD · 拖动到实验场地以部署")
            return true
        end
    end
    return false
end

local function ResolveActiveCard(x, y)
    local id = activeCardId_
    activeCardId_ = nil
    if not id then return end
    if not PointerInPlayfield(x, y) then
        if not launched_ and Rules.CARDS[id].kind == "field" then Rules.ToggleField(rules_, id); SetGravity() end
        return
    end
    if Rules.CARDS[id].kind == "field" then
        if launched_ then rules_.activeFields[id] = true else Rules.ToggleField(rules_, id) end
        if id == "side-gravity" then
            local dx, dy = x - activeCardStart_.x, y - activeCardStart_.y
            if math.abs(dx) > math.abs(dy) then rules_.sideGravity = { x = dx >= 0 and 1 or -1, y = 0 } else rules_.sideGravity = { x = 0, y = dy >= 0 and 1 or -1 } end
        end
        SetGravity()
        return
    end
    if launched_ then ApplyDecision(id, x, y) end
end

local function HandlePointer()
    if not frame_ or not apple_ then return end
    local x, y = DesignPointer()
    local down = input:GetMouseButtonDown(MOUSEB_LEFT)
    local press = input:GetMouseButtonPress(MOUSEB_LEFT)
    local release = input:GetMouseButtonRelease(MOUSEB_LEFT)
    if press then
        if isEditor_ then
            for _, object in ipairs(runtime_.ordered) do
                local t = object.data.transform
                local ox = frame_.playfieldX + t.x / 1400 * frame_.playfieldWidth
                local oy = frame_.playfieldY + t.y / 700 * frame_.playfieldHeight
                if math.abs(x - ox) <= t.width and math.abs(y - oy) <= t.height then editorSelection_ = object; break end
            end
        elseif x >= frame_.workspaceX + 274 and x <= frame_.workspaceX + 324 and y < 94 then
            BuildLevel(levelIndex_ - 1)
        elseif x >= frame_.workspaceX + 330 and x <= frame_.workspaceX + 380 and y < 94 then
            ResetExperiment()
        elseif x >= frame_.workspaceX + 386 and x <= frame_.workspaceX + 440 and y < 94 then
            isPaused_ = not isPaused_; if physicsWorld_ then physicsWorld_:SetUpdateEnabled(not isPaused_) end
        elseif x >= frame_.playfieldX + frame_.playfieldWidth - 100 and x <= frame_.playfieldX + frame_.playfieldWidth and math.abs(y - (frame_.cardHandY + 23)) < 48 then
            if launched_ then Rules.Punch(rules_); SetGravity(); anger_ = math.min(100, anger_ + 18); SetStatus("NEWTON · 修正拳已出手") end
        elseif not launched_ and IsNearApple(x, y) then
            draggedApple_ = true
        elseif not isPaused_ then
            TryCardPress(x, y)
        end
    end
    if down and draggedApple_ and not launched_ then UpdateAppleDrag(x, y) end
    if release then
        if draggedApple_ then LaunchApple() end
        if activeCardId_ then ResolveActiveCard(x, y) end
    end
    lastPointerDown_ = down
end

local function ResetGoal()
    goalContact_ = false
    goalContactMs_ = 0
end

local function RecordReplay(dt)
    if not launched_ or replayActive_ or not apple_ then return end
    replaySampleAccumulator_ = replaySampleAccumulator_ + dt * 1000
    if replaySampleAccumulator_ < CONFIG.replaySampleMs then return end
    replaySampleAccumulator_ = 0
    local p = apple_.node.position2D
    local v = apple_.body.linearVelocity
    replaySamples_[#replaySamples_ + 1] = { x = p.x, y = p.y, vx = v.x, vy = v.y }
end

local function UpdateExperiment(dt)
    if not launched_ or replayActive_ then return end
    flightMs_ = flightMs_ + dt * 1000
    sensorAngle_ = sensorAngle_ + dt * 1.8
    RecordReplay(dt)
    local p = apple_.node.position2D
    local screenX, screenY = design_:WorldToLogical(p.x, p.y)
    trail_[#trail_ + 1] = { x = screenX, y = screenY }
    if #trail_ > 70 then table.remove(trail_, 1) end
    if goalContact_ then
        goalContactMs_ = goalContactMs_ + dt * 1000
        if goalContactMs_ >= CONFIG.goalStayMs then success_ = true; launched_ = false; SetStatus("COMPLETE · 观察成功") end
    else goalContactMs_ = 0 end
    if not PointerInPlayfield(screenX, screenY) then outsideMs_ = outsideMs_ + dt * 1000 else outsideMs_ = 0 end
    if outsideMs_ >= CONFIG.failOutsideMs or flightMs_ > CONFIG.maxFlightMs then failed_ = true; launched_ = false; SetStatus("FAILED · 苹果离开实验区域") end
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

local function DrawTrail()
    if #trail_ < 2 then return end
    nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 120)); nvgStrokeWidth(painter_.vg, 2)
    nvgBeginPath(painter_.vg)
    for i, p in ipairs(trail_) do if i == 1 then nvgMoveTo(painter_.vg, p.x, p.y) else nvgLineTo(painter_.vg, p.x, p.y) end end
    nvgStroke(painter_.vg)
end

local function DrawHUD()
    local f = frame_
    painter_:Text(f.workspaceX - 37, 19, "牛顿看了想打人", 29, Renderer2D.COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(f.workspaceX - 37, 57, string.format("实验 %02d · %s", levelIndex_, level_.name or ""), 13, Renderer2D.COLORS.greenSecondary)
    painter_:RoundedRect(f.workspaceX + 254, 23, 46, 46, 5, Renderer2D.COLORS.dark, Renderer2D.COLORS.white, 2, 110)
    painter_:Text(f.workspaceX + 277, 32, "←", 27, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    painter_:RoundedRect(f.workspaceX + 314, 23, 46, 46, 5, Renderer2D.COLORS.dark, Renderer2D.COLORS.white, 2, 110)
    painter_:Text(f.workspaceX + 337, 32, "↻", 27, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    painter_:RoundedRect(f.workspaceX + 374, 23, 46, 46, 5, Renderer2D.COLORS.dark, Renderer2D.COLORS.white, 2, 110)
    painter_:Text(f.workspaceX + 397, 34, isPaused_ and "▶" or "Ⅱ", 21, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
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
        local pose = poses[i]
        local def = Rules.CARDS[card.cardId]
        local active = activeCardId_ == card.cardId
        local field = def.kind == "field"
        local fill = card.cardId == "quantum-phase" and Renderer2D.COLORS.quantumSoft or (field and Renderer2D.COLORS.greenSecondary or Renderer2D.COLORS.instantSoft)
        local edge = card.cardId == "quantum-phase" and Renderer2D.COLORS.quantum or (field and Renderer2D.COLORS.greenStrong or Renderer2D.COLORS.instant)
        nvgSave(painter_.vg); nvgTranslate(painter_.vg, pose.x, pose.y - (active and 18 or 0)); nvgRotate(painter_.vg, math.rad(active and 0 or pose.angle))
        painter_:RoundedRect(-72, -101, 144, 202, 8, fill, edge, 2)
        painter_:Text(-56, -82, field and "场地" or "决策", 9, edge)
        painter_:Text(0, -61, def.name, 16, Renderer2D.COLORS.text, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
        painter_:Text(0, -9, def.symbol, 42, edge, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
        painter_:Text(0, 45, def.description, 10, Renderer2D.COLORS.body, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        painter_:RoundedRect(51, -92, 20, 19, 4, edge)
        painter_:Text(61, -89, card.usageMode == "REUSABLE" and "∞" or tostring(card.count), 10, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgRestore(painter_.vg)
    end
    local cx = frame_.playfieldX + frame_.playfieldWidth - 58
    local cy = frame_.cardHandY + 23
    painter_:Circle(cx, cy, 40, Renderer2D.COLORS.dark, Renderer2D.COLORS.warningLow, 2, 240)
    painter_:Text(cx, cy - 16, "✊", 28, Renderer2D.COLORS.warningLow, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
    painter_:Text(cx, cy + 16, "修正拳", 10, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
end

local function DrawOverlay()
    if isPaused_ then
        painter_:FillRect(frame_.playfieldX, frame_.playfieldY, frame_.playfieldWidth, frame_.playfieldHeight, { 0, 0, 0, 255 }, 66)
        painter_:Text(frame_.playfieldX + frame_.playfieldWidth - 24, frame_.playfieldY + 18, "实验暂停 · 规则卡可操作", 13, Renderer2D.COLORS.text, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    end
    if success_ or failed_ then
        painter_:FillRect(frame_.playfieldX, frame_.playfieldY, frame_.playfieldWidth, frame_.playfieldHeight, { 248, 250, 228, 255 }, 194)
        local title = success_ and "观测成功" or "实验失败"
        local body = success_ and "苹果已进入爱因斯坦观察窗" or "苹果离开实验区域，重新调整初始条件"
        painter_:Text(frame_.playfieldX + frame_.playfieldWidth / 2, frame_.playfieldY + 190, title, 34, Renderer2D.COLORS.text, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
        painter_:Text(frame_.playfieldX + frame_.playfieldWidth / 2, frame_.playfieldY + 248, body, 16, Renderer2D.COLORS.body, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        painter_:RoundedRect(frame_.playfieldX + frame_.playfieldWidth / 2 - 75, frame_.playfieldY + 300, 150, 46, 5, Renderer2D.COLORS.greenStrong, Renderer2D.COLORS.dark, 1)
        painter_:Text(frame_.playfieldX + frame_.playfieldWidth / 2, frame_.playfieldY + 312, "↻ 重新实验", 15, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        painter_:Text(frame_.playfieldX + frame_.playfieldWidth / 2, frame_.playfieldY + 370, "V 轨迹回放", 13, Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
    if replayActive_ then
        painter_:RoundedRect(frame_.playfieldX + 18, frame_.playfieldY + 18, 190, 42, 5, Renderer2D.COLORS.dark, Renderer2D.COLORS.greenLight, 1, 225)
        painter_:Text(frame_.playfieldX + 32, frame_.playfieldY + 30, string.format("REPLAY · %.1fs", replayTime_), 14, Renderer2D.COLORS.white)
    end
    if isEditor_ then
        painter_:RoundedRect(frame_.playfieldX + 18, frame_.playfieldY + 70, 300, 34, 5, Renderer2D.COLORS.dark, Renderer2D.COLORS.warningLow, 1, 230)
        painter_:Text(frame_.playfieldX + 30, frame_.playfieldY + 79, "EDITOR · E 退出 · Ctrl+Z 撤销 · Ctrl+Y 重做", 12, Renderer2D.COLORS.white)
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
    frame_ = design_:Frame()
    HandlePointer()
    if input:GetKeyPress(KEY_R) then ResetExperiment() end
    if input:GetKeyPress(KEY_P) or input:GetKeyPress(KEY_SPACE) then
        isPaused_ = not isPaused_; if physicsWorld_ then physicsWorld_:SetUpdateEnabled(not isPaused_) end
    end
    if input:GetKeyPress(KEY_E) then isEditor_ = not isEditor_; SetStatus(isEditor_ and "EDITOR · 选择对象并拖动" or "READY · 编辑器已退出") end
    if input:GetKeyPress(KEY_Z) then debugDraw_ = not debugDraw_ end
    if input:GetKeyPress(KEY_V) and #replaySamples_ > 1 then replayActive_ = not replayActive_; replayTime_ = 0 end
    if input:GetKeyPress(KEY_Y) and isEditor_ and #editorFuture_ > 0 then
        local value = table.remove(editorFuture_); editorHistory_[#editorHistory_ + 1] = value
    end
    if input:GetKeyPress(KEY_LEFT) and levelIndex_ > 1 then BuildLevel(levelIndex_ - 1) end
    if input:GetKeyPress(KEY_RIGHT) and levelIndex_ < CONFIG.levelCount then BuildLevel(levelIndex_ + 1) end
    if replayActive_ then
        replayTime_ = replayTime_ + dt
        if replayTime_ > (#replaySamples_ - 1) * CONFIG.replaySampleMs / 1000 then replayActive_ = false end
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
    if IsAppleGoalPair(nodeA, nodeB) then goalContact_ = true; SetStatus("OBSERVE · 苹果进入观察窗"); return end
    if not nodeA or not nodeB or not runtime_ or not IsAppleNode(nodeA) and not IsAppleNode(nodeB) then return end
    local other = IsAppleNode(nodeA) and nodeB or nodeA
    local object = runtime_.byId[other.name]
    if not object then return end
    if object.type == "spring" and not object.spent then
        local props = object.data.properties or {}
        local v = apple_.body.linearVelocity
        local direction = props.direction or "UP"
        local ix, iy = 0, 0
        if direction == "UP" then iy = 1 elseif direction == "DOWN" then iy = -1 elseif direction == "LEFT" then ix = -1 else ix = 1 end
        local impulse = props.impulseStrength or 5
        apple_.body:ApplyLinearImpulseToCenter(Vector2(ix * impulse, iy * impulse), true)
        object.spent = props.oneShot == true
    elseif object.type == "button" then
        object.contactCount = object.contactCount + 1
        object.active = true
        local channel = object.channelId
        for _, candidate in ipairs(runtime_.ordered) do if candidate.type == "door" and candidate.data.properties and candidate.data.properties.channelId == channel then candidate.targetOpen = true end end
    end
end

---@param _eventType string
---@param eventData PhysicsEndContact2DEventData
function HandleCollisionEnd(_eventType, eventData)
    local nodeA = eventData:GetPtr("NodeA")
    local nodeB = eventData:GetPtr("NodeB")
    if IsAppleGoalPair(nodeA, nodeB) then ResetGoal(); return end
    if not nodeA or not nodeB or not runtime_ or not IsAppleNode(nodeA) and not IsAppleNode(nodeB) then return end
    local other = IsAppleNode(nodeA) and nodeB or nodeA
    local object = runtime_.byId[other.name]
    if object and object.type == "button" then object.contactCount = math.max(0, object.contactCount - 1); object.active = object.contactCount > 0 end
end

function HandleRender()
    if not painter_ or not frame_ or not level_ then return end
    painter_:Begin(frame_)
    painter_:DrawBackground(frame_)
    painter_:DrawNewton(frame_, level_, anger_)
    painter_:DrawGround(frame_)
    if runtime_ then for _, object in ipairs(runtime_.ordered) do painter_:DrawObject(frame_, object, { sensorAngle = sensorAngle_ }) end end
    DrawTrail()
    DrawAim()
    painter_:DrawApple(frame_, apple_)
    DrawHUD()
    DrawCards()
    DrawOverlay()
    painter_:Finish()
end
