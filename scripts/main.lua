local UI = require("urhox-libs/UI")
local LevelData = require("migration.LevelData")
local CoordinateMapper = require("migration.CoordinateMapper")
local RuntimeFactory = require("migration.RuntimeFactory")

local CONFIG = {
    Title = "牛顿看了想打人 · 迁移第一阶段",
    LevelResource = "Data/Levels/level_01.json",
    ViewportWidth = 1500,
    ViewportHeight = 596,
    PixelsPerMeter = 100,
    GravityAcceleration = 10,
}

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
---@type Viewport|nil
local viewport_ = nil
---@type PhysicsWorld2D|nil
local physicsWorld_ = nil
---@type CoordinateMapper|nil
local mapper_ = nil
---@type table|nil
local level_ = nil
---@type table|nil
local runtime_ = nil
---@type table|nil
local apple_ = nil
---@type Panel|nil
local uiRoot_ = nil
---@type Label|nil
local statusLabel_ = nil
---@type Label|nil
local sensorLabel_ = nil
local debugDraw_ = false
local dragging_ = false
local launched_ = false
local goalContact_ = false
local goalNodeName_ = ""
local screenViewport_ = { x = 0, y = 0, width = 1, height = 1 }

local function SetStatus(text)
    print("[Phase1] " .. text)
    if statusLabel_ then statusLabel_:SetText(text) end
end

local function SetGoalContact(active)
    if goalContact_ == active then return end
    goalContact_ = active
    local text = active and "目标 Sensor：苹果已进入" or "目标 Sensor：等待苹果"
    print("[Phase1] " .. text)
    if sensorLabel_ then sensorLabel_:SetText(text) end
end

local function ConfigureFixedViewport()
    if not viewport_ then return end
    local physicalWidth = graphics:GetWidth()
    local physicalHeight = graphics:GetHeight()
    local scale = math.min(
        physicalWidth / CONFIG.ViewportWidth,
        physicalHeight / CONFIG.ViewportHeight
    )
    local width = math.max(1, math.floor(CONFIG.ViewportWidth * scale + 0.5))
    local height = math.max(1, math.floor(CONFIG.ViewportHeight * scale + 0.5))
    local x = math.floor((physicalWidth - width) * 0.5)
    local y = math.floor((physicalHeight - height) * 0.5)
    screenViewport_ = { x = x, y = y, width = width, height = height }
    viewport_:SetRect(IntRect(x, y, x + width, y + height))
    print(string.format("[Phase1] fixed viewport %dx%d at (%d,%d)", width, height, x, y))
end

local function CreateScene()
    assert(level_, "关卡数据尚未加载")
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")
    physicsWorld_ = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld_.velocityIterations = 8
    physicsWorld_.positionIterations = 10
    physicsWorld_.continuousPhysics = true
    physicsWorld_.autoClearForces = true

    local gravity = level_.rules.initialGravity
    physicsWorld_.gravity = Vector2(
        gravity.x * gravity.strength * CONFIG.GravityAcceleration,
        -gravity.y * gravity.strength * CONFIG.GravityAcceleration
    )
end

local function SetupViewport()
    assert(scene_, "场景尚未创建")
    cameraNode_ = scene_:CreateChild("Camera")
    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.orthographic = true
    camera_.orthoSize = CONFIG.ViewportHeight / CONFIG.PixelsPerMeter
    cameraNode_.position = Vector3(0, 0, -10)
    viewport_ = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport_)
    ConfigureFixedViewport()
end

local function CreateGameContent()
    assert(scene_ and mapper_ and level_, "第一阶段运行上下文尚未就绪")
    RuntimeFactory.CreateViewportBackground(
        scene_,
        CONFIG.ViewportWidth / CONFIG.PixelsPerMeter,
        CONFIG.ViewportHeight / CONFIG.PixelsPerMeter
    )
    RuntimeFactory.CreateGround(scene_, mapper_, LevelData.PLAYFIELD_GROUND_Y)
    runtime_ = RuntimeFactory.CreateLevelObjects({ scene = scene_, mapper = mapper_ }, level_)
    local launcher = LevelData.FindFirst(level_, "launcher")
    local goal = LevelData.FindFirst(level_, "goal_sensor")
    if not launcher then error("关卡缺少发射器") end
    if not goal then error("关卡缺少目标 Sensor") end
    goalNodeName_ = goal.id
    local launcherRuntime = runtime_.byId[launcher.id]
    if not launcherRuntime then error("发射器 RuntimeFactory 未注册") end
    apple_ = RuntimeFactory.CreateApple(scene_, launcherRuntime)
end

local function CreateUI()
    statusLabel_ = UI.Label {
        text = "正在加载第一阶段垂直切片…",
        fontSize = 14,
        fontColor = { 239, 231, 205, 255 },
    }
    sensorLabel_ = UI.Label {
        text = "目标 Sensor：等待苹果",
        fontSize = 12,
        fontColor = { 142, 211, 196, 255 },
    }
    uiRoot_ = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.SafeAreaView {
                width = "100%",
                height = "100%",
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        position = "absolute",
                        top = 14,
                        left = 14,
                        padding = 12,
                        gap = 5,
                        backgroundColor = { 8, 22, 19, 224 },
                        borderColor = { 105, 166, 143, 150 },
                        borderWidth = 1,
                        borderRadius = 8,
                        pointerEvents = "none",
                        children = {
                            UI.Label {
                                text = "MIGRATION PHASE 1 · level_01",
                                fontSize = 11,
                                fontColor = { 128, 177, 158, 255 },
                            },
                            statusLabel_,
                            sensorLabel_,
                        },
                    },
                    UI.Label {
                        position = "absolute",
                        left = 0,
                        right = 0,
                        bottom = 16,
                        textAlign = "center",
                        text = "拖动苹果并松开发射 · R 重置 · Z 物理调试",
                        fontSize = 12,
                        fontColor = { 235, 232, 218, 230 },
                        textStroke = { width = 1, color = { 0, 0, 0, 180 } },
                    },
                },
            },
        },
    }
    UI.SetRoot(uiRoot_)
end

local function ResetApple()
    assert(apple_, "苹果尚未创建")
    dragging_ = false
    launched_ = false
    SetGoalContact(false)
    apple_.body.bodyType = BT_STATIC
    apple_.body.linearVelocity = Vector2(0, 0)
    apple_.body.angularVelocity = 0
    apple_.node:SetRotation2D(0)
    apple_.node:SetPosition2D(apple_.launcher.spawnWorldX, apple_.launcher.spawnWorldY)
    apple_.body.awake = true
    SetStatus("READY · 关卡 JSON 已加载，可拖动苹果")
end

local function PointerLevelPosition()
    assert(mapper_, "坐标映射器尚未创建")
    if UI.IsPointerOverUI() then return nil, nil end
    local position = input.mousePosition
    return mapper_:ScreenToLevel(position.x, position.y, screenViewport_)
end

local function PointerHitsApple(levelX, levelY)
    assert(apple_ and mapper_, "苹果运行时尚未创建")
    local applePosition = apple_.node.position2D
    local worldX, worldY = mapper_:LevelToWorld(levelX, levelY)
    local dx = worldX - applePosition.x
    local dy = worldY - applePosition.y
    return dx * dx + dy * dy <= (apple_.radius * 1.35) ^ 2
end

local function UpdateDrag(levelX, levelY)
    assert(apple_ and mapper_, "苹果运行时尚未创建")
    local launcher = apple_.launcher
    local deltaX, deltaY = mapper_:ClampLauncherDrag(
        levelX - launcher.spawnLevelX,
        levelY - launcher.spawnLevelY
    )
    local worldX, worldY = mapper_:LevelToWorld(
        launcher.spawnLevelX + deltaX,
        launcher.spawnLevelY + deltaY
    )
    apple_.node:SetPosition2D(worldX, worldY)
end

local function ReleaseApple()
    assert(apple_ and mapper_, "苹果运行时尚未创建")
    dragging_ = false
    local launcher = apple_.launcher
    local appleWorld = apple_.node.position2D
    local launcherWorldX, launcherWorldY = mapper_:LevelToWorld(
        launcher.spawnLevelX,
        launcher.spawnLevelY
    )
    local viewportDeltaX = (appleWorld.x - launcherWorldX) * CONFIG.PixelsPerMeter
    local viewportDeltaY = -(appleWorld.y - launcherWorldY) * CONFIG.PixelsPerMeter
    local length = math.sqrt(viewportDeltaX * viewportDeltaX + viewportDeltaY * viewportDeltaY)
    if length < 24 then
        ResetApple()
        return
    end

    local matterVelocityX = -viewportDeltaX * 0.165
    local matterVelocityY = -viewportDeltaY * 0.165
    local velocityX, velocityY = mapper_:MatterVelocityToWorld(matterVelocityX, matterVelocityY)
    apple_.body.bodyType = BT_DYNAMIC
    apple_.body.linearVelocity = Vector2(velocityX, velocityY)
    apple_.body.angularVelocity = mapper_.MatterAngularVelocityToWorld(matterVelocityX)
    apple_.body.awake = true
    launched_ = true
    SetStatus(string.format("RUNNING · 发射速度 (%.2f, %.2f) m/s", velocityX, velocityY))
end

local function HandlePointerInput()
    if launched_ then return end
    local levelX, levelY = PointerLevelPosition()
    if input:GetMouseButtonPress(MOUSEB_LEFT)
        and levelX
        and levelY
        and PointerHitsApple(levelX, levelY) then
        dragging_ = true
        SetStatus("AIMING · 保留 Phaser 拖拽约束")
    end
    if dragging_ and input:GetMouseButtonDown(MOUSEB_LEFT) and levelX and levelY then
        UpdateDrag(levelX, levelY)
    end
    if dragging_ and input:GetMouseButtonRelease(MOUSEB_LEFT) then
        ReleaseApple()
    end
end

local function IsAppleGoalPair(nodeA, nodeB)
    if not nodeA or not nodeB then return false end
    local a = nodeA.name
    local b = nodeB.name
    return (a == "Apple" and b == goalNodeName_) or (b == "Apple" and a == goalNodeName_)
end

function Start()
    graphics.windowTitle = CONFIG.Title
    UI.Init({ theme = "default-dark", scale = UI.Scale.DEFAULT })

    local loadError
    level_, loadError = LevelData.Load(CONFIG.LevelResource)
    if not level_ then error(loadError) end
    mapper_ = CoordinateMapper.New({
        levelWidth = level_.playfield.width,
        levelHeight = level_.playfield.height,
        viewportWidth = CONFIG.ViewportWidth,
        viewportHeight = CONFIG.ViewportHeight,
        pixelsPerMeter = CONFIG.PixelsPerMeter,
    })

    CreateScene()
    SetupViewport()
    CreateGameContent()
    CreateUI()
    ResetApple()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleCollisionBegin")
    SubscribeToEvent("PhysicsEndContact2D", "HandleCollisionEnd")
    print("[Phase1] minimal vertical slice started")
end

function Stop()
    UI.Shutdown()
end

---@param _eventType string
---@param eventData UpdateEventData
function HandleUpdate(_eventType, eventData)
    local _ = eventData:GetFloat("TimeStep")
    HandlePointerInput()
    if input:GetKeyPress(KEY_R) then ResetApple() end
    if input:GetKeyPress(KEY_Z) then
        debugDraw_ = not debugDraw_
        SetStatus(debugDraw_ and "DEBUG · Box2D 碰撞体已显示" or "READY · Box2D 调试已关闭")
    end
    if debugDraw_ and physicsWorld_ then physicsWorld_:DrawDebugGeometry() end
end

---@param _eventType string
---@param _eventData ScreenModeEventData
function HandleScreenMode(_eventType, _eventData)
    ConfigureFixedViewport()
end

---@param _eventType string
---@param eventData PhysicsBeginContact2DEventData
function HandleCollisionBegin(_eventType, eventData)
    local nodeA = eventData:GetPtr("NodeA")
    local nodeB = eventData:GetPtr("NodeB")
    if IsAppleGoalPair(nodeA, nodeB) then SetGoalContact(true) end
end

---@param _eventType string
---@param eventData PhysicsEndContact2DEventData
function HandleCollisionEnd(_eventType, eventData)
    local nodeA = eventData:GetPtr("NodeA")
    local nodeB = eventData:GetPtr("NodeB")
    if IsAppleGoalPair(nodeA, nodeB) then SetGoalContact(false) end
end
