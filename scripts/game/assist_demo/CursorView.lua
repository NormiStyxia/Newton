local CursorView = {}
CursorView.__index = CursorView

local COLORS = {
    ink = { 47, 73, 56, 255 },
    inkSoft = { 82, 117, 93, 255 },
    paper = { 255, 253, 238, 255 },
    glow = { 165, 202, 139, 255 },
    shadow = { 32, 55, 44, 255 },
}

local function Clamp01(value)
    return math.max(0, math.min(1, value or 0))
end

local function SmoothStep(value)
    value = Clamp01(value)
    return value * value * (3 - 2 * value)
end

function CursorView.New(renderer)
    local self = setmetatable({}, CursorView)
    self.renderer = assert(renderer, "AssistantCursorView requires the shared renderer")
    self.active = false
    self.closing = false
    self.presence = 0
    self.x, self.y = 0, 0
    self.cursorInitialized = false
    self.motion = nil
    self.target = nil
    self.dragging = false
    self.dragOrigin = nil
    self.rings = {}
    self.cursorPulse = 0
    self.message = nil
    return self
end

CursorView.new = CursorView.New

function CursorView:open(x, y)
    self.active = true
    self.closing = false
    self.presence = 0
    if x and y then self.x, self.y, self.cursorInitialized = x, y, true end
end

function CursorView:close()
    self.closing = true
    self.motion = nil
    self.target = nil
    self.dragging = false
    self.dragOrigin = nil
    self.message = nil
end

function CursorView:setMessage(text) self.message = text end
function CursorView:setTarget(target) self.target = target end

function CursorView:moveTo(x, y, duration)
    if not self.cursorInitialized then
        self.x, self.y, self.cursorInitialized = x, y, true
        self.motion = nil
        return
    end
    local dx, dy = x - self.x, y - self.y
    if dx * dx + dy * dy <= 1 then
        self.x, self.y, self.motion = x, y, nil
        return
    end
    self.motion = {
        fromX = self.x, fromY = self.y, toX = x, toY = y,
        duration = math.max(0.001, duration or 0.45), elapsed = 0,
    }
end

function CursorView:isMotionFinished() return self.motion == nil end

function CursorView:startDrag()
    self.dragging = true
    self.dragOrigin = { x = self.x, y = self.y }
    self.cursorPulse = 0.16
end

function CursorView:click(x, y)
    self.rings[#self.rings + 1] = { x = x or self.x, y = y or self.y, elapsed = 0, duration = 0.25 }
    self.cursorPulse = 0.25
end

function CursorView:endDrag()
    self.dragging = false
    self.dragOrigin = nil
    self:click(self.x, self.y)
end

function CursorView:update(dt)
    dt = math.max(0, dt or 0)
    if self.active and not self.closing then
        self.presence = math.min(1, self.presence + dt / 0.24)
    elseif self.closing then
        self.presence = math.max(0, self.presence - dt / 0.2)
        if self.presence <= 0 then self.active, self.closing = false, false end
    end
    if self.motion then
        self.motion.elapsed = math.min(self.motion.duration, self.motion.elapsed + dt)
        local progress = SmoothStep(self.motion.elapsed / self.motion.duration)
        self.x = self.motion.fromX + (self.motion.toX - self.motion.fromX) * progress
        self.y = self.motion.fromY + (self.motion.toY - self.motion.fromY) * progress
        if self.motion.elapsed >= self.motion.duration then self.motion = nil end
    end
    if self.target then self.target.elapsed = (self.target.elapsed or 0) + dt end
    self.cursorPulse = math.max(0, self.cursorPulse - dt)
    for index = #self.rings, 1, -1 do
        local ring = self.rings[index]
        ring.elapsed = ring.elapsed + dt
        if ring.elapsed >= ring.duration then table.remove(self.rings, index) end
    end
end

local function DrawDashedLine(vg, x1, y1, x2, y2, alpha)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0.001 then return end
    local ux, uy = dx / length, dy / length
    nvgBeginPath(vg)
    for distance = 0, length, 13 do
        local finish = math.min(length, distance + 7)
        nvgMoveTo(vg, x1 + ux * distance, y1 + uy * distance)
        nvgLineTo(vg, x1 + ux * finish, y1 + uy * finish)
    end
    nvgStrokeColor(vg, nvgRGBA(COLORS.glow[1], COLORS.glow[2], COLORS.glow[3], alpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

function CursorView:_drawTarget(alpha)
    local target = self.target
    if not target then return end
    local pulse = 0.5 + math.sin((target.elapsed or 0) * 5) * 0.08
    local strokeAlpha = math.floor(alpha * pulse)
    if target.shape == "circle" then
        self.renderer:Circle(target.x, target.y, (target.radius or 24) + 5, nil, COLORS.glow, 2, strokeAlpha)
    else
        self.renderer:RoundedRect(target.x - target.w * 0.5 - 5, target.y - target.h * 0.5 - 5,
            target.w + 10, target.h + 10, 5, nil, COLORS.glow, 2, strokeAlpha)
    end
end

function CursorView:_drawCursor(alpha)
    if not self.cursorInitialized then return end
    local vg = self.renderer.vg
    local entranceScale = 0.8 + 0.2 * SmoothStep(self.presence)
    local pulseScale = self.cursorPulse > 0 and (0.9 + 0.1 * (1 - self.cursorPulse / 0.25)) or 1
    local scale = entranceScale * pulseScale
    if self.dragging and self.dragOrigin then
        self.renderer:Circle(self.dragOrigin.x, self.dragOrigin.y, 5, COLORS.glow, COLORS.inkSoft, 1, math.floor(alpha * 0.7))
        DrawDashedLine(vg, self.dragOrigin.x, self.dragOrigin.y, self.x, self.y, math.floor(alpha * 0.48))
    end
    self.renderer:Circle(self.x + 8 * scale, self.y + 10 * scale, 21 * scale, COLORS.glow, nil, nil,
        math.floor(alpha * 0.12))
    nvgSave(vg)
    nvgTranslate(vg, self.x, self.y)
    nvgScale(vg, scale, scale)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, 0)
    nvgLineTo(vg, 4, 23)
    nvgLineTo(vg, 10, 17)
    nvgLineTo(vg, 17, 25)
    nvgLineTo(vg, 22, 21)
    nvgLineTo(vg, 14, 13)
    nvgLineTo(vg, 23, 10)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(COLORS.ink[1], COLORS.ink[2], COLORS.ink[3], alpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(COLORS.paper[1], COLORS.paper[2], COLORS.paper[3], alpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgRestore(vg)
end

function CursorView:_drawStatus(frame, alpha)
    local progress = SmoothStep(self.presence)
    local width = 390
    local height = self.message and 68 or 50
    local x = frame.playfieldX + frame.playfieldWidth * 0.5 - width * 0.5
    local y = 16 - (1 - progress) * 18
    self.renderer:RoundedRect(x + 2, y + 4, width, height, 7, COLORS.shadow, nil, nil, math.floor(alpha * 0.14))
    self.renderer:RoundedRect(x, y, width, height, 7, COLORS.paper, COLORS.inkSoft, 1.5, math.floor(alpha * 0.94))
    self.renderer:Circle(x + 24, y + 24, 9, nil, COLORS.inkSoft, 1.5, alpha)
    self.renderer:Text(x + 24, y + 16, "A", 11, COLORS.ink, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", alpha)
    self.renderer:Text(x + 43, y + 14, "绿毛同事正在操作  ·  ESC 退出", 15, COLORS.ink,
        NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display", alpha)
    if self.message then
        self.renderer:Text(x + 43, y + 39, self.message, 12, COLORS.inkSoft,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-body", math.floor(alpha * 0.9))
    end
end

function CursorView:render(frame)
    if self.presence <= 0 or not frame then return end
    local alpha = math.floor(255 * Clamp01(self.presence))
    self.renderer:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight, COLORS.ink, math.floor(28 * self.presence))
    self:_drawTarget(alpha)
    for _, ring in ipairs(self.rings) do
        local progress = Clamp01(ring.elapsed / ring.duration)
        self.renderer:Circle(ring.x, ring.y, 8 + progress * 24, nil, COLORS.glow, 2,
            math.floor(alpha * (1 - progress) * 0.75))
    end
    self:_drawCursor(alpha)
    self:_drawStatus(frame, alpha)
end

return CursorView
