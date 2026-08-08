local PreviewSession = {}

local function clone(levelDocument, value)
    return levelDocument.Clone(value)
end

local function capture(context, levelDocument, current)
    return {
        document = clone(levelDocument, current.document),
        view = clone(levelDocument, current.view),
        entryId = current.entryId,
        metadata = clone(levelDocument, current.metadata),
        readOnly = current.readOnly,
        dirty = current.dirty,
        failureCountsByLevel = clone(levelDocument, context.failureCountsByLevel_),
        resultReportClearCounts = clone(levelDocument, context.resultReportClearCounts_),
        resultReportHistory = clone(levelDocument, context.resultReportHistory_),
        resultReportNextId = context.resultReportNextId_,
        levelIndex = context.levelIndex_,
    }
end

local function restore(context, levelDocument, current, snapshot)
    if not snapshot then return end
    current.document = clone(levelDocument, snapshot.document)
    current.view = clone(levelDocument, snapshot.view)
    current.entryId = snapshot.entryId
    current.metadata = clone(levelDocument, snapshot.metadata)
    current.readOnly, current.dirty = snapshot.readOnly, snapshot.dirty
    current.selectedObjectIds, current.selectedObjects = {}, {}
    current.selectedObjectId, current.selectedObject = nil, nil
    current.selectionCount, current.canDuplicateSelection = 0, false
    current.marqueeRect = nil
    context.failureCountsByLevel_ = clone(levelDocument, snapshot.failureCountsByLevel)
    context.resultReportClearCounts_ = clone(levelDocument, snapshot.resultReportClearCounts)
    context.resultReportHistory_ = clone(levelDocument, snapshot.resultReportHistory)
    context.resultReportNextId_ = snapshot.resultReportNextId
    context.levelIndex_ = snapshot.levelIndex
end

function PreviewSession.End(context, levelDocument, current)
    local snapshot = current.previewSnapshot
    if context.audioManager_ then context.audioManager_:leavePreview() end
    if context.scene_ or context.level_ then context.ReleaseLevelRuntime() end
    context.screen_ = "workshop"
    if renderer then renderer:SetNumViewports(0) end
    restore(context, levelDocument, current, snapshot)
    current.previewSnapshot = nil
    return true
end

function PreviewSession.Begin(context, levelDocument, current)
    current.previewSnapshot = capture(context, levelDocument, current)
    if context.audioManager_ then context.audioManager_:enterPreview() end
    current.modal, current.textEdit, current.transaction = nil, nil, nil
    local ok, session, errorMessage = pcall(context.StartRuntimeSessionFromDocument, current.document, {
        sourceKind = "workshop-preview",
        screen = "workshop_preview",
        enablePhysicsProbe = false,
        notifyAssistant = false,
        notifyDialogue = false,
    })
    if not ok or not session then
        local failure = tostring(ok and errorMessage or session)
        PreviewSession.End(context, levelDocument, current)
        return false, failure
    end
    return true, nil
end

return PreviewSession
