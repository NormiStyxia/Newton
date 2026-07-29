local MatterCalibration = require("game.physics.Calibration")
local PhysicsTelemetry = require("game.physics.Telemetry")

---@class PhysicsProbe
---@field active boolean
---@field current table|nil
---@field caseIndex integer
---@field timeScale number
---@field telemetry PhysicsTelemetry
---@field fixtures table<string, table>
---@field root Node|nil
---@field pendingExitVelocity Vector2|nil
---@field originalMaskBits integer|nil
local PhysicsProbe = {}
PhysicsProbe.__index = PhysicsProbe

local PROBE_CATEGORY = 0x0800
local LAB_WIDTH = 1500
local LAB_HEIGHT = 596
local PLAYFIELD_HEIGHT = 700
local FLOOR_Y = 580 / PLAYFIELD_HEIGHT * LAB_HEIGHT

local CASES = {
    { id = "free_flight", durationMs = 1000, fixtureId = nil, x = 310, y = 238, vx = 12, vy = -8 },
    { id = "ground_slide", durationMs = 1000, fixtureId = "world-floor", x = 510, y = FLOOR_Y - 27, vx = 12, vy = 0 },
    { id = "right_wall", durationMs = 500, fixtureId = "world-right", x = 1410, y = LAB_HEIGHT * .5, vx = 18, vy = 0 },
    { id = "spring_exit", durationMs = 500, fixtureId = "spring", x = 510, y = 288, vx = 0, vy = 20 },
}

local function fixtureDefinition(id)
    if id == "world-floor" then
        return { x = LAB_WIDTH * .5, y = FLOOR_Y + 14, width = LAB_WIDTH - 34, height = 28 }
    end
    if id == "world-right" then
        return { x = LAB_WIDTH - 14, y = LAB_HEIGHT * .5, width = 24, height = LAB_HEIGHT - 44 }
    end
    return { x = 510, y = 430, width = 110 * LAB_HEIGHT / PLAYFIELD_HEIGHT, height = 34 * LAB_HEIGHT / PLAYFIELD_HEIGHT }
end

---@return PhysicsProbe
function PhysicsProbe.New()
    local self = setmetatable({}, PhysicsProbe)
    self.active = false
    self.current = nil
    self.caseIndex = 1
    self.timeScale = 1
    self.telemetry = PhysicsTelemetry.New()
    self.fixtures = {}
    self.root = nil
    self.pendingExitVelocity = nil
    self.originalMaskBits = nil
    return self
end

function PhysicsProbe:IsActive()
    return self.active
end

function PhysicsProbe:GetTimeScale()
    return self.timeScale
end

function PhysicsProbe:EnsureFixtures(context)
    if self.root then return end
    self.root = context.scene:CreateChild("PhysicsProbeFixtures")
    for _, id in ipairs({ "world-floor", "world-right", "spring" }) do
        local definition = fixtureDefinition(id)
        local node = self.root:CreateChild(id)
        local worldX, worldY = context.mapper:ViewportToWorld(definition.x, definition.y)
        node:SetPosition2D(worldX, worldY)
        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = node:CreateComponent("CollisionBox2D")
        shape:SetSize(definition.width / context.pixelsPerMeter, definition.height / context.pixelsPerMeter)
        shape.friction = MatterCalibration.STATIC_FRICTION
        shape.restitution = MatterCalibration.STATIC_RESTITUTION
        shape.categoryBits = PROBE_CATEGORY
        shape.maskBits = context.apple.shape.categoryBits
        shape.trigger = true
        self.fixtures[id] = { node = node, shape = shape }
    end
end

function PhysicsProbe:SetFixture(id)
    for fixtureId, fixture in pairs(self.fixtures) do
        fixture.shape.trigger = fixtureId ~= id
    end
end

function PhysicsProbe:Material(context)
    return {
        appleFriction = context.apple.shape.friction,
        appleFrictionAir = context.apple.baseFrictionAir,
        appleRestitution = context.apple.shape.restitution,
        contactFriction = MatterCalibration.APPLE_FRICTION,
        contactRestitution = MatterCalibration.STATIC_RESTITUTION,
        matterForceScale = .001,
        matterBaseDeltaMs = 1000 / 60,
        appleRadiusPx = context.apple.radius * context.pixelsPerMeter,
    }
end

function PhysicsProbe:BeginCurrentCase(context)
    local spec = self.current
    if not spec then return end
    self.timeScale = spec.timeScale
    self.pendingExitVelocity = nil
    self:SetFixture(spec.fixtureId)
    local apple = context.apple
    local worldX, worldY = context.mapper:ViewportToWorld(spec.x, spec.y)
    apple.node:SetPosition2D(worldX, worldY)
    apple.node:SetRotation2D(0)
    apple.body.bodyType = BT_DYNAMIC
    MatterCalibration.ApplyAppleMassProperties(apple.body)
    apple.body.linearVelocity = Vector2(
        spec.vx * context.matterVelocityToWorld * self.timeScale,
        -spec.vy * context.matterVelocityToWorld * self.timeScale
    )
    apple.body.angularVelocity = 0
    apple.body.linearDamping = MatterCalibration.Box2DLinearDamping(apple.baseFrictionAir, self.timeScale)
    apple.body.angularDamping = MatterCalibration.Box2DLinearDamping(apple.baseFrictionAir, self.timeScale)
    apple.shape.friction = MatterCalibration.APPLE_FRICTION
    apple.shape.restitution = MatterCalibration.APPLE_INITIAL_RESTITUTION
    apple.shape.maskBits = PROBE_CATEGORY
    apple.body.awake = true
    context.applyGravity()
    self.telemetry:Begin(spec.id, self.timeScale, self:Material(context))
    self.telemetry:Capture(0, self.timeScale, apple.node.position2D, apple.body.linearVelocity,
        apple.node.rotation2D, context.pixelsPerMeter, context.matterVelocityToWorld)
    context.setStatus("PHYSICS PROBE · " .. spec.id .. " @ " .. string.format("%.2fx", self.timeScale))
end

function PhysicsProbe:Start(context)
    if self.active then return false end
    self:EnsureFixtures(context)
    self.active = true
    self.caseIndex = 1
    self.current = nil
    self.timeScale = 1
    self.originalMaskBits = context.apple.shape.maskBits
    context.setLaunched(true)
    self:Update(context)
    return true
end

function PhysicsProbe:Update(context)
    if not self.active or self.current then return nil end
    if self.caseIndex > #CASES * 2 then
        self:Stop(context)
        context.setLaunched(false)
        context.setStatus("PHYSICS PROBE · complete")
        return "finished"
    end
    local baseIndex = math.floor((self.caseIndex - 1) / 2) + 1
    local scale = self.caseIndex % 2 == 1 and 1 or .05
    local definition = CASES[baseIndex]
    self.current = {
        id = definition.id,
        durationMs = definition.durationMs,
        fixtureId = definition.fixtureId,
        x = definition.x,
        y = definition.y,
        vx = definition.vx,
        vy = definition.vy,
        timeScale = scale,
    }
    self:BeginCurrentCase(context)
    return nil
end

---@param other Node|nil
---@param preSolveVelocity Vector2|nil
function PhysicsProbe:OnContactBegin(other, preSolveVelocity, context)
    if not self.active or not self.current or not other then return end
    local id = other.name
    if id ~= self.current.fixtureId then return end
    self.telemetry:BeginContact(id)
    if id == "spring" and not self.pendingExitVelocity then
        local velocity = preSolveVelocity or context.apple.body.linearVelocity
        self.pendingExitVelocity = Vector2(
            velocity.x,
            velocity.y - 10 * context.matterVelocityToWorld * self.timeScale
        )
    end
end

---@param other Node|nil
function PhysicsProbe:OnContactEnd(other)
    if not self.active or not self.current or not other then return end
    if other.name == self.current.fixtureId then self.telemetry:EndContact(other.name) end
end

function PhysicsProbe:AfterPhysicsStep(context, timeStep)
    if not self.active or not self.current then return end
    local apple = context.apple
    if self.pendingExitVelocity then
        apple.body.linearVelocity = self.pendingExitVelocity
        apple.body.awake = true
        self.pendingExitVelocity = nil
    end
    self.telemetry:Capture(timeStep, self.timeScale, apple.node.position2D, apple.body.linearVelocity,
        apple.node.rotation2D, context.pixelsPerMeter, context.matterVelocityToWorld)
    if self.telemetry.simulationTime + .0001 < self.current.durationMs then return end
    self.telemetry:Stop()
    self:SetFixture(nil)
    self.current = nil
    self.caseIndex = self.caseIndex + 1
end

function PhysicsProbe:Stop(context)
    self.telemetry:Stop()
    self:SetFixture(nil)
    if self.root then self.root:Remove() end
    self.root = nil
    self.fixtures = {}
    if context and context.apple and self.originalMaskBits then
        context.apple.shape.maskBits = self.originalMaskBits
    end
    self.originalMaskBits = nil
    self.pendingExitVelocity = nil
    self.current = nil
    self.active = false
    self.timeScale = 1
end

return PhysicsProbe
