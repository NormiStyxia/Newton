local Repository = require("game.workshop.Repository")
local History = require("game.workshop.History")
local DraftStore = require("game.workshop.DraftStore")
local CustomLevelCloudSync = require("game.workshop.CustomLevelCloudSync")
local DraftCloudSync = require("game.workshop.DraftCloudSync")
local Export = require("game.workshop.Export")
local Layout = require("game.workshop.Layout")
local Interaction = require("game.workshop.Interaction")
local Selection = require("game.workshop.Selection")
local View = require("game.workshop.View")
local Inspector = require("game.workshop.Inspector")
local DocumentActions = require("game.workshop.DocumentActions")
local TextTransfer = require("game.workshop.TextTransfer")
local TextEditor = require("game.workshop.TextEditor")
local Numeric = require("game.workshop.Numeric")
local TouchScroller = require("game.workshop.TouchScroller")
local PreviewSession = require("game.workshop.PreviewSession")
local SemanticActions = require("game.input.SemanticActions")
local M = {}
local function clone(levelDocument, value) return levelDocument.Clone(value) end
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end
local function nowText(timestamp)
    timestamp = tonumber(timestamp)
    if not timestamp or not os or not os.date then return "未知时间" end
    local ok, result = pcall(os.date, "%Y-%m-%d %H:%M:%S", timestamp)
    return ok and result or tostring(timestamp)
end
---@param context GameContext
function M.Install(context)
    local LevelData = context.LevelData
    local LevelDocument = context.LevelDocument
    local Rules = context.Rules
    local CONFIG = context.CONFIG
    local _ENV = context
    local function state() return context.workshopState_ end
    local function toast(message, duration)
        local current = state()
        current.toast, current.toastTime = tostring(message), duration or 2.8
        current.status = tostring(message)
    end
    local function refreshEntries() state().entries = state().repository:List() end
    local function refreshCatalog(preferredEntryId)
        if context.RefreshExperimentCatalogCustomLevels then
            context.RefreshExperimentCatalogCustomLevels(preferredEntryId)
        end
    end
    local function persistRemoteRecord(record, mode)
        local current = state()
        if not current.repository or type(record) ~= "table" then return end
        local localEntry = current.repository:FindByLevelId(record.localLevelId)
        if mode == "delete" then
            if current.document and current.document.levelId == record.localLevelId and current.dirty then
                record.syncState = "conflict"
                record.remoteDeleted = true
                return
            end
            if localEntry and localEntry.sourceKind == "custom" then
                local deleted, deleteError = current.draftStore:DeleteCustom(record.localLevelId)
                if not deleted then print("[WorkshopCloud] 云端删除未能清理本地文件：" .. tostring(deleteError)) end
                current.repository:DeleteCustom(localEntry.entryId)
                refreshEntries()
                refreshCatalog()
            end
            return
        end
        local remoteDocument = mode == "conflict" and record.remoteDocument or record.document
        if type(remoteDocument) ~= "table" then return end
        local report = LevelDocument.ValidateDetailed(remoteDocument)
        if not report.valid then
            print("[WorkshopCloud] 忽略无效云实验：" .. report.errors[1].message)
            return
        end
        local document = clone(LevelDocument, remoteDocument)
        local existing = current.repository:FindByLevelId(document.levelId)
        if existing and (mode == "new" or mode == "conflict") then
            document.levelId = current.repository:NextCustomLevelId()
            document.name = (document.name or "未命名实验") .. "（云端副本）"
            existing = nil
        end
        local metadata
        if existing and existing.sourceKind == "custom" then
            local replaced, replaceError = current.repository:ReplaceCustom(existing.entryId, document, record.updatedAt)
            if not replaced then
                print("[WorkshopCloud] 云实验更新失败：" .. tostring(replaceError))
                return
            end
            metadata = current.repository:GetEntry(existing.entryId)
        else
            metadata = current.repository:RestoreCustom(document, record.updatedAt, { normalizeTransform = false })
            if not metadata then return end
        end
        local saved, persistence = current.draftStore:SaveCustom(document, {
            cloudEntityId = record.entityId,
            syncRevision = record.remoteRevision,
            syncState = mode == "conflict" and "conflictCopy" or "synced",
        })
        if not saved then
            print("[WorkshopCloud] 云实验本地保存失败：" .. tostring(persistence))
            return
        end
        refreshEntries()
        refreshCatalog(metadata and metadata.entryId or nil)
    end
    local function persistRemoteDraft(envelope)
        local current = state()
        if not current.draftStore or type(envelope) ~= "table" or type(envelope.document) ~= "table" then return end
        if current.document and current.document.levelId == envelope.levelId and current.dirty then
            print("[WorkshopCloud] 当前关卡正在编辑，保留本地草稿")
            return
        end
        local restored, result = current.draftStore:RestoreDraft(envelope)
        if not restored then
            print("[WorkshopCloud] 云草稿恢复失败：" .. tostring(result))
            return
        end
        if result.restored and current.document and current.document.levelId == envelope.levelId
            and not current.modal then
            current.modal = {
                kind = "recovery",
                title = "发现云端未完成草稿",
                message = string.format("%s\n最后同步：%s\n可继续、放弃，或另存为新关卡。",
                    envelope.document.name or envelope.levelId, nowText(envelope.updatedAt)),
                draft = clone(LevelDocument, envelope),
            }
        end
    end
    local function refreshSelection()
        local current = state()
        Selection.Normalize(current, current.document)
    end
    local function refreshValidation()
        local current = state()
        current.validation = current.document and LevelDocument.ValidateDetailed(current.document)
            or { valid = false, errors = {}, warnings = {} }
        if current.validation and #current.validation.errors > 0 then
            current.status = current.validation.errors[1].path .. "：" .. current.validation.errors[1].message
        end
    end
    local function refreshHistoryFlags()
        local current = state()
        current.canUndo = current.history and current.history:CanUndo() or false
        current.canRedo = current.history and current.history:CanRedo() or false
    end
    local function markDraftCloudDirty(current)
        current.cloudDraftRevision = (current.cloudDraftRevision or 0) + 1
        if not current.cloudDraftSyncDue then
            current.cloudDraftSyncDue = current.elapsed + (current.cloudDraftSyncInterval or 30)
        end
    end
    local function markChanged(label)
        local current = state()
        current.dirty = true
        current.autoSaveDue = current.elapsed + current.autoSaveDelay
        markDraftCloudDirty(current)
        current.history:Push(current.document, current.view, label)
        refreshSelection()
        refreshValidation()
        refreshHistoryFlags()
        current.status = label .. " · 待保存"
    end
    local function editable()
        local current = state()
        if current.readOnly then
            toast("官方关卡为只读，请先复制为自定义关卡")
            return false
        end
        return current.document ~= nil
    end
    local function buildInspectorFields()
        local current = state()
        current.inspectorFields = Inspector.Build(current, LevelDocument, Rules, View.TYPE_LABELS)
    end
    local function rebuildUI()
        local current = state()
        refreshEntries()
        refreshSelection()
        buildInspectorFields()
        current.layout = Layout.Resolve(frame_, current.view, current.layoutConfig)
        current.controls = View.BuildControls(current, current.layout, Interaction)
        refreshHistoryFlags()
    end
    local function saveDraft(reason)
        local current = state()
        if not current.document or current.readOnly or not current.dirty then return true end
        local ok, result = current.draftStore:SaveDraft(current.document.levelId, current.document, current.view, "custom")
        if not ok then toast("草稿保存失败：" .. tostring(result)); return false end
        current.lastDraftSaveAt = result.updatedAt
        current.status = result.persisted and (reason or "草稿已自动保存")
            or ((reason or "草稿已保存在运行内存") .. " · 本地槽位不可用")
        return true
    end
    local function syncDraftToCloud(reason, draftAlreadySaved)
        local current = state()
        if not current.document or current.readOnly or not current.dirty then return true end
        if not draftAlreadySaved and not saveDraft() then return false end
        local envelope, loadError = current.draftStore:LoadDraft(current.document.levelId)
        if not envelope then
            current.cloudDraftSyncDue = current.elapsed + (current.cloudDraftSyncInterval or 30)
            current.status = "云草稿同步未启动：" .. tostring(loadError)
            return false
        end
        local levelId = current.document.levelId
        local revision = current.cloudDraftRevision or 0
        current.cloudDraftSyncDue = nil
        local queued, queueError = current.draftCloudSync:QueueSave(envelope, function(ok, errorMessage)
            local latest = state()
            if ok then
                latest.cloudDraftSyncedRevision = math.max(latest.cloudDraftSyncedRevision or 0, revision)
                if latest.document and latest.document.levelId == levelId and latest.dirty
                    and (latest.cloudDraftRevision or 0) <= revision then
                    latest.status = reason or "草稿已自动同步云端"
                end
            else
                print("[WorkshopCloud] 云草稿同步失败：" .. tostring(errorMessage))
            end
            if latest.document and latest.document.levelId == levelId and latest.dirty
                and (latest.cloudDraftRevision or 0) > (latest.cloudDraftSyncedRevision or 0)
                and not latest.cloudDraftSyncDue then
                latest.cloudDraftSyncDue = latest.elapsed + (latest.cloudDraftSyncInterval or 30)
            end
        end)
        if not queued then
            current.cloudDraftSyncDue = current.elapsed + (current.cloudDraftSyncInterval or 30)
            current.status = "草稿已保存在本地 · 云同步未启动：" .. tostring(queueError)
            return false
        end
        current.status = "草稿已保存 · 正在同步云端"
        return true
    end
    local function saveDraftAndSync(reason)
        if not saveDraft(reason) then return false end
        syncDraftToCloud(reason or "草稿已同步云端", true)
        return true
    end
    local function deleteCloudDraft(levelId)
        local current = state()
        if not current.draftCloudSync then return false end
        local queued, errorMessage = current.draftCloudSync:QueueDelete(levelId, function(ok, reason)
            if not ok then print("[WorkshopCloud] 云草稿删除失败：" .. tostring(reason)) end
        end)
        if not queued and errorMessage ~= "云草稿服务不可用" then
            print("[WorkshopCloud] 云草稿删除未启动：" .. tostring(errorMessage))
        end
        return queued
    end
    local function openEntryNow(entryId, options)
        options = options or {}
        local current = state()
        local document, metadata = current.repository:Open(entryId)
        if not document then toast(metadata or "关卡不存在"); return false end
        current.entryId, current.metadata = entryId, metadata
        current.readOnly = metadata.readOnly == true
        if not current.readOnly then Inspector.EnsureCustomFields(document) end
        current.document = document
        Selection.Clear(current)
        current.view = options.viewState and clone(LevelDocument, options.viewState) or DocumentActions.NewViewState()
        if current.layout and current.layout.folded then current.view.drawerMode = "files" end
        current.dirty = options.dirty == true
        current.cloudDraftRevision = current.dirty and 1 or 0
        current.cloudDraftSyncedRevision = 0
        current.cloudDraftSyncDue = current.dirty
            and current.elapsed + (current.cloudDraftSyncInterval or 30) or nil
        current.transaction, current.touchScroll, current.textEdit = nil, nil, nil
        current.history:Reset(current.document, current.view, "打开关卡")
        refreshValidation()
        refreshHistoryFlags()
        current.status = current.readOnly and "官方关卡只读 · 可复制为自定义关卡" or "自定义关卡已打开"
        rebuildUI()

        if not current.readOnly and not options.skipRecovery then
            local draft = current.draftStore:LoadDraft(current.document.levelId)
            if draft and type(draft.document) == "table" then
                current.modal = {
                    kind = "recovery",
                    title = "发现未完成草稿",
                    message = string.format("%s\n最后编辑：%s\n可继续、放弃，或另存为新关卡。",
                        draft.document.name or draft.levelId, nowText(draft.updatedAt)),
                    draft = draft,
                }
            end
        end
        return true
    end
    local function switchEntry(entryId)
        local current = state()
        if entryId == current.entryId then return true end
        if current.dirty then
            current.modal = {
                kind = "dirtySwitch", title = "当前关卡有未保存修改",
                message = "切换前请选择如何处理当前修改。",
                targetEntryId = entryId,
            }
            return false
        end
        return openEntryNow(entryId)
    end
    function InitializeLevelWorkshop()
        local current = state()
        current.selectedObjectIds = current.selectedObjectIds or {}
        current.selectedObjects = current.selectedObjects or {}
        current.selectionCount = current.selectionCount or 0
        current.canDuplicateSelection = current.canDuplicateSelection == true
        current.canvasTool = current.canvasTool == "marquee" and "marquee" or "pan"
        current.marqueeRect = nil
        if current.initialized then return true end
        local adapter = DraftStore.CreateLocalAdapter()
        current.repository = Repository.New({ LevelDocument = LevelDocument })
        current.history = History.New({ clone = LevelDocument.Clone, limit = 100 })
        current.draftStore = DraftStore.New({ clone = LevelDocument.Clone, json = cjson, adapter = adapter })
        current.persistenceKind = current.draftStore:PersistenceKind()
        local syncState = current.draftStore:LoadSyncState()
        current.cloudSync = CustomLevelCloudSync.New({
            draftStore = current.draftStore,
            levelDocument = LevelDocument,
            json = cjson,
            state = type(syncState) == "table" and syncState or nil,
            onRemoteRecord = persistRemoteRecord,
        })
        current.draftCloudSync = DraftCloudSync.New({
            levelDocument = LevelDocument,
            json = cjson,
        })
        current.supportedTypes = LevelDocument.SupportedTypes()
        current.initializationErrors = current.repository:InitializeOfficial(CONFIG.levelCount, function(index)
            local document, errorMessage = LevelData.Load(string.format("Data/Levels/level_%02d.json", index))
            if not document then error(errorMessage) end
            return document
        end)
        for _, envelope in ipairs(current.draftStore:LoadCustomLevels()) do
            local metadata, errorMessage = current.repository:RestoreCustom(envelope.document, envelope.updatedAt,
                { normalizeTransform = false })
            if metadata then
                current.cloudSync:RegisterLocal(envelope.document, envelope)
            else
                current.initializationErrors[#current.initializationErrors + 1] = errorMessage
            end
        end
        current.initialized = true
        refreshEntries()
        current.cloudSync:Refresh(function(ok, errorMessage)
            if ok then
                print("[WorkshopCloud] 同账号自制实验同步完成")
            else
                print("[WorkshopCloud] 使用本地自制实验：" .. tostring(errorMessage))
            end
        end)
        current.draftCloudSync:Refresh(function(ok, draftsOrError)
            if ok then
                for _, envelope in pairs(draftsOrError or {}) do persistRemoteDraft(envelope) end
                print("[WorkshopCloud] 同账号关卡草稿同步完成")
            else
                print("[WorkshopCloud] 使用本地关卡草稿：" .. tostring(draftsOrError))
            end
        end)
        return #current.initializationErrors == 0
    end
    function OpenLevelWorkshop(selectedLevelId)
        InitializeLevelWorkshop()
        if scene_ or level_ then ReleaseLevelRuntime() end
        renderer:SetNumViewports(0)
        local current = state()
        current.returnScreen = screen_ == "title" and "title" or "catalog"
        screen_ = "workshop"
        current.canvasTool = "pan"
        local entryId = nil
        if type(selectedLevelId) == "string" and selectedLevelId:find(":", 1, true) then
            entryId = selectedLevelId
        elseif selectedLevelId then
            entryId = "official:" .. tostring(selectedLevelId)
        end
        if not entryId or not current.repository:GetEntry(entryId) then
            entryId = current.entries[1] and current.entries[1].entryId or nil
        end
        if not entryId then toast("没有可用关卡"); return false end
        openEntryNow(entryId)
        if #current.initializationErrors > 0 then
            toast("部分关卡未载入：" .. current.initializationErrors[1], 5)
        end
        return true
    end
    function SaveWorkshopCurrent()
        local current = state()
        if not editable() then return false end
        local report = LevelDocument.ValidateDetailed(current.document)
        current.validation = report
        if not report.valid then toast("校验失败：" .. report.errors[1].message, 4); return false end
        local replaced, replaceError = current.repository:ReplaceCustom(current.entryId, current.document, os.time())
        if not replaced then toast("保存失败：" .. tostring(replaceError)); return false end
        local ok, persistence = current.draftStore:SaveCustom(current.document)
        if not ok then toast("保存失败：" .. tostring(persistence)); return false end
        local cloudQueued, cloudError = current.cloudSync:QueueSave(current.document)
        local draftDeleted, draftDeleteError = current.draftStore:DeleteDraft(current.document.levelId)
        deleteCloudDraft(current.document.levelId)
        current.dirty, current.autoSaveDue = false, nil
        current.cloudDraftSyncDue = nil
        current.cloudDraftRevision, current.cloudDraftSyncedRevision = 0, 0
        current.persistenceKind = current.draftStore:PersistenceKind()
        refreshEntries()
        if not draftDeleted then
            toast("关卡已保存，但旧草稿清理失败：" .. tostring(draftDeleteError), 5)
        elseif cloudQueued then
            toast(persistence.persisted and "关卡已保存，正在同步到云端"
                or "关卡已保存在运行内存，正在同步到云端")
        else
            toast((persistence.persisted and "关卡已保存到本地槽位" or "关卡已保存在运行内存")
                .. " · 云同步未启动：" .. tostring(cloudError), 5)
        end
        return true
    end
    local function createCustom(copyCurrent)
        local current = state()
        local document, metadata, errorMessage = DocumentActions.CreateCustom(
            current.repository, current.entryId, copyCurrent, Inspector)
        if not document then toast(errorMessage); return false end
        local saved, persistence = DocumentActions.PersistNewCustom(
            current.repository, current.draftStore, metadata, document)
        if not saved then
            refreshEntries()
            toast("创建失败：" .. tostring(persistence))
            return false
        end
        current.persistenceKind = current.draftStore:PersistenceKind()
        current.cloudSync:RegisterLocal(document)
        current.cloudSync:QueueSave(document)
        current.dirty = false
        refreshEntries()
        openEntryNow(metadata.entryId, { skipRecovery = true })
        state().dirty = true
        state().autoSaveDue = state().elapsed + state().autoSaveDelay
        markDraftCloudDirty(state())
        state().history:Push(state().document, state().view, copyCurrent and "复制关卡" or "新建关卡")
        refreshHistoryFlags()
        toast(copyCurrent and "已创建可编辑副本" or "已创建新关卡")
        return true
    end

    local function deleteCurrent()
        local current = state()
        if current.readOnly then toast("官方关卡不能删除"); return false end
        local levelId = current.document.levelId
        local entityId = current.cloudSync:FindEntityId(levelId)
        local ok, errorMessage = DocumentActions.DeleteCustom(current.repository, current.draftStore,
            current.entryId, levelId)
        if not ok then toast(errorMessage); return false end
        if entityId then current.cloudSync:QueueDelete(entityId) end
        deleteCloudDraft(levelId)
        current.modal, current.dirty = nil, false
        refreshEntries()
        local target = current.entries[1] and current.entries[1].entryId
        if target then openEntryNow(target, { skipRecovery = true }) end
        toast("自定义关卡已删除")
        return true
    end
    local function undo()
        local current = state()
        if current.readOnly then return end
        local document, viewState = current.history:Undo()
        if not document then return end
        current.document, current.view = document, viewState
        current.dirty, current.textEdit = true, nil
        current.autoSaveDue = current.elapsed + current.autoSaveDelay
        markDraftCloudDirty(current)
        refreshSelection(); refreshValidation(); rebuildUI()
        current.status = "已撤销"
    end
    local function redo()
        local current = state()
        if current.readOnly then return end
        local document, viewState = current.history:Redo()
        if not document then return end
        current.document, current.view = document, viewState
        current.dirty, current.textEdit = true, nil
        current.autoSaveDue = current.elapsed + current.autoSaveDelay
        markDraftCloudDirty(current)
        refreshSelection(); refreshValidation(); rebuildUI()
        current.status = "已重做"
    end
    local function addObject(objectType)
        local current = state()
        if not editable() then return end
        local object, errorMessage = DocumentActions.AddObject(current, objectType,
            current.repository, LevelDocument, View.TYPE_LABELS)
        if not object then toast(errorMessage); return end
        Selection.SetSingle(current, object)
        markChanged("新增" .. (View.TYPE_LABELS[objectType] or objectType))
        if current.layout.folded then current.view.drawerMode = "inspector" end
        rebuildUI()
    end
    local function deleteSelected()
        local current = state()
        if not editable() or (current.selectionCount or 0) == 0 then return end
        local removed = DocumentActions.DeleteObjects(current.document, current.selectedObjectIds)
        if #removed == 0 then return end
        Selection.Clear(current)
        markChanged(#removed > 1 and ("删除 " .. tostring(#removed) .. " 个对象") or "删除对象")
        rebuildUI()
    end
    local function duplicateSelected()
        local current = state()
        if not editable() or (current.selectionCount or 0) == 0 then return end
        local objects, skipped, errorMessage = DocumentActions.DuplicateObjects(current, current.repository,
            LevelDocument, Interaction, current.selectedObjects)
        if #objects == 0 then toast(errorMessage or "没有可复制的对象"); return end
        local objectIds = {}
        for _, object in ipairs(objects) do objectIds[#objectIds + 1] = object.id end
        Selection.SetMany(current, objectIds, objectIds[#objectIds])
        markChanged(#objects > 1 and ("复制 " .. tostring(#objects) .. " 个对象") or "复制对象")
        if skipped > 0 then toast("已复制 " .. tostring(#objects) .. " 个对象，跳过 " .. tostring(skipped) .. " 个不可复制对象") end
        rebuildUI()
    end

    local function beginTextEdit(field, value, mode)
        if field and field.editable == false then return end
        local current = state()
        current.textEdit = TextEditor.Begin(field, value, mode, current.elapsed, Export.MAX_JSON_BYTES)
        if input then input:SetScreenKeyboardVisible(true) end
    end

    local function cancelTextEdit()
        state().textEdit = nil
        if input then input:SetScreenKeyboardVisible(false) end
    end

    local function commitTextEdit()
        local current = state()
        local edit = current.textEdit
        if not edit then return true end
        if edit.mode == "rename" then
            local value = edit.value
            if value == "" then toast("关卡名称不能为空"); return false end
            current.modal = nil
            cancelTextEdit()
            current.document.name = value
            markChanged("重命名关卡")
            rebuildUI()
            return true
        end
        if edit.mode == "import" then return false end
        local field = edit.field
        if not field or not field.set then cancelTextEdit(); return false end
        local value = edit.value
        if field.kind == "number" then
            value = tonumber(value)
            value = Numeric.NormalizeInspectorValue(field.key, value)
            if value == nil then toast("请输入有效数值"); return false end
        end
        field.set(value)
        cancelTextEdit()
        markChanged("修改" .. field.label)
        rebuildUI()
        return true
    end

    function HandleWorkshopTextInput(_eventType, eventData)
        local current = state()
        if screen_ ~= "workshop" or not current.textEdit then return end
        local text = eventData:GetString("Text")
        if type(text) ~= "string" or text == "" then return end
        local edit = current.textEdit
        local accepted, errorMessage = TextTransfer.AppendInput(edit, text,
            edit.maxLength or Export.MAX_JSON_BYTES)
        if accepted then
            TextEditor.ResetBlink(edit, current.elapsed)
            if edit.mode == "import" and current.modal then
                current.modal.text = edit.value
                current.modal.scroll = 0
                current.modal.receivedTextInput = true
            end
        else
            toast(errorMessage, 5)
        end
    end

    local function pasteImportClipboard()
        local current = state()
        local edit = current.textEdit
        if not edit or edit.mode ~= "import" then return false end
        if TextTransfer.GetClipboardMode(ui) ~= "direct" then
            toast("请保持导入窗口激活，然后按 Ctrl+V 或使用系统长按粘贴", 5)
            return true
        end
        local text, errorMessage = TextTransfer.ReadClipboard(ui, Export.MAX_JSON_BYTES)
        if not text then toast("无法粘贴：" .. tostring(errorMessage), 5); return false end
        edit.value, edit.clipboardEchoRemaining = text, text
        TextEditor.Initialize(edit, false, current.elapsed)
        if current.modal then current.modal.text, current.modal.scroll = text, 0 end
        rebuildUI()
        toast("已从系统剪贴板读取 JSON 文本")
        return true
    end

    local function updateTextEditKeys(pointerFrame)
        local current = state()
        local edit = current.textEdit
        if not edit then return false end
        local navigationCancel = SemanticActions.Find(pointerFrame, SemanticActions.CANCEL, "navigation")
        if navigationCancel then
            SemanticActions.Consume(navigationCancel, "WorkshopTextEdit")
            if current.modal and (edit.mode == "rename" or edit.mode == "import") then current.modal = nil end
            cancelTextEdit()
            return true
        end
        local directClipboard = TextTransfer.GetClipboardMode(ui) == "direct"
        local keyAction = TextEditor.KeyAction(edit, input, current.elapsed, directClipboard)
        if keyAction == "paste" then pasteImportClipboard()
        elseif keyAction == "cancel" then
            if current.modal and (edit.mode == "rename" or edit.mode == "import") then current.modal = nil end
            cancelTextEdit()
        elseif keyAction == "commit" then commitTextEdit() end
        return true
    end

    local function cycleEnum(field)
        local options = field.options or {}
        local index = 0
        for candidate, value in ipairs(options) do if value == field.value then index = candidate end end
        index = index % math.max(1, #options) + 1
        field.set(options[index])
        markChanged("修改" .. field.label)
        rebuildUI()
    end

    local function openExport()
        local current = state()
        local payload, errorMessage = Export.Prepare(current.document, LevelDocument, cjson)
        if not payload then toast("导出失败：" .. tostring(errorMessage), 4); return end
        current.modal = { kind = "export", title = "导出 JSON", payload = payload, scroll = 0 }
        rebuildUI()
    end

    local function copyExport()
        local current = state()
        local text = current.modal and current.modal.payload and current.modal.payload.text
        if not text then return end
        local ok = TextTransfer.WriteClipboard(ui, text)
        if ok then toast("JSON 已复制到系统剪贴板")
        else toast("剪贴板未确认写入；完整 JSON 仍保留在导出面板", 5) end
    end

    local function openImport()
        local current = state()
        local clipboardMode = TextTransfer.GetClipboardMode(ui)
        current.modal = {
            kind = "import",
            title = "导入 JSON",
            text = "",
            scroll = 0,
            maxBytes = Export.MAX_JSON_BYTES,
            clipboardMode = clipboardMode,
        }
        beginTextEdit(nil, "", "import")
        rebuildUI()
    end

    local function confirmImport()
        local current = state()
        local text = current.textEdit and current.textEdit.value or ""
        local document, errorMessage = Export.Deserialize(text, LevelData)
        if not document then toast("导入失败：" .. tostring(errorMessage), 5); return false end
        local imported, metadata, persistence = DocumentActions.ImportCustom(
            current.repository, current.draftStore, document, Inspector)
        if not imported then refreshEntries(); toast("导入失败：" .. tostring(metadata), 5); return false end
        cancelTextEdit(); current.modal = nil
        refreshEntries()
        openEntryNow(metadata.entryId, { skipRecovery = true })
        state().dirty, state().autoSaveDue = false, nil
        state().persistenceKind = state().draftStore:PersistenceKind()
        local cloudQueued, cloudError = state().cloudSync:QueueSave(imported)
        if not cloudQueued and cloudError == "同步正在进行" then
            state().cloudSync:RegisterLocal(imported)
            cloudQueued = true
        end
        toast(cloudQueued and "JSON 已导入并正在同步到云端"
            or "JSON 已导入到本地，但云同步未启动：" .. tostring(cloudError))
        return true
    end

    function BeginWorkshopPreview()
        local current = state()
        if not current.document then return false end
        local report = LevelDocument.ValidateDetailed(current.document)
        current.validation = report
        if not report.valid then toast("无法预览：" .. report.errors[1].message, 5); return false end
        saveDraftAndSync("预览前草稿已同步云端")
        Selection.Clear(current)
        local started, errorMessage = PreviewSession.Begin(context, LevelDocument, current)
        if not started then
            refreshSelection(); refreshValidation(); rebuildUI()
            toast("预览启动失败：" .. tostring(errorMessage), 5)
            return false
        end
        return true
    end

    function ExitWorkshopPreview(reason)
        local current = state()
        PreviewSession.End(context, LevelDocument, current)
        refreshSelection(); refreshValidation(); rebuildUI()
        current.status = reason == "complete" and "预览已完成 · 编辑数据未被运行状态污染" or "已退出预览并恢复编辑快照"
        return true
    end
    local function finishWorkshopExit()
        local current = state()
        screen_ = current.returnScreen == "title" and "title" or "catalog"
        renderer:SetNumViewports(0)
        Selection.Clear(current)
        current.canvasTool = "pan"
        current.modal, current.textEdit, current.transaction = nil, nil, nil
        if screen_ == "catalog" and context.RefreshExperimentCatalogCustomLevels then
            local preferredEntryId = current.metadata and current.metadata.sourceKind == "custom"
                and current.entryId or nil
            context.RefreshExperimentCatalogCustomLevels(preferredEntryId)
        end
        return true
    end
    local function leaveWorkshop()
        local current = state()
        if current.dirty then
            current.modal = { kind = "dirtySwitch", title = "退出关卡工坊",
                message = "当前关卡有未保存修改，请选择保存、放弃或取消。", targetExit = true }
            rebuildUI()
            return false
        end
        return finishWorkshopExit()
    end
    local function finishDirtyAction(action)
        local current = state()
        local modal = current.modal
        if action == "cancel" then current.modal = nil; rebuildUI(); return end
        if action == "save" and not saveDraftAndSync("草稿已同步云端") then return end
        if action == "save" then
            current.dirty, current.autoSaveDue, current.cloudDraftSyncDue = false, nil, nil
        end
        if action == "discard" then
            if current.document and not current.readOnly then
                local deleted, errorMessage = current.draftStore:DeleteDraft(current.document.levelId)
                if not deleted then toast("放弃失败：" .. tostring(errorMessage), 5); return end
                deleteCloudDraft(current.document.levelId)
            end
            current.dirty = false
        end
        local target, targetExit = modal.targetEntryId, modal.targetExit
        current.modal = nil
        if targetExit then
            finishWorkshopExit()
        elseif target then
            openEntryNow(target, { skipRecovery = action == "discard" })
        end
    end
    local function handleRecovery(action)
        local current = state()
        local draft = current.modal.draft
        if action == "continue" then
            local normalized = LevelDocument.Normalize(draft.document)
            current.document = normalized
            Inspector.EnsureCustomFields(current.document)
            current.view = type(draft.viewState) == "table" and clone(LevelDocument, draft.viewState)
                or DocumentActions.NewViewState()
            current.dirty = true
            current.autoSaveDue = current.elapsed + current.autoSaveDelay
            markDraftCloudDirty(current)
            current.history:Reset(current.document, current.view, "恢复草稿")
            current.status = "已恢复未完成草稿"
        elseif action == "discard" then
            local deleted, errorMessage = current.draftStore:DeleteDraft(current.document.levelId)
            if not deleted then toast("放弃草稿失败：" .. tostring(errorMessage), 5); return end
            deleteCloudDraft(current.document.levelId)
            current.status = "草稿已放弃"
        elseif action == "saveAs" then
            local imported, metadata = current.repository:ImportAsCustom(draft.document, (draft.document.name or "未命名实验") .. " 恢复副本")
            if not imported then toast(metadata); return end
            local saved, persistence = DocumentActions.PersistNewCustom(
                current.repository, current.draftStore, metadata, imported)
            if not saved then
                toast("草稿另存失败：" .. tostring(persistence), 5)
                return
            end
            local deleted, errorMessage = current.draftStore:DeleteDraft(draft.levelId)
            if not deleted then toast("恢复副本已保存，但旧草稿清理失败：" .. tostring(errorMessage), 5) end
            deleteCloudDraft(draft.levelId)
            current.modal = nil; refreshEntries(); openEntryNow(metadata.entryId, { skipRecovery = true })
            state().dirty = true; state().history:Push(state().document, state().view, "草稿另存")
            state().cloudSync:QueueSave(imported)
            state().autoSaveDue = state().elapsed + state().autoSaveDelay
            markDraftCloudDirty(state())
            rebuildUI(); return
        end
        current.modal = nil
        refreshSelection(); refreshValidation(); rebuildUI()
    end
    local function handleModalButton(id)
        local current = state()
        local modal = current.modal
        if not modal then return end
        playUIClick()
        if modal.kind == "dirtySwitch" then finishDirtyAction(id)
        elseif modal.kind == "recovery" then handleRecovery(id)
        elseif modal.kind == "confirmDelete" then if id == "confirm" then deleteCurrent() else current.modal = nil; rebuildUI() end
        elseif modal.kind == "rename" then if id == "confirm" then commitTextEdit() else current.modal = nil; cancelTextEdit(); rebuildUI() end
        elseif modal.kind == "import" then
            if id == "confirm" then confirmImport()
            elseif id == "paste" then pasteImportClipboard()
            else current.modal = nil; cancelTextEdit(); rebuildUI() end
        elseif modal.kind == "export" then if id == "copy" then copyExport() else current.modal = nil; rebuildUI() end
        else current.modal = nil; rebuildUI() end
    end

    local function isControlEnabled(id, current)
        if id == "save" or id == "draft" then return not current.readOnly and current.document ~= nil end
        if id == "undo" then return current.canUndo == true end
        if id == "redo" then return current.canRedo == true end
        if id == "copyObject" then return current.canDuplicateSelection == true and not current.readOnly end
        if id == "preview" or id == "export" then return current.document ~= nil end
        if id == "file_rename" or id == "file_delete" then
            return current.document ~= nil and not current.readOnly
        end
        if id == "file_copy" then return current.document ~= nil end
        if id == "deleteObject" then
            return current.document ~= nil and (current.selectionCount or 0) > 0 and not current.readOnly
        end
        return true
    end

    local function handleControl(id)
        local current = state()
        if not isControlEnabled(id, current) then return false end
        playUIClick()
        if id == "exit" then leaveWorkshop()
        elseif id == "draft" then
            if editable() and saveDraftAndSync("草稿已手动同步云端") then toast("草稿已保存") end
        elseif id == "save" then SaveWorkshopCurrent()
        elseif id == "export" then openExport()
        elseif id == "import" then openImport()
        elseif id == "undo" then undo()
        elseif id == "redo" then redo()
        elseif id == "copyObject" then duplicateSelected()
        elseif id == "preview" then BeginWorkshopPreview()
        elseif id == "file_new" then createCustom(false)
        elseif id == "file_copy" then createCustom(true)
        elseif id == "file_rename" then
            if editable() then
                current.modal = { kind = "rename", title = "重命名自定义关卡", message = "输入新的关卡名称。" }
                beginTextEdit(nil, current.document.name, "rename"); rebuildUI()
            end
        elseif id == "file_delete" then
            if editable() then current.modal = { kind = "confirmDelete", title = "删除自定义关卡",
                message = "将删除该关卡及其草稿槽位。官方关卡不受影响。" }; rebuildUI() end
        elseif id == "grid" then current.view.showGrid = not current.view.showGrid; rebuildUI()
        elseif id == "snap" then current.view.snap = not current.view.snap; rebuildUI()
        elseif id == "canvasTool" then
            current.canvasTool = current.canvasTool == "marquee" and "pan" or "marquee"
            current.marqueeRect = nil
            current.status = current.canvasTool == "marquee" and "框选模式 · 拖动空白区域选择多个对象"
                or "画布拖动模式"
            rebuildUI()
        elseif id == "zoomOut" then current.view.zoom = math.max(.35, current.view.zoom / 1.2); rebuildUI()
        elseif id == "zoomIn" then current.view.zoom = math.min(4, current.view.zoom * 1.2); rebuildUI()
        elseif id == "deleteObject" then deleteSelected()
        elseif id == "drawer_files" then current.view.drawerMode = current.view.drawerMode ~= "files" and "files" or nil; rebuildUI()
        elseif id == "drawer_inspector" then current.view.drawerMode = current.view.drawerMode ~= "inspector" and "inspector" or nil; rebuildUI()
        end
    end

    local function handleInspectorRow(row, pointerX)
        local field = row.field
        if field.kind == "section" or field.editable == false or not editable() then return end
        if field.kind == "boolean" then
            field.set(not field.value); markChanged("修改" .. field.label); rebuildUI()
        elseif field.kind == "enum" then cycleEnum(field)
        else
            local editValue = field.kind == "number"
                and Numeric.FormatEditValue(field.key, field.value) or field.value
            beginTextEdit(field, editValue, "field")
            View.PlaceTextCursor(context.painter_, state().textEdit, row.valueRect or row.rect,
                pointerX, state().elapsed)
            rebuildUI()
        end
    end

    local function beginCanvasGesture(pointerFrame)
        local current = state()
        Selection.BeginCanvasGesture(current, pointerFrame, Interaction)
        rebuildUI()
    end

    local function updateCanvasGesture(pointerFrame)
        local current = state()
        local changeKind = Selection.UpdateCanvasGesture(current, pointerFrame, Interaction)
        if not changeKind then return end
        if changeKind == "document" then refreshValidation() end
        refreshSelection()
        rebuildUI()
    end

    local function endCanvasGesture(pointerFrame)
        local current = state()
        local historyLabel = Selection.EndCanvasGesture(current, pointerFrame)
        if historyLabel then markChanged(historyLabel) else refreshSelection() end
        rebuildUI()
    end

    local function handleWorkshopScroll(current, action, target)
        if not action then return false end
        local wheelStep = (target == "modal" and .54)
            or ((target == "files" or target == "inspector") and .48) or 1
        local _, deltaY = SemanticActions.ScrollDelta(action, wheelStep)
        if target == "modal" and current.modal then
            current.modal.scroll = clamp((current.modal.scroll or 0) + deltaY,
                0, current.modal.scrollMax or 0)
        elseif target == "files" then
            current.view.fileScroll = clamp(current.view.fileScroll + deltaY,
                0, current.view.fileScrollMax)
        elseif target == "inspector" then
            current.view.inspectorScroll = clamp(current.view.inspectorScroll + deltaY,
                0, current.view.inspectorScrollMax)
        elseif target == "canvas" then
            if deltaY == 0 then return false end
            current.view.zoom = clamp(current.view.zoom * (deltaY < 0 and 1.12 or .89), .35, 4)
        else
            return false
        end
        SemanticActions.Consume(action, "Workshop:" .. target)
        rebuildUI()
        return true
    end

    function UpdateLevelWorkshop(dt, pointerFrame)
        SemanticActions.Ensure(pointerFrame)
        local current = state()
        current.elapsed = current.elapsed + math.max(0, dt or 0)
        current.toastTime = math.max(0, (current.toastTime or 0) - math.max(0, dt or 0))
        if current.toastTime == 0 then current.toast = nil end
        if current.dirty and current.autoSaveDue and current.elapsed >= current.autoSaveDue then
            current.autoSaveDue = nil; saveDraft("草稿已自动保存")
        end
        if current.dirty and current.cloudDraftSyncDue and current.elapsed >= current.cloudDraftSyncDue then
            syncDraftToCloud("草稿已自动同步云端")
        end
        rebuildUI()
        if not current.layout.supported then
            local navigationCancel = SemanticActions.Find(pointerFrame, SemanticActions.CANCEL, "navigation")
            if navigationCancel then
                SemanticActions.Consume(navigationCancel, "WorkshopUnsupported")
                if current.dirty then current.modal = { targetExit = true }; finishDirtyAction("save") else leaveWorkshop() end
            end
            return
        end
        local textEditing = updateTextEditKeys(pointerFrame)
        local x, y = Layout.PointerToWorkspace(current.layout, pointerFrame.x, pointerFrame.y)
        pointerFrame.x, pointerFrame.y = x, y
        local gesture, touch = TouchScroller.Update(current.touchScroll, pointerFrame,
            TouchScroller.Targets(current), 8)
        current.touchScroll = gesture
        if touch and touch.action then handleWorkshopScroll(current, touch.action, touch.target) end
        if touch and touch.consume then
            if touch.tap then
                pointerFrame.pressed = true
                SemanticActions.Add(pointerFrame, SemanticActions.PRIMARY_PRESS, {
                    x = pointerFrame.x,
                    y = pointerFrame.y,
                    source = pointerFrame.source,
                    raw = "direct.scroll_tap",
                })
            else
                return
            end
        end
        current.hoverTooltip = nil
        if SemanticActions.SupportsHover(pointerFrame) and not current.modal then
            for _, row in ipairs(current.controls.fileRows or {}) do
                if View.PointIn(row.rect, x, y) then
                    current.hoverTooltip = { text = row.entry.name .. "  ·  " .. row.entry.levelId, x = x + 14, y = y + 18 }
                    break
                end
            end
            if not current.hoverTooltip then
                for _, row in ipairs(current.controls.inspectorRows or {}) do
                    if row.field.kind ~= "section" and View.PointIn(row.rect, x, y) then
                        current.hoverTooltip = { text = row.field.label .. "："
                            .. View.FieldValue(row.field), x = x + 14, y = y + 18 }
                        break
                    end
                end
            end
        end
        if current.modal then
            local scrollAction = SemanticActions.Find(pointerFrame, SemanticActions.SCROLL)
            if scrollAction and current.controls.modalBody and View.PointIn(current.controls.modalBody, x, y) then
                handleWorkshopScroll(current, scrollAction, "modal")
            end
            if pointerFrame.pressed then
                if current.controls.renameField and View.PointIn(current.controls.renameField, x, y) then
                    View.PlaceTextCursor(context.painter_, current.textEdit, current.controls.renameField,
                        x, current.elapsed, 16)
                    return
                end
                for _, button in ipairs(current.controls.modalButtons or {}) do
                    if View.PointIn(button.rect, x, y) then handleModalButton(button.id); return end
                end
            end
            local navigationCancel = SemanticActions.Find(pointerFrame, SemanticActions.CANCEL, "navigation")
            if navigationCancel then
                SemanticActions.Consume(navigationCancel, "WorkshopModal")
                handleModalButton("cancel")
            end
            return
        end
        if textEditing then
            if not pointerFrame.pressed then return end
            for _, row in ipairs(current.controls.inspectorRows or {}) do
                if current.textEdit and current.textEdit.fieldKey == row.field.key
                    and View.PointIn(row.rect, x, y) then
                    View.PlaceTextCursor(context.painter_, current.textEdit, row.valueRect or row.rect,
                        x, current.elapsed)
                    return
                end
            end
            -- A press outside the active field behaves like Return. On success the
            -- same press continues through normal control/canvas dispatch below.
            if not commitTextEdit() then return end
        end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_S) then SaveWorkshopCurrent(); return end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyDown(KEY_SHIFT) and input:GetKeyPress(KEY_Z) then redo(); return end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_Z) then undo(); return end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_Y) then redo(); return end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_C) then duplicateSelected(); return end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_D) then duplicateSelected(); return end
        if input:GetKeyPress(KEY_DELETE) then deleteSelected(); return end
        local navigationCancel = SemanticActions.Find(pointerFrame, SemanticActions.CANCEL, "navigation")
        if navigationCancel then
            SemanticActions.Consume(navigationCancel, "Workshop")
            leaveWorkshop()
            return
        end

        local scrollAction = SemanticActions.Find(pointerFrame, SemanticActions.SCROLL)
        if scrollAction then
            if current.layout.fileViewport and View.PointIn(current.layout.fileViewport, x, y) then
                handleWorkshopScroll(current, scrollAction, "files")
            elseif current.layout.inspectorViewport and View.PointIn(current.layout.inspectorViewport, x, y) then
                handleWorkshopScroll(current, scrollAction, "inspector")
            elseif View.ControlHitAllowed(current.layout, "canvas", x, y) and View.PointIn(current.layout.canvasViewport, x, y) then
                handleWorkshopScroll(current, scrollAction, "canvas")
            end
        end

        if pointerFrame.pressed then
            for id, rect in pairs(current.controls.byId) do
                if View.PointIn(rect, x, y) and View.ControlHitAllowed(current.layout, id, x, y) then handleControl(id); return end
            end
            for _, row in ipairs(current.controls.fileRows) do
                if View.PointIn(row.rect, x, y) then switchEntry(row.entry.entryId); rebuildUI(); return end
            end
            for _, row in ipairs(current.controls.paletteRows) do
                if View.PointIn(row.rect, x, y) then addObject(row.objectType); return end
            end
            for _, row in ipairs(current.controls.inspectorRows) do
                if View.PointIn(row.rect, x, y) then handleInspectorRow(row, x); return end
            end
            if View.ControlHitAllowed(current.layout, "canvas", x, y) and View.PointIn(current.layout.canvasViewport, x, y) then beginCanvasGesture(pointerFrame); return end
        end
        updateCanvasGesture(pointerFrame)
        if pointerFrame.released or (current.transaction and not pointerFrame.down) then endCanvasGesture(pointerFrame) end
    end

    function DrawLevelWorkshop()
        rebuildUI()
        View.Draw(context, state())
    end

    function ShutdownLevelWorkshop()
        if state().initialized then saveDraftAndSync("退出前草稿已同步云端") end
        Selection.Clear(state())
        state().canvasTool = "pan"
        if input then input:SetScreenKeyboardVisible(false) end
    end
    function HandleWorkshopScreenMode()
        if state().initialized and state().dirty then saveDraft("窗口变化前草稿已保存") end
    end

    -- Stable service surface used by the catalog entry and non-visual contract tests.
    function WorkshopListCustomExperiments()
        InitializeLevelWorkshop()
        local current = state()
        local result = {}
        if not current.repository then return result end
        for _, metadata in ipairs(current.repository:List()) do
            if metadata.sourceKind == "custom" then
                local document, openedMetadata = current.repository:Open(metadata.entryId)
                if document then
                    result[#result + 1] = {
                        entryId = metadata.entryId,
                        levelId = metadata.levelId,
                        name = metadata.name,
                        updatedAt = metadata.updatedAt,
                        metadata = openedMetadata,
                        document = document,
                    }
                end
            end
        end
        return result
    end
    function WorkshopOpenCustomExperiment(entryId)
        InitializeLevelWorkshop()
        local current = state()
        local metadata = current.repository and current.repository:GetEntry(entryId) or nil
        if not metadata or metadata.sourceKind ~= "custom" then
            return nil, "自制实验不存在：" .. tostring(entryId)
        end
        return current.repository:Open(entryId)
    end
    function WorkshopOpenEntry(entryId) return switchEntry(entryId) end
    function WorkshopCreateCustom() return createCustom(false) end
    function WorkshopCopyCurrent() return createCustom(true) end
    function WorkshopDeleteCurrent() return deleteCurrent() end
    function WorkshopAddObject(objectType) return addObject(objectType) end
    function WorkshopDeleteSelected() return deleteSelected() end
    function WorkshopDuplicateSelected() return duplicateSelected() end
    function WorkshopUndo() return undo() end
    function WorkshopRedo() return redo() end
    function WorkshopSaveDraft() return saveDraftAndSync("草稿已手动同步云端") end
    function WorkshopPrepareExport() return Export.Prepare(state().document, LevelDocument, cjson) end
    function WorkshopOpenImport() openImport(); return true end
    function WorkshopPasteImport() return pasteImportClipboard() end
    function WorkshopConfirmImport() return confirmImport() end
    function WorkshopResolveModal(id) return handleModalButton(id) end
end

return M
