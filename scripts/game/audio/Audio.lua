local Effects = require("urhox-libs.Effects.Effects")

---@class SynthAudio
---@field scene Scene
---@field ownsScene boolean
---@field elapsedMs number
---@field lastImpactMs number
---@field lastUIClickIndex integer|nil
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

local UI_CLICK_PATHS = {
    "audio/sfx/UI_Click_01.mp3",
    "audio/sfx/UI_Click_02.mp3",
    "audio/sfx/UI_Click_03.mp3",
    "audio/sfx/UI_Click_04.mp3",
}

---@param scene Scene|nil
---@return SynthAudio
function SynthAudio.New(scene)
    local self = setmetatable({}, SynthAudio)
    self.scene = scene or Scene()
    self.ownsScene = scene == nil
    self.elapsedMs = 0
    self.lastImpactMs = -math.huge
    self.lastUIClickIndex = nil
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

function SynthAudio:PlayUIClick()
    if not self.scene then return end
    local index = math.random(1, #UI_CLICK_PATHS)
    if #UI_CLICK_PATHS > 1 and index == self.lastUIClickIndex then
        index = index % #UI_CLICK_PATHS + 1
    end
    self.lastUIClickIndex = index
    Effects.PlaySound(self.scene, UI_CLICK_PATHS[index], { gain = 0.55 })
end

function SynthAudio:Dispose()
    if self.ownsScene and self.scene then
        self.scene:Dispose()
    end
    self.scene = nil
end

return SynthAudio
