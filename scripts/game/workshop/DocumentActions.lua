local DocumentActions = {}

function DocumentActions.NewViewState()
    return {
        zoom = 1, panX = 0, panY = 0,
        showGrid = true, snap = true, gridSize = 10, angleSnap = 15,
        fileScroll = 0, fileScrollMax = 0,
        inspectorScroll = 0, inspectorScrollMax = 0,
        drawerMode = "files",
    }
end

function DocumentActions.FindObject(document, objectId)
    for _, object in ipairs(document and document.objects or {}) do
        if object.id == objectId then return object end
    end
    return nil
end

function DocumentActions.CreateCustom(repository, sourceEntryId, copyCurrent, inspector)
    local document, metadata
    if copyCurrent and sourceEntryId then
        document, metadata = repository:CopyAsCustom(sourceEntryId)
    else
        document, metadata = repository:CreateCustom("未命名实验")
    end
    if not document then return nil, nil, metadata or "创建失败" end
    inspector.EnsureCustomFields(document)
    local replaced, errorMessage = repository:ReplaceCustom(metadata.entryId, document)
    if not replaced then return nil, nil, errorMessage end
    return document, metadata, nil
end

function DocumentActions.PersistNewCustom(repository, draftStore, metadata, document)
    local saved, persistence = draftStore:SaveCustom(document)
    if saved then return true, persistence end
    repository:DeleteCustom(metadata.entryId)
    return false, persistence
end

function DocumentActions.ImportCustom(repository, draftStore, document, inspector)
    local imported, metadata = repository:ImportAsCustom(document)
    if not imported then return nil, metadata end
    inspector.EnsureCustomFields(imported)
    local replaced, replaceError = repository:ReplaceCustom(metadata.entryId, imported)
    if not replaced then
        repository:DeleteCustom(metadata.entryId)
        return nil, replaceError
    end
    local saved, persistence = DocumentActions.PersistNewCustom(
        repository, draftStore, metadata, imported)
    if not saved then return nil, persistence end
    return imported, metadata, persistence
end

function DocumentActions.DeleteCustom(repository, draftStore, entryId, levelId)
    local deleted, errorMessage = draftStore:DeleteCustom(levelId)
    if not deleted then return false, errorMessage end
    return repository:DeleteCustom(entryId)
end

function DocumentActions.AddObject(current, objectType, repository, levelDocument, typeLabels)
    if objectType == "launcher" or objectType == "goal_sensor" then
        for _, object in ipairs(current.document.objects) do
            if object.type == objectType then
                return nil, "关卡只能包含一个" .. (typeLabels[objectType] or objectType)
            end
        end
    end
    local id = repository:NextObjectId(current.document, objectType)
    local object = levelDocument.NewObject(objectType, id,
        current.document.playfield.width * 0.5, math.min(580, current.document.playfield.height) * 0.5)
    current.document.objects[#current.document.objects + 1] = object
    return object, nil
end

function DocumentActions.DeleteObject(document, objectId)
    for index, object in ipairs(document.objects or {}) do
        if object.id == objectId then
            table.remove(document.objects, index)
            return object
        end
    end
    return nil
end

function DocumentActions.DuplicateObject(current, repository, levelDocument, interaction)
    local selected = current.selectedObject
    if not selected then return nil, "未选择对象" end
    if selected.type == "launcher" or selected.type == "goal_sensor" then
        return nil, "发射器和观察皿不可重复"
    end
    local object = levelDocument.Clone(selected)
    object.id = repository:NextObjectId(current.document, object.type)
    object.name = object.name .. " 副本"
    object.transform.x, object.transform.y = interaction.ClampPosition(current.document, object,
        object.transform.x + 20, object.transform.y + 20)
    current.document.objects[#current.document.objects + 1] = object
    return object, nil
end

return DocumentActions
