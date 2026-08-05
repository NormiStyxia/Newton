local TextTransfer = require("game.workshop.TextTransfer")

local View = {}

local COLORS = {
    background = { 31, 35, 38, 255 },
    top = { 22, 25, 27, 255 },
    panel = { 246, 246, 241, 255 },
    panelMuted = { 229, 230, 224, 255 },
    canvas = { 52, 57, 60, 255 },
    canvasInner = { 64, 70, 73, 255 },
    grid = { 101, 111, 113, 90 },
    text = { 37, 43, 44, 255 },
    textMuted = { 91, 99, 101, 255 },
    lightText = { 231, 235, 230, 255 },
    accent = { 64, 134, 103, 255 },
    accentBright = { 89, 177, 132, 255 },
    brass = { 183, 145, 66, 255 },
    warning = { 180, 73, 64, 255 },
    line = { 178, 182, 174, 255 },
    selection = { 244, 196, 86, 255 },
    wall = { 125, 132, 132, 255 },
    phase = { 116, 105, 172, 255 },
    launcher = { 73, 127, 110, 255 },
    goal = { 186, 146, 67, 255 },
    spring = { 69, 136, 165, 255 },
    button = { 169, 91, 72, 255 },
    door = { 91, 97, 113, 255 },
    overlay = { 8, 10, 11, 205 },
}

local TYPE_LABELS = {
    wall = "墙体", launcher = "发射器", goal_sensor = "观察皿",
    spring = "弹簧", button = "按钮", door = "机关门",
}

local function pointIn(rect, x, y)
    return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local DRAWER_OCCLUDED_CONTROLS = {
    canvas = true, grid = true, snap = true, zoomOut = true, zoomIn = true, deleteObject = true,
}

function View.ControlHitAllowed(layout, controlId, x, y)
    return not pointIn(layout and layout.drawer, x, y)
        or not DRAWER_OCCLUDED_CONTROLS[controlId or "canvas"]
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function truncate(value, maxCharacters)
    value = tostring(value or "")
    if utf8 and utf8.len and utf8.offset then
        local ok, count = pcall(function() return utf8.len(value) end)
        if ok and count and count > maxCharacters then
            local byte = utf8.offset(value, maxCharacters)
            return value:sub(1, math.max(0, (byte or #value + 1) - 1)) .. "..."
        end
    elseif #value > maxCharacters then
        return value:sub(1, maxCharacters) .. "..."
    end
    return value
end

local function utf8Characters(value)
    local result = {}
    value = tostring(value or "")
    if utf8 and utf8.codes and utf8.char then
        for _, codepoint in utf8.codes(value) do result[#result + 1] = utf8.char(codepoint) end
    else
        for index = 1, #value do result[#result + 1] = value:sub(index, index) end
    end
    return result
end

local function textWidth(painter, value, font, size)
    painter:UseFont(font)
    nvgFontSize(painter.vg, size)
    local measured = nvgTextBounds(painter.vg, 0, 0, tostring(value or ""), nil)
    if type(measured) == "number" then return measured end
    return #utf8Characters(value) * size
end

local function fitText(painter, value, font, preferredSize, minimumSize, maxWidth)
    value = tostring(value or "")
    local size = preferredSize
    while size > minimumSize and textWidth(painter, value, font, size) > maxWidth do
        size = math.max(minimumSize, size - 0.5)
    end
    if textWidth(painter, value, font, size) <= maxWidth then return value, size end
    local characters = utf8Characters(value)
    while #characters > 1 do
        table.remove(characters)
        local candidate = table.concat(characters) .. "..."
        if textWidth(painter, candidate, font, size) <= maxWidth then return candidate, size end
    end
    return "...", size
end

local function addControl(controls, group, id, rect, data)
    controls[group] = controls[group] or {}
    local control = data or {}
    control.id, control.rect = id, rect
    controls[group][#controls[group] + 1] = control
    return control
end

function View.BuildControls(state, layout, interaction)
    local controls = { byId = {}, fileRows = {}, paletteRows = {}, inspectorRows = {}, modalButtons = {} }
    if not layout.supported then return controls end
    for id, rect in pairs(layout.toolbar or {}) do controls.byId[id] = rect end
    for id, rect in pairs(layout.fileActions or {}) do controls.byId["file_" .. id] = rect end
    for id, rect in pairs(layout.drawerTabs or {}) do controls.byId["drawer_" .. id] = rect end

    controls.byId.grid = { x = layout.canvas.x + 12, y = layout.canvas.y + 8, w = 64, h = 36 }
    controls.byId.snap = { x = layout.canvas.x + 82, y = layout.canvas.y + 8, w = 64, h = 36 }
    controls.byId.zoomOut = { x = layout.canvas.x + layout.canvas.w - 92, y = layout.canvas.y + 8, w = 36, h = 36 }
    controls.byId.zoomIn = { x = layout.canvas.x + layout.canvas.w - 50, y = layout.canvas.y + 8, w = 36, h = 36 }
    controls.byId.deleteObject = { x = layout.canvas.x + layout.canvas.w - 202, y = layout.canvas.y + 8, w = 98, h = 36 }

    if layout.fileViewport then
        local entries = state.entries or {}
        local rowHeight = layout.ultraCompact and 38 or (layout.mobileCompact and 44 or 52)
        state.view.fileScrollMax = math.max(0, #entries * rowHeight - layout.fileViewport.h)
        state.view.fileScroll = clamp(state.view.fileScroll or 0, 0, state.view.fileScrollMax)
        for index, entry in ipairs(entries) do
            local y = layout.fileViewport.y + (index - 1) * rowHeight - state.view.fileScroll
            local rect = { x = layout.fileViewport.x, y = y, w = layout.fileViewport.w, h = rowHeight - 3 }
            if y + rect.h >= layout.fileViewport.y and y <= layout.fileViewport.y + layout.fileViewport.h then
                addControl(controls, "fileRows", entry.entryId, rect, { entry = entry })
            end
        end
    end
    if layout.paletteViewport then
        local types = state.supportedTypes or {}
        local rowHeight = layout.paletteRowHeight or 44
        local columns = math.max(1, layout.paletteColumns or 1)
        local gap = 4
        local cellWidth = (layout.paletteViewport.w - (columns - 1) * gap) / columns
        for index, objectType in ipairs(types) do
            local column = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            local y = layout.paletteViewport.y + row * rowHeight
            local rect = { x = layout.paletteViewport.x + column * (cellWidth + gap), y = y,
                w = cellWidth, h = rowHeight - 4 }
            if y + rect.h <= layout.paletteViewport.y + layout.paletteViewport.h then
                addControl(controls, "paletteRows", objectType, rect, { objectType = objectType })
            end
        end
    end
    if layout.inspectorViewport then
        local y = layout.inspectorViewport.y - (state.view.inspectorScroll or 0)
        local contentHeight = 0
        for index, field in ipairs(state.inspectorFields or {}) do
            local height = field.kind == "section" and (layout.ultraCompact and 32 or 38)
                or (layout.ultraCompact and 44 or 52)
            local rect = { x = layout.inspectorViewport.x, y = y, w = layout.inspectorViewport.w, h = height }
            if y + height >= layout.inspectorViewport.y and y <= layout.inspectorViewport.y + layout.inspectorViewport.h then
                addControl(controls, "inspectorRows", field.key or tostring(index), rect, { field = field })
            end
            y = y + height
            contentHeight = contentHeight + height
        end
        state.view.inspectorScrollMax = math.max(0, contentHeight - layout.inspectorViewport.h)
        state.view.inspectorScroll = clamp(state.view.inspectorScroll or 0, 0, state.view.inspectorScrollMax)
    end
    if state.document and layout.canvasViewport then
        controls.canvasTransform = interaction.CanvasTransform(state.document, layout.canvasViewport, state.view)
        local selected = state.selectedObject
        if selected then controls.handles = interaction.HandlePositions(selected, controls.canvasTransform) end
    end

    local modal = state.modal
    if modal then
        local wideModal = modal.kind == "export" or modal.kind == "import"
        ---@type number
        local width = wideModal and 1040 or 560
        ---@type number
        local height = wideModal and 610 or 270
        width = math.min(width, layout.full.w - 80)
        height = math.min(height, layout.full.h - 80)
        controls.modal = {
            x = (layout.full.w - width) * 0.5,
            y = (layout.full.h - height) * 0.5,
            w = width,
            h = height,
        }
        controls.modalBody = {
            x = controls.modal.x + 24, y = controls.modal.y + 78,
            w = controls.modal.w - 48, h = controls.modal.h - 144,
        }
        local definitions
        if modal.kind == "dirtySwitch" then
            definitions = { { "save", "保存草稿并继续" }, { "discard", "放弃修改" }, { "cancel", "取消" } }
        elseif modal.kind == "recovery" then
            definitions = { { "continue", "继续编辑" }, { "discard", "放弃草稿" }, { "saveAs", "另存为新关卡" } }
        elseif modal.kind == "confirmDelete" then
            definitions = { { "confirm", "删除" }, { "cancel", "取消" } }
        elseif modal.kind == "rename" then
            definitions = { { "confirm", "确认" }, { "cancel", "取消" } }
        elseif modal.kind == "import" then
            definitions = { { "paste", "从剪贴板粘贴" }, { "confirm", "导入为新关卡" }, { "cancel", "取消" } }
        elseif modal.kind == "export" then
            definitions = { { "copy", "复制全部" }, { "close", "关闭" } }
        else
            definitions = { { "close", "关闭" } }
        end
        local buttonWidth = modal.kind == "dirtySwitch" and 132 or 142
        local total = #definitions * buttonWidth + (#definitions - 1) * 10
        local x = controls.modal.x + controls.modal.w - 24 - total
        local y = controls.modal.y + controls.modal.h - 50
        for _, definition in ipairs(definitions) do
            addControl(controls, "modalButtons", definition[1], { x = x, y = y, w = buttonWidth, h = 34 },
                { label = definition[2] })
            x = x + buttonWidth + 10
        end
        if wideModal then
            local text = modal.kind == "export" and (modal.payload and modal.payload.text or "")
                or (state.textEdit and state.textEdit.value or modal.text or "")
            TextTransfer.UpdateModal(modal, text, controls.modalBody, 14, 1.4)
        end
    end
    return controls
end

local function drawButton(painter, rect, label, options)
    options = options or {}
    local enabled = options.enabled ~= false
    local fill = options.primary and COLORS.accent or (options.danger and COLORS.warning or COLORS.panelMuted)
    if options.active then fill = COLORS.brass end
    local text = (options.primary or options.danger or options.active) and COLORS.lightText or COLORS.text
    if not enabled then fill, text = COLORS.panelMuted, COLORS.textMuted end
    painter:RoundedRect(rect.x, rect.y, rect.w, rect.h, 4, fill, enabled and COLORS.line or COLORS.panelMuted, 1,
        enabled and 255 or 150)
    local preferredSize = options.fontSize or math.min(20, rect.h * 0.48)
    local fittedLabel, fittedSize = fitText(painter, label, "maker-body", preferredSize,
        options.minimumFontSize or 10, math.max(1, rect.w - 12))
    painter:Text(rect.x + rect.w * 0.5, rect.y + rect.h * 0.5, fittedLabel, fittedSize, text,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-body")
end

local function drawUnsupported(painter, layout)
    painter:FillRect(0, 0, layout.full.w, layout.full.h, COLORS.background)
    local text = layout.mode == "portrait" and "请切换横屏使用关卡工坊" or "当前窗口尺寸暂不支持关卡工坊"
    painter:Text(layout.full.w * 0.5, layout.full.h * 0.5 - 18, text, 30, COLORS.lightText,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display")
    painter:Text(layout.full.w * 0.5, layout.full.h * 0.5 + 24, "调整窗口后将自动恢复，不会丢失当前草稿", 16,
        COLORS.textMuted, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-body")
end

local function drawPanel(painter, rect, title)
    if not rect then return end
    painter:FillRect(rect.x, rect.y, rect.w, rect.h, COLORS.panel)
    painter:StrokeRect(rect.x, rect.y, rect.w, rect.h, COLORS.line, 1)
    local fittedTitle, fittedSize = fitText(painter, title, "maker-display", 21, 16, rect.w - 24)
    painter:Text(rect.x + 12, rect.y + 12, fittedTitle, fittedSize, COLORS.text, nil, "maker-display")
end

local function drawTop(painter, state, layout, controls)
    painter:FillRect(0, 0, layout.full.w, layout.top.h, COLORS.top)
    local labels = layout.mobileCompact
        and { exit = "退出", draft = "草稿", save = "保存", export = "导出", import = "导入",
            undo = "撤", redo = "重", preview = "预览" }
        or { exit = "退出", draft = "保存草稿", save = "保存关卡", export = "导出 JSON", import = "导入 JSON",
            undo = "撤销", redo = "重做", preview = "快速预览" }
    for id, rect in pairs(layout.toolbar) do
        local enabled = true
        if id == "save" or id == "draft" then enabled = not state.readOnly and state.document ~= nil end
        if id == "undo" then enabled = state.canUndo end
        if id == "redo" then enabled = state.canRedo end
        if id == "preview" or id == "export" then enabled = state.document ~= nil end
        drawButton(painter, rect, labels[id], { enabled = enabled, primary = id == "preview",
            fontSize = layout.ultraCompact and 16 or (layout.mobileCompact and 19 or 20) })
    end
    local suffix = state.dirty and "  ·  未保存" or ""
    if not layout.mobileCompact and layout.title.w >= 80 then
        local title, titleSize = fitText(painter,
            (state.document and state.document.name or "关卡工坊") .. suffix,
            "maker-display", 23, 16, layout.title.w)
        painter:Text(layout.title.x, layout.title.y + layout.title.h * 0.5,
            title, titleSize,
            COLORS.lightText, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-display")
    end
    if layout.drawerTabs then
        drawButton(painter, layout.drawerTabs.files, "文件", { active = state.view.drawerMode == "files", fontSize = 18 })
        drawButton(painter, layout.drawerTabs.inspector, "属性", { active = state.view.drawerMode == "inspector", fontSize = 18 })
    end
end

local function drawLeft(painter, state, layout, controls)
    if not layout.left then return end
    drawPanel(painter, layout.left, "关卡与对象")
    local labels = { new = "新建", copy = "复制", rename = "重命名", delete = "删除" }
    for id, rect in pairs(layout.fileActions or {}) do
        local enabled = id == "new" or state.document ~= nil
        if id == "rename" or id == "delete" then enabled = enabled and not state.readOnly end
        drawButton(painter, rect, labels[id], { enabled = enabled, danger = id == "delete" })
    end
    if layout.fileViewport then
        nvgSave(painter.vg)
        nvgScissor(painter.vg, layout.fileViewport.x, layout.fileViewport.y, layout.fileViewport.w, layout.fileViewport.h)
        for _, row in ipairs(controls.fileRows) do
            local entry = row.entry
            local selected = state.entryId == entry.entryId
            painter:FillRect(row.rect.x, row.rect.y, row.rect.w, row.rect.h,
                selected and COLORS.panelMuted or COLORS.panel, 255)
            if selected then painter:FillRect(row.rect.x, row.rect.y, 4, row.rect.h, COLORS.accent) end
            local name, nameSize = fitText(painter, entry.name, "maker-body", 19, 14, row.rect.w - 20)
            if layout.ultraCompact then
                painter:Text(row.rect.x + 10, row.rect.y + row.rect.h * 0.5,
                    name, nameSize, COLORS.text, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-body")
            else
                painter:Text(row.rect.x + 10, row.rect.y + 5, name, nameSize, COLORS.text, nil, "maker-body")
                local metadata, metadataSize = fitText(painter,
                    (entry.readOnly and "官方 · 只读" or "自定义") .. "  " .. entry.levelId,
                    "maker-body", 15, 11, row.rect.w - 20)
                painter:Text(row.rect.x + 10, row.rect.y + 30,
                    metadata, metadataSize, COLORS.textMuted, nil, "maker-body")
            end
        end
        nvgRestore(painter.vg)
    end
    if layout.paletteViewport then
        if not layout.mobileCompact then
            painter:Text(layout.paletteViewport.x, layout.paletteViewport.y - 27,
                "新增对象", 18, COLORS.text, nil, "maker-display")
        end
        nvgSave(painter.vg)
        nvgScissor(painter.vg, layout.paletteViewport.x, layout.paletteViewport.y,
            layout.paletteViewport.w, layout.paletteViewport.h)
        for _, row in ipairs(controls.paletteRows) do
            drawButton(painter, row.rect, "+  " .. (TYPE_LABELS[row.objectType] or row.objectType),
                { enabled = not state.readOnly })
        end
        nvgRestore(painter.vg)
    end
end

local function objectColor(object)
    if object.type == "wall" then return object.properties and object.properties.isPhaseable and COLORS.phase or COLORS.wall end
    return COLORS[object.type == "goal_sensor" and "goal" or object.type] or COLORS.wall
end

local function drawGrid(painter, viewport, transform, playfield)
    nvgSave(painter.vg)
    nvgScissor(painter.vg, viewport.x, viewport.y, viewport.w, viewport.h)
    local spacing = 50
    nvgStrokeColor(painter.vg, nvgRGBA(COLORS.grid[1], COLORS.grid[2], COLORS.grid[3], COLORS.grid[4]))
    nvgStrokeWidth(painter.vg, 1)
    nvgBeginPath(painter.vg)
    for x = 0, playfield.width, spacing do
        local sx = transform.originX + x * transform.scale
        nvgMoveTo(painter.vg, sx, transform.originY)
        nvgLineTo(painter.vg, sx, transform.originY + playfield.height * transform.scale)
    end
    for y = 0, playfield.height, spacing do
        local sy = transform.originY + y * transform.scale
        nvgMoveTo(painter.vg, transform.originX, sy)
        nvgLineTo(painter.vg, transform.originX + playfield.width * transform.scale, sy)
    end
    nvgStroke(painter.vg)
    nvgRestore(painter.vg)
end

local function drawObject(painter, object, transform, selected)
    local x = transform.originX + object.transform.x * transform.scale
    local y = transform.originY + object.transform.y * transform.scale
    local w = object.transform.width * transform.scale
    local h = object.transform.height * transform.scale
    local rotation = math.rad(object.transform.rotation or 0)
    local fill = objectColor(object)
    nvgSave(painter.vg)
    nvgTranslate(painter.vg, x, y)
    nvgRotate(painter.vg, rotation)
    painter:FillRect(-w * 0.5, -h * 0.5, w, h, fill, object.properties and object.properties.collisionEnabled == false and 90 or 205)
    painter:StrokeRect(-w * 0.5, -h * 0.5, w, h, selected and COLORS.selection or COLORS.lightText,
        selected and 3 or 1, selected and 255 or 135)
    if object.type == "goal_sensor" then
        painter:StrokeRect(-w * 0.32, -h * 0.30, w * 0.64, h * 0.60, COLORS.lightText, 2, 180)
    elseif object.type == "launcher" then
        painter:Circle(0, 0, math.min(w, h) * 0.22, nil, COLORS.lightText, 2, 190)
    elseif object.type == "spring" then
        nvgBeginPath(painter.vg)
        nvgMoveTo(painter.vg, -w * 0.38, h * 0.2)
        for step = 1, 6 do
            nvgLineTo(painter.vg, -w * 0.38 + w * 0.76 * step / 6, (step % 2 == 0 and 1 or -1) * h * 0.2)
        end
        nvgStrokeColor(painter.vg, nvgRGBA(236, 238, 231, 220)); nvgStrokeWidth(painter.vg, 2); nvgStroke(painter.vg)
    elseif object.type == "button" then
        painter:FillRect(-w * 0.34, -h * 0.18, w * 0.68, h * 0.36, COLORS.brass)
    elseif object.type == "door" then
        painter:FillRect(-2, -h * 0.42, 4, h * 0.84, COLORS.lightText, 150)
    end
    nvgRestore(painter.vg)
    local objectId, objectIdSize = fitText(painter, object.id, "maker-body", 14, 9, math.max(10, w - 6))
    painter:Text(x, y, objectId, objectIdSize, COLORS.lightText,
        NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-body")
end

local function drawCanvas(painter, state, layout, controls)
    painter:FillRect(layout.canvas.x, layout.canvas.y, layout.canvas.w, layout.canvas.h, COLORS.canvas)
    painter:StrokeRect(layout.canvas.x, layout.canvas.y, layout.canvas.w, layout.canvas.h, COLORS.line, 1)
    if not layout.ultraCompact then
        painter:Text(layout.canvas.x + 154, layout.canvas.y + 17, "灰盒画布", 18,
            COLORS.lightText, nil, "maker-display")
    end
    drawButton(painter, controls.byId.grid, "网格", { active = state.view.showGrid })
    drawButton(painter, controls.byId.snap, "吸附", { active = state.view.snap })
    drawButton(painter, controls.byId.deleteObject, "删除对象", { enabled = state.selectedObject ~= nil and not state.readOnly, danger = true })
    drawButton(painter, controls.byId.zoomOut, "−", { fontSize = 20 })
    drawButton(painter, controls.byId.zoomIn, "+", { fontSize = 18 })
    local viewport = layout.canvasViewport
    painter:FillRect(viewport.x, viewport.y, viewport.w, viewport.h, COLORS.canvasInner)
    if not state.document or not controls.canvasTransform then return end
    local transform = controls.canvasTransform
    nvgSave(painter.vg)
    nvgScissor(painter.vg, viewport.x, viewport.y, viewport.w, viewport.h)
    painter:FillRect(transform.originX, transform.originY,
        state.document.playfield.width * transform.scale, state.document.playfield.height * transform.scale,
        COLORS.background)
    if state.view.showGrid then drawGrid(painter, viewport, transform, state.document.playfield) end
    painter:StrokeRect(transform.originX, transform.originY,
        state.document.playfield.width * transform.scale, state.document.playfield.height * transform.scale,
        COLORS.lightText, 2, 190)
    local groundY = transform.originY + 580 * transform.scale
    painter:FillRect(transform.originX, groundY,
        state.document.playfield.width * transform.scale,
        math.max(0, (state.document.playfield.height - 580) * transform.scale), COLORS.top, 170)
    for _, object in ipairs(state.document.objects or {}) do
        drawObject(painter, object, transform, state.selectedObjectId == object.id)
    end
    if state.selectedObject and controls.handles then
        local handles = controls.handles
        painter:Circle(handles.rotate.x, handles.rotate.y, handles.rotate.radius, COLORS.selection, COLORS.top, 2)
        painter:FillRect(handles.resize.x - handles.resize.radius, handles.resize.y - handles.resize.radius,
            handles.resize.radius * 2, handles.resize.radius * 2, COLORS.selection)
        painter:Text(transform.originX + 8, transform.originY + 8,
            string.format("%s  x %.1f  y %.1f  %.1f × %.1f  %.1f°", state.selectedObject.id,
                state.selectedObject.transform.x, state.selectedObject.transform.y,
                state.selectedObject.transform.width, state.selectedObject.transform.height,
                state.selectedObject.transform.rotation), 15, COLORS.lightText, nil, "maker-body")
    end
    nvgRestore(painter.vg)
end

local function fieldValue(field)
    if field.kind == "boolean" then return field.value and "开" or "关" end
    if field.kind == "readonly" then return tostring(field.value or "") end
    if field.kind == "enum" then return tostring(field.value or "") .. "  ▾" end
    return tostring(field.value == nil and "" or field.value)
end

local function drawInspector(painter, state, layout, controls)
    if not layout.right then return end
    drawPanel(painter, layout.right, state.selectedObject and "对象 Inspector" or "关卡 Inspector")
    local viewport = layout.inspectorViewport
    if not viewport then return end
    nvgSave(painter.vg)
    nvgScissor(painter.vg, viewport.x, viewport.y, viewport.w, viewport.h)
    for _, row in ipairs(controls.inspectorRows) do
        local field = row.field
        if field.kind == "section" then
            painter:FillRect(row.rect.x, row.rect.y, row.rect.w, row.rect.h, COLORS.panelMuted)
            local section, sectionSize = fitText(painter, field.label, "maker-display", 18, 14, row.rect.w - 16)
            painter:Text(row.rect.x + 8, row.rect.y + row.rect.h * 0.5, section, sectionSize, COLORS.text,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-display")
        else
            local fieldLabel, labelSize = fitText(painter, field.label, "maker-body", 16, 12,
                row.rect.w * 0.4 - 5)
            painter:Text(row.rect.x + 5, row.rect.y + 7, fieldLabel, labelSize,
                COLORS.textMuted, nil, "maker-body")
            local valueRect = { x = row.rect.x + row.rect.w * 0.43, y = row.rect.y + 5,
                w = row.rect.w * 0.57 - 5, h = row.rect.h - 10 }
            local active = state.textEdit and state.textEdit.fieldKey == field.key
            painter:RoundedRect(valueRect.x, valueRect.y, valueRect.w, valueRect.h, 3,
                active and COLORS.panel or COLORS.panelMuted, active and COLORS.accent or COLORS.line, active and 2 or 1)
            local value = active and state.textEdit.value or fieldValue(field)
            local fittedValue, valueSize = fitText(painter, value, "maker-body", 18, 12, valueRect.w - 16)
            painter:Text(valueRect.x + 8, valueRect.y + valueRect.h * 0.5,
                fittedValue, valueSize,
                field.editable == false and COLORS.textMuted or COLORS.text,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-body")
        end
    end
    nvgRestore(painter.vg)
end

local function drawStatus(painter, state, layout)
    painter:FillRect(layout.bottom.x, layout.bottom.y, layout.bottom.w, layout.bottom.h, COLORS.top)
    local validation = state.validation
    local errors = validation and #validation.errors or 0
    local warnings = validation and #validation.warnings or 0
    local text = state.status or "就绪"
    if errors > 0 then
        local issue = validation.errors[1]
        text = issue.path .. "：" .. issue.message
    elseif warnings > 0 then
        local issue = validation.warnings[1]
        text = issue.path .. "：" .. issue.message
    end
    if state.document then
        text = text .. string.format("   ·   %d 对象   ·   %d 错误 / %d 警告   ·   %s",
            #(state.document.objects or {}), errors, warnings, state.persistenceKind or "memory-only")
    end
    local statusText, statusSize = fitText(painter, text, "maker-body", 16, 11, layout.statusText.w)
    painter:Text(layout.statusText.x, layout.statusText.y, statusText, statusSize,
        errors > 0 and COLORS.warning or COLORS.lightText, nil, "maker-body")
end

local function drawModal(painter, state, controls)
    local modal, rect = state.modal, controls.modal
    if not modal or not rect then return end
    painter:FillRect(0, 0, state.layout.full.w, state.layout.full.h, COLORS.overlay)
    painter:RoundedRect(rect.x, rect.y, rect.w, rect.h, 6, COLORS.panel, COLORS.line, 2)
    painter:Text(rect.x + 24, rect.y + 22, modal.title or "关卡工坊", 22, COLORS.text, nil, "maker-display")
    local body = controls.modalBody
    if modal.kind == "export" or modal.kind == "import" then
        painter:FillRect(body.x, body.y, body.w, body.h, COLORS.top)
        painter:StrokeRect(body.x, body.y, body.w, body.h, COLORS.line, 1)
        nvgSave(painter.vg)
        nvgScissor(painter.vg, body.x + 8, body.y + 8, body.w - 16, body.h - 16)
        local text = modal.kind == "export" and (modal.payload and modal.payload.text or "")
            or (state.textEdit and state.textEdit.value or modal.text or "")
        text = modal.previewText or text
        nvgTranslate(painter.vg, 0, -(modal.previewOffsetY or modal.scroll or 0))
        painter:TextBox(body.x + 10, body.y + 10, body.w - 20, text, 14, COLORS.lightText,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-body", 1.4)
        nvgRestore(painter.vg)
        local stats = modal.payload and string.format("%d 字符 · %d 字节 · %d 对象 · schemaVersion %s",
            modal.payload.characterCount, modal.payload.byteCount, modal.payload.objectCount,
            tostring(modal.payload.schemaVersion)) or (modal.textMetrics and string.format(
                "%d 字符 · %d 字节 · 上限 %d 字节", modal.textMetrics.characterCount,
                modal.textMetrics.byteCount, modal.maxBytes or 0) or "等待 JSON 文本")
        painter:Text(body.x, body.y + body.h + 8, stats, 13, COLORS.textMuted, nil, "maker-body")
    else
        painter:TextBox(body.x, body.y, body.w, modal.message or "", 16, COLORS.text,
            NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-body", 1.25)
        if modal.kind == "rename" then
            local field = { x = body.x, y = body.y + 62, w = body.w, h = 38 }
            painter:RoundedRect(field.x, field.y, field.w, field.h, 3, COLORS.panelMuted, COLORS.accent, 2)
            painter:Text(field.x + 10, field.y + field.h * 0.5,
                truncate(state.textEdit and state.textEdit.value or "", 60), 16, COLORS.text,
                NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-body")
        end
    end
    for _, button in ipairs(controls.modalButtons or {}) do
        drawButton(painter, button.rect, button.label, {
            primary = button.id == "confirm" or button.id == "save" or button.id == "continue" or button.id == "copy",
            danger = button.id == "discard" or (modal.kind == "confirmDelete" and button.id == "confirm"),
        })
    end
end

function View.Draw(context, state)
    local painter, layout, controls = context.painter_, state.layout, state.controls
    nvgSave(painter.vg)
    local compensation = tonumber(layout.renderScaleCompensation) or 1
    if math.abs(compensation - 1) > 0.0001 then nvgScale(painter.vg, compensation, compensation) end
    if not layout.supported then
        drawUnsupported(painter, layout)
        nvgRestore(painter.vg)
        return
    end
    painter:FillRect(0, 0, layout.full.w, layout.full.h, COLORS.background)
    drawTop(painter, state, layout, controls)
    drawCanvas(painter, state, layout, controls)
    drawLeft(painter, state, layout, controls)
    drawInspector(painter, state, layout, controls)
    drawStatus(painter, state, layout)
    if state.hoverTooltip and not state.modal then
        local tooltip = state.hoverTooltip
        local width = math.min(560, math.max(150, #tooltip.text * 8 + 20))
        local x = clamp(tooltip.x, 10, layout.full.w - width - 10)
        local y = clamp(tooltip.y, 10, layout.full.h - 42)
        painter:RoundedRect(x, y, width, 32, 3, COLORS.top, COLORS.accent, 1)
        painter:Text(x + 10, y + 16, truncate(tooltip.text, 62), 14, COLORS.lightText,
            NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, "maker-body")
    end
    drawModal(painter, state, controls)
    if state.toast and (state.toastTime or 0) > 0 then
        local width = math.min(620, 32 + #state.toast * 14)
        local x, y = (layout.full.w - width) * 0.5, layout.full.h - 88
        painter:RoundedRect(x, y, width, 42, 4, COLORS.top, COLORS.accent, 1)
        painter:Text(x + width * 0.5, y + 21, truncate(state.toast, 60), 15, COLORS.lightText,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-body")
    end
    nvgRestore(painter.vg)
end

View.PointIn = pointIn
View.TYPE_LABELS = TYPE_LABELS

return View
