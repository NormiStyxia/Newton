local RuntimeFactory = {}

local CATEGORY_APPLE = 0x0001
local CATEGORY_WORLD = 0x0002
local CATEGORY_SENSOR = 0x0004
local MASK_ALL = 0xFFFF

local APPLE_RADIUS = 27 / 100
local APPLE_DISPLAY_DIAMETER = 64 / 100
local APPLE_MASS = 1

local ASSETS = {
    apple = "image/phase1/apple.png",
    launcher = "image/phase1/launcher.png",
    goal = "image/phase1/goal-ring.png",
}

local function RequireSprite(resourcePath)
    local sprite = cache:GetResource("Sprite2D", resourcePath)
    if not sprite then error("Sprite2D 资源加载失败：" .. resourcePath) end
    ---@cast sprite Sprite2D
    return sprite
end

---@param node Node
---@param resourcePath string
---@param rect Rect
---@param layer integer
---@param color Color|nil
---@return StaticSprite2D
local function AddSprite(node, resourcePath, rect, layer, color)
    local drawable = node:CreateComponent("StaticSprite2D")
    ---@cast drawable StaticSprite2D
    drawable.sprite = RequireSprite(resourcePath)
    drawable.useDrawRect = true
    drawable.drawRect = rect
    drawable.layer = layer
    if color then drawable.color = color end
    return drawable
end

---@param scene Scene
---@param width number
---@param height number
---@return Node
function RuntimeFactory.CreateViewportBackground(scene, width, height)
    local node = scene:CreateChild("GameplayViewportBackground")
    local zone = node:CreateComponent("Zone")
    ---@cast zone Zone
    zone.boundingBox = BoundingBox(-1000.0, 1000.0)
    zone.ambientColor = Color(0.035, 0.075, 0.068, 1)
    zone.fogColor = Color(0.035, 0.075, 0.068, 1)
    zone.fogStart = 1000.0
    zone.fogEnd = 1001.0
    return node
end

---@param scene Scene
---@param mapper table
---@param groundLevelY number
---@return table
function RuntimeFactory.CreateGround(scene, mapper, groundLevelY)
    -- Collision layout (ported from Phaser PlayScene.createLaboratory):
    --
    --        playable area
    --  --------------------------  groundLevelY (top surface)
    --  |  1466 px × 28 px body  |  detects/stops the apple
    --  --------------------------
    --
    -- Edge cases: the 17 px horizontal inset is preserved; the body center is
    -- half a thickness below the visible surface so grazing the top is stable.
    local _, groundViewportY = mapper:LevelToViewport(0, groundLevelY)
    local bodyWidth = (mapper.viewportWidth - 34) / mapper.pixelsPerMeter
    local bodyHeight = 28 / mapper.pixelsPerMeter
    local worldX, worldY = mapper:ViewportToWorld(mapper.viewportWidth * 0.5, groundViewportY + 14)

    local node = scene:CreateChild("Ground")
    node:SetPosition2D(worldX, worldY)
    local body = node:CreateComponent("RigidBody2D")
    ---@cast body RigidBody2D
    body.bodyType = BT_STATIC
    local shape = node:CreateComponent("CollisionBox2D")
    ---@cast shape CollisionBox2D
    shape:SetSize(bodyWidth, bodyHeight)
    shape.friction = 0.78
    shape.restitution = 0.22
    shape.categoryBits = CATEGORY_WORLD
    shape.maskBits = MASK_ALL

    -- The ground remains a fully functional Box2D body. Its former solid PNG
    -- visual is intentionally omitted because Maker recognized the asset UUID
    -- but repeatedly failed to materialize the hashed PNG in the runtime pack.
    return { id = "world-floor", type = "ground", node = node, body = body, shape = shape }
end

---@type table<string, fun(context: table, data: table): table>
local FACTORIES = {}

FACTORIES.launcher = function(context, data)
    local mapper = context.mapper
    local transform = data.transform
    local spawnLevelX = transform.x + data.properties.appleSpawnOffsetX
    local spawnLevelY = transform.y + data.properties.appleSpawnOffsetY
    local worldX, worldY = mapper:LevelToWorld(spawnLevelX, spawnLevelY)
    local displayWidth = transform.width * mapper.objectScale / mapper.pixelsPerMeter
    local displayHeight = displayWidth * 190 / 150
    local anchorY = 36 / 190

    local node = context.scene:CreateChild(data.id)
    node:SetPosition2D(worldX, worldY)
    node:SetRotation2D(mapper.LevelRotationToWorld(transform.rotation))
    AddSprite(
        node,
        ASSETS.launcher,
        Rect(
            -displayWidth * 0.5,
            -displayHeight * (1 - anchorY),
            displayWidth * 0.5,
            displayHeight * anchorY
        ),
        10,
        nil
    )
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
    -- Collision layout:
    --  +---------------------------+
    --  | rectangular trigger only |  apple enters/leaves -> HUD/log signal
    --  +---------------------------+
    -- The trigger never changes velocity; its LevelData transform is the source
    -- of truth for both the visible ring and the Box2D sensor.
    local mapper = context.mapper
    local transform = data.transform
    local worldX, worldY = mapper:LevelToWorld(transform.x, transform.y)
    local worldWidth, worldHeight = mapper:LevelSizeToWorld(transform.width, transform.height)

    local node = context.scene:CreateChild(data.id)
    node:SetPosition2D(worldX, worldY)
    node:SetRotation2D(mapper.LevelRotationToWorld(transform.rotation))
    local body = node:CreateComponent("RigidBody2D")
    ---@cast body RigidBody2D
    body.bodyType = BT_STATIC
    local shape = node:CreateComponent("CollisionBox2D")
    ---@cast shape CollisionBox2D
    shape:SetSize(worldWidth, worldHeight)
    shape.trigger = true
    shape.categoryBits = CATEGORY_SENSOR
    shape.maskBits = CATEGORY_APPLE
    AddSprite(
        node,
        ASSETS.goal,
        Rect(-worldWidth * 0.5, -worldHeight * 0.5, worldWidth * 0.5, worldHeight * 0.5),
        8,
        nil
    )
    return { id = data.id, type = data.type, node = node, body = body, shape = shape, data = data }
end

---@param context table
---@param level table
---@return table
function RuntimeFactory.CreateLevelObjects(context, level)
    local runtime = { ordered = {}, byId = {}, skipped = {} }
    for _, data in ipairs(level.objects) do
        local factory = rawget(FACTORIES, data.type)
        if factory then
            local instance = factory(context, data)
            runtime.ordered[#runtime.ordered + 1] = instance
            runtime.byId[instance.id] = instance
            print(string.format("[Phase1] instantiated %s (%s)", instance.id, instance.type))
        else
            runtime.skipped[#runtime.skipped + 1] = data.id
            print(string.format("[Phase1] deferred %s (%s)", data.id, data.type))
        end
    end
    return runtime
end

---@param scene Scene
---@param launcher table
---@return table
function RuntimeFactory.CreateApple(scene, launcher)
    local node = scene:CreateChild("Apple")
    node:SetPosition2D(launcher.spawnWorldX, launcher.spawnWorldY)
    local body = node:CreateComponent("RigidBody2D")
    ---@cast body RigidBody2D
    body.bodyType = BT_STATIC
    body.useFixtureMass = false
    body.mass = APPLE_MASS
    body.linearDamping = 0.0015
    body.angularDamping = 0
    body.fixedRotation = false
    body.bullet = false
    local shape = node:CreateComponent("CollisionCircle2D")
    ---@cast shape CollisionCircle2D
    shape.radius = APPLE_RADIUS
    shape.density = APPLE_MASS / (math.pi * APPLE_RADIUS * APPLE_RADIUS)
    shape.friction = 0.002
    shape.restitution = 0.36
    shape.categoryBits = CATEGORY_APPLE
    shape.maskBits = MASK_ALL
    AddSprite(
        node,
        ASSETS.apple,
        Rect(
            -APPLE_DISPLAY_DIAMETER * 0.5,
            -APPLE_DISPLAY_DIAMETER * 0.5,
            APPLE_DISPLAY_DIAMETER * 0.5,
            APPLE_DISPLAY_DIAMETER * 0.5
        ),
        20,
        nil
    )
    return {
        id = "apple",
        type = "apple",
        node = node,
        body = body,
        shape = shape,
        radius = APPLE_RADIUS,
        launcher = launcher,
    }
end

return RuntimeFactory
