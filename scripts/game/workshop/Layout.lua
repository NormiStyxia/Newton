local Layout = {}

Layout.DEFAULTS = {
    minimumSystemWidth = 960,
    minimumSystemHeight = 540,
    foldedSystemWidth = 1380,
    foldedSystemHeight = 680,
    safeInset = 16,
}

local function rect(x, y, w, h)
    return { x = x, y = y, w = math.max(0, w), h = math.max(0, h) }
end

local function copyDefaults(overrides)
    local result = {}
    for key, value in pairs(Layout.DEFAULTS) do result[key] = value end
    for key, value in pairs(overrides or {}) do
        if type(value) == "number" then result[key] = value end
    end
    return result
end

local function buttonRow(x, y, definitions, height, gap)
    local result = {}
    for _, definition in ipairs(definitions) do
        result[definition.id] = rect(x, y, definition.width, height)
        x = x + definition.width + gap
    end
    return result
end

local function resolveSafeInsets(frame, minimum)
    local source = frame.safeAreaInsets
    if not source and _G.GetSafeAreaInsets then
        local ok, rect = pcall(GetSafeAreaInsets, false)
        if ok and rect then
            source = { left = rect.min.x, top = rect.min.y, right = rect.max.x, bottom = rect.max.y }
        end
    end
    source = source or {}
    local scale = math.max(0.001, (tonumber(frame.dpr) or 1) * (tonumber(frame.renderScale) or 1))
    return {
        left = math.max(minimum, (tonumber(source.left) or 0) / scale),
        top = math.max(minimum, (tonumber(source.top) or 0) / scale),
        right = math.max(minimum, (tonumber(source.right) or 0) / scale),
        bottom = math.max(minimum, (tonumber(source.bottom) or 0) / scale),
    }
end

function Layout.Resolve(frame, viewState, overrides)
    local config = copyDefaults(overrides)
    local systemWidth = tonumber(frame.systemLogicalWidth) or tonumber(frame.logicalWidth) or 0
    local systemHeight = tonumber(frame.systemLogicalHeight) or tonumber(frame.logicalHeight) or 0
    local landscape = systemWidth >= systemHeight
    local supported = landscape
        and systemWidth >= config.minimumSystemWidth
        and systemHeight >= config.minimumSystemHeight
    if not supported then
        return {
            mode = landscape and "unsupported" or "portrait",
            supported = false,
            frame = frame,
            config = config,
            full = rect(0, 0, frame.logicalWidth, frame.logicalHeight),
        }
    end

    local folded = systemWidth < config.foldedSystemWidth or systemHeight < config.foldedSystemHeight
    local safe = resolveSafeInsets(frame, config.safeInset)
    local width, height = frame.logicalWidth, frame.logicalHeight
    local topHeight, bottomHeight = 66, 34
    local bodyY = safe.top + topHeight
    local bodyHeight = height - bodyY - bottomHeight - safe.bottom
    local leftWidth = folded and 0 or 292
    local rightWidth = folded and 0 or 356
    local gap = 10
    local canvasX = safe.left + (leftWidth > 0 and leftWidth + gap or 0)
    local canvasRight = width - safe.right - (rightWidth > 0 and rightWidth + gap or 0)
    local canvas = rect(canvasX, bodyY, canvasRight - canvasX, bodyHeight)
    local left = leftWidth > 0 and rect(safe.left, bodyY, leftWidth, bodyHeight) or nil
    local right = rightWidth > 0 and rect(width - safe.right - rightWidth, bodyY, rightWidth, bodyHeight) or nil

    local toolbar = buttonRow(safe.left, safe.top, {
        { id = "exit", width = 92 },
        { id = "draft", width = 104 },
        { id = "save", width = 94 },
        { id = "export", width = 106 },
        { id = "import", width = 106 },
        { id = "undo", width = 46 },
        { id = "redo", width = 46 },
        { id = "preview", width = 116 },
    }, 46, 8)

    local result = {
        mode = folded and "folded" or "full",
        supported = true,
        folded = folded,
        frame = frame,
        config = config,
        safeInsets = safe,
        full = rect(0, 0, width, height),
        top = rect(0, 0, width, topHeight + safe.top),
        bottom = rect(0, height - bottomHeight - safe.bottom, width, bottomHeight + safe.bottom),
        left = left,
        right = right,
        canvas = canvas,
        toolbar = toolbar,
        title = rect(toolbar.preview.x + toolbar.preview.w + 18, safe.top, math.max(120,
            width - safe.right - (toolbar.preview.x + toolbar.preview.w + 18)), 46),
    }

    if folded then
        result.drawerTabs = {
            files = rect(width - safe.right - 112, safe.top, 50, 46),
            inspector = rect(width - safe.right - 54, safe.top, 54, 46),
        }
        local drawerMode = viewState and viewState.drawerMode or nil
        if drawerMode == "files" or drawerMode == "inspector" then
            local drawerWidth = math.min(372, width * 0.34)
            result.drawer = rect(width - safe.right - drawerWidth, bodyY, drawerWidth, bodyHeight)
            if drawerMode == "files" then result.left = result.drawer else result.right = result.drawer end
        end
    end

    if result.left then
        local panel = result.left
        result.fileActions = buttonRow(panel.x + 10, panel.y + 44, {
            { id = "new", width = 58 }, { id = "copy", width = 58 },
            { id = "rename", width = 58 }, { id = "delete", width = 58 },
        }, 34, 6)
        result.fileViewport = rect(panel.x + 10, panel.y + 86, panel.w - 20, math.max(120, panel.h * 0.48))
        local paletteY = result.fileViewport.y + result.fileViewport.h + 38
        result.paletteViewport = rect(panel.x + 10, paletteY, panel.w - 20,
            math.max(80, panel.y + panel.h - paletteY - 10))
    end
    if result.right then
        local panel = result.right
        result.inspectorViewport = rect(panel.x + 10, panel.y + 48, panel.w - 20, panel.h - 58)
    end
    result.canvasViewport = rect(canvas.x + 12, canvas.y + 44, canvas.w - 24, canvas.h - 58)
    result.statusText = rect(safe.left + 8, height - bottomHeight - safe.bottom + 7,
        width - safe.left - safe.right - 16, 22)
    return result
end

function Layout.PointIn(target, x, y)
    return target ~= nil and x >= target.x and x <= target.x + target.w
        and y >= target.y and y <= target.y + target.h
end

return Layout
