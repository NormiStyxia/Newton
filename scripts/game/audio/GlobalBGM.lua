---@class BGMOptions
---@field volume? number
---@field fadeIn? number

---@class GlobalBGM
---@field scene Scene|nil
---@field node Node|nil
---@field source SoundSource|nil
---@field sound Sound|nil
---@field path string|nil
---@field targetVolume number
---@field fadeDuration number
---@field fadeElapsed number
---@field startAttempted boolean
local GlobalBGM = {}
GlobalBGM.__index = GlobalBGM

local DEFAULT_VOLUME = 0.4
local DEFAULT_FADE_IN = 0.45

local function clampVolume(volume)
    return math.max(0, math.min(1, tonumber(volume) or DEFAULT_VOLUME))
end

---@return GlobalBGM
function GlobalBGM.New()
    local self = setmetatable({}, GlobalBGM)
    self:init()
    return self
end

function GlobalBGM:init()
    self.scene = nil
    self.node = nil
    self.source = nil
    self.sound = nil
    self.path = nil
    self.targetVolume = DEFAULT_VOLUME
    self.fadeDuration = 0
    self.fadeElapsed = 0
    self.startAttempted = false
end

---@return boolean
function GlobalBGM:canStartWithoutGesture()
    return not (_G.GetPlatform and GetPlatform() == "Web")
end

---@return boolean
function GlobalBGM:isPlaying()
    return self.source ~= nil and self.source:IsPlaying()
end

---@param path string
---@param options? BGMOptions
---@return boolean
function GlobalBGM:playBGM(path, options)
    if self.source then
        if self.source:IsPlaying() then
            return true
        end
        -- Keep the existing source intact when the engine has temporarily
        -- suspended audio during an app/browser lifecycle transition.
        return false
    end
    if self.startAttempted then return false end
    self.startAttempted = true

    options = options or {}
    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("[BGM] Failed to load: " .. tostring(path))
        return false
    end

    local scene = Scene()
    local node = scene:CreateChild("GlobalBGM")
    local source = node:CreateComponent("SoundSource")
    local targetVolume = clampVolume(options.volume)
    local fadeDuration = math.max(0, tonumber(options.fadeIn) or DEFAULT_FADE_IN)

    sound.looped = true
    source.soundType = SOUND_MUSIC
    source.gain = fadeDuration > 0 and 0 or targetVolume

    -- Retain the entire ownership chain before playback. This Scene is
    -- application-owned and is never tied to a gameplay Scene or viewport.
    self.scene = scene
    self.node = node
    self.source = source
    self.sound = sound
    self.path = path
    self.targetVolume = targetVolume
    self.fadeDuration = fadeDuration
    self.fadeElapsed = 0

    source:Play(sound)
    print(string.format("[BGM] Started global loop: %s (volume %.2f)", path, targetVolume))
    return true
end

---@param timeStep number
function GlobalBGM:Update(timeStep)
    if not self.source or self.fadeDuration <= 0 or self.fadeElapsed >= self.fadeDuration then return end
    self.fadeElapsed = math.min(self.fadeDuration, self.fadeElapsed + math.max(0, timeStep or 0))
    self.source.gain = self.targetVolume * (self.fadeElapsed / self.fadeDuration)
end

function GlobalBGM:stopBGM()
    if self.source then self.source:Stop() end
    if self.scene then self.scene:Dispose() end
    self:init()
    print("[BGM] Stopped global loop")
end

---@param volume number
function GlobalBGM:setBGMVolume(volume)
    self.targetVolume = clampVolume(volume)
    if self.source and (self.fadeDuration <= 0 or self.fadeElapsed >= self.fadeDuration) then
        self.source.gain = self.targetVolume
    end
end

return GlobalBGM
