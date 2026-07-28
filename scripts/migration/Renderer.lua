local Renderer = {}
Renderer.__index = Renderer

local COLORS = {
    background = { 248, 250, 228, 255 },
    panel = { 255, 253, 248, 255 },
    panelSecondary = { 232, 241, 222, 255 },
    playfield = { 255, 242, 199, 255 },
    playfieldAccent = { 249, 222, 121, 255 },
    floor = { 47, 73, 56, 255 },
    dark = { 32, 55, 44, 255 },
    darkSecondary = { 82, 117, 93, 255 },
    greenSoft = { 232, 241, 222, 255 },
    greenLight = { 165, 202, 139, 255 },
    greenStrong = { 95, 143, 104, 255 },
    greenSecondary = { 208, 221, 151, 255 },
    text = { 47, 73, 56, 255 },
    body = { 68, 85, 72, 255 },
    secondary = { 100, 114, 104, 255 },
    muted = { 148, 160, 152, 255 },
    white = { 255, 253, 248, 255 },
    warning = { 168, 85, 73, 255 },
    warningSoft = { 247, 227, 221, 255 },
    warningActive = { 201, 108, 89, 255 },
    warningLow = { 217, 170, 161, 255 },
    quantum = { 128, 118, 181, 255 },
    quantumSoft = { 232, 227, 244, 255 },
    instant = { 180, 147, 69, 255 },
    instantSoft = { 249, 231, 168, 255 },
    wall = { 175, 196, 157, 255 },
    wallEdge = { 82, 117, 93, 255 },
}

Renderer.COLORS = COLORS

local function color(c, alpha)
    return nvgRGBA(c[1], c[2], c[3], alpha or c[4] or 255)
end

local function hex(value, alpha)
    local n = tonumber(value:sub(2), 16)
    return nvgRGBA((n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF, alpha or 255)
end

function Renderer.New()
    local self = setmetatable({}, Renderer)
    self:Init()
    return self
end

function Renderer:Init()
    self.vg = nvgCreate(1)
    if not self.vg then error("NanoVG context 创建失败") end
    self.fontBody = nvgCreateFont(self.vg, "maker-body", "Fonts/MiSans-Regular.ttf")
    self.fontDisplay = nvgCreateFont(self.vg, "maker-display", "Fonts/MiSans-Regular.ttf")
    self.images = {
        apple = nvgCreateImage(self.vg, "image/phase1/apple.png", 0),
        launcher = nvgCreateImage(self.vg, "image/phase1/launcher.png", 0),
        portrait = nvgCreateImage(self.vg, "image/newton-portrait.png", 0),
    }
end

function Renderer:Destroy()
    if self.vg then
        nvgDelete(self.vg)
        self.vg = nil
    end
end

function Renderer:Begin(frame)
    nvgBeginFrame(self.vg, frame.logicalWidth, frame.logicalHeight, frame.dpr)
    nvgTextAlign(self.vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
end

function Renderer:Finish()
    nvgEndFrame(self.vg)
end

function Renderer:FillRect(x, y, w, h, c, alpha)
    nvgBeginPath(self.vg)
    nvgRect(self.vg, x, y, w, h)
    nvgFillColor(self.vg, color(c, alpha))
    nvgFill(self.vg)
end

function Renderer:StrokeRect(x, y, w, h, c, width, alpha)
    nvgBeginPath(self.vg)
    nvgRect(self.vg, x, y, w, h)
    nvgStrokeColor(self.vg, color(c, alpha))
    nvgStrokeWidth(self.vg, width or 1)
    nvgStroke(self.vg)
end

function Renderer:RoundedRect(x, y, w, h, r, fill, stroke, width, alpha)
    nvgBeginPath(self.vg)
    nvgRoundedRect(self.vg, x, y, w, h, r)
    if fill then nvgFillColor(self.vg, color(fill, alpha)); nvgFill(self.vg) end
    if stroke then nvgStrokeColor(self.vg, color(stroke, alpha)); nvgStrokeWidth(self.vg, width or 1); nvgStroke(self.vg) end
end

function Renderer:Circle(x, y, radius, fill, stroke, width, alpha)
    nvgBeginPath(self.vg)
    nvgCircle(self.vg, x, y, radius)
    if fill then nvgFillColor(self.vg, color(fill, alpha)); nvgFill(self.vg) end
    if stroke then nvgStrokeColor(self.vg, color(stroke, alpha)); nvgStrokeWidth(self.vg, width or 1); nvgStroke(self.vg) end
end

function Renderer:Text(x, y, value, size, c, align, font)
    nvgFontFace(self.vg, font or "maker-body")
    nvgFontSize(self.vg, size)
    nvgTextAlign(self.vg, align or (NVG_ALIGN_LEFT + NVG_ALIGN_TOP))
    nvgFillColor(self.vg, color(c or COLORS.text))
    nvgText(self.vg, x, y, value, nil)
end

function Renderer:Image(image, x, y, w, h, alpha, angle, originX, originY)
    if not image or image < 0 then return end
    originX = originX or 0.5
    originY = originY or 0.5
    nvgSave(self.vg)
    nvgTranslate(self.vg, x, y)
    if angle and angle ~= 0 then nvgRotate(self.vg, angle) end
    nvgBeginPath(self.vg)
    nvgRect(self.vg, -w * originX, -h * originY, w, h)
    nvgFillPaint(self.vg, nvgImagePattern(self.vg, -w * originX, -h * originY, w, h, 0, image, alpha or 1))
    nvgFill(self.vg)
    nvgRestore(self.vg)
end

function Renderer:DrawBackground(frame)
    self:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight, COLORS.background)
    self:FillRect(frame.playfieldX, frame.playfieldY, frame.playfieldWidth, frame.playfieldHeight, COLORS.playfield)
    self:StrokeRect(frame.playfieldX, frame.playfieldY, frame.playfieldWidth, frame.playfieldHeight, COLORS.greenLight, 2, 180)
    self:DrawFormulas(frame)
end

function Renderer:DrawFormulas(frame)
    local x, y, w, h = frame.playfieldX, frame.playfieldY, frame.playfieldWidth, frame.playfieldHeight
    local c = COLORS.greenStrong
    local formulas = {
        { "s = ½gt²", .08, .08, 18, -0.025 }, { "v = v₀ + gt", .08, .16, 16, 0.018 },
        { "F = ma", .35, .15, 25, -0.025 }, { "y = ½gt²", .59, .08, 19, 0.018 },
        { "E = mc²", .94, .16, 18, 0.018 }, { "ΣF = ma", .12, .38, 20, 0.025 },
        { "ΣF = ma", .45, .3, 21, -0.02 }, { "F_g = Gm₁m₂ / r²", .72, .39, 20, -0.018 },
        { "a = Δv / Δt", .92, .36, 18, 0.02 }, { "y = sin 3t + ½sin(7t + φ) + ¼cos 11t", .36, .73, 14, 0.015 },
        { "v² = v₀² + 2aΔx", .58, .8, 19, -0.018 }, { "y = kx²", .91, .55, 17, -0.018 },
    }
    for _, f in ipairs(formulas) do
        nvgSave(self.vg)
        nvgTranslate(self.vg, x + w * f[2], y + h * f[3])
        nvgRotate(self.vg, f[5])
        self:Text(0, 0, f[1], f[4], c, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
        nvgRestore(self.vg)
    end
    nvgStrokeColor(self.vg, color(c, 34)); nvgStrokeWidth(self.vg, 1)
    nvgBeginPath(self.vg); nvgMoveTo(self.vg, x + w * .2, y + h * .3); nvgLineTo(self.vg, x + w * .3, y + h * .3); nvgStroke(self.vg)
end

function Renderer:DrawNewton(frame, level, anger)
    local x, y, w, h = frame.newtonX, frame.newtonY, frame.newtonWidth, frame.newtonHeight
    self:RoundedRect(x, y, w, h, 7, COLORS.dark, COLORS.darkSecondary, 2)
    self:RoundedRect(x + 18, y + 12, w - 36, 58, 6, COLORS.dark, COLORS.warningLow, 1)
    self:Text(x + 30, y + 21, "ISAAC NEWTON", 11, COLORS.warningLow)
    self:Text(x + 30, y + 41, "牛顿 · 经典定律维护者", 18, COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
    if self.images.portrait and self.images.portrait >= 0 then
        nvgBeginPath(self.vg)
        nvgCircle(self.vg, x + w * .5, y + 242, 94)
        nvgFillPaint(self.vg, nvgImagePattern(self.vg, x + w * .5 - 95, y + 148, 190, 238, 0, self.images.portrait, 1))
        nvgFill(self.vg)
    else
        self:Circle(x + w * .5, y + 242, 94, COLORS.greenSoft, COLORS.greenLight, 2)
    end
    nvgStrokeColor(self.vg, color(COLORS.warningLow, 180)); nvgStrokeWidth(self.vg, 3)
    nvgBeginPath(self.vg); nvgMoveTo(self.vg, x + 22, y + 90); nvgLineTo(self.vg, x + 22, y + 140); nvgStroke(self.vg)
    self:Text(x + 36, y + 95, "“" .. ((level and level.observation) or "先观察抛物线，再谈万有引力。") .. "”", 13, COLORS.body)
    self:Text(x + 24, y + h - 112, "牛顿怒气", 12, COLORS.secondary)
    self:RoundedRect(x + 24, y + h - 86, w - 48, 12, 5, COLORS.warningSoft, COLORS.warningLow, 1)
    self:RoundedRect(x + 27, y + h - 84, math.max(0, w - 54) * math.max(0, math.min(1, anger / 100)), 7, 3, COLORS.warningActive)
    self:Text(x + w - 24, y + h - 114, string.format("%d%%", math.floor(anger + 0.5)), 12, COLORS.warning, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    self:Text(x + 24, y + h - 58, "修正拳：恢复持续规则，保留运动状态", 11, COLORS.secondary)
end

function Renderer:DrawGround(frame)
    self:FillRect(frame.playfieldX + 17, frame.groundY + 7, frame.playfieldWidth - 34, 14, COLORS.floor)
    self:FillRect(frame.playfieldX + 17, frame.groundY + 2, frame.playfieldWidth - 34, 4, COLORS.darkSecondary)
end

function Renderer:DrawObject(frame, object, state)
    if not object or not object.data then return end
    local t = object.data.transform
    local scale = frame.playfieldHeight / 700
    local x = frame.playfieldX + t.x / 1400 * frame.playfieldWidth
    local y = frame.playfieldY + t.y / 700 * frame.playfieldHeight
    local w = t.width * scale
    local h = t.height * scale
    local rotation = math.rad(-(t.rotation or 0))
    if object.type == "wall" or object.type == "door" then
        local fill = object.phaseable and COLORS.quantumSoft or COLORS.wall
        local edge = object.phaseable and COLORS.quantum or COLORS.wallEdge
        self:RoundedRect(x - w / 2, y - h / 2, w, h, 3, fill, edge, 3, 255)
        self:StrokeRect(x - w / 2 + 4, y - h / 2 + 4, w - 8, h - 8, edge, 1, 96)
        if object.type == "door" and object.openness and object.openness > 0 then
            local alpha = math.floor(255 * (1 - object.openness * .8))
            self:RoundedRect(x - w / 2, y - h / 2, w, h, 3, fill, edge, 3, alpha)
        end
    elseif object.type == "launcher" then
        self:Image(self.images.launcher, x, y, w, w * 190 / 150, 1, rotation, .5, 36 / 190)
    elseif object.type == "goal_sensor" then
        local radius = math.min(w, h) * .42
        local active = object.active or false
        self:Circle(x, y, radius, COLORS.panel, COLORS.darkSecondary, 3, 118)
        self:Circle(x, y, radius - 5, nil, COLORS.greenLight, 1, 165)
        for i = 0, 7 do
            local a = (i / 8) * math.pi * 2 + (state.sensorAngle or 0)
            local r1, r2 = radius + 2, radius + (i % 2 == 0 and 8 or 5)
            nvgStrokeColor(self.vg, color(i % 2 == 0 and COLORS.greenLight or COLORS.darkSecondary, active and 240 or 130))
            nvgStrokeWidth(self.vg, i % 2 == 0 and 3 or 2)
            nvgBeginPath(self.vg); nvgMoveTo(self.vg, x + math.cos(a) * r1, y + math.sin(a) * r1); nvgLineTo(self.vg, x + math.cos(a) * r2, y + math.sin(a) * r2); nvgStroke(self.vg)
        end
        if self.images.portrait and self.images.portrait >= 0 then
            nvgBeginPath(self.vg); nvgCircle(self.vg, x, y, radius * .62)
            nvgFillPaint(self.vg, nvgImagePattern(self.vg, x - radius * .62, y - radius * .62, radius * 1.25, radius * 1.55, 0, self.images.portrait, 1)); nvgFill(self.vg)
        end
        if active then self:Circle(x, y, radius * 1.1, nil, COLORS.primaryActive or COLORS.greenLight, 3, 230) end
    elseif object.type == "spring" then
        nvgStrokeColor(self.vg, color(COLORS.warningActive)); nvgStrokeWidth(self.vg, 4); nvgBeginPath(self.vg)
        for i = 0, 8 do
            local px = x - w / 2 + w * i / 8
            local py = y + (i == 0 or i == 8 and 0 or (i % 2 == 0 and -h * .36 or h * .36))
            if i == 0 then nvgMoveTo(self.vg, px, py) else nvgLineTo(self.vg, px, py) end
        end
        nvgStroke(self.vg)
    elseif object.type == "button" then
        self:RoundedRect(x - w / 2, y - h / 2, w, h, 3, COLORS.dark, COLORS.darkSecondary, 2)
        local top = object.active and y + 1 or y - h * .18
        self:RoundedRect(x - math.max(6, w / 2 - 6), top - h * .22, math.max(12, w - 12), math.max(6, h * .45), 2, object.active and COLORS.greenStrong or COLORS.warningActive)
    end
end

function Renderer:DrawApple(frame, apple)
    if not apple or not apple.node then return end
    local p = apple.node.position2D
    local x, y = frame.playfieldX + frame.playfieldWidth * .5 + p.x * 100, frame.playfieldY + frame.playfieldHeight * .5 - p.y * 100
    local r = apple.displayRadius or 32
    if self.images.apple and self.images.apple >= 0 then self:Image(self.images.apple, x, y, r * 2, r * 2, 1) else self:Circle(x, y, r, COLORS.warningActive, COLORS.warning) end
end

return Renderer
