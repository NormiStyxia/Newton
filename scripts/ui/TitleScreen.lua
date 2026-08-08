-- The illustrated title page is one fixed design stage.  Its artwork and
-- interaction rectangles share the same coordinates so resize never changes
-- the relationship between the title, characters, and menu.
local M = {}

local SOURCE_OFFSET_X = 0
local TITLE_FILL = { 248, 231, 206, 255 }
local MENU = {
    x = 1290,
    y = 288,
    width = 410,
    rowHeight = 64,
    rowStep = 64,
    textSize = 29,
}

local MENU_ITEMS = { "实验目录", "实验工坊", "设置", "退出游戏" }
local MENU_INK = { 43, 70, 47, 255 }
local MENU_MUTED = { 91, 111, 81, 225 }
local MENU_ACCENT = { 164, 139, 76, 255 }
local TIP_COLOR = { 77, 96, 72, 180 }
local OVERLAY_FILL = { 250, 239, 216, 246 }

-- Cropped source layers keep these original 1870 x 841 canvas positions.  The
-- small padding in the files is intentional: it preserves antialiased edges
-- without paying for the original transparent canvas around each layer.
local TITLE_LAYERS = {
    { key = "bu", x = 148, y = 94, w = 216, h = 189 },
    { key = "jing", x = 357, y = 87, w = 187, h = 197 },
    { key = "dian", x = 530, y = 76, w = 207, h = 206 },
    { key = "li", x = 683, y = 93, w = 188, h = 232 },
    { key = "xue", x = 858, y = 76, w = 197, h = 216 },
}

local CHARACTER_LAYERS = {
    { id = "left1", key = "left1", hoverKey = "left1", x = 248, y = 291, w = 304, h = 489,
        hit = { x = 228, y = 268, w = 345, h = 535 } },
    { id = "left2", key = "left2", hoverKey = "left2", x = 530, y = 336, w = 216, h = 438,
        hit = { x = 510, y = 313, w = 256, h = 485 } },
    { id = "right2", key = "right2", hoverKey = "right2", x = 760, y = 305, w = 219, h = 475,
        hit = { x = 740, y = 282, w = 259, h = 520 } },
    { id = "right1", key = "right1", hoverKey = "right1", x = 974, y = 315, w = 272, h = 465,
        hit = { x = 954, y = 292, w = 312, h = 510 } },
}

local SETTINGS = {
    x = 1138, y = 206, w = 560, h = 384,
    music = { x = 1210, y = 332, w = 380 },
    sound = { x = 1210, y = 408, w = 380 },
    mute = { x = 1188, y = 485, w = 420, h = 52 },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function pointIn(rect, x, y)
    return rect and rect.x and rect.y and rect.w and rect.h
        and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

local function pointInSlider(rect, x, y)
    return pointIn({ x = rect.x - 12, y = rect.y - 24, w = rect.w + 24, h = 48 }, x, y)
end

local function characterAt(x, y)
    local sourceX = x - SOURCE_OFFSET_X
    for _, character in ipairs(CHARACTER_LAYERS) do
        if pointIn(character.hit, sourceX, y) then return character end
    end
    return nil
end

local function image(painter, handle, x, y, w, h, alpha)
    if handle and handle >= 0 then painter:ImageRect(handle, x, y, w, h, alpha or 255) end
end

local function drawFourPointStar(vg, x, y, radius, active, color)
    local inner = radius * 0.22
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y - radius)
    nvgLineTo(vg, x + inner, y - inner)
    nvgLineTo(vg, x + radius, y)
    nvgLineTo(vg, x + inner, y + inner)
    nvgLineTo(vg, x, y + radius)
    nvgLineTo(vg, x - inner, y + inner)
    nvgLineTo(vg, x - radius, y)
    nvgLineTo(vg, x - inner, y - inner)
    nvgClosePath(vg)
    if active then
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4]))
        nvgFill(vg)
    else
        nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], color[4]))
        nvgStrokeWidth(vg, 1.35)
        nvgStroke(vg)
    end
end

local function drawArrow(vg, x, y, color, alpha)
    local c = nvgRGBA(color[1], color[2], color[3], alpha or color[4] or 255)
    nvgStrokeColor(vg, c)
    nvgStrokeWidth(vg, 1.55)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y)
    nvgLineTo(vg, x + 22, y)
    nvgMoveTo(vg, x + 22, y)
    nvgLineTo(vg, x + 15, y - 4.5)
    nvgMoveTo(vg, x + 22, y)
    nvgLineTo(vg, x + 15, y + 4.5)
    nvgStroke(vg)
end

local function drawSlider(painter, rect, label, value)
    local vg = painter.vg
    painter:Text(rect.x, rect.y - 25, label, 19, MENU_INK, nil, "maker-body")
    nvgStrokeColor(vg, nvgRGBA(109, 119, 90, 120))
    nvgStrokeWidth(vg, 2)
    nvgBeginPath(vg)
    nvgMoveTo(vg, rect.x, rect.y)
    nvgLineTo(vg, rect.x + rect.w, rect.y)
    nvgStroke(vg)
    local knobX = rect.x + rect.w * clamp(value, 0, 1)
    nvgBeginPath(vg)
    nvgCircle(vg, knobX, rect.y, 7)
    nvgFillColor(vg, nvgRGBA(MENU_ACCENT[1], MENU_ACCENT[2], MENU_ACCENT[3], 255))
    nvgFill(vg)
    painter:Text(rect.x + rect.w + 18, rect.y, string.format("%d%%", math.floor(value * 100 + .5)),
        17, MENU_INK, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-body")
end

local function setMusicVolume(state, context, value)
    state.musicVolume = clamp(value, 0, 1)
    if not state.muted then context.setBGMVolume(state.musicVolume) end
end

local function setSoundVolume(state, context, value)
    state.soundVolume = clamp(value, 0, 1)
    local audio = context.uiAudio_
    if audio and audio.setVolume then audio:setVolume(state.muted and 0 or state.soundVolume) end
end

local function setMuted(state, context, muted)
    state.muted = muted == true
    context.setBGMVolume(state.muted and 0 or state.musicVolume)
    local audio = context.uiAudio_
    if audio and audio.setMuted then audio:setMuted(state.muted) end
    if audio and audio.setVolume then audio:setVolume(state.muted and 0 or state.soundVolume) end
end

local function updateSelection(state, dt)
    for index = 1, #MENU_ITEMS do
        local target = state.selectedIndex == index and 1 or 0
        local current = state.selectionProgress[index] or 0
        local step = clamp(math.max(0, dt or 0) / .14, 0, 1)
        state.selectionProgress[index] = current + (target - current) * step
    end
end

local function menuHit(index, x, y)
    local top = MENU.y + (index - 1) * MENU.rowStep
    return pointIn({ x = MENU.x - 24, y = top, w = MENU.width, h = MENU.rowHeight }, x, y)
end

local function menuIndexAt(x, y)
    for index = 1, #MENU_ITEMS do
        if menuHit(index, x, y) then return index end
    end
    return nil
end

local function updateSettingSlider(state, context, pointerX)
    local drag = state.settingsDrag
    local rect = drag == "music" and SETTINGS.music or SETTINGS.sound
    if not rect then return end
    local value = clamp((pointerX - rect.x) / rect.w, 0, 1)
    if drag == "music" then setMusicVolume(state, context, value) else setSoundVolume(state, context, value) end
end

local function activateMenu(state, context, index)
    if index == 1 then
        context.playUIClick()
        return context.RequestReturnToCatalog(1)
    elseif index == 2 then
        context.playUIClick()
        local catalogState = context.catalogState_
        local level = catalogState and catalogState.levels and catalogState.levels[1]
        if level and context.RequestEnterWorkshop then return context.RequestEnterWorkshop(level.levelId) end
        return context.RequestReturnToCatalog(1)
    elseif index == 3 then
        context.playUIClick()
        state.settingsOpen = true
        state.settingsDrag = nil
        return true
    elseif index == 4 then
        context.playUIClick()
        if _G.engine and engine.Exit then engine:Exit()
        elseif _G.GetEngine and GetEngine() and GetEngine().Exit then GetEngine():Exit() end
        return true
    end
    return false
end

---@param context GameContext
function M.Install(context)
    local _ENV = context
    local state = context.titleState_

    function InitializeTitleScreen()
        state.selectedIndex = 1
        state.focusIndex = 1
        state.hoverIndex = nil
        state.pressedIndex = nil
        state.selectionProgress = { 1, 0, 0, 0 }
        state.settingsOpen = false
        state.settingsDrag = nil
        state.academyIdCardCharacter = nil
        state.academyIdCardElapsed = 0
        state.musicVolume = state.musicVolume or .4
        state.soundVolume = state.soundVolume or .55
        state.muted = state.muted == true
        setMusicVolume(state, context, state.musicVolume)
        setSoundVolume(state, context, state.soundVolume)
        setMuted(state, context, state.muted)
    end

    function openAcademyIdCard(characterId)
        state.academyIdCardCharacter = characterId
        state.academyIdCardElapsed = 0
        print("[TitleScreen] academy id card requested: " .. tostring(characterId))
    end

    local function updateSettings(pointerFrame)
        if input:GetKeyPress(KEY_ESCAPE) then
            state.settingsOpen = false
            state.settingsDrag = nil
            context.playUIClick()
            return
        end
        if pointerFrame.pressed then
            if pointInSlider(SETTINGS.music, pointerFrame.x, pointerFrame.y) then
                state.settingsDrag = "music"
                updateSettingSlider(state, context, pointerFrame.x)
                return
            elseif pointInSlider(SETTINGS.sound, pointerFrame.x, pointerFrame.y) then
                state.settingsDrag = "sound"
                updateSettingSlider(state, context, pointerFrame.x)
                return
            elseif pointIn(SETTINGS.mute, pointerFrame.x, pointerFrame.y) then
                setMuted(state, context, not state.muted)
                context.playUIClick()
                return
            elseif not pointIn(SETTINGS, pointerFrame.x, pointerFrame.y) then
                state.settingsOpen = false
                state.settingsDrag = nil
                context.playUIClick()
                return
            end
        end
        if state.settingsDrag then
            if pointerFrame.down then updateSettingSlider(state, context, pointerFrame.x)
            else state.settingsDrag = nil end
        end
    end

    function UpdateTitleScreen(dt, pointerFrame)
        if state.academyIdCardCharacter then
            state.academyIdCardElapsed = state.academyIdCardElapsed + math.max(0, dt or 0)
            if state.academyIdCardElapsed > .28 then state.academyIdCardCharacter = nil end
        end
        if state.settingsOpen then
            updateSettings(pointerFrame)
            return
        end

        local hovered = menuIndexAt(pointerFrame.x, pointerFrame.y)
        local hoveredCharacter = characterAt(pointerFrame.x, pointerFrame.y)
        state.hoverIndex = hovered
        state.hoverCharacter = hoveredCharacter and hoveredCharacter.id or nil
        if hovered then state.selectedIndex = hovered else state.selectedIndex = state.focusIndex or 1 end

        if input:GetKeyPress(KEY_UP) then
            state.focusIndex = math.max(1, (state.focusIndex or 1) - 1)
            state.selectedIndex = state.focusIndex
        elseif input:GetKeyPress(KEY_DOWN) then
            state.focusIndex = math.min(#MENU_ITEMS, (state.focusIndex or 1) + 1)
            state.selectedIndex = state.focusIndex
        elseif input:GetKeyPress(KEY_RETURN) then
            activateMenu(state, context, state.selectedIndex or 1)
            return
        end

        if pointerFrame.pressed then
            state.pressedIndex = hovered
            if hovered then state.selectedIndex, state.focusIndex = hovered, hovered end
        elseif pointerFrame.released then
            local pressed = state.pressedIndex
            state.pressedIndex = nil
            if pressed and pressed == hovered then activateMenu(state, context, pressed) end
            local character = characterAt(pointerFrame.x, pointerFrame.y)
            if character then
                openAcademyIdCard(character.id)
                return
            end
        end
        updateSelection(state, dt)
    end

    local function drawSettings(painter)
        local vg = painter.vg
        painter:FillRect(0, 0, 1870, 841, { 38, 50, 36, 255 }, 54)
        painter:FillRect(SETTINGS.x, SETTINGS.y, SETTINGS.w, SETTINGS.h, OVERLAY_FILL)
        painter:StrokeRect(SETTINGS.x, SETTINGS.y, SETTINGS.w, SETTINGS.h, MENU_ACCENT, 1.4, 225)
        painter:Text(SETTINGS.x + 42, SETTINGS.y + 30, "设置", 30, MENU_INK, nil, "maker-body")
        painter:Text(SETTINGS.x + SETTINGS.w - 42, SETTINGS.y + 39, "ESC 关闭", 15, TIP_COLOR,
            NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE, "maker-body")
        drawSlider(painter, SETTINGS.music, "音乐音量", state.musicVolume)
        drawSlider(painter, SETTINGS.sound, "音效音量", state.soundVolume)
        local checkX, checkY = SETTINGS.mute.x + 18, SETTINGS.mute.y + SETTINGS.mute.h * .5
        nvgBeginPath(vg)
        nvgRect(vg, checkX - 10, checkY - 10, 20, 20)
        if state.muted then
            nvgFillColor(vg, nvgRGBA(MENU_ACCENT[1], MENU_ACCENT[2], MENU_ACCENT[3], 255)); nvgFill(vg)
        else
            nvgStrokeColor(vg, nvgRGBA(MENU_MUTED[1], MENU_MUTED[2], MENU_MUTED[3], 190)); nvgStrokeWidth(vg, 1.4); nvgStroke(vg)
        end
        painter:Text(checkX + 30, checkY, "禁用声音 / 静音", 20, MENU_INK,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-body")
    end

    function DrawTitleScreen()
        if not painter_ or not frame_ then return end
        local art = painter_.images and painter_.images.ui and painter_.images.ui.titleScreen
        if not art then return end
        local offsetX = SOURCE_OFFSET_X
        image(painter_, art.background, offsetX, 0, 1870, 841)
        for _, layer in ipairs(TITLE_LAYERS) do
            image(painter_, art.title[layer.key], offsetX + layer.x, layer.y, layer.w, layer.h)
        end
        for _, layer in ipairs(CHARACTER_LAYERS) do
            if state.hoverCharacter == layer.id or state.academyIdCardCharacter == layer.id then
                local hover = layer.id == "left1" and { x = 275, y = 275, w = 273, h = 517 }
                    or layer.id == "left2" and { x = 522, y = 320, w = 236, h = 467 }
                    or layer.id == "right2" and { x = 745, y = 295, w = 246, h = 494 }
                    or { x = 967, y = 303, w = 293, h = 491 }
                image(painter_, art.characterHover[layer.hoverKey], offsetX + hover.x, hover.y, hover.w, hover.h)
            end
            image(painter_, art.characters[layer.key], offsetX + layer.x, layer.y, layer.w, layer.h)
        end

        local vg = painter_.vg
        for index, label in ipairs(MENU_ITEMS) do
            local centerY = MENU.y + (index - 1) * MENU.rowStep + MENU.rowHeight * .5
            local progress = state.selectionProgress[index] or 0
            local active = state.selectedIndex == index
            local scale = 1 + .022 * progress
            local pressedScale = state.pressedIndex == index and .98 or 1
            local drawScale = scale * pressedScale
            nvgSave(vg)
            nvgTranslate(vg, MENU.x, centerY)
            nvgScale(vg, drawScale, drawScale)
            drawFourPointStar(vg, 10, 0, 8.2, active, active and MENU_ACCENT or MENU_MUTED)
            painter_:Text(36 + (active and 4 or 0), 0, label, MENU.textSize,
                active and MENU_INK or MENU_MUTED,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-body")
            if active then drawArrow(vg, MENU.width - 47, 0, MENU_ACCENT, 245) end
            nvgRestore(vg)
        end
        painter_:Text(MENU.x, MENU.y + #MENU_ITEMS * MENU.rowStep + 27,
            "（戳左边四个有角色介绍）", 16, TIP_COLOR, nil, "maker-body")
        if state.settingsOpen then drawSettings(painter_) end
    end
end

M.TITLE_FILL = TITLE_FILL
M.DESIGN_WIDTH = 1870
M.DESIGN_HEIGHT = 841

return M
