---@class Renderer2D
---@field vg unknown
---@field fontBody integer
---@field fontDisplay integer
---@field images table<string, integer>
local Renderer = {}
Renderer.__index = Renderer

local COLORS = {
    background = { 248, 250, 228, 255 },
    panel = { 255, 253, 248, 255 },
    panelSecondary = { 232, 241, 222, 255 },
    playfield = { 255, 242, 199, 255 },
    playfieldAccent = { 249, 222, 121, 255 },
    floor = { 47, 73, 56, 255 },
    darkPrimary = { 47, 73, 56, 255 },
    dark = { 32, 55, 44, 255 },
    darkSecondary = { 82, 117, 93, 255 },
    greenSoft = { 232, 241, 222, 255 },
    greenLight = { 165, 202, 139, 255 },
    greenStrong = { 95, 143, 104, 255 },
    -- Match the source theme's primary color. WorldView uses this for the
    -- trajectory dots and flight trail; keeping it explicit avoids a nil fill
    -- color silently dropping those primitives.
    primary = { 95, 143, 104, 255 },
    primaryActive = { 117, 180, 110, 255 },
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
    glass = { 216, 214, 232, 255 },
    glassEdge = { 128, 118, 181, 255 },
    instant = { 180, 147, 69, 255 },
    instantSoft = { 249, 231, 168, 255 },
    ash = { 111, 102, 93, 255 },
    burnCore = { 244, 210, 122, 255 },
    burnEdge = { 198, 106, 88, 255 },
    spark = { 233, 164, 90, 255 },
    fieldCardSurface = { 208, 221, 151, 255 },
    fieldCardSurfaceHover = { 219, 230, 171, 255 },
    fieldCardBorder = { 142, 175, 114, 255 },
    decisionCardSurface = { 249, 222, 121, 255 },
    decisionCardSurfaceHover = { 252, 233, 155, 255 },
    decisionCardBorder = { 208, 181, 86, 255 },
    decisionCardText = { 73, 63, 39, 255 },
    decisionCardBody = { 101, 90, 52, 255 },
    quantumCardSurfaceHover = { 240, 236, 248, 255 },
    wall = { 175, 196, 157, 255 },
    wallEdge = { 82, 117, 93, 255 },
}

Renderer.COLORS = COLORS

local function color(c, alpha)
    return nvgRGBA(c[1], c[2], c[3], alpha or c[4] or 255)
end

local function tint(c, tintColor)
    return {
        math.floor(c[1] * tintColor[1] / 255 + .5),
        math.floor(c[2] * tintColor[2] / 255 + .5),
        math.floor(c[3] * tintColor[3] / 255 + .5),
        255,
    }
end

local function hex(value, alpha)
    local n = tonumber(value:sub(2), 16)
    return nvgRGBA((n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF, alpha or 255)
end

---@return Renderer2D
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
    nvgBeginFrame(self.vg, frame.systemLogicalWidth, frame.systemLogicalHeight, frame.dpr)
    nvgScale(self.vg, frame.renderScale, frame.renderScale)
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

function Renderer:Text(x, y, value, size, c, align, font, alpha)
    nvgFontFace(self.vg, font or "maker-body")
    nvgFontSize(self.vg, size)
    nvgTextAlign(self.vg, align or (NVG_ALIGN_LEFT + NVG_ALIGN_TOP))
    nvgFillColor(self.vg, color(c or COLORS.text, alpha))
    nvgText(self.vg, x, y, value, nil)
end

function Renderer:TextBox(x, y, width, value, size, c, align, font, lineHeight)
    nvgFontFace(self.vg, font or "maker-body")
    nvgFontSize(self.vg, size)
    nvgTextLineHeight(self.vg, lineHeight or 1)
    nvgTextAlign(self.vg, align or (NVG_ALIGN_LEFT + NVG_ALIGN_TOP))
    nvgFillColor(self.vg, color(c or COLORS.text))
    nvgTextBox(self.vg, x, y, width, value, nil)
end

-- These source UI glyphs use browser fallback fonts (Georgia/Arial). Keep the
-- semantic artwork deterministic until the licensed font package is supplied.
function Renderer:DrawCardSymbol(id, x, y, c, alpha)
    local vg = self.vg
    local opacity = alpha or 255
    local stroke = color(c or COLORS.text, opacity)
    local function arrow(x1, y1, x2, y2, head)
        local dx, dy = x2 - x1, y2 - y1
        local length = math.sqrt(dx * dx + dy * dy)
        if length <= .001 then return end
        local ux, uy = dx / length, dy / length
        local nx, ny = -uy, ux
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, x2, y2)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x2, y2)
        nvgLineTo(vg, x2 - ux * head + nx * head * .58, y2 - uy * head + ny * head * .58)
        nvgLineTo(vg, x2 - ux * head - nx * head * .58, y2 - uy * head - ny * head * .58)
        nvgClosePath(vg)
        nvgFill(vg)
    end

    nvgSave(vg)
    nvgTranslate(vg, x, y)
    nvgStrokeColor(vg, stroke)
    nvgFillColor(vg, stroke)
    nvgStrokeWidth(vg, 3)

    if id == "feather-gravity" then
        self:Text(-27, -22, "g", 42, c, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-body", opacity)
        self:Text(5, -23, "1", 16, c, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-body", opacity)
        self:Text(9, 5, "2", 16, c, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-body", opacity)
        nvgStrokeWidth(vg, 2)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 3, 5)
        nvgLineTo(vg, 20, -4)
        nvgStroke(vg)
    elseif id == "side-gravity" then
        self:Text(-31, -22, "g", 42, c, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-body", opacity)
        arrow(-1, 2, 31, 2, 11)
    elseif id == "hooke-bounce" or id == "up-impulse" then
        arrow(0, 25, 0, -28, 15)
    elseif id == "mirror-motion" then
        arrow(-31, -8, 31, -8, 11)
        arrow(31, 13, -31, 13, 11)
    elseif id == "quantum-phase" then
        nvgStrokeWidth(vg, 3)
        nvgBeginPath(vg)
        for step = 0, 48 do
            local px = -32 + step / 48 * 64
            local py = math.sin(step / 48 * math.pi * 4) * 13
            if step == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
        end
        nvgStroke(vg)
    end
    nvgRestore(vg)
end

function Renderer:DrawNavigationIcon(kind, x, y, c, alpha)
    local vg = self.vg
    local stroke = color(c or COLORS.white, alpha or 255)
    nvgStrokeColor(vg, stroke)
    nvgFillColor(vg, stroke)
    nvgStrokeWidth(vg, 2.4)
    if kind == "back" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + 10, y)
        nvgLineTo(vg, x - 10, y)
        nvgMoveTo(vg, x - 10, y)
        nvgLineTo(vg, x - 2, y - 8)
        nvgMoveTo(vg, x - 10, y)
        nvgLineTo(vg, x - 2, y + 8)
        nvgStroke(vg)
    elseif kind == "reset" then
        nvgBeginPath(vg)
        nvgArc(vg, x, y, 11, math.pi * .18, math.pi * 1.72, NVG_CW)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - 1, y - 11)
        nvgLineTo(vg, x + 10, y - 11)
        nvgLineTo(vg, x + 6, y - 1)
        nvgClosePath(vg)
        nvgFill(vg)
    elseif kind == "pause" then
        nvgBeginPath(vg)
        nvgRect(vg, x - 7, y - 10, 5, 20)
        nvgRect(vg, x + 2, y - 10, 5, 20)
        nvgFill(vg)
    else
        nvgBeginPath(vg)
        nvgMoveTo(vg, x - 7, y - 11)
        nvgLineTo(vg, x + 11, y)
        nvgLineTo(vg, x - 7, y + 11)
        nvgClosePath(vg)
        nvgFill(vg)
    end
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

require("game.render.WorldPrimitives").Install(Renderer, COLORS, color, tint)

return Renderer
