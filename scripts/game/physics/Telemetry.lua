---@class PhysicsTelemetry
---@field enabled boolean
---@field caseId string|nil
---@field simulationTime number
---@field sampleInterval number
---@field nextSample number
---@field sampleEveryStep boolean
---@field contacts table<string, boolean>
local PhysicsTelemetry = {}
PhysicsTelemetry.__index = PhysicsTelemetry

local function Number(value)
    return string.format("%.6f", value or 0)
end

---@return PhysicsTelemetry
function PhysicsTelemetry.New()
    local self = setmetatable({}, PhysicsTelemetry)
    self.enabled = false
    self.caseId = nil
    self.simulationTime = 0
    self.sampleInterval = 1000 / 60
    self.nextSample = 0
    self.sampleEveryStep = false
    self.contacts = {}
    return self
end

function PhysicsTelemetry:ContactSummary()
    local ids = {}
    for contactId in pairs(self.contacts) do ids[#ids + 1] = contactId end
    table.sort(ids)
    return table.concat(ids, ",")
end

---@param caseId string
---@param timeScale number
---@param material table
function PhysicsTelemetry:Begin(caseId, timeScale, material)
    self.enabled = true
    self.caseId = caseId
    self.simulationTime = 0
    self.nextSample = 0
    -- Matter advances a .05x simulation with a .833ms delta. Capture every
    -- Box2D post-step at that speed so contact and low-speed friction
    -- differences remain observable instead of being hidden by 60Hz samples.
    self.sampleEveryStep = timeScale <= .05
    self.contacts = {}
    print(string.format(
        '[PhysicsTelemetry] {"type":"begin","case":"%s","scale":%s}',
        caseId,
        Number(timeScale)
    ))
    print(string.format(
        '[PhysicsTelemetry] {"type":"material","case":"%s","scale":%s,"material":{"apple_friction":%s,"apple_friction_air":%s,"apple_restitution":%s,"contact_friction":%s,"contact_restitution":%s,"matter_force_scale":%s,"matter_base_delta_ms":%s,"apple_radius_px":%s}}',
        caseId,
        Number(timeScale),
        Number(material.appleFriction),
        Number(material.appleFrictionAir),
        Number(material.appleRestitution),
        Number(material.contactFriction),
        Number(material.contactRestitution),
        Number(material.matterForceScale),
        Number(material.matterBaseDeltaMs),
        Number(material.appleRadiusPx)
    ))
end

function PhysicsTelemetry:Stop()
    if self.enabled then
        print(string.format(
            '[PhysicsTelemetry] {"type":"end","case":"%s","t":%s}',
            self.caseId or "unknown",
            Number(self.simulationTime)
        ))
    end
    self.enabled = false
    self.caseId = nil
    self.contacts = {}
end

---@param contactId string
function PhysicsTelemetry:BeginContact(contactId)
    if not self.enabled or self.contacts[contactId] then return end
    self.contacts[contactId] = true
    print(string.format(
        '[PhysicsTelemetry] {"type":"contact_begin","case":"%s","t":%s,"contact":"%s"}',
        self.caseId or "unknown",
        Number(self.simulationTime),
        contactId
    ))
end

---@param contactId string
function PhysicsTelemetry:EndContact(contactId)
    if not self.enabled or not self.contacts[contactId] then return end
    self.contacts[contactId] = nil
    print(string.format(
        '[PhysicsTelemetry] {"type":"contact_end","case":"%s","t":%s,"contact":"%s"}',
        self.caseId or "unknown",
        Number(self.simulationTime),
        contactId
    ))
end

---@param timeStep number
---@param timeScale number
---@param position Vector2
---@param velocity Vector2
---@param angle number
---@param pixelsPerMeter number
---@param matterVelocityToWorld number
function PhysicsTelemetry:Capture(timeStep, timeScale, position, velocity, angle, pixelsPerMeter, matterVelocityToWorld)
    if not self.enabled then return end
    local stepMs = math.max(0, timeStep) * 1000 * timeScale
    self.simulationTime = self.simulationTime + stepMs
    if not self.sampleEveryStep and self.simulationTime + .0001 < self.nextSample then return end
    -- The caller provides the unscaled 60 Hz conversion. Applying timeScale
    -- exactly once keeps the .05x capture in the same coordinate space as
    -- Matter's engine.timing.timeScale output.
    local matterVelocityScale = math.max(.000001, matterVelocityToWorld * timeScale)
    local contact = self:ContactSummary()
    print(string.format(
        '[PhysicsTelemetry] {"type":"sample","case":"%s","t":%s,"dt":%s,"scale":%s,"x":%s,"y":%s,"vx":%s,"vy":%s,"angle":%s,"contact":"%s"}',
        self.caseId or "unknown",
        Number(self.simulationTime),
        Number(stepMs),
        Number(timeScale),
        Number(position.x * pixelsPerMeter),
        Number(-position.y * pixelsPerMeter),
        Number(velocity.x / matterVelocityScale),
        Number(-velocity.y / matterVelocityScale),
        Number(angle),
        contact
    ))
    if not self.sampleEveryStep then
        repeat
            self.nextSample = self.nextSample + self.sampleInterval
        until self.nextSample > self.simulationTime + .0001
    end
end

return PhysicsTelemetry
