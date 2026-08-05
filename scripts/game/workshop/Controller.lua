local Repository = require("game.workshop.Repository")
local History = require("game.workshop.History")
local DraftStore = require("game.workshop.DraftStore")
local Export = require("game.workshop.Export")
local Layout = require("game.workshop.Layout")
local Interaction = require("game.workshop.Interaction")
local View = require("game.workshop.View")
local Inspector = require("game.workshop.Inspector")
local DocumentActions = require("game.workshop.DocumentActions")
local TextTransfer = require("game.workshop.TextTransfer")
local PreviewSession = require("game.workshop.PreviewSession")

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
    local function refreshSelection()
        local current = state()
        current.selectedObject = DocumentActions.FindObject(current.document, current.selectedObjectId)
        if current.selectedObjectId and not current.selectedObject then current.selectedObjectId = nil end
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

    local function markChanged(label)
        local current = state()
        current.dirty = true
        current.autoSaveDue = current.elapsed + current.autoSaveDelay
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

    local function openEntryNow(entryId, options)
        options = options or {}
        local current = state()
        local document, metadata = current.repository:Open(entryId)
        if not document then toast(metadata or "关卡不存在"); return false end
        current.entryId, current.metadata = entryId, metadata
        current.readOnly = metadata.readOnly == true
        if not current.readOnly then Inspector.EnsureCustomFields(document) end
        current.document = document
        current.selectedObjectId, current.selectedObject = nil, nil
        current.view = options.viewState and clone(LevelDocument, options.viewState) or DocumentActions.NewViewState()
        if current.layout and current.layout.folded then current.view.drawerMode = "files" end
        current.dirty = options.dirty == true
        current.transaction, current.textEdit = nil, nil
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
        if current.initialized then return true end
        local adapter = DraftStore.CreateLocalAdapter()
        current.repository = Repository.New({ LevelDocument = LevelDocument })
        current.history = History.New({ clone = LevelDocument.Clone, limit = 100 })
        current.draftStore = DraftStore.New({ clone = LevelDocument.Clone, json = cjson, adapter = adapter })
        current.persistenceKind = current.draftStore:PersistenceKind()
        current.supportedTypes = LevelDocument.SupportedTypes()
        current.initializationErrors = current.repository:InitializeOfficial(CONFIG.levelCount, function(index)
            local document, errorMessage = LevelData.Load(string.format("Data/Levels/level_%02d.json", index))
            if not document then error(errorMessage) end
            return document
        end)
        for _, envelope in ipairs(current.draftStore:LoadCustomLevels()) do
            local metadata, errorMessage = current.repository:RestoreCustom(envelope.document, envelope.updatedAt)
            if not metadata then current.initializationErrors[#current.initializationErrors + 1] = errorMessage end
        end
        current.initialized = true
        refreshEntries()
        return #current.initializationErrors == 0
    end

    function OpenLevelWorkshop(selectedLevelId)
        InitializeLevelWorkshop()
        if scene_ or level_ then ReleaseLevelRuntime() end
        renderer:SetNumViewports(0)
        screen_ = "workshop"
        local entryId = selectedLevelId and ("official:" .. selectedLevelId) or nil
        if not entryId or not state().repository:GetEntry(entryId) then
            entryId = state().entries[1] and state().entries[1].entryId or nil
        end
        if not entryId then toast("没有可用关卡"); return false end
        openEntryNow(entryId)
        if #state().initializationErrors > 0 then
            toast("部分关卡未载入：" .. state().initializationErrors[1], 5)
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
        local draftDeleted, draftDeleteError = current.draftStore:DeleteDraft(current.document.levelId)
        current.dirty, current.autoSaveDue = false, nil
        current.persistenceKind = current.draftStore:PersistenceKind()
        refreshEntries()
        if not draftDeleted then toast("关卡已保存，但旧草稿清理失败：" .. tostring(draftDeleteError), 5)
        else toast(persistence.persisted and "关卡已保存到本地槽位，建议同时导出 JSON"
            or "关卡已保存在运行内存，请导出 JSON 备份") end
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
        current.dirty = false
        refreshEntries()
        openEntryNow(metadata.entryId, { skipRecovery = true })
        state().dirty = true
        state().autoSaveDue = state().elapsed + state().autoSaveDelay
        state().history:Push(state().document, state().view, copyCurrent and "复制关卡" or "新建关卡")
        refreshHistoryFlags()
        toast(copyCurrent and "已创建可编辑副本" or "已创建新关卡")
        return true
    end

    local function deleteCurrent()
        local current = state()
        if current.readOnly then toast("官方关卡不能删除"); return false end
        local ok, errorMessage = DocumentActions.DeleteCustom(current.repository, current.draftStore,
            current.entryId, current.document.levelId)
        if not ok then toast(errorMessage); return false end
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
        refreshSelection(); refreshValidation(); rebuildUI()
        current.status = "已重做"
    end

    local function addObject(objectType)
        local current = state()
        if not editable() then return end
        local object, errorMessage = DocumentActions.AddObject(current, objectType,
            current.repository, LevelDocument, View.TYPE_LABELS)
        if not object then toast(errorMessage); return end
        current.selectedObjectId = object.id
        markChanged("新增" .. (View.TYPE_LABELS[objectType] or objectType))
        if current.layout.folded then current.view.drawerMode = "inspector" end
        rebuildUI()
    end

    local function deleteSelected()
        local current = state()
        if not editable() or not current.selectedObjectId then return end
        if not DocumentActions.DeleteObject(current.document, current.selectedObjectId) then return end
        current.selectedObjectId, current.selectedObject = nil, nil
        markChanged("删除对象")
        rebuildUI()
    end

    local function duplicateSelected()
        local current = state()
        if not editable() or not current.selectedObject then return end
        local object, errorMessage = DocumentActions.DuplicateObject(current, current.repository,
            LevelDocument, Interaction)
        if not object then toast(errorMessage); return end
        current.selectedObjectId = object.id
        markChanged("复制对象")
        rebuildUI()
    end

    local function beginTextEdit(field, value, mode)
        if field and field.editable == false then return end
        local current = state()
        current.textEdit = {
            field = field,
            fieldKey = field and field.key or mode,
            value = tostring(value == nil and "" or value),
            selectAll = true,
            maxLength = field and field.maxLength or (mode == "import" and 1000000 or 256),
            mode = mode or "field",
        }
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
            edit.maxLength or Export.MAX_IMPORT_BYTES)
        if not accepted then toast(errorMessage, 5) end
    end

    local function pasteImportClipboard()
        local current = state()
        local edit = current.textEdit
        if not edit or edit.mode ~= "import" then return false end
        local text, errorMessage = TextTransfer.ReadClipboard(ui, Export.MAX_IMPORT_BYTES)
        if not text then toast("无法粘贴：" .. tostring(errorMessage), 5); return false end
        edit.value, edit.selectAll, edit.clipboardEchoRemaining = text, false, text
        if current.modal then current.modal.text, current.modal.scroll = text, 0 end
        rebuildUI()
        toast("已从系统剪贴板读取 JSON 文本")
        return true
    end

    local function updateTextEditKeys()
        local current = state()
        local edit = current.textEdit
        if not edit then return false end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_A) then edit.selectAll = true; return true end
        if edit.mode == "import" and input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_V) then
            pasteImportClipboard()
            return true
        end
        if input:GetKeyPress(KEY_BACKSPACE) then
            if edit.selectAll then
                edit.value, edit.selectAll = "", false
            elseif #edit.value > 0 then
                local byte = utf8 and utf8.offset and utf8.offset(edit.value, -1, #edit.value + 1) or #edit.value
                edit.value = edit.value:sub(1, math.max(0, (byte or #edit.value) - 1))
            end
            return true
        end
        if input:GetKeyPress(KEY_ESCAPE) then
            if current.modal and (edit.mode == "rename" or edit.mode == "import") then current.modal = nil end
            cancelTextEdit(); return true
        end
        if input:GetKeyPress(KEY_RETURN) and edit.mode ~= "import" then commitTextEdit(); return true end
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
        current.modal = { kind = "import", title = "导入 JSON", text = "", scroll = 0,
            maxBytes = Export.MAX_IMPORT_BYTES }
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
        toast(persistence.persisted and "JSON 已导入并保存为独立自定义关卡"
            or "JSON 已导入到运行内存，请立即导出备份")
        return true
    end

    function BeginWorkshopPreview()
        local current = state()
        if not current.document then return false end
        local report = LevelDocument.ValidateDetailed(current.document)
        current.validation = report
        if not report.valid then toast("无法预览：" .. report.errors[1].message, 5); return false end
        saveDraft("预览前草稿已保存")
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
    local function leaveWorkshop()
        local current = state()
        if current.dirty then
            current.modal = { kind = "dirtySwitch", title = "退出关卡工坊",
                message = "当前关卡有未保存修改，请选择保存、放弃或取消。", targetExit = true }
            rebuildUI()
            return false
        end
        screen_ = "catalog"
        renderer:SetNumViewports(0)
        current.modal, current.textEdit, current.transaction = nil, nil, nil
        return true
    end
    local function finishDirtyAction(action)
        local current = state()
        local modal = current.modal
        if action == "cancel" then current.modal = nil; rebuildUI(); return end
        if action == "save" and not saveDraft("草稿已保存") then return end
        if action == "save" then current.dirty, current.autoSaveDue = false, nil end
        if action == "discard" then
            if current.document and not current.readOnly then
                local deleted, errorMessage = current.draftStore:DeleteDraft(current.document.levelId)
                if not deleted then toast("放弃失败：" .. tostring(errorMessage), 5); return end
            end
            current.dirty = false
        end
        local target, targetExit = modal.targetEntryId, modal.targetExit
        current.modal = nil
        if targetExit then
            screen_ = "catalog"; renderer:SetNumViewports(0)
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
            current.history:Reset(current.document, current.view, "恢复草稿")
            current.status = "已恢复未完成草稿"
        elseif action == "discard" then
            local deleted, errorMessage = current.draftStore:DeleteDraft(current.document.levelId)
            if not deleted then toast("放弃草稿失败：" .. tostring(errorMessage), 5); return end
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
            current.modal = nil; refreshEntries(); openEntryNow(metadata.entryId, { skipRecovery = true })
            state().dirty = true; state().history:Push(state().document, state().view, "草稿另存")
            state().autoSaveDue = state().elapsed + state().autoSaveDelay
            rebuildUI(); return
        end
        current.modal = nil
        refreshSelection(); refreshValidation(); rebuildUI()
    end
    local function handleModalButton(id)
        local current = state()
        local modal = current.modal
        if not modal then return end
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

    local function handleControl(id)
        local current = state()
        if id == "exit" then leaveWorkshop()
        elseif id == "draft" then if editable() and saveDraft("草稿已手动保存") then toast("草稿已保存") end
        elseif id == "save" then SaveWorkshopCurrent()
        elseif id == "export" then openExport()
        elseif id == "import" then openImport()
        elseif id == "undo" then undo()
        elseif id == "redo" then redo()
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
        elseif id == "zoomOut" then current.view.zoom = math.max(.35, current.view.zoom / 1.2); rebuildUI()
        elseif id == "zoomIn" then current.view.zoom = math.min(4, current.view.zoom * 1.2); rebuildUI()
        elseif id == "deleteObject" then deleteSelected()
        elseif id == "drawer_files" then current.view.drawerMode = current.view.drawerMode == "files" and nil or "files"; rebuildUI()
        elseif id == "drawer_inspector" then current.view.drawerMode = current.view.drawerMode == "inspector" and nil or "inspector"; rebuildUI()
        end
    end

    local function handleInspectorRow(row)
        local field = row.field
        if field.kind == "section" or field.editable == false or not editable() then return end
        if field.kind == "boolean" then
            field.set(not field.value); markChanged("修改" .. field.label); rebuildUI()
        elseif field.kind == "enum" then cycleEnum(field)
        else beginTextEdit(field, field.value, "field"); rebuildUI() end
    end

    local function beginCanvasGesture(pointerFrame)
        local current = state()
        local controls = current.controls
        local transform = controls.canvasTransform
        if not transform then return end
        local x, y = pointerFrame.x, pointerFrame.y
        if current.selectedObject and not current.readOnly then
            ---@type string|nil
            local handle = Interaction.HitHandle(controls.handles, x, y)
            if handle then
                current.transaction = { kind = handle, objectId = current.selectedObject.id, changed = false }
                return
            end
        end
        local levelX, levelY = Interaction.ScreenToLevel(transform, x, y)
        local object = Interaction.FindTopObject(current.document, levelX, levelY, 5 / transform.scale)
        if object then
            current.selectedObjectId, current.selectedObject = object.id, object
            if current.layout.folded then current.view.drawerMode = "inspector" end
            if not current.readOnly then
                current.transaction = {
                    kind = "move", objectId = object.id,
                    offsetX = object.transform.x - levelX, offsetY = object.transform.y - levelY,
                    changed = false,
                }
            end
            rebuildUI()
        elseif input:GetKeyDown(KEY_SHIFT) then
            current.transaction = { kind = "pan", startX = x, startY = y,
                panX = current.view.panX, panY = current.view.panY, changed = false }
        else
            current.selectedObjectId, current.selectedObject = nil, nil
            buildInspectorFields(); rebuildUI()
        end
    end

    local function updateCanvasGesture(pointerFrame)
        local current = state()
        local transaction = current.transaction
        if not transaction or not pointerFrame.down then return end
        if transaction.kind == "pan" then
            current.view.panX = transaction.panX + pointerFrame.x - transaction.startX
            current.view.panY = transaction.panY + pointerFrame.y - transaction.startY
            transaction.changed = true; rebuildUI(); return
        end
        local object = DocumentActions.FindObject(current.document, transaction.objectId)
        local transform = current.controls.canvasTransform
        if not object or not transform then return end
        local levelX, levelY = Interaction.ScreenToLevel(transform, pointerFrame.x, pointerFrame.y)
        if transaction.kind == "move" then
            local x, y = levelX + transaction.offsetX, levelY + transaction.offsetY
            if current.view.snap then x, y = Interaction.Snap(x, current.view.gridSize), Interaction.Snap(y, current.view.gridSize) end
            object.transform.x, object.transform.y = Interaction.ClampPosition(current.document, object, x, y)
        elseif transaction.kind == "resize" then
            object.transform.width, object.transform.height = Interaction.ResizeFromPointer(current.document, object,
                levelX, levelY, 4, current.view.snap and current.view.gridSize or nil)
            object.transform.x, object.transform.y = Interaction.ClampPosition(current.document, object,
                object.transform.x, object.transform.y)
        elseif transaction.kind == "rotate" then
            object.transform.rotation = Interaction.RotationFromPointer(object, levelX, levelY,
                current.view.snap and current.view.angleSnap or nil)
            object.transform.x, object.transform.y = Interaction.ClampPosition(current.document, object,
                object.transform.x, object.transform.y)
        end
        transaction.changed = true
        refreshSelection(); refreshValidation(); rebuildUI()
    end

    local function endCanvasGesture()
        local current = state()
        local transaction = current.transaction
        current.transaction = nil
        if transaction and transaction.changed and transaction.kind ~= "pan" then markChanged("画布变换") end
        rebuildUI()
    end

    function UpdateLevelWorkshop(dt, pointerFrame)
        local current = state()
        current.elapsed = current.elapsed + math.max(0, dt or 0)
        current.toastTime = math.max(0, (current.toastTime or 0) - math.max(0, dt or 0))
        if current.toastTime == 0 then current.toast = nil end
        if current.dirty and current.autoSaveDue and current.elapsed >= current.autoSaveDue then
            current.autoSaveDue = nil; saveDraft("草稿已自动保存")
        end
        rebuildUI()
        if not current.layout.supported then
            if input:GetKeyPress(KEY_ESCAPE) then
                if current.dirty then current.modal = { targetExit = true }; finishDirtyAction("save") else leaveWorkshop() end
            end
            return
        end
        local textEditing = updateTextEditKeys()
        local x, y = Layout.PointerToWorkspace(current.layout, pointerFrame.x, pointerFrame.y)
        pointerFrame.x, pointerFrame.y = x, y
        local wheel = input.mouseMoveWheel or 0
        current.hoverTooltip = nil
        if not current.modal then
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
                            .. tostring(row.field.value == nil and "" or row.field.value), x = x + 14, y = y + 18 }
                        break
                    end
                end
            end
        end
        if current.modal then
            if wheel ~= 0 and current.controls.modalBody and View.PointIn(current.controls.modalBody, x, y) then
                current.modal.scroll = clamp((current.modal.scroll or 0) - wheel * 54, 0, current.modal.scrollMax or 0)
            end
            if pointerFrame.pressed then
                for _, button in ipairs(current.controls.modalButtons or {}) do
                    if View.PointIn(button.rect, x, y) then handleModalButton(button.id); return end
                end
            end
            if input:GetKeyPress(KEY_ESCAPE) then handleModalButton("cancel") end
            return
        end
        if textEditing then return end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_S) then SaveWorkshopCurrent(); return end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_Z) then undo(); return end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_Y) then redo(); return end
        if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_D) then duplicateSelected(); return end
        if input:GetKeyPress(KEY_DELETE) then deleteSelected(); return end
        if input:GetKeyPress(KEY_ESCAPE) then leaveWorkshop(); return end

        if wheel ~= 0 then
            if current.layout.fileViewport and View.PointIn(current.layout.fileViewport, x, y) then
                current.view.fileScroll = clamp(current.view.fileScroll - wheel * 48, 0, current.view.fileScrollMax)
            elseif current.layout.inspectorViewport and View.PointIn(current.layout.inspectorViewport, x, y) then
                current.view.inspectorScroll = clamp(current.view.inspectorScroll - wheel * 48, 0, current.view.inspectorScrollMax)
            elseif View.ControlHitAllowed(current.layout, "canvas", x, y) and View.PointIn(current.layout.canvasViewport, x, y) then
                current.view.zoom = clamp(current.view.zoom * (wheel > 0 and 1.12 or .89), .35, 4)
            end
            rebuildUI()
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
                if View.PointIn(row.rect, x, y) then handleInspectorRow(row); return end
            end
            if View.ControlHitAllowed(current.layout, "canvas", x, y) and View.PointIn(current.layout.canvasViewport, x, y) then beginCanvasGesture(pointerFrame); return end
        end
        updateCanvasGesture(pointerFrame)
        if pointerFrame.released or (current.transaction and not pointerFrame.down) then endCanvasGesture() end
    end

    function DrawLevelWorkshop()
        rebuildUI()
        View.Draw(context, state())
    end

    function ShutdownLevelWorkshop()
        if state().initialized then saveDraft("退出前草稿已保存") end
        if input then input:SetScreenKeyboardVisible(false) end
    end
    function HandleWorkshopScreenMode()
        if state().initialized and state().dirty then saveDraft("窗口变化前草稿已保存") end
    end

    -- Stable service surface used by the catalog entry and non-visual contract tests.
    function WorkshopOpenEntry(entryId) return switchEntry(entryId) end
    function WorkshopCreateCustom() return createCustom(false) end
    function WorkshopCopyCurrent() return createCustom(true) end
    function WorkshopDeleteCurrent() return deleteCurrent() end
    function WorkshopAddObject(objectType) return addObject(objectType) end
    function WorkshopDeleteSelected() return deleteSelected() end
    function WorkshopDuplicateSelected() return duplicateSelected() end
    function WorkshopUndo() return undo() end
    function WorkshopRedo() return redo() end
    function WorkshopSaveDraft() return saveDraft("草稿已手动保存") end
    function WorkshopPrepareExport() return Export.Prepare(state().document, LevelDocument, cjson) end
    function WorkshopOpenImport() openImport(); return true end
    function WorkshopPasteImport() return pasteImportClipboard() end
    function WorkshopConfirmImport() return confirmImport() end
    function WorkshopResolveModal(id) return handleModalButton(id) end
end

return M
