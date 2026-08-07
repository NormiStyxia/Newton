local SketchDrawing = {}
SketchDrawing.__index = SketchDrawing

SketchDrawing.DEFAULT_STYLE = {
    enabled = true,
    -- The catalog preview uses the same hand-drawn treatment for every level.
    pilotLevelId = nil,
    -- Keep the irregularity visible after mobile downscaling, while every
    -- object still owns one continuous path with shared corners.
    version = 3,
    lineJitter = 1.15,
    largeShapeJitter = 1.6,
    circleRadiusJitter = 0.8,
    mainStrokeAlpha = 0.86,
    secondaryStrokeEnabled = true,
    secondaryStrokeOffset = 0.7,
    secondaryStrokeAlpha = 0.20,
    secondaryStrokeWidthScale = 0.75,
    fillOffsetMax = 0.8,
    fillOverlayAlpha = 0.08,
    textRotationMax = 0.6,
    textOffsetMax = 0.8,
    gridAlphaVariation = 0.04,
    majorGridEvery = 5,
}

local function copyStyle(overrides)
    local result = {}
    for key, value in pairs(SketchDrawing.DEFAULT_STYLE) do result[key] = value end
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function alphaByte(value, fallback)
    value = value == nil and fallback or value
    if value <= 1 then value = value * 255 end
    return math.floor(clamp(value, 0, 255) + .5)
end

local function color(value, alpha)
    return nvgRGBA(value[1], value[2], value[3], alphaByte(alpha, value[4] or 255))
end

local function hashParts(...)
    local hash = 5381
    for index = 1, select("#", ...) do
        local value = tostring(select(index, ...))
        for byteIndex = 1, #value do
            hash = (hash * 131 + value:byte(byteIndex)) % 2147483647
        end
        hash = (hash * 131 + 124) % 2147483647
    end
    return hash
end

local function noise(seed, index)
    local value = (seed + index * 104729) % 2147483647
    value = (value * 48271 + 1) % 2147483647
    return value / 1073741823.5 - 1
end

local function geometryNumber(value)
    return string.format("%.3f", tonumber(value) or 0)
end

local function point(x, y)
    return { x = x, y = y }
end

local function intermediateCount(length)
    if length < 40 then return 1 end
    if length <= 150 then return math.max(2, math.min(4, math.floor(length / 42))) end
    return math.max(4, math.min(7, math.floor(length / 55)))
end

local function buildLinePoints(x1, y1, x2, y2, seed, amplitude, offsetX, offsetY)
    offsetX, offsetY = offsetX or 0, offsetY or 0
    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length < .001 then return { point(x1 + offsetX, y1 + offsetY) } end
    local normalX, normalY = -dy / length, dx / length
    local tangentX, tangentY = dx / length, dy / length
    local points = { point(x1 + offsetX, y1 + offsetY) }
    local count = intermediateCount(length)
    for index = 1, count do
        local progress = index / (count + 1)
        local envelope = math.sin(math.pi * progress)
        local normalOffset = noise(seed, index) * amplitude * envelope
        local tangentOffset = noise(seed, index + 37) * amplitude * .08 * envelope
        points[#points + 1] = point(
            x1 + dx * progress + normalX * normalOffset + tangentX * tangentOffset + offsetX,
            y1 + dy * progress + normalY * normalOffset + tangentY * tangentOffset + offsetY)
    end
    points[#points + 1] = point(x2 + offsetX, y2 + offsetY)
    return points
end

local function appendSegment(target, segment)
    for index = #target > 0 and 2 or 1, #segment do target[#target + 1] = segment[index] end
end

local function buildPolylinePoints(vertices, seed, amplitude, closed, offsetX, offsetY)
    local result = {}
    local segmentCount = closed and #vertices or #vertices - 1
    for index = 1, segmentCount do
        local from = vertices[index]
        local to = vertices[index % #vertices + 1]
        appendSegment(result, buildLinePoints(from.x, from.y, to.x, to.y,
            hashParts(seed, index), amplitude, offsetX, offsetY))
    end
    if closed and #result > 1 then table.remove(result) end
    return result
end

local function offsetPoints(points, offsetX, offsetY)
    local result = {}
    for index, value in ipairs(points or {}) do
        result[index] = point(value.x + (offsetX or 0), value.y + (offsetY or 0))
    end
    return result
end

local function tracePolyline(vg, points, closed)
    if not points or #points == 0 then return end
    nvgBeginPath(vg)
    nvgMoveTo(vg, points[1].x, points[1].y)
    for index = 2, #points do nvgLineTo(vg, points[index].x, points[index].y) end
    if closed then nvgClosePath(vg) end
end

local function traceSmoothClosed(vg, points)
    local count = points and #points or 0
    if count < 4 then tracePolyline(vg, points, true); return end
    nvgBeginPath(vg)
    nvgMoveTo(vg, points[1].x, points[1].y)
    for index = 1, count do
        local previous = points[(index - 2) % count + 1]
        local current = points[index]
        local following = points[index % count + 1]
        local after = points[(index + 1) % count + 1]
        nvgBezierTo(vg,
            current.x + (following.x - previous.x) / 6,
            current.y + (following.y - previous.y) / 6,
            following.x - (after.x - current.x) / 6,
            following.y - (after.y - current.y) / 6,
            following.x, following.y)
    end
    nvgClosePath(vg)
end

local function strokePath(vg, points, closed, smooth, strokeColor, width, alpha)
    if smooth then traceSmoothClosed(vg, points) else tracePolyline(vg, points, closed) end
    nvgLineJoin(vg, NVG_ROUND)
    nvgLineCap(vg, NVG_ROUND)
    nvgStrokeColor(vg, color(strokeColor, alpha))
    nvgStrokeWidth(vg, width)
    nvgStroke(vg)
end

local function fillPath(vg, points, smooth, fillColor, alpha)
    if smooth then traceSmoothClosed(vg, points) else tracePolyline(vg, points, true) end
    nvgFillColor(vg, color(fillColor, alpha))
    nvgFill(vg)
end

local function buildRectVertices(x, y, width, height, seed, jitter)
    local base = {
        point(x, y), point(x + width, y), point(x + width, y + height), point(x, y + height),
    }
    for index, value in ipairs(base) do
        value.x = value.x + noise(seed, index * 2 - 1) * jitter
        value.y = value.y + noise(seed, index * 2) * jitter
    end
    return base
end

local function roundedRectVertices(x, y, width, height, radius, seed, jitter)
    radius = clamp(radius or 0, 0, math.min(width, height) * .5)
    local centers = {
        { x + radius, y + radius, math.pi, math.pi * 1.5 },
        { x + width - radius, y + radius, math.pi * 1.5, math.pi * 2 },
        { x + width - radius, y + height - radius, 0, math.pi * .5 },
        { x + radius, y + height - radius, math.pi * .5, math.pi },
    }
    local result, sample = {}, 0
    for _, corner in ipairs(centers) do
        for step = 0, 3 do
            sample = sample + 1
            local angle = corner[3] + (corner[4] - corner[3]) * step / 3
            local radialOffset = noise(seed, sample) * jitter
            result[#result + 1] = point(
                corner[1] + math.cos(angle) * (radius + radialOffset),
                corner[2] + math.sin(angle) * (radius + radialOffset))
        end
    end
    return result
end

local function ellipseVertices(centerX, centerY, radiusX, radiusY, seed, jitter)
    local result = {}
    for index = 1, 20 do
        local angle = (index - 1) * math.pi * 2 / 20
        local radialOffset = noise(seed, index) * jitter
        result[index] = point(
            centerX + math.cos(angle) * (radiusX + radialOffset),
            centerY + math.sin(angle) * (radiusY + radialOffset))
    end
    return result
end

function SketchDrawing.New(styleOverrides)
    local self = setmetatable({}, SketchDrawing)
    self.style = copyStyle(styleOverrides)
    self.cache = {}
    self.used = {}
    self.cacheCount = 0
    return self
end

function SketchDrawing:IsEnabled(levelId)
    local pilot = self.style.pilotLevelId
    return self.style.enabled and (pilot == nil or pilot == levelId)
end

function SketchDrawing:SetEnabled(enabled)
    self.style.enabled = enabled == true
end

function SketchDrawing:BeginFrame()
    for key in pairs(self.used) do self.used[key] = nil end
end

function SketchDrawing:EndFrame()
    for key in pairs(self.cache) do
        if not self.used[key] then
            self.cache[key] = nil
            self.cacheCount = self.cacheCount - 1
        end
    end
end

function SketchDrawing:Clear()
    for key in pairs(self.cache) do self.cache[key] = nil end
    for key in pairs(self.used) do self.used[key] = nil end
    self.cacheCount = 0
end

function SketchDrawing:CacheSize()
    return self.cacheCount
end

function SketchDrawing:_key(levelId, objectId, primitiveType, ...)
    local parts = { tostring(self.style.version), tostring(levelId), tostring(objectId), tostring(primitiveType) }
    for index = 1, select("#", ...) do parts[#parts + 1] = geometryNumber(select(index, ...)) end
    return table.concat(parts, "|")
end

function SketchDrawing:_geometry(key, builder)
    self.used[key] = true
    local geometry = self.cache[key]
    if geometry then return geometry end
    geometry = builder(hashParts(key))
    self.cache[key] = geometry
    self.cacheCount = self.cacheCount + 1
    return geometry
end

function SketchDrawing:_strokePair(vg, geometry, strokeColor, width, options)
    options = options or {}
    strokePath(vg, geometry.main, options.closed, options.smooth, strokeColor, width,
        options.strokeAlpha or self.style.mainStrokeAlpha)
    if options.secondary ~= false and self.style.secondaryStrokeEnabled and geometry.secondary then
        strokePath(vg, geometry.secondary, options.closed, options.smooth, strokeColor,
            width * self.style.secondaryStrokeWidthScale, self.style.secondaryStrokeAlpha)
    end
end

function SketchDrawing:DrawFill(vg, points, fillColor, alpha, smooth)
    fillPath(vg, points, smooth == true, fillColor, alpha)
end

function SketchDrawing:DrawLine(vg, levelId, objectId, primitiveType,
        x1, y1, x2, y2, strokeColor, width, options)
    options = options or {}
    local amplitude = options.jitter or self.style.lineJitter
    local key = self:_key(levelId, objectId, primitiveType, x1, y1, x2, y2, amplitude)
    local geometry = self:_geometry(key, function(seed)
        local offsetAngle = noise(seed, 91) * math.pi
        local offset = self.style.secondaryStrokeOffset
        local main = buildLinePoints(x1, y1, x2, y2, seed, amplitude)
        return {
            main = main,
            secondary = offsetPoints(main,
                math.cos(offsetAngle) * offset, math.sin(offsetAngle) * offset),
        }
    end)
    self:_strokePair(vg, geometry, strokeColor, width, options)
end

function SketchDrawing:DrawPolyline(vg, levelId, objectId, primitiveType,
        vertices, strokeColor, width, options)
    options = options or {}
    local signature = {}
    for _, value in ipairs(vertices) do
        signature[#signature + 1] = geometryNumber(value.x)
        signature[#signature + 1] = geometryNumber(value.y)
    end
    local amplitude = options.jitter or self.style.lineJitter
    local key = table.concat({ self.style.version, levelId, objectId, primitiveType,
        options.closed and "closed" or "open", geometryNumber(amplitude), table.concat(signature, ",") }, "|")
    local geometry = self:_geometry(key, function(seed)
        local offsetAngle = noise(seed, 91) * math.pi
        local offset = self.style.secondaryStrokeOffset
        local main = buildPolylinePoints(vertices, seed, amplitude, options.closed)
        return {
            main = main,
            secondary = offsetPoints(main,
                math.cos(offsetAngle) * offset, math.sin(offsetAngle) * offset),
        }
    end)
    self:_strokePair(vg, geometry, strokeColor, width, options)
end

local function drawFilledShape(self, vg, geometry, fillColor, strokeColor, width, options)
    options = options or {}
    if fillColor then
        fillPath(vg, geometry.main, options.smooth, fillColor, options.fillAlpha)
        if self.style.fillOverlayAlpha > 0 and geometry.fillOffset then
            nvgSave(vg)
            nvgTranslate(vg, geometry.fillOffset.x, geometry.fillOffset.y)
            fillPath(vg, geometry.main, options.smooth, fillColor, self.style.fillOverlayAlpha)
            nvgRestore(vg)
        end
    end
    if strokeColor and width and width > 0 then
        self:_strokePair(vg, geometry, strokeColor, width, options)
    end
end

function SketchDrawing:DrawRect(vg, levelId, objectId, primitiveType,
        x, y, width, height, fillColor, strokeColor, strokeWidth, options)
    options = options or {}
    local jitter = options.jitter or self.style.largeShapeJitter
    local key = self:_key(levelId, objectId, primitiveType, x, y, width, height, jitter)
    local geometry = self:_geometry(key, function(seed)
        local mainVertices = buildRectVertices(x, y, width, height, seed, jitter)
        local angle = noise(seed, 77) * math.pi
        local main = buildPolylinePoints(mainVertices, seed, jitter * .55, true)
        return {
            main = main,
            secondary = offsetPoints(main,
                math.cos(angle) * self.style.secondaryStrokeOffset,
                math.sin(angle) * self.style.secondaryStrokeOffset),
            fillOffset = point(noise(seed, 81) * self.style.fillOffsetMax,
                noise(seed, 82) * self.style.fillOffsetMax),
        }
    end)
    options.closed = true
    drawFilledShape(self, vg, geometry, fillColor, strokeColor, strokeWidth, options)
end

function SketchDrawing:DrawRoundedRect(vg, levelId, objectId, primitiveType,
        x, y, width, height, radius, fillColor, strokeColor, strokeWidth, options)
    options = options or {}
    local jitter = options.jitter or self.style.largeShapeJitter
    local key = self:_key(levelId, objectId, primitiveType, x, y, width, height, radius, jitter)
    local geometry = self:_geometry(key, function(seed)
        local angle = noise(seed, 77) * math.pi
        local dx = math.cos(angle) * self.style.secondaryStrokeOffset
        local dy = math.sin(angle) * self.style.secondaryStrokeOffset
        local main = roundedRectVertices(x, y, width, height, radius, seed, jitter)
        return {
            main = main,
            secondary = offsetPoints(main, dx, dy),
            fillOffset = point(noise(seed, 81) * self.style.fillOffsetMax,
                noise(seed, 82) * self.style.fillOffsetMax),
        }
    end)
    options.closed, options.smooth = true, true
    drawFilledShape(self, vg, geometry, fillColor, strokeColor, strokeWidth, options)
end

function SketchDrawing:DrawEllipse(vg, levelId, objectId, primitiveType,
        centerX, centerY, radiusX, radiusY, fillColor, strokeColor, strokeWidth, options)
    options = options or {}
    local jitter = options.jitter or self.style.circleRadiusJitter
    local key = self:_key(levelId, objectId, primitiveType, centerX, centerY, radiusX, radiusY, jitter)
    local geometry = self:_geometry(key, function(seed)
        local angle = noise(seed, 77) * math.pi
        local dx = math.cos(angle) * self.style.secondaryStrokeOffset
        local dy = math.sin(angle) * self.style.secondaryStrokeOffset
        local main = ellipseVertices(centerX, centerY, radiusX, radiusY, seed, jitter)
        return {
            main = main,
            secondary = offsetPoints(main, dx, dy),
            fillOffset = point(noise(seed, 81) * self.style.fillOffsetMax,
                noise(seed, 82) * self.style.fillOffsetMax),
        }
    end)
    options.closed, options.smooth = true, true
    drawFilledShape(self, vg, geometry, fillColor, strokeColor, strokeWidth, options)
end

function SketchDrawing:DrawCircle(vg, levelId, objectId, primitiveType,
        centerX, centerY, radius, fillColor, strokeColor, strokeWidth, options)
    self:DrawEllipse(vg, levelId, objectId, primitiveType, centerX, centerY, radius, radius,
        fillColor, strokeColor, strokeWidth, options)
end

function SketchDrawing:DrawArrow(vg, levelId, objectId, primitiveType,
        x1, y1, x2, y2, strokeColor, width, options)
    options = options or {}
    local dx, dy = x2 - x1, y2 - y1
    local angle = math.atan(dy, dx)
    local length = math.sqrt(dx * dx + dy * dy)
    local headLength = options.headLength or math.min(12, math.max(5, length * .28))
    local seed = hashParts(levelId, objectId, primitiveType, self.style.version)
    local leftLength = headLength * (1 + noise(seed, 1) * .05)
    local rightLength = headLength * (1 + noise(seed, 2) * .05)
    local spread = options.headSpread or .55
    self:DrawLine(vg, levelId, objectId, primitiveType .. ":shaft",
        x1, y1, x2, y2, strokeColor, width, options)
    self:DrawLine(vg, levelId, objectId, primitiveType .. ":head-left",
        x2, y2, x2 - math.cos(angle - spread) * leftLength,
        y2 - math.sin(angle - spread) * leftLength, strokeColor, width, options)
    self:DrawLine(vg, levelId, objectId, primitiveType .. ":head-right",
        x2, y2, x2 - math.cos(angle + spread) * rightLength,
        y2 - math.sin(angle + spread) * rightLength, strokeColor, width, options)
end

function SketchDrawing:GetTextMark(levelId, objectId, primitiveType)
    local key = table.concat({ self.style.version, levelId, objectId, primitiveType, "text" }, "|")
    return self:_geometry(key, function(seed)
        return {
            offsetX = noise(seed, 1) * self.style.textOffsetMax,
            offsetY = noise(seed, 2) * self.style.textOffsetMax,
            rotation = math.rad(noise(seed, 3) * self.style.textRotationMax),
            alpha = .94 + noise(seed, 4) * .03,
        }
    end)
end

function SketchDrawing:GridAlpha(levelId, axis, index, baseAlpha)
    local seed = hashParts(levelId, "grid", axis, index, self.style.version)
    local multiplier = 1 + noise(seed, 1) * self.style.gridAlphaVariation
    if self.style.majorGridEvery > 0 and index % self.style.majorGridEvery == 0 then
        multiplier = multiplier * 1.08
    end
    return alphaByte((baseAlpha or 76) * multiplier, baseAlpha or 76)
end

return SketchDrawing
