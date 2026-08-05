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
    local padding = 22
    local baseScale = math.min(
        math.max(1, viewport.w - padding * 2) / math.max(1, playfield.width),
        math.max(1, viewport.h - padding * 2) / math.max(1, playfield.height)
    )
    local zoom = clamp(tonumber(viewState and viewState.zoom) or 1, 0.35, 4)
    local scale = baseScale * zoom
    return {
        scale = scale,
        originX = viewport.x + viewport.w * 0.5 - playfield.width * scale * 0.5
            + (tonumber(viewState and viewState.panX) or 0),
        originY = viewport.y + viewport.h * 0.5 - playfield.height * scale * 0.5
            + (tonumber(viewState and viewState.panY) or 0),
        playfieldWidth = playfield.width,
        playfieldHeight = playfield.height,
    }
end

function Interaction.LevelToScreen(transform, x, y)
    return transform.originX + x * transform.scale, transform.originY + y * transform.scale
end

function Interaction.ScreenToLevel(transform, x, y)
    return (x - transform.originX) / transform.scale, (y - transform.originY) / transform.scale
end

local function localPoint(object, levelX, levelY)
    local transform = object.transform
    local radians = math.rad(-(transform.rotation or 0))
    local dx, dy = levelX - transform.x, levelY - transform.y
    local cosValue, sinValue = math.cos(radians), math.sin(radians)
    return dx * cosValue - dy * sinValue, dx * sinValue + dy * cosValue
end

function Interaction.HitObject(object, levelX, levelY, padding)
    if not object or type(object.transform) ~= "table" then return false end
    local x, y = localPoint(object, levelX, levelY)
    local extra = tonumber(padding) or 0
    return math.abs(x) <= object.transform.width * 0.5 + extra
        and math.abs(y) <= object.transform.height * 0.5 + extra
end

function Interaction.FindTopObject(document, levelX, levelY, padding)
    for index = #(document.objects or {}), 1, -1 do
        local object = document.objects[index]
        if Interaction.HitObject(object, levelX, levelY, padding) then return object, index end
    end
    return nil, nil
end

function Interaction.HandlePositions(object, canvasTransform)
    local transform = object.transform
    local radians = math.rad(transform.rotation or 0)
    local cosValue, sinValue = math.cos(radians), math.sin(radians)
    local function rotate(localX, localY)
        return transform.x + localX * cosValue - localY * sinValue,
            transform.y + localX * sinValue + localY * cosValue
    end
    local resizeX, resizeY = rotate(transform.width * 0.5, transform.height * 0.5)
    local rotateX, rotateY = rotate(0, -transform.height * 0.5 - 34 / canvasTransform.scale)
    local rsx, rsy = Interaction.LevelToScreen(canvasTransform, resizeX, resizeY)
    local rotx, roty = Interaction.LevelToScreen(canvasTransform, rotateX, rotateY)
    return {
        resize = { x = rsx, y = rsy, radius = 10 },
        rotate = { x = rotx, y = roty, radius = 10 },
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

function Interaction.ResizeFromPointer(document, object, levelX, levelY, minimumSize, snapSize)
    local localX, localY = localPoint(object, levelX, levelY)
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

function Interaction.RotationFromPointer(object, levelX, levelY, snapAngle)
    local degrees = math.deg(math.atan(levelY - object.transform.y, levelX - object.transform.x)) + 90
    if snapAngle then degrees = Interaction.Snap(degrees, snapAngle) end
    while degrees > 180 do degrees = degrees - 360 end
    while degrees <= -180 do degrees = degrees + 360 end
    return degrees
end

return Interaction
