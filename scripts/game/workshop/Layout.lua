local Layout = {}

Layout.DEFAULTS = {
    minimumSystemWidth = 568,
    minimumSystemHeight = 300,
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
    local scale = math.max(0.001, tonumber(frame.dpr) or 1)
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
    local coordinateScale = tonumber(frame.renderScale)
    if not coordinateScale then
        local sourceWidth = math.max(1, tonumber(frame.logicalWidth) or systemWidth)
        local sourceHeight = math.max(1, tonumber(frame.logicalHeight) or systemHeight)
        coordinateScale = math.min(systemWidth / sourceWidth, systemHeight / sourceHeight)
    end
    coordinateScale = math.max(0.001, coordinateScale)
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
            coordinateScale = coordinateScale,
            renderScaleCompensation = 1 / coordinateScale,
            full = rect(0, 0, systemWidth, systemHeight),
        }
    end

    local folded = systemWidth < config.foldedSystemWidth or systemHeight < config.foldedSystemHeight
    local mobileCompact = systemWidth < 960 or systemHeight < 480
    local ultraCompact = systemWidth < 720 or systemHeight < 360
    local safe = resolveSafeInsets(frame, config.safeInset)
    local width, height = systemWidth, systemHeight
    local topHeight = ultraCompact and 50 or (mobileCompact and 60 or 68)
    local bottomHeight = ultraCompact and 28 or 38
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

    local toolbarDefinitions = ultraCompact and {
        { id = "exit", width = 40 },
        { id = "draft", width = 42 },
        { id = "save", width = 42 },
        { id = "export", width = 42 },
        { id = "import", width = 42 },
        { id = "undo", width = 32 },
        { id = "redo", width = 32 },
        { id = "preview", width = 50 },
    } or (mobileCompact and {
        { id = "exit", width = 52 },
        { id = "draft", width = 60 },
        { id = "save", width = 60 },
        { id = "export", width = 60 },
        { id = "import", width = 60 },
        { id = "undo", width = 42 },
        { id = "redo", width = 42 },
        { id = "preview", width = 72 },
    } or {
        { id = "exit", width = 92 },
        { id = "draft", width = 104 },
        { id = "save", width = 94 },
        { id = "export", width = 106 },
        { id = "import", width = 106 },
        { id = "undo", width = 46 },
        { id = "redo", width = 46 },
        { id = "preview", width = 116 },
    })
    local toolbarHeight = ultraCompact and 40 or (mobileCompact and 44 or 48)
    local toolbarGap = ultraCompact and 4 or (mobileCompact and 6 or 8)
    local toolbar = buttonRow(safe.left, safe.top, toolbarDefinitions, toolbarHeight, toolbarGap)
    local titleX = toolbar.preview.x + toolbar.preview.w + 18
    local titleRight = width - safe.right
    if folded then titleRight = titleRight - 124 end

    local result = {
        mode = folded and "folded" or "full",
        supported = true,
        folded = folded,
        mobileCompact = mobileCompact,
        ultraCompact = ultraCompact,
        coordinateScale = coordinateScale,
        renderScaleCompensation = 1 / coordinateScale,
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
        title = rect(titleX, safe.top, titleRight - titleX, toolbarHeight),
    }

    if folded then
        result.drawerTabs = {
            files = rect(width - safe.right - 112, safe.top, 50, 46),
            inspector = rect(width - safe.right - 54, safe.top, 54, 46),
        }
        local drawerMode = viewState and viewState.drawerMode or nil
        if drawerMode == "files" or drawerMode == "inspector" then
            local drawerWidth = math.min(ultraCompact and 320 or (mobileCompact and 360 or 420),
                width * (ultraCompact and 0.58 or (mobileCompact and 0.46 or 0.38)))
            result.drawer = rect(width - safe.right - drawerWidth, bodyY, drawerWidth, bodyHeight)
            if drawerMode == "files" then result.left = result.drawer else result.right = result.drawer end
        end
    end

    if result.left then
        local panel = result.left
        local actionWidth = ultraCompact and 54 or 58
        result.fileActions = buttonRow(panel.x + 10, panel.y + (ultraCompact and 34 or 44), {
            { id = "new", width = actionWidth }, { id = "copy", width = actionWidth },
            { id = "rename", width = actionWidth }, { id = "delete", width = actionWidth },
        }, ultraCompact and 28 or 34, ultraCompact and 4 or 6)
        local paletteColumns = mobileCompact and 3 or (folded and 2 or 1)
        local paletteRowHeight = ultraCompact and 34 or (mobileCompact and 40 or 44)
        local paletteRows = math.ceil(6 / paletteColumns)
        local paletteHeight = paletteRows * paletteRowHeight
        local contentBottom = panel.y + panel.h - 10
        local paletteY = contentBottom - paletteHeight
        local fileY = panel.y + (ultraCompact and 66 or 86)
        local fileGap = ultraCompact and 6 or 32
        local fileHeight = math.max(0, paletteY - fileY - fileGap)
        result.fileViewport = rect(panel.x + 10, fileY, panel.w - 20, fileHeight)
        result.paletteViewport = rect(panel.x + 10, paletteY, panel.w - 20, paletteHeight)
        result.paletteColumns = paletteColumns
        result.paletteRowHeight = paletteRowHeight
    end
    if result.right then
        local panel = result.right
        result.inspectorViewport = rect(panel.x + 10, panel.y + 48, panel.w - 20, panel.h - 58)
    end
    local canvasHeader = ultraCompact and 46 or 52
    local canvasFooter = ultraCompact and 12 or 16
    result.canvasViewport = rect(canvas.x + 12, canvas.y + canvasHeader,
        canvas.w - 24, canvas.h - canvasHeader - canvasFooter)
    result.statusText = rect(safe.left + 8, height - bottomHeight - safe.bottom + 7,
        width - safe.left - safe.right - 16, 22)
    return result
end

function Layout.PointerToWorkspace(layout, x, y)
    local scale = layout and layout.coordinateScale or 1
    return (tonumber(x) or 0) * scale, (tonumber(y) or 0) * scale
end

function Layout.PointIn(target, x, y)
    return target ~= nil and x >= target.x and x <= target.x + target.w
        and y >= target.y and y <= target.y + target.h
end

return Layout
