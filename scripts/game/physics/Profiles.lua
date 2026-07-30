local PhysicsProfiles = {}

PhysicsProfiles.DEFAULT_ID = "standard"
PhysicsProfiles.INCIDENT_ID = "incident_codex_migration_01"

-- Level JSON omits physicsProfile for standard behavior. The incident requires
-- the explicit value "incident_codex_migration_01".

local MATTER_FRAMES_PER_SECOND = 60
local MATTER_BASE_DELTA_MS = 1000 / MATTER_FRAMES_PER_SECOND
local MATTER_FORCE_SCALE = 0.001
local PIXELS_PER_METRE = 100

-- Matter integrates force over delta squared. The incident conversion omitted
-- one 60 Hz factor, producing the migration's deterministic weak gravity.
local STANDARD_GRAVITY_ACCELERATION = MATTER_FORCE_SCALE
    * MATTER_BASE_DELTA_MS * MATTER_BASE_DELTA_MS
    * MATTER_FRAMES_PER_SECOND * MATTER_FRAMES_PER_SECOND
    / PIXELS_PER_METRE
local INCIDENT_GRAVITY_ACCELERATION = MATTER_FORCE_SCALE
    * MATTER_BASE_DELTA_MS * 1000
    / PIXELS_PER_METRE

local DEFINITIONS = {
    standard = {
        gravityAcceleration = STANDARD_GRAVITY_ACCELERATION,
        -- Matter does not enable Box2D-style CCD. The source speed cap keeps
        -- the apple inside the ordinary discrete-contact range.
        continuousPhysics = false,
        boundaries = {
            floor = true,
            ceiling = true,
            left = true,
            right = true,
        },
    },
    incident_codex_migration_01 = {
        gravityAcceleration = INCIDENT_GRAVITY_ACCELERATION,
        continuousPhysics = false,
        boundaries = {
            floor = true,
            ceiling = false,
            left = false,
            right = false,
        },
    },
}

---@class PhysicsProfileBoundaries
---@field floor boolean
---@field ceiling boolean
---@field left boolean
---@field right boolean

---@class PhysicsProfile
---@field id string
---@field gravityAcceleration number
---@field continuousPhysics boolean
---@field boundaries PhysicsProfileBoundaries

---@param id any
---@return boolean
function PhysicsProfiles.IsKnown(id)
    return type(id) == "string" and DEFINITIONS[id] ~= nil
end

---@param requestedId any
---@return PhysicsProfile profile
function PhysicsProfiles.Resolve(requestedId)
    local id = PhysicsProfiles.IsKnown(requestedId) and requestedId or PhysicsProfiles.DEFAULT_ID
    local definition = DEFINITIONS[id]
    return {
        id = id,
        gravityAcceleration = definition.gravityAcceleration,
        continuousPhysics = definition.continuousPhysics == true,
        boundaries = {
            floor = definition.boundaries.floor,
            ceiling = definition.boundaries.ceiling,
            left = definition.boundaries.left,
            right = definition.boundaries.right,
        },
    }
end

return PhysicsProfiles
