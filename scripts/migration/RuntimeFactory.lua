local RuntimeFactory = {}
local MatterCalibration = require("migration.MatterCalibration")

local CATEGORY_APPLE = 0x0001
local CATEGORY_WORLD = 0x0002
local CATEGORY_SENSOR = 0x0004
local CATEGORY_PHASEABLE = 0x0008
local MASK_ALL = 0xFFFF

local function levelTransform(mapper, transform)
    local x, y = mapper:LevelToWorld(transform.x, transform.y)
    local width, height = mapper:LevelSizeToWorld(transform.width, transform.height)
    return x, y, width, height
end

local function createBox(context, data, category, mask, trigger)
    local mapper = context.mapper
    local x, y, width, height = levelTransform(mapper, data.transform)
    local node = context.scene:CreateChild(data.id)
    node:SetPosition2D(x, y)
    node:SetRotation2D(mapper.LevelRotationToWorld(data.transform.rotation))
    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC
    local shape = node:CreateComponent("CollisionBox2D")
    shape:SetSize(width, height)
    shape.categoryBits = category
    shape.maskBits = mask
    shape.trigger = trigger == true
    shape.friction = MatterCalibration.STATIC_FRICTION
    shape.restitution = MatterCalibration.STATIC_RESTITUTION
    return {
        id = data.id,
        type = data.type,
        node = node,
        body = body,
        shape = shape,
        data = data,
        worldX = x,
        worldY = y,
        worldWidth = width,
        worldHeight = height,
    }
end

local FACTORIES = {}

FACTORIES.wall = function(context, data)
    local props = data.properties or {}
    local phaseable = props.isPhaseable == true
    local category = phaseable and CATEGORY_PHASEABLE or CATEGORY_WORLD
    local runtime = createBox(context, data, category, MASK_ALL, false)
    runtime.phaseable = phaseable
    runtime.collisionEnabled = props.collisionEnabled ~= false
    -- SetBody + setStatic reset Phaser's declared wall material. Keep the
    -- runtime-effective values here, while preserving source values in JSON.
    runtime.baseFriction = MatterCalibration.STATIC_FRICTION
    runtime.baseRestitution = MatterCalibration.STATIC_RESTITUTION
    runtime.shape.friction = runtime.baseFriction
    runtime.shape.restitution = runtime.baseRestitution
    runtime.shape.trigger = not runtime.collisionEnabled
    return runtime
end

FACTORIES.launcher = function(context, data)
    local transform = data.transform
    local properties = data.properties or {}
    local spawnLevelX = transform.x + (properties.appleSpawnOffsetX or 0)
    local spawnLevelY = transform.y + (properties.appleSpawnOffsetY or 0)
    local worldX, worldY = context.mapper:LevelToWorld(spawnLevelX, spawnLevelY)
    local node = context.scene:CreateChild(data.id)
    node:SetPosition2D(worldX, worldY)
    node:SetRotation2D(context.mapper.LevelRotationToWorld(transform.rotation or 0))
    return {
        id = data.id,
        type = data.type,
        node = node,
        data = data,
        spawnLevelX = spawnLevelX,
        spawnLevelY = spawnLevelY,
        spawnWorldX = worldX,
        spawnWorldY = worldY,
    }
end

FACTORIES.goal_sensor = function(context, data)
    local runtime = createBox(context, data, CATEGORY_SENSOR, CATEGORY_APPLE, true)
    runtime.requiredStayTime = (data.properties and data.properties.requiredStayTime) or 700
    runtime.contactMs = 0
    runtime.active = false
    return runtime
end

FACTORIES.spring = function(context, data)
    local runtime = createBox(context, data, CATEGORY_WORLD, CATEGORY_APPLE, false)
    local props = data.properties or {}
    runtime.spent = false
    runtime.triggeredAt = -math.huge
    runtime.pendingExitVelocity = nil
    runtime.pulseElapsedMs = nil
    runtime.direction = props.direction or "UP"
    runtime.impulseStrength = props.impulseStrength or 10
    runtime.cooldown = props.cooldown or 500
    runtime.oneShot = props.oneShot == true
    runtime.enabled = props.enabled ~= false
    runtime.enabledChannel = props.enabledChannel or ""
    runtime.channelEnabled = true
    runtime.shape.friction = MatterCalibration.STATIC_FRICTION
    runtime.shape.restitution = MatterCalibration.STATIC_RESTITUTION
    return runtime
end

FACTORIES.button = function(context, data)
    local runtime = createBox(context, data, CATEGORY_SENSOR, CATEGORY_APPLE, true)
    local props = data.properties or {}
    runtime.active = props.initialState == true
    runtime.contactCount = 0
    runtime.conditionSatisfied = false
    runtime.lastActivationAt = -math.huge
    runtime.mode = props.mode == "TOGGLE" and "TOGGLE" or "HOLD"
    runtime.gravityThreshold = math.max(0, props.gravityThreshold or 1)
    runtime.channelId = props.channelId or "route_A"
    runtime.debounceTime = props.debounceTime or 180
    return runtime
end

FACTORIES.door = function(context, data)
    local runtime = createBox(context, data, CATEGORY_WORLD, MASK_ALL, false)
    local props = data.properties or {}
    runtime.openness = props.initialState == "OPEN" and 1 or 0
    runtime.targetOpen = runtime.openness == 1
    runtime.closeAt = 0
    runtime.state = runtime.targetOpen and "OPEN" or "CLOSED"
    runtime.channelId = props.channelId or "route_A"
    runtime.response = props.response or "OPEN"
    runtime.openDirection = props.openDirection or "UP"
    runtime.openDistance = props.openDistance or 190
    runtime.duration = props.duration or 420
    runtime.closeDelay = props.closeDelay or 180
    runtime.antiCrush = props.antiCrush ~= false
    runtime.shape.friction = MatterCalibration.STATIC_FRICTION
    runtime.shape.restitution = MatterCalibration.STATIC_RESTITUTION
    return runtime
end

function RuntimeFactory.CreateViewportBackground(scene)
    -- The background is rendered in design pixels by NanoVG. Keeping this
    -- function as a no-op preserves the old factory boundary without creating
    -- a 3D Zone or a model substitute.
    return { scene = scene, type = "design-background" }
end

local function createWorldBoundary(scene, mapper, definition)
    local worldX, worldY = mapper:ViewportToWorld(definition.x, definition.y)
    local bodyWidth = definition.width / mapper.pixelsPerMeter
    local bodyHeight = definition.height / mapper.pixelsPerMeter
    local node = scene:CreateChild(definition.id)
    node:SetPosition2D(worldX, worldY)
    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC
    local shape = node:CreateComponent("CollisionBox2D")
    shape:SetSize(bodyWidth, bodyHeight)
    -- Matter Body.setStatic makes all laboratory boundaries use its default
    -- material, despite the constructor options in PlayScene.ts.
    shape.friction = MatterCalibration.STATIC_FRICTION
    shape.restitution = MatterCalibration.STATIC_RESTITUTION
    shape.categoryBits = CATEGORY_WORLD
    shape.maskBits = MASK_ALL
    return {
        id = definition.id,
        type = "world-boundary",
        boundary = definition.boundary,
        node = node,
        body = body,
        shape = shape,
        bodyWidth = bodyWidth,
        bodyHeight = bodyHeight,
        worldX = worldX,
        worldY = worldY,
    }
end

---@param scene Scene
---@param mapper CoordinateMapper
---@param groundLevelY number
---@param enabledBoundaries table<string, boolean>
---@return table
function RuntimeFactory.CreateLaboratoryBoundaries(scene, mapper, groundLevelY, enabledBoundaries)
    assert(type(enabledBoundaries) == "table", "physics profile boundaries are required")
    local _, groundViewportY = mapper:LevelToViewport(0, groundLevelY)
    local definitions = {
        {
            boundary = "floor",
            id = "world-floor",
            x = mapper.viewportWidth * 0.5,
            y = groundViewportY + 14,
            width = mapper.viewportWidth - 34,
            height = 28,
            friction = 0.78,
            restitution = 0.22,
        },
        {
            boundary = "ceiling",
            id = "world-ceiling",
            x = mapper.viewportWidth * 0.5,
            y = 24,
            width = mapper.viewportWidth - 34,
            height = 24,
            friction = 0.1,
            restitution = 0.25,
        },
        {
            boundary = "left",
            id = "world-left",
            x = 14,
            y = mapper.viewportHeight * 0.5,
            width = 24,
            height = mapper.viewportHeight - 44,
            friction = 0.1,
            restitution = 0,
        },
        {
            boundary = "right",
            id = "world-right",
            x = mapper.viewportWidth - 14,
            y = mapper.viewportHeight * 0.5,
            width = 24,
            height = mapper.viewportHeight - 44,
            friction = 0.1,
            restitution = 0,
        },
    }
    local runtime = { ordered = {}, byId = {} }
    for _, definition in ipairs(definitions) do
        if enabledBoundaries[definition.boundary] == true then
            local boundary = createWorldBoundary(scene, mapper, definition)
            runtime.ordered[#runtime.ordered + 1] = boundary
            runtime.byId[boundary.id] = boundary
        end
    end
    return runtime
end

function RuntimeFactory.CreateApple(scene, launcher)
    local node = scene:CreateChild("Apple")
    node:SetPosition2D(launcher.spawnWorldX, launcher.spawnWorldY)
    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC
    body.useFixtureMass = false
    body.mass = 1
    -- The source's setCircle call resets frictionAir to Matter's .01 default.
    -- Box2D damping is per second, so use its equivalent 60 Hz coefficient.
    body.linearDamping = MatterCalibration.Box2DLinearDamping(MatterCalibration.APPLE_FRICTION_AIR)
    body.angularDamping = 0
    body.fixedRotation = false
    body.bullet = false
    local shape = node:CreateComponent("CollisionCircle2D")
    shape.radius = 0.27
    shape.density = 1 / (math.pi * 0.27 * 0.27)
    shape.friction = MatterCalibration.APPLE_FRICTION
    shape.restitution = MatterCalibration.APPLE_INITIAL_RESTITUTION
    shape.categoryBits = CATEGORY_APPLE
    shape.maskBits = MASK_ALL
    return {
        id = "apple",
        type = "apple",
        node = node,
        body = body,
        shape = shape,
        radius = 0.27,
        baseRestitution = MatterCalibration.APPLE_INITIAL_RESTITUTION,
        baseFrictionAir = MatterCalibration.APPLE_FRICTION_AIR,
        displayRadius = 32,
        launcher = launcher,
        phaseActive = false,
    }
end

function RuntimeFactory.CreateLevelObjects(context, level)
    local runtime = { ordered = {}, byId = {}, skipped = {} }
    for _, data in ipairs(level.objects or {}) do
        local factory = FACTORIES[data.type]
        if factory then
            local instance = factory(context, data)
            runtime.ordered[#runtime.ordered + 1] = instance
            runtime.byId[instance.id] = instance
        else
            runtime.skipped[#runtime.skipped + 1] = data.id
        end
    end
    return runtime
end

RuntimeFactory.CATEGORY_APPLE = CATEGORY_APPLE
RuntimeFactory.CATEGORY_WORLD = CATEGORY_WORLD
RuntimeFactory.CATEGORY_SENSOR = CATEGORY_SENSOR
RuntimeFactory.CATEGORY_PHASEABLE = CATEGORY_PHASEABLE
RuntimeFactory.MASK_ALL = MASK_ALL

return RuntimeFactory
