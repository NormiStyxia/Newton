local DesignSpace = require("game.layout.DesignSpace")

local LevelPreviewTransform = {}

local function positive(value, fallback)
    value = tonumber(value)
    return value and value > 0 and value or fallback
end

---@param playfield table
---@param viewport table
---@param options table|nil
---@return table
function LevelPreviewTransform.Fit(playfield, viewport, options)
    options = options or {}
    playfield = playfield or {}
    viewport = viewport or { x = 0, y = 0, w = 1, h = 1 }

    local levelWidth = positive(playfield.width, 1400)
    local levelHeight = positive(playfield.height, 700)
    local runtimeWidth = DesignSpace.LAB.width
    local runtimeHeight = DesignSpace.LAB.height
    local padding = math.max(0, tonumber(options.padding) or 0)
    local zoom = math.max(0.001, tonumber(options.zoom) or 1)
    local displayScale = math.min(
        math.max(1, viewport.w - padding * 2) / runtimeWidth,
        math.max(1, viewport.h - padding * 2) / runtimeHeight
    ) * zoom
    local drawWidth = runtimeWidth * displayScale
    local drawHeight = runtimeHeight * displayScale

    return {
        originX = viewport.x + viewport.w * .5 - drawWidth * .5 + (tonumber(options.panX) or 0),
        originY = viewport.y + viewport.h * .5 - drawHeight * .5 + (tonumber(options.panY) or 0),
        displayScale = displayScale,
        drawWidth = drawWidth,
        drawHeight = drawHeight,
        runtimeWidth = runtimeWidth,
        runtimeHeight = runtimeHeight,
        playfieldWidth = levelWidth,
        playfieldHeight = levelHeight,
        positionScaleX = displayScale * runtimeWidth / levelWidth,
        positionScaleY = displayScale * runtimeHeight / levelHeight,
        -- RuntimeFactory sizes every object from the playfield-height scale.
        objectScale = displayScale * runtimeHeight / levelHeight,
        scale = displayScale * runtimeHeight / levelHeight,
    }
end

function LevelPreviewTransform.LevelToScreen(transform, x, y)
    return transform.originX + (tonumber(x) or 0) * transform.positionScaleX,
        transform.originY + (tonumber(y) or 0) * transform.positionScaleY
end

function LevelPreviewTransform.ScreenToLevel(transform, x, y)
    return ((tonumber(x) or 0) - transform.originX) / transform.positionScaleX,
        ((tonumber(y) or 0) - transform.originY) / transform.positionScaleY
end

function LevelPreviewTransform.SizeToScreen(transform, width, height)
    return (tonumber(width) or 0) * transform.objectScale,
        (tonumber(height) or 0) * transform.objectScale
end

return LevelPreviewTransform
