local Effects = require("urhox-libs.Effects.Effects")

---@class SynthAudio
---@field scene Scene
---@field elapsedMs number
---@field lastImpactMs number
local SynthAudio = {}
SynthAudio.__index = SynthAudio

local PATHS = {
    launch = "audio/phase1/launch.wav",
    card = "audio/phase1/card.wav",
    impact = "audio/phase1/impact.wav",
    punch = "audio/phase1/punch.wav",
    success = "audio/phase1/success.wav",
    reset = "audio/phase1/reset.wav",
    spring = "audio/sfx/spring_trigger_02_light.mp3",
}

---@param scene Scene
---@return SynthAudio
function SynthAudio.New(scene)
    local self = setmetatable({}, SynthAudio)
    self.scene = scene
    self.elapsedMs = 0
    self.lastImpactMs = -math.huge
    return self
end

---@param dt number
function SynthAudio:Update(dt)
    self.elapsedMs = self.elapsedMs + math.max(0, dt) * 1000
end

---@param kind "launch"|"card"|"impact"|"punch"|"success"|"reset"|"spring"
function SynthAudio:Play(kind)
    local path = PATHS[kind]
    if not path or not self.scene then return end
    if kind == "impact" then
        if self.elapsedMs - self.lastImpactMs < 80 then return end
        self.lastImpactMs = self.elapsedMs
    end
    Effects.PlaySound(self.scene, path, { gain = 1 })
end

return SynthAudio
