---@class BGMOptions
---@field volume? number
---@field fadeIn? number
---@field showNowPlaying? boolean

---@class BGMTrack
---@field id string
---@field title string
---@field asset string

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
---@field bgmVolume number
---@field bgmMuted boolean
---@field currentContext string|nil
---@field currentTrackId string|nil
---@field selectedTrackByContext table<string, string>
---@field nowPlayingTitle string|nil
---@field nowPlayingElapsed number
local GlobalBGM = {}
GlobalBGM.__index = GlobalBGM

local DEFAULT_VOLUME = 0.4
local DEFAULT_FADE_IN = 0.45
local DEFAULT_FADE_OUT = 0.28
local DEFAULT_FADE_IN_SWITCH = 0.4

-- Keep the registry data-only: id, display title, and asset path remain
-- separate so adding a track never requires touching playback code.
local BGM_TRACKS = {
    academy_01 = {
        id = "academy_01",
        title = "《经典力学，很神奇吧》",
        asset = "audio/music_1786095252543.ogg",
    },
    -- The project currently has no second audio file checked into assets/audio.
    -- Keep the requested registry entry ready for the supplied asset path.
    academy_02 = {
        id = "academy_02",
        title = "《实验开始之前》",
        asset = "audio/academy_02.ogg",
    },
    gameplay_01 = {
        id = "gameplay_01",
        title = "实验场",
        asset = "audio/music_1786095252543.ogg",
    },
}

local BGM_PLAYLISTS = {
    academy = { "academy_01", "academy_02" },
    gameplay = { "gameplay_01" },
}

local function clampVolume(volume)
    return math.max(0, math.min(1, tonumber(volume) or DEFAULT_VOLUME))
end

local function validContext(context)
    return type(context) == "string" and BGM_PLAYLISTS[context] ~= nil
end

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
    self.bgmVolume = DEFAULT_VOLUME
    self.bgmMuted = false
    self.currentContext = nil
    self.currentTrackId = nil
    self.selectedTrackByContext = {}
    self.pendingSwitch = nil
    self.nowPlayingTitle = nil
    self.nowPlayingElapsed = 0
    self.nowPlayingDuration = 1.8
end

function GlobalBGM:canStartWithoutGesture()
    return not (_G.GetPlatform and GetPlatform() == "Web")
end

function GlobalBGM:isPlaying()
    return self.source ~= nil and self.source:IsPlaying()
end

function GlobalBGM:getEffectiveVolume()
    return self.bgmMuted and 0 or self.bgmVolume
end

local function trackForId(trackId)
    local track = BGM_TRACKS[trackId]
    if not track then return nil end
    return { id = track.id, title = track.title, asset = track.asset }
end

function GlobalBGM:getPlaylist(context)
    local ids = BGM_PLAYLISTS[context or self.currentContext] or {}
    local tracks = {}
    for _, id in ipairs(ids) do
        local track = trackForId(id)
        if track then tracks[#tracks + 1] = track end
    end
    return tracks
end

function GlobalBGM:getCurrentTrack()
    return trackForId(self.currentTrackId)
end

function GlobalBGM:getCurrentTrackTitle()
    local track = self:getCurrentTrack()
    return track and track.title or "未播放音乐"
end

function GlobalBGM:getMusicContext()
    return self.currentContext
end

function GlobalBGM:showNowPlaying(title)
    if type(title) ~= "string" or title == "" then return false end
    self.nowPlayingTitle = title
    self.nowPlayingElapsed = 0
    return true
end

function GlobalBGM:getNowPlayingState()
    if not self.nowPlayingTitle then return nil end
    local elapsed = self.nowPlayingElapsed
    local fadeIn = 0.18
    local fadeOut = 0.55
    local alpha = 1
    if elapsed < fadeIn then
        alpha = elapsed / fadeIn
    elseif elapsed > self.nowPlayingDuration - fadeOut then
        alpha = (self.nowPlayingDuration - elapsed) / fadeOut
    end
    alpha = math.max(0, math.min(1, alpha))
    if alpha <= 0 then return nil end
    return { title = self.nowPlayingTitle, alpha = alpha, yOffset = -3 * (1 - alpha) }
end

---@param track BGMTrack
---@param options BGMOptions|nil
---@return boolean
function GlobalBGM:startTrack(track, options)
    if not track then return false end
    options = options or {}
    if options.volume ~= nil then self.bgmVolume = clampVolume(options.volume) end
    if not _G.cache or type(cache.GetResource) ~= "function" then
        print("[BGM] Audio cache unavailable: " .. tostring(track.asset))
        return false
    end
    local sound = cache:GetResource("Sound", track.asset)
    if not sound then
        print("[BGM] Failed to load: " .. tostring(track.asset))
        return false
    end

    local scene = Scene()
    local node = scene:CreateChild("GlobalBGM")
    local source = node:CreateComponent("SoundSource")
    local fadeDuration = math.max(0, tonumber(options.fadeIn) or DEFAULT_FADE_IN)
    local targetVolume = self:getEffectiveVolume()

    sound.looped = true
    source.soundType = SOUND_MUSIC
    source.gain = fadeDuration > 0 and 0 or targetVolume

    -- Retain the ownership chain before playback. This Scene is application-
    -- owned and never tied to a gameplay Scene or viewport.
    self.scene = scene
    self.node = node
    self.source = source
    self.sound = sound
    self.path = track.asset
    self.targetVolume = targetVolume
    self.fadeDuration = fadeDuration
    self.fadeElapsed = 0
    self.startAttempted = true
    self.currentTrackId = track.id

    source:Play(sound)
    if options.showNowPlaying then self:showNowPlaying(track.title) end
    print(string.format("[BGM] Started global loop: %s (%s, volume %.2f)",
        track.asset, track.id, targetVolume))
    return true
end

function GlobalBGM:replaceWithTrack(track, options)
    if not track then return false end
    if not _G.cache or type(cache.GetResource) ~= "function" then return false end
    -- Check the asset before fading the current song out. A missing supplied
    -- asset must never leave the application silent.
    if not cache:GetResource("Sound", track.asset) then
        print("[BGM] Track asset unavailable: " .. tostring(track.asset))
        return false
    end
    if not self.source then return self:startTrack(track, options) end
    self.pendingSwitch = {
        track = track,
        fadeOut = math.max(0.2, tonumber(options and options.fadeOut) or DEFAULT_FADE_OUT),
        fadeIn = math.max(0.3, tonumber(options and options.fadeIn) or DEFAULT_FADE_IN_SWITCH),
        showNowPlaying = options and options.showNowPlaying == true,
        elapsed = 0,
        phase = "out",
    }
    self.fadeDuration, self.fadeElapsed = 0, 0
    return true
end

function GlobalBGM:playBGM(path, options)
    local candidates = self:getPlaylist(self.currentContext)
    for _, track in ipairs(candidates) do
        if track.asset == path then
            if self.source and self.path == path and self:isPlaying() then return true end
            self.currentContext = self.currentContext or "academy"
            return self:replaceWithTrack(track, options or {})
        end
    end
    for _, track in pairs(BGM_TRACKS) do
        if track.asset == path then
            if self.source and self.path == path and self:isPlaying() then return true end
            self.currentContext = self.currentContext or "academy"
            return self:replaceWithTrack(track, options or {})
        end
    end
    local track = { id = path, title = path, asset = path }
    if self.source and self.path == path and self:isPlaying() then return true end
    return self:replaceWithTrack(track, options or {})
end

function GlobalBGM:setMusicContext(context, options)
    if not validContext(context) then return false end
    if self.currentContext == context and self.source and self:isPlaying() then return false end
    local previousContext = self.currentContext
    local previousSelection = self.selectedTrackByContext[context]
    self.currentContext = context
    local tracks = self:getPlaylist(context)
    if #tracks == 0 then return false end
    local selectedId = self.selectedTrackByContext[context]
    local selected = nil
    for _, track in ipairs(tracks) do
        if track.id == selectedId then selected = track; break end
    end
    selected = selected or tracks[1]
    self.selectedTrackByContext[context] = selected.id
    options = options or {}
    options.showNowPlaying = options.showNowPlaying == true
    local changed = self:replaceWithTrack(selected, options)
    if not changed and selected ~= tracks[1] then
        selected = tracks[1]
        self.selectedTrackByContext[context] = selected.id
        changed = self:replaceWithTrack(selected, options)
    end
    if not changed then
        self.currentContext = previousContext
        self.selectedTrackByContext[context] = previousSelection
    end
    return changed
end

function GlobalBGM:selectTrack(trackId, options)
    local tracks = self:getPlaylist()
    local selected = nil
    for _, track in ipairs(tracks) do
        if track.id == trackId then selected = track; break end
    end
    if not selected then return false end
    if self.currentTrackId == selected.id and self.source and self:isPlaying() then return false end
    options = options or {}
    options.showNowPlaying = options.showNowPlaying ~= false
    local changed = self:replaceWithTrack(selected, options)
    if changed then self.selectedTrackByContext[self.currentContext] = selected.id end
    return changed
end

function GlobalBGM:moveTrack(delta)
    local tracks = self:getPlaylist()
    if #tracks == 0 then return false end
    local index = 1
    for i, track in ipairs(tracks) do
        if track.id == self.currentTrackId then index = i; break end
    end
    index = ((index - 1 + delta) % #tracks) + 1
    return self:selectTrack(tracks[index].id)
end

function GlobalBGM:nextTrack() return self:moveTrack(1) end
function GlobalBGM:previousTrack() return self:moveTrack(-1) end

function GlobalBGM:Update(timeStep)
    local dt = math.max(0, tonumber(timeStep) or 0)
    if self.pendingSwitch and self.source then
        local pending = self.pendingSwitch
        pending.elapsed = pending.elapsed + dt
        if pending.phase == "out" then
            local amount = math.max(0, math.min(1, pending.elapsed / pending.fadeOut))
            self.source.gain = self:getEffectiveVolume() * (1 - amount)
            if amount >= 1 then
                self.source:Stop()
                if self.scene then self.scene:Dispose() end
                self.scene, self.node, self.source, self.sound = nil, nil, nil, nil
                self.path, self.targetVolume = nil, self:getEffectiveVolume()
                pending.phase, pending.elapsed = "in", 0
                self:startTrack(pending.track, { fadeIn = pending.fadeIn,
                    showNowPlaying = pending.showNowPlaying })
                self.pendingSwitch = nil
            end
            return
        end
    end
    if not self.source or self.fadeDuration <= 0 or self.fadeElapsed >= self.fadeDuration then
        if self.source and self.fadeDuration <= 0 then self.source.gain = self:getEffectiveVolume() end
        if self.nowPlayingTitle then
            self.nowPlayingElapsed = self.nowPlayingElapsed + dt
            if self.nowPlayingElapsed >= self.nowPlayingDuration then self.nowPlayingTitle = nil end
        end
        return
    end
    self.fadeElapsed = math.min(self.fadeDuration, self.fadeElapsed + dt)
    self.source.gain = self:getEffectiveVolume() * (self.fadeElapsed / self.fadeDuration)
    if self.nowPlayingTitle then
        self.nowPlayingElapsed = self.nowPlayingElapsed + dt
        if self.nowPlayingElapsed >= self.nowPlayingDuration then self.nowPlayingTitle = nil end
    end
end

function GlobalBGM:stopBGM()
    if self.source then self.source:Stop() end
    if self.scene then self.scene:Dispose() end
    self.scene, self.node, self.source, self.sound = nil, nil, nil, nil
    self.path, self.targetVolume, self.fadeDuration, self.fadeElapsed = nil, self:getEffectiveVolume(), 0, 0
    self.startAttempted, self.pendingSwitch = false, nil
    print("[BGM] Stopped global loop")
end

function GlobalBGM:setBGMVolume(volume)
    self.bgmVolume = clampVolume(volume)
    self.targetVolume = self:getEffectiveVolume()
    if self.source and (self.fadeDuration <= 0 or self.fadeElapsed >= self.fadeDuration) then
        self.source.gain = self.targetVolume
    end
end

function GlobalBGM:setBgmMuted(muted)
    self.bgmMuted = muted == true
    self.targetVolume = self:getEffectiveVolume()
    if self.source and (self.fadeDuration <= 0 or self.fadeElapsed >= self.fadeDuration) then
        self.source.gain = self.targetVolume
    end
end

function GlobalBGM:setMuted(muted)
    return self:setBgmMuted(muted)
end

function GlobalBGM:getTracks() return BGM_TRACKS end
function GlobalBGM:getPlaylists() return BGM_PLAYLISTS end

GlobalBGM.BGM_TRACKS = BGM_TRACKS
GlobalBGM.BGM_PLAYLISTS = BGM_PLAYLISTS
return GlobalBGM
