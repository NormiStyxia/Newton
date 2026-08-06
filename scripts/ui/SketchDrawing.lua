local SketchDrawing = {}
SketchDrawing.__index = SketchDrawing

SketchDrawing.DEFAULT_STYLE = {
    enabled = true,
    pilotLevelId = "level_01",
    version = 2,
    -- Kept as compatibility switches. Stage one deliberately uses exact geometry.
    lineJitter = 0,
    largeShapeJitter = 0,
    circleRadiusJitter = 0,
    mainStrokeAlpha = 0.86,
    secondaryStrokeEnabled = true,
    secondaryStrokeOffset = 0.45,
    secondaryStrokeRotationMax = 0.18,
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

local function polylinePath(vertices, closed)
    local points = {}
    local minX, minY, maxX, maxY
    for index, vertex in ipairs(vertices) do
        local x, y = vertex.x, vertex.y
        points[index] = point(x, y)
        minX, minY = math.min(minX or x, x), math.min(minY or y, y)
        maxX, maxY = math.max(maxX or x, x), math.max(maxY or y, y)
    end
    return {
        kind = "polyline",
        points = points,
        closed = closed == true,
        pivotX = ((minX or 0) + (maxX or 0)) * .5,
        pivotY = ((minY or 0) + (maxY or 0)) * .5,
    }
end

local function rectPath(x, y, width, height)
    return {
        kind = "rect",
        x = x, y = y, width = width, height = height,
        pivotX = x + width * .5,
        pivotY = y + height * .5,
    }
end

local function roundedRectPath(x, y, width, height, radius)
    return {
        kind = "roundedRect",
        x = x, y = y, width = width, height = height,
        radius = clamp(radius or 0, 0, math.min(width, height) * .5),
        pivotX = x + width * .5,
        pivotY = y + height * .5,
    }
end

local function ellipsePath(centerX, centerY, radiusX, radiusY)
    return {
        kind = "ellipse",
        centerX = centerX, centerY = centerY,
        radiusX = radiusX, radiusY = radiusY,
        pivotX = centerX, pivotY = centerY,
    }
end

local function commandPath(commands, pivotX, pivotY)
    return {
        kind = "commands",
        commands = commands,
        pivotX = pivotX,
        pivotY = pivotY,
    }
end

local function tracePath(vg, path)
    nvgBeginPath(vg)
    if path.kind == "rect" then
        nvgRect(vg, path.x, path.y, path.width, path.height)
    elseif path.kind == "roundedRect" then
        nvgRoundedRect(vg, path.x, path.y, path.width, path.height, path.radius)
    elseif path.kind == "ellipse" then
        nvgEllipse(vg, path.centerX, path.centerY, path.radiusX, path.radiusY)
    elseif path.kind == "commands" then
        for _, command in ipairs(path.commands) do
            if command[1] == "M" then
                nvgMoveTo(vg, command[2], command[3])
            elseif command[1] == "L" then
                nvgLineTo(vg, command[2], command[3])
            end
        end
    elseif path.points and #path.points > 0 then
        nvgMoveTo(vg, path.points[1].x, path.points[1].y)
        for index = 2, #path.points do
            nvgLineTo(vg, path.points[index].x, path.points[index].y)
        end
        if path.closed then nvgClosePath(vg) end
    end
end

local function beginPathTransform(vg, path, transform)
    if not transform then return false end
    nvgSave(vg)
    nvgTranslate(vg, transform.offsetX or 0, transform.offsetY or 0)
    if transform.rotation and transform.rotation ~= 0 then
        nvgTranslate(vg, path.pivotX or 0, path.pivotY or 0)
        nvgRotate(vg, transform.rotation)
        nvgTranslate(vg, -(path.pivotX or 0), -(path.pivotY or 0))
    end
    return true
end

local function endPathTransform(vg, transformed)
    if transformed then nvgRestore(vg) end
end

local function strokePath(vg, path, strokeColor, width, alpha, transform)
    local transformed = beginPathTransform(vg, path, transform)
    tracePath(vg, path)
    nvgLineJoin(vg, NVG_ROUND)
    nvgLineCap(vg, NVG_ROUND)
    nvgStrokeColor(vg, color(strokeColor, alpha))
    nvgStrokeWidth(vg, width)
    nvgStroke(vg)
    endPathTransform(vg, transformed)
end

local function fillPath(vg, path, fillColor, alpha, transform)
    local transformed = beginPathTransform(vg, path, transform)
    tracePath(vg, path)
    nvgFillColor(vg, color(fillColor, alpha))
    nvgFill(vg)
    endPathTransform(vg, transformed)
end

local function fixedOffset(seed, index, magnitude)
    local angle = noise(seed, index) * math.pi
    return point(math.cos(angle) * magnitude, math.sin(angle) * magnitude)
end

local function secondaryTransform(style, seed)
    local offset = clamp(style.secondaryStrokeOffset or .45, .3, .6)
    local translation = fixedOffset(seed, 91, offset)
    local rotationMax = style.secondaryStrokeRotationMax or 0
    local rotation = 0
    if rotationMax > 0 then
        rotationMax = clamp(rotationMax, .1, .25)
        rotation = math.rad(noise(seed, 92) * rotationMax)
    end
    return {
        offsetX = translation.x,
        offsetY = translation.y,
        rotation = rotation,
    }
end

local function fillTransform(style, seed)
    if (style.fillOffsetMax or 0) <= 0 then return nil end
    local offset = fixedOffset(seed, 81, clamp(style.fillOffsetMax, .5, 1))
    return { offsetX = offset.x, offsetY = offset.y, rotation = 0 }
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

function SketchDrawing:_shapeGeometry(key, levelId, objectId, builder)
    return self:_geometry(key, function(seed)
        return {
            main = builder(),
            secondaryTransform = secondaryTransform(
                self.style, hashParts(self.style.version, levelId, objectId, "object")),
            fillTransform = fillTransform(self.style, seed),
        }
    end)
end

function SketchDrawing:_strokePair(vg, geometry, strokeColor, width, options)
    options = options or {}
    strokePath(vg, geometry.main, strokeColor, width,
        options.strokeAlpha or self.style.mainStrokeAlpha)
    if options.secondary ~= false and self.style.secondaryStrokeEnabled and geometry.secondaryTransform then
        strokePath(vg, geometry.main, strokeColor,
            width * self.style.secondaryStrokeWidthScale,
            self.style.secondaryStrokeAlpha, geometry.secondaryTransform)
    end
end

function SketchDrawing:DrawFill(vg, points, fillColor, alpha)
    fillPath(vg, polylinePath(points, true), fillColor, alpha)
end

function SketchDrawing:DrawLine(vg, levelId, objectId, primitiveType,
        x1, y1, x2, y2, strokeColor, width, options)
    local key = self:_key(levelId, objectId, primitiveType, x1, y1, x2, y2)
    local geometry = self:_shapeGeometry(key, levelId, objectId, function()
        return polylinePath({ point(x1, y1), point(x2, y2) }, false)
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
    local key = table.concat({ self.style.version, levelId, objectId, primitiveType,
        options.closed and "closed" or "open", table.concat(signature, ",") }, "|")
    local geometry = self:_shapeGeometry(key, levelId, objectId, function()
        return polylinePath(vertices, options.closed)
    end)
    self:_strokePair(vg, geometry, strokeColor, width, options)
end

local function drawFilledShape(self, vg, geometry, fillColor, strokeColor, width, options)
    options = options or {}
    if fillColor and self.style.fillOverlayAlpha > 0 and geometry.fillTransform then
        fillPath(vg, geometry.main, fillColor, self.style.fillOverlayAlpha, geometry.fillTransform)
    end

    -- Fill and the primary outline share this exact NanoVG path. The path is
    -- traced once, so their corners and closure cannot diverge.
    tracePath(vg, geometry.main)
    if fillColor then
        nvgFillColor(vg, color(fillColor, options.fillAlpha))
        nvgFill(vg)
    end
    if strokeColor and width and width > 0 then
        nvgLineJoin(vg, NVG_ROUND)
        nvgLineCap(vg, NVG_ROUND)
        nvgStrokeColor(vg, color(strokeColor,
            options.strokeAlpha or self.style.mainStrokeAlpha))
        nvgStrokeWidth(vg, width)
        nvgStroke(vg)
        if options.secondary ~= false and self.style.secondaryStrokeEnabled and geometry.secondaryTransform then
            strokePath(vg, geometry.main, strokeColor,
                width * self.style.secondaryStrokeWidthScale,
                self.style.secondaryStrokeAlpha, geometry.secondaryTransform)
        end
    end
end

function SketchDrawing:DrawRect(vg, levelId, objectId, primitiveType,
        x, y, width, height, fillColor, strokeColor, strokeWidth, options)
    local key = self:_key(levelId, objectId, primitiveType, x, y, width, height)
    local geometry = self:_shapeGeometry(key, levelId, objectId, function()
        return rectPath(x, y, width, height)
    end)
    drawFilledShape(self, vg, geometry, fillColor, strokeColor, strokeWidth, options)
end

function SketchDrawing:DrawRoundedRect(vg, levelId, objectId, primitiveType,
        x, y, width, height, radius, fillColor, strokeColor, strokeWidth, options)
    local key = self:_key(levelId, objectId, primitiveType, x, y, width, height, radius)
    local geometry = self:_shapeGeometry(key, levelId, objectId, function()
        return roundedRectPath(x, y, width, height, radius)
    end)
    drawFilledShape(self, vg, geometry, fillColor, strokeColor, strokeWidth, options)
end

function SketchDrawing:DrawEllipse(vg, levelId, objectId, primitiveType,
        centerX, centerY, radiusX, radiusY, fillColor, strokeColor, strokeWidth, options)
    local key = self:_key(levelId, objectId, primitiveType, centerX, centerY, radiusX, radiusY)
    local geometry = self:_shapeGeometry(key, levelId, objectId, function()
        return ellipsePath(centerX, centerY, radiusX, radiusY)
    end)
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
    local spread = options.headSpread or .55
    local leftX = x2 - math.cos(angle - spread) * headLength
    local leftY = y2 - math.sin(angle - spread) * headLength
    local rightX = x2 - math.cos(angle + spread) * headLength
    local rightY = y2 - math.sin(angle + spread) * headLength
    local key = self:_key(levelId, objectId, primitiveType,
        x1, y1, x2, y2, headLength, spread)
    local geometry = self:_shapeGeometry(key, levelId, objectId, function()
        return commandPath({
            { "M", x1, y1 }, { "L", x2, y2 },
            { "M", leftX, leftY }, { "L", x2, y2 }, { "L", rightX, rightY },
        }, (x1 + x2) * .5, (y1 + y2) * .5)
    end)
    self:_strokePair(vg, geometry, strokeColor, width, options)
end

function SketchDrawing:GetShapeOffset(levelId, objectId, primitiveType, minimum, maximum)
    minimum, maximum = minimum or .3, maximum or .6
    local key = table.concat({ self.style.version, levelId, objectId, primitiveType, "shape-offset" }, "|")
    return self:_geometry(key, function(seed)
        local progress = (noise(seed, 1) + 1) * .5
        return fixedOffset(seed, 2, minimum + (maximum - minimum) * progress)
    end)
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
