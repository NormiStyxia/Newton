local LevelPreviewTransform = require("game.layout.LevelPreviewTransform")

local Interaction = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function Interaction.Snap(value, gridSize)
    gridSize = math.max(0.0001, tonumber(gridSize) or 10)
    return math.floor(value / gridSize + 0.5) * gridSize
end

function Interaction.CanvasTransform(document, viewport, viewState)
    local playfield = document and document.playfield or { width = 1400, height = 700 }
    local zoom = clamp(tonumber(viewState and viewState.zoom) or 1, 0.35, 4)
    return LevelPreviewTransform.Fit(playfield, viewport, {
        padding = 22,
        zoom = zoom,
        panX = tonumber(viewState and viewState.panX) or 0,
        panY = tonumber(viewState and viewState.panY) or 0,
    })
end

function Interaction.LevelToScreen(transform, x, y)
    return LevelPreviewTransform.LevelToScreen(transform, x, y)
end

function Interaction.ScreenToLevel(transform, x, y)
    return LevelPreviewTransform.ScreenToLevel(transform, x, y)
end

local function localPoint(object, levelX, levelY, canvasTransform)
    local transform = object.transform
    local radians = math.rad(-(transform.rotation or 0))
    local dx, dy = levelX - transform.x, levelY - transform.y
    if canvasTransform then
        local objectScale = math.max(0.0001, canvasTransform.objectScale or canvasTransform.scale or 1)
        dx = dx * (canvasTransform.positionScaleX or objectScale) / objectScale
        dy = dy * (canvasTransform.positionScaleY or objectScale) / objectScale
    end
    local cosValue, sinValue = math.cos(radians), math.sin(radians)
    return dx * cosValue - dy * sinValue, dx * sinValue + dy * cosValue
end

function Interaction.HitObject(object, levelX, levelY, padding, canvasTransform)
    if not object or type(object.transform) ~= "table" then return false end
    local x, y = localPoint(object, levelX, levelY, canvasTransform)
    local extra = tonumber(padding) or 0
    return math.abs(x) <= object.transform.width * 0.5 + extra
        and math.abs(y) <= object.transform.height * 0.5 + extra
end

function Interaction.FindTopObject(document, levelX, levelY, padding, canvasTransform)
    for index = #(document.objects or {}), 1, -1 do
        local object = document.objects[index]
        if Interaction.HitObject(object, levelX, levelY, padding, canvasTransform) then return object, index end
    end
    return nil, nil
end

function Interaction.HandlePositions(object, canvasTransform)
    local transform = object.transform
    local centerX, centerY = Interaction.LevelToScreen(canvasTransform, transform.x, transform.y)
    local width = transform.width * canvasTransform.objectScale
    local height = transform.height * canvasTransform.objectScale
    local radians = math.rad(transform.rotation or 0)
    local cosValue, sinValue = math.cos(radians), math.sin(radians)
    local function rotate(localX, localY)
        return centerX + localX * cosValue - localY * sinValue,
            centerY + localX * sinValue + localY * cosValue
    end
    local resizeX, resizeY = rotate(width * 0.5, height * 0.5)
    local rotateX, rotateY = rotate(0, -height * 0.5 - 34)
    return {
        resize = { x = resizeX, y = resizeY, radius = 10 },
        rotate = { x = rotateX, y = rotateY, radius = 10 },
    }
end

function Interaction.HitHandle(handles, x, y)
    for _, name in ipairs({ "rotate", "resize" }) do
        local handle = handles and handles[name]
        if handle then
            local dx, dy = x - handle.x, y - handle.y
            if dx * dx + dy * dy <= handle.radius * handle.radius then return name end
        end
    end
    return nil
end

function Interaction.ClampPosition(document, object, x, y)
    local width = document.playfield.width
    local height = math.min(document.playfield.height, 580)
    local radians = math.rad(object.transform.rotation or 0)
    local cosValue, sinValue = math.abs(math.cos(radians)), math.abs(math.sin(radians))
    local halfX = cosValue * object.transform.width * 0.5 + sinValue * object.transform.height * 0.5
    local halfY = sinValue * object.transform.width * 0.5 + cosValue * object.transform.height * 0.5
    return clamp(x, halfX, math.max(halfX, width - halfX)),
        clamp(y, halfY, math.max(halfY, height - halfY))
end

local function rotatedHalfExtents(object)
    local radians = math.rad(object.transform.rotation or 0)
    local cosValue, sinValue = math.abs(math.cos(radians)), math.abs(math.sin(radians))
    return cosValue * object.transform.width * 0.5 + sinValue * object.transform.height * 0.5,
        sinValue * object.transform.width * 0.5 + cosValue * object.transform.height * 0.5
end

function Interaction.ClampGroupDelta(document, positions, deltaX, deltaY)
    local width = document.playfield.width
    local height = math.min(document.playfield.height, 580)
    local minimumX, maximumX = -math.huge, math.huge
    local minimumY, maximumY = -math.huge, math.huge
    for _, position in ipairs(positions or {}) do
        local halfX, halfY = rotatedHalfExtents(position.object)
        minimumX = math.max(minimumX, halfX - position.x)
        maximumX = math.min(maximumX, width - halfX - position.x)
        minimumY = math.max(minimumY, halfY - position.y)
        maximumY = math.min(maximumY, height - halfY - position.y)
    end
    if minimumX == -math.huge then return deltaX, deltaY end
    return clamp(deltaX, minimumX, maximumX), clamp(deltaY, minimumY, maximumY)
end

function Interaction.ObjectScreenCorners(object, canvasTransform)
    local centerX, centerY = Interaction.LevelToScreen(canvasTransform,
        object.transform.x, object.transform.y)
    local halfWidth = object.transform.width * canvasTransform.objectScale * 0.5
    local halfHeight = object.transform.height * canvasTransform.objectScale * 0.5
    local radians = math.rad(object.transform.rotation or 0)
    local cosValue, sinValue = math.cos(radians), math.sin(radians)
    local corners = {}
    for _, point in ipairs({
        { -halfWidth, -halfHeight }, { halfWidth, -halfHeight },
        { halfWidth, halfHeight }, { -halfWidth, halfHeight },
    }) do
        corners[#corners + 1] = {
            x = centerX + point[1] * cosValue - point[2] * sinValue,
            y = centerY + point[1] * sinValue + point[2] * cosValue,
        }
    end
    return corners
end

local function pointInRect(point, rect)
    return point.x >= rect.x and point.x <= rect.x + rect.w
        and point.y >= rect.y and point.y <= rect.y + rect.h
end

local function pointInPolygon(point, polygon)
    local inside = false
    local previous = polygon[#polygon]
    for _, current in ipairs(polygon) do
        if ((current.y > point.y) ~= (previous.y > point.y))
            and point.x < (previous.x - current.x) * (point.y - current.y)
                / (previous.y - current.y) + current.x then
            inside = not inside
        end
        previous = current
    end
    return inside
end

local function orientation(a, b, c)
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
end

local function onSegment(a, b, point)
    local epsilon = 0.0001
    return math.abs(orientation(a, b, point)) <= epsilon
        and point.x >= math.min(a.x, b.x) - epsilon
        and point.x <= math.max(a.x, b.x) + epsilon
        and point.y >= math.min(a.y, b.y) - epsilon
        and point.y <= math.max(a.y, b.y) + epsilon
end

local function segmentsIntersect(a, b, c, d)
    local abC, abD = orientation(a, b, c), orientation(a, b, d)
    local cdA, cdB = orientation(c, d, a), orientation(c, d, b)
    if ((abC > 0 and abD < 0) or (abC < 0 and abD > 0))
        and ((cdA > 0 and cdB < 0) or (cdA < 0 and cdB > 0)) then return true end
    return onSegment(a, b, c) or onSegment(a, b, d)
        or onSegment(c, d, a) or onSegment(c, d, b)
end

function Interaction.ObjectIntersectsScreenRect(object, canvasTransform, rect)
    if not object or not object.transform or not rect then return false end
    local corners = Interaction.ObjectScreenCorners(object, canvasTransform)
    for _, corner in ipairs(corners) do
        if pointInRect(corner, rect) then return true end
    end
    local rectCorners = {
        { x = rect.x, y = rect.y }, { x = rect.x + rect.w, y = rect.y },
        { x = rect.x + rect.w, y = rect.y + rect.h }, { x = rect.x, y = rect.y + rect.h },
    }
    for _, corner in ipairs(rectCorners) do
        if pointInPolygon(corner, corners) then return true end
    end
    for index = 1, 4 do
        local objectNext = index % 4 + 1
        for rectIndex = 1, 4 do
            local rectNext = rectIndex % 4 + 1
            if segmentsIntersect(corners[index], corners[objectNext],
                rectCorners[rectIndex], rectCorners[rectNext]) then return true end
        end
    end
    return false
end

function Interaction.GroupScreenBounds(objects, canvasTransform)
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    for _, object in ipairs(objects or {}) do
        for _, corner in ipairs(Interaction.ObjectScreenCorners(object, canvasTransform)) do
            left, top = math.min(left, corner.x), math.min(top, corner.y)
            right, bottom = math.max(right, corner.x), math.max(bottom, corner.y)
        end
    end
    if left == math.huge then return nil end
    return { x = left, y = top, w = right - left, h = bottom - top }
end

function Interaction.ResizeFromPointer(document, object, levelX, levelY, minimumSize, snapSize, canvasTransform)
    local localX, localY = localPoint(object, levelX, levelY, canvasTransform)
    local width = math.max(minimumSize or 4, math.abs(localX) * 2)
    local height = math.max(minimumSize or 4, math.abs(localY) * 2)
    if snapSize then
        width = math.max(minimumSize or 4, Interaction.Snap(width, snapSize))
        height = math.max(minimumSize or 4, Interaction.Snap(height, snapSize))
    end
    width = math.min(width, document.playfield.width)
    height = math.min(height, 580)
    return width, height
end

function Interaction.RotationFromPointer(object, levelX, levelY, snapAngle, canvasTransform)
    local objectScale = canvasTransform and math.max(0.0001,
        canvasTransform.objectScale or canvasTransform.scale or 1) or 1
    local dx = levelX - object.transform.x
    local dy = levelY - object.transform.y
    if canvasTransform then
        dx = dx * (canvasTransform.positionScaleX or objectScale) / objectScale
        dy = dy * (canvasTransform.positionScaleY or objectScale) / objectScale
    end
    local degrees = math.deg(math.atan(dy, dx)) + 90
    if snapAngle then degrees = Interaction.Snap(degrees, snapAngle) end
    while degrees > 180 do degrees = degrees - 360 end
    while degrees <= -180 do degrees = degrees + 360 end
    return degrees
end

return Interaction
