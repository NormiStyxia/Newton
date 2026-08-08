---@class AudioManager
---@field bgm GlobalBGM|nil
---@field uiAudio SynthAudio|nil
---@field activeSfx SynthAudio|nil
---@field bgmVolume number
---@field sfxVolume number
---@field bgmMuted boolean
---@field sfxMuted boolean
---@field selectedTrackByContext table<string, string>
---@field currentContext string|nil
-- AudioManager is the small application-level facade shared by title, UI,
-- workshop, and gameplay. It keeps BGM and SFX settings independent while
-- leaving existing SynthAudio call sites unchanged.
local AudioManager = {}
AudioManager.__index = AudioManager

local SETTINGS_ROOT = "audio-settings"
local SETTINGS_PATH = SETTINGS_ROOT .. "/settings.json"

local function clamp(value, fallback)
    return math.max(0, math.min(1, tonumber(value) or fallback))
end

local function createLocalAdapter()
    if _G.GetPlatform and GetPlatform() == "Web" then return nil end
    if not (_G.File and _G.fileSystem and _G.FILE_READ and _G.FILE_WRITE) then return nil end
    local adapter = { kind = "local-slot-best-effort" }
    function adapter:createDir(path) return fileSystem:CreateDir(path) end
    function adapter:exists(path) return fileSystem:FileExists(path) end
    function adapter:write(path, text)
        local file = File(path, FILE_WRITE)
        if not file or not file:IsOpen() then return false end
        local ok, written = pcall(file.WriteString, file, text)
        if file.Close then file:Close() elseif file.Dispose then file:Dispose() end
        return ok and written == true
    end
    function adapter:read(path)
        if not fileSystem:FileExists(path) then return nil end
        local file = File(path, FILE_READ)
        if not file or not file:IsOpen() then return nil end
        local text = file:ReadString()
        if file.Close then file:Close() elseif file.Dispose then file:Dispose() end
        return text
    end
    return adapter
end

function AudioManager.New(options)
    options = options or {}
    local self = setmetatable({}, AudioManager)
    self:init(options)
    return self
end

function AudioManager:init(options)
    self.bgm = options.bgm
    self.uiAudio = options.uiAudio
    self.json = options.json
    self.adapter = options.adapter or createLocalAdapter()
    self.bgmVolume = clamp(options.bgmVolume, 0.4)
    self.sfxVolume = clamp(options.sfxVolume, 0.55)
    self.bgmMuted = options.bgmMuted == true
    self.sfxMuted = options.sfxMuted == true
    self.currentContext = nil
    self.activeSfx = nil
    self.selectedTrackByContext = {}
    if self.adapter then pcall(self.adapter.createDir, self.adapter, SETTINGS_ROOT) end
    self:loadAudioSettings()
    self:_applyBgmSettings()
    self:_applySfxSettings()
end

function AudioManager:AttachBgm(bgm)
    self.bgm = bgm
    self:_applyBgmSettings()
    if self.bgm and self.bgm.selectedTrackByContext then
        self.bgm.selectedTrackByContext = self.selectedTrackByContext
    end
end

function AudioManager:AttachSfx(audio)
    self.activeSfx = audio
    self:_applySfxSettings(audio)
end

function AudioManager:DetachSfx(audio)
    if not audio or self.activeSfx == audio then self.activeSfx = nil end
end

function AudioManager:_applyBgmSettings()
    if not self.bgm then return end
    self.bgm.bgmVolume = self.bgmVolume
    self.bgm.bgmMuted = self.bgmMuted
    self.bgm.selectedTrackByContext = self.selectedTrackByContext
    self.bgm:setBGMVolume(self.bgmVolume)
    self.bgm:setBgmMuted(self.bgmMuted)
end

function AudioManager:_applySfxSettings(audio)
    local targets = audio and { audio } or { self.uiAudio, self.activeSfx }
    for _, target in ipairs(targets) do
        if target then
            target:setVolume(self.sfxVolume)
            target:setMuted(self.sfxMuted)
        end
    end
end

function AudioManager:setBgmVolume(value)
    self.bgmVolume = clamp(value, self.bgmVolume)
    if self.bgm then self.bgm:setBGMVolume(self.bgmVolume) end
    self:saveAudioSettings()
end

function AudioManager:setSfxVolume(value)
    self.sfxVolume = clamp(value, self.sfxVolume)
    self:_applySfxSettings()
    self:saveAudioSettings()
end

function AudioManager:setBgmMuted(muted)
    self.bgmMuted = muted == true
    if self.bgm then self.bgm:setBgmMuted(self.bgmMuted) end
    self:saveAudioSettings()
end

function AudioManager:setSfxMuted(muted)
    self.sfxMuted = muted == true
    self:_applySfxSettings()
    self:saveAudioSettings()
end

-- Compatibility for callers that used the old all-audio toggle.
function AudioManager:setMuted(muted)
    self:setBgmMuted(muted)
    self:setSfxMuted(muted)
end

function AudioManager:setMusicContext(context, options)
    if not self.bgm then return false end
    local changed = self.bgm:setMusicContext(context, options)
    self.currentContext = self.bgm:getMusicContext()
    self.selectedTrackByContext = self.bgm.selectedTrackByContext
    if changed then self:saveAudioSettings() end
    return changed
end

function AudioManager:getEffectiveBgmVolume()
    return self.bgmMuted and 0 or self.bgmVolume
end

function AudioManager:getEffectiveSfxVolume()
    return self.sfxMuted and 0 or self.sfxVolume
end

function AudioManager:getMusicContext()
    return self.bgm and self.bgm:getMusicContext() or self.currentContext
end

-- Preview changes the runtime scene only. Capturing the context here makes
-- that rule explicit without issuing a music-context request.
function AudioManager:enterPreview()
    self.previewContext = self:getMusicContext()
    return self.previewContext
end

function AudioManager:leavePreview()
    self.previewContext = nil
    return true
end

function AudioManager:selectTrack(trackId)
    if not self.bgm then return false end
    local changed = self.bgm:selectTrack(trackId)
    self.selectedTrackByContext = self.bgm.selectedTrackByContext
    if changed then self:saveAudioSettings() end
    return changed
end

function AudioManager:nextTrack()
    if not self.bgm then return false end
    local changed = self.bgm:nextTrack()
    self.selectedTrackByContext = self.bgm.selectedTrackByContext
    if changed then self:saveAudioSettings() end
    return changed
end

function AudioManager:previousTrack()
    if not self.bgm then return false end
    local changed = self.bgm:previousTrack()
    self.selectedTrackByContext = self.bgm.selectedTrackByContext
    if changed then self:saveAudioSettings() end
    return changed
end

function AudioManager:getCurrentTrack()
    return self.bgm and self.bgm:getCurrentTrack() or nil
end

function AudioManager:getCurrentTrackTitle()
    return self.bgm and self.bgm:getCurrentTrackTitle() or "未播放音乐"
end

function AudioManager:getTracks()
    return self.bgm and self.bgm:getTracks() or {}
end

function AudioManager:getPlaylists()
    return self.bgm and self.bgm:getPlaylists() or {}
end

function AudioManager:showNowPlaying(title)
    return self.bgm and self.bgm:showNowPlaying(title) or false
end

function AudioManager:playSfx(kind)
    local target = self.activeSfx or self.uiAudio
    if target then return target:Play(kind) end
    return false
end

function AudioManager:playUIClick()
    if self.uiAudio then return self.uiAudio:PlayUIClick() end
    return false
end

function AudioManager:Update(dt)
    if self.bgm then self.bgm:Update(dt) end
    if self.uiAudio then self.uiAudio:Update(dt) end
end

function AudioManager:saveAudioSettings()
    if not self.adapter or not self.json or type(self.json.encode) ~= "function" then return false end
    local ok, text = pcall(self.json.encode, {
        kind = "audio-settings",
        schemaVersion = 1,
        bgmVolume = self.bgmVolume,
        sfxVolume = self.sfxVolume,
        bgmMuted = self.bgmMuted,
        sfxMuted = self.sfxMuted,
        selectedTrackByContext = self.selectedTrackByContext,
    })
    if not ok or type(text) ~= "string" then return false end
    return self.adapter:write(SETTINGS_PATH, text) == true
end

function AudioManager:loadAudioSettings()
    if not self.adapter or not self.json or type(self.json.decode) ~= "function" then return false end
    local text = self.adapter:read(SETTINGS_PATH)
    if type(text) ~= "string" or text == "" then return false end
    local ok, value = pcall(self.json.decode, text)
    if not ok or type(value) ~= "table" or value.kind ~= "audio-settings" then return false end
    self.bgmVolume = clamp(value.bgmVolume, self.bgmVolume)
    self.sfxVolume = clamp(value.sfxVolume, self.sfxVolume)
    self.bgmMuted = value.bgmMuted == true
    self.sfxMuted = value.sfxMuted == true
    if type(value.selectedTrackByContext) == "table" then
        for context, trackId in pairs(value.selectedTrackByContext) do
            if type(context) == "string" and type(trackId) == "string" then
                self.selectedTrackByContext[context] = trackId
            end
        end
    end
    return true
end

-- Keep the exact names requested by the settings contract available to Lua UI.
AudioManager.setBGMVolume = AudioManager.setBgmVolume
AudioManager.setSFXVolume = AudioManager.setSfxVolume
AudioManager.setBGMMuted = AudioManager.setBgmMuted
AudioManager.setSFXMuted = AudioManager.setSfxMuted
AudioManager.setMusicContext = AudioManager.setMusicContext

return AudioManager
