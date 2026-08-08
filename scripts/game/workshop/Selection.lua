local Selection = {}

local function findObject(document, objectId)
    for _, object in ipairs(document and document.objects or {}) do
        if object.id == objectId then return object end
    end
    return nil
end

local function contains(values, target)
    for _, value in ipairs(values or {}) do
        if value == target then return true end
    end
    return false
end

function Selection.Clear(current)
    current.selectedObjectIds = {}
    current.selectedObjectId = nil
    current.selectedObjects = {}
    current.selectedObject = nil
    current.selectionCount = 0
    current.canDuplicateSelection = false
    current.marqueeRect = nil
end

function Selection.SetMany(current, objectIds, primaryId)
    local ids, seen = {}, {}
    for _, objectId in ipairs(objectIds or {}) do
        if type(objectId) == "string" and objectId ~= "" and not seen[objectId] then
            seen[objectId] = true
            ids[#ids + 1] = objectId
        end
    end
    if primaryId and seen[primaryId] and ids[#ids] ~= primaryId then
        for index = #ids, 1, -1 do
            if ids[index] == primaryId then table.remove(ids, index); break end
        end
        ids[#ids + 1] = primaryId
    end
    current.selectedObjectIds = ids
    current.selectedObjectId = ids[#ids]
    current.selectedObjects = {}
    current.selectedObject = nil
    current.selectionCount = #ids
end

function Selection.SetSingle(current, objectOrId)
    local objectId = type(objectOrId) == "table" and objectOrId.id or objectOrId
    if not objectId then Selection.Clear(current); return end
    Selection.SetMany(current, { objectId }, objectId)
    if type(objectOrId) == "table" then
        current.selectedObjects = { objectOrId }
        current.selectedObject = objectOrId
    end
end

function Selection.Contains(current, objectId)
    return contains(current.selectedObjectIds, objectId)
end

function Selection.Normalize(current, document)
    if not document then Selection.Clear(current); return {} end
    local ids = current.selectedObjectIds
    if type(ids) ~= "table" then ids = {} end

    -- Keep the pre-multiselect selectedObjectId surface compatible with callers and tests.
    if current.selectedObjectId and not contains(ids, current.selectedObjectId) then
        ids = { current.selectedObjectId }
    end

    local normalizedIds, objects, seen = {}, {}, {}
    for _, objectId in ipairs(ids) do
        if not seen[objectId] then
            local object = findObject(document, objectId)
            if object then
                seen[objectId] = true
                normalizedIds[#normalizedIds + 1] = objectId
                objects[#objects + 1] = object
            end
        end
    end

    local primaryId = current.selectedObjectId
    if primaryId and seen[primaryId] and normalizedIds[#normalizedIds] ~= primaryId then
        local primaryObject
        for index = #normalizedIds, 1, -1 do
            if normalizedIds[index] == primaryId then
                table.remove(normalizedIds, index)
                primaryObject = table.remove(objects, index)
                break
            end
        end
        normalizedIds[#normalizedIds + 1] = primaryId
        objects[#objects + 1] = primaryObject
    end

    current.selectedObjectIds = normalizedIds
    current.selectedObjects = objects
    current.selectedObjectId = normalizedIds[#normalizedIds]
    current.selectedObject = objects[#objects]
    current.selectionCount = #normalizedIds
    current.canDuplicateSelection = false
    for _, object in ipairs(objects) do
        if object.type ~= "launcher" and object.type ~= "goal_sensor" then
            current.canDuplicateSelection = true
            break
        end
    end
    return objects
end

function Selection.BeginMove(current, levelX, levelY)
    local objects = Selection.Normalize(current, current.document)
    if #objects == 0 then return nil end
    local positions = {}
    for _, object in ipairs(objects) do
        positions[#positions + 1] = {
            id = object.id,
            object = object,
            x = object.transform.x,
            y = object.transform.y,
        }
    end
    local primary = current.selectedObject or objects[#objects]
    return {
        kind = "moveGroup",
        startLevelX = levelX,
        startLevelY = levelY,
        primaryId = primary.id,
        primaryX = primary.transform.x,
        primaryY = primary.transform.y,
        positions = positions,
        changed = false,
    }
end

function Selection.UpdateMove(current, transaction, levelX, levelY, interaction)
    local deltaX = levelX - transaction.startLevelX
    local deltaY = levelY - transaction.startLevelY
    if current.view.snap then
        deltaX = interaction.Snap(transaction.primaryX + deltaX, current.view.gridSize) - transaction.primaryX
        deltaY = interaction.Snap(transaction.primaryY + deltaY, current.view.gridSize) - transaction.primaryY
    end
    deltaX, deltaY = interaction.ClampGroupDelta(current.document, transaction.positions, deltaX, deltaY)
    for _, position in ipairs(transaction.positions) do
        position.object.transform.x = position.x + deltaX
        position.object.transform.y = position.y + deltaY
    end
    transaction.changed = math.abs(deltaX) > 0.0001 or math.abs(deltaY) > 0.0001
    return transaction.changed
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function Selection.MarqueeRect(startX, startY, currentX, currentY, viewport)
    local x1 = clamp(startX, viewport.x, viewport.x + viewport.w)
    local y1 = clamp(startY, viewport.y, viewport.y + viewport.h)
    local x2 = clamp(currentX, viewport.x, viewport.x + viewport.w)
    local y2 = clamp(currentY, viewport.y, viewport.y + viewport.h)
    return {
        x = math.min(x1, x2),
        y = math.min(y1, y2),
        w = math.abs(x2 - x1),
        h = math.abs(y2 - y1),
    }
end

function Selection.MarqueeIds(document, canvasTransform, rect, interaction)
    local ids = {}
    for _, object in ipairs(document and document.objects or {}) do
        if interaction.ObjectIntersectsScreenRect(object, canvasTransform, rect) then
            ids[#ids + 1] = object.id
        end
    end
    return ids
end

local DRAG_THRESHOLD_SQUARED = 8 * 8

local function panTransaction(current, x, y)
    return { kind = "pan", startX = x, startY = y,
        panX = current.view.panX, panY = current.view.panY, changed = false }
end

function Selection.BeginCanvasGesture(current, pointerFrame, interaction, ctrlDown)
    local controls = current.controls
    local transform = controls.canvasTransform
    if not transform then return false end
    local x, y = pointerFrame.x, pointerFrame.y
    if current.selectedObject and (current.selectionCount or 0) == 1 and not current.readOnly then
        local handle = interaction.HitHandle(controls.handles, x, y)
        if handle then
            current.transaction = { kind = handle, objectId = current.selectedObject.id, changed = false }
            return true
        end
    end
    local levelX, levelY = interaction.ScreenToLevel(transform, x, y)
    local object = interaction.FindTopObject(current.document, levelX, levelY,
        5 / transform.objectScale, transform)
    if object then
        local alreadySelected = Selection.Contains(current, object.id)
        if not alreadySelected then Selection.SetSingle(current, object) else Selection.Normalize(current, current.document) end
        if current.layout.folded then current.view.drawerMode = "inspector" end
        if alreadySelected and (current.selectionCount or 0) > 1 then
            current.transaction = {
                kind = "pendingObject", objectId = object.id,
                startX = x, startY = y, startLevelX = levelX, startLevelY = levelY,
                panX = current.view.panX, panY = current.view.panY,
                readOnly = current.readOnly, changed = false,
            }
        elseif current.readOnly then
            current.transaction = panTransaction(current, x, y)
        else
            current.transaction = Selection.BeginMove(current, levelX, levelY)
        end
        return true
    end

    local tool = current.canvasTool == "marquee" and "marquee" or "pan"
    if not pointerFrame.isTouch and ctrlDown then tool = "marquee" end
    current.transaction = {
        kind = "pendingCanvas", tool = tool,
        startX = x, startY = y, panX = current.view.panX, panY = current.view.panY,
        changed = false,
    }
    return true
end

function Selection.UpdateCanvasGesture(current, pointerFrame, interaction)
    local transaction = current.transaction
    if not transaction or not pointerFrame.down then return nil end
    local deltaX, deltaY = pointerFrame.x - (transaction.startX or pointerFrame.x),
        pointerFrame.y - (transaction.startY or pointerFrame.y)

    if transaction.kind == "pendingCanvas" then
        if deltaX * deltaX + deltaY * deltaY <= DRAG_THRESHOLD_SQUARED then return nil end
        transaction.kind = transaction.tool
    elseif transaction.kind == "pendingObject" then
        if deltaX * deltaX + deltaY * deltaY <= DRAG_THRESHOLD_SQUARED then return nil end
        if transaction.readOnly then
            transaction.kind = "pan"
        else
            local move = Selection.BeginMove(current, transaction.startLevelX, transaction.startLevelY)
            current.transaction, transaction = move, move
        end
    end

    if transaction.kind == "pan" then
        current.view.panX = transaction.panX + pointerFrame.x - transaction.startX
        current.view.panY = transaction.panY + pointerFrame.y - transaction.startY
        transaction.changed = true
        return "view"
    end
    if transaction.kind == "marquee" then
        local rect = Selection.MarqueeRect(transaction.startX, transaction.startY,
            pointerFrame.x, pointerFrame.y, current.layout.canvasViewport)
        local ids = Selection.MarqueeIds(current.document, current.controls.canvasTransform, rect, interaction)
        current.marqueeRect = rect
        Selection.SetMany(current, ids, ids[#ids])
        Selection.Normalize(current, current.document)
        current.status = #ids > 0 and ("框选中 · " .. tostring(#ids) .. " 个对象") or "框选中 · 暂无对象"
        return "selection"
    end

    local transform = current.controls.canvasTransform
    if not transform then return nil end
    local levelX, levelY = interaction.ScreenToLevel(transform, pointerFrame.x, pointerFrame.y)
    if transaction.kind == "moveGroup" then
        Selection.UpdateMove(current, transaction, levelX, levelY, interaction)
    else
        local object = findObject(current.document, transaction.objectId)
        if not object then return nil end
        if transaction.kind == "resize" then
            object.transform.width, object.transform.height = interaction.ResizeFromPointer(current.document, object,
                levelX, levelY, 4, current.view.snap and current.view.gridSize or nil, transform)
            object.transform.x, object.transform.y = interaction.ClampPosition(current.document, object,
                object.transform.x, object.transform.y)
        elseif transaction.kind == "rotate" then
            object.transform.rotation = interaction.RotationFromPointer(object, levelX, levelY,
                current.view.snap and current.view.angleSnap or nil, transform)
            object.transform.x, object.transform.y = interaction.ClampPosition(current.document, object,
                object.transform.x, object.transform.y)
        end
        transaction.changed = true
    end
    Selection.Normalize(current, current.document)
    return "document"
end

function Selection.EndCanvasGesture(current)
    local transaction = current.transaction
    current.transaction = nil
    if not transaction then return nil end
    if transaction.kind == "pendingCanvas" then
        Selection.Clear(current)
        current.status = "未选择对象 · 显示关卡属性"
    elseif transaction.kind == "pendingObject" then
        Selection.SetSingle(current, transaction.objectId)
        Selection.Normalize(current, current.document)
        current.status = "已选择对象 " .. tostring(transaction.objectId)
    elseif transaction.kind == "marquee" then
        current.marqueeRect = nil
        current.status = (current.selectionCount or 0) > 0
            and ("已选择 " .. tostring(current.selectionCount) .. " 个对象")
            or "未选择对象 · 显示关卡属性"
    elseif transaction.changed and transaction.kind ~= "pan" then
        local count = current.selectionCount or 0
        return transaction.kind == "moveGroup" and count > 1
            and ("移动 " .. tostring(count) .. " 个对象") or "画布变换"
    end
    return nil
end

return Selection
