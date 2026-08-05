package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local LevelDocument = require("game.level.LevelDocument")
local Rules = require("game.gameplay.Rules")
local State = require("game.State")
local Controller = require("game.workshop.Controller")
local Interaction = require("game.workshop.Interaction")

local codecStore, codecIndex = {}, 0
cjson = {}
function cjson.encode(value)
    codecIndex = codecIndex + 1
    local token = "controller-json-" .. tostring(codecIndex)
    codecStore[token] = LevelDocument.Clone(value)
    return token
end
function cjson.decode(token)
    assert(codecStore[token], "unknown token")
    return LevelDocument.Clone(codecStore[token])
end

local persistentFiles = {}
FILE_READ, FILE_WRITE, SCAN_FILES = 1, 2, 0
function GetPlatform() return "Windows" end
fileSystem = {}
function fileSystem:CreateDir(_) return true end
function fileSystem:FileExists(path) return persistentFiles[path] ~= nil end
function fileSystem:Delete(path) persistentFiles[path] = nil; return true end
function fileSystem:Rename(source, destination)
    if persistentFiles[source] == nil then return false end
    persistentFiles[destination], persistentFiles[source] = persistentFiles[source], nil
    return true
end
function fileSystem:ScanDir(path, _, _, _)
    local result = {}
    for filePath in pairs(persistentFiles) do
        if filePath:sub(1, #path) == path then
            local name = filePath:sub(#path + 1)
            if name:match("^[^/]+%.json$") then result[#result + 1] = name end
        end
    end
    return result
end
function File(path, mode)
    local file = { open = mode == FILE_WRITE or persistentFiles[path] ~= nil }
    function file:IsOpen() return self.open end
    function file:WriteString(value)
        if not self.open then return false end
        persistentFiles[path] = value
        return true
    end
    function file:ReadString() return persistentFiles[path] end
    function file:Close() self.open = false end
    return file
end

renderer = { viewports = 0 }
function renderer:SetNumViewports(value) self.viewports = value end
input = {}
input.mouseMoveWheel = 0
function input:SetScreenKeyboardVisible(_) end
function input:GetKeyDown(key) return self.downKeys and self.downKeys[key] == true or false end
KEY_ESCAPE, KEY_CTRL, KEY_S, KEY_Z, KEY_Y, KEY_D, KEY_DELETE = 27, 1000, 83, 90, 89, 68, 127
KEY_BACKSPACE, KEY_RETURN, KEY_A, KEY_V, KEY_SHIFT = 8, 13, 65, 86, 1001
function input:GetKeyPress(key)
    local pressed = self.pressedKey == key
    if pressed then self.pressedKey = nil end
    return pressed
end
ui = { clipboard = "" }
function ui:SetUseSystemClipboard(value) self.useSystemClipboard = value end
function ui:SetClipboardText(value) self.clipboard = value end
function ui:GetClipboardText() return self.clipboard end

local LevelData = {
    Load = function(path)
        local index = tonumber(path:match("level_(%d+)"))
        if not index then return nil, "bad resource path" end
        local level = LevelDocument.New(string.format("level_%02d", index), "官方关卡 " .. tostring(index))
        level.objects[#level.objects + 1] = LevelDocument.NewObject("wall", "wall_001", 500, 300)
        return level
    end,
    Normalize = LevelDocument.Normalize,
    Validate = LevelDocument.Validate,
    ValidateDetailed = LevelDocument.ValidateDetailed,
    Decode = function(text)
        local ok, decoded = pcall(cjson.decode, text)
        if not ok then return nil, "JSON 解析失败：" .. tostring(decoded) end
        local normalized = LevelDocument.Normalize(decoded)
        local valid, errors = LevelDocument.Validate(normalized)
        if not valid then return nil, table.concat(errors, ";") end
        return normalized
    end,
}
local designStub = { New = function() return {} end }
local function newTestContext(frame)
    local result = State.New({
        DesignSpace = designStub,
        Rules = Rules,
        ReplayMode = { NONE = 0 },
        LevelData = LevelData,
        LevelDocument = LevelDocument,
    }, { CONFIG = { pixelsPerMeter = 100, levelCount = 2 } })
    result.frame_ = frame
    Controller.Install(result)
    return result
end
local context = State.New({
    DesignSpace = designStub,
    Rules = Rules,
    ReplayMode = { NONE = 0 },
    LevelData = LevelData,
    LevelDocument = LevelDocument,
}, { CONFIG = { pixelsPerMeter = 100, levelCount = 2 } })
context.frame_ = {
    systemLogicalWidth = 1880, systemLogicalHeight = 840,
    logicalWidth = 1880, logicalHeight = 840,
}
Controller.Install(context)

local releaseCount = 0
context.ReleaseLevelRuntime = function()
    releaseCount = releaseCount + 1
    context.scene_, context.level_ = nil, nil
    renderer:SetNumViewports(0)
    return true
end
context.StartRuntimeSessionFromDocument = function(document, options)
    context.scene_ = {}
    context.level_ = LevelDocument.Clone(document)
    context.screen_ = options.screen
    renderer:SetNumViewports(1)
    return { sourceKind = options.sourceKind, screen = options.screen }
end

expect(context.OpenLevelWorkshop("level_01"), "catalog entry did not open workshop")
local workshop = context.workshopState_

local function idlePointer()
    return { x = 0, y = 0, down = false, pressed = false, released = false }
end

local function updateWorkshop(targetContext, pointer)
    targetContext.UpdateLevelWorkshop(0, pointer or idlePointer())
end

local function rawPoint(current, x, y)
    local scale = current.layout and current.layout.coordinateScale or 1
    return x / scale, y / scale
end

local function clickRect(targetContext, current, rect)
    expect(rect and rect.w > 0 and rect.h > 0, "attempted to click a missing control rectangle")
    local x, y = rect.x + rect.w * 0.5, rect.y + rect.h * 0.5
    local rawX, rawY = rawPoint(current, x, y)
    updateWorkshop(targetContext, { x = rawX, y = rawY, down = true, pressed = true, released = false })
    updateWorkshop(targetContext, { x = rawX, y = rawY, down = false, pressed = false, released = true })
end

local function clickControl(targetContext, current, id)
    updateWorkshop(targetContext)
    clickRect(targetContext, current, current.controls.byId[id])
end

local function clickModalButton(targetContext, current, id)
    updateWorkshop(targetContext)
    for _, button in ipairs(current.controls.modalButtons or {}) do
        if button.id == id then clickRect(targetContext, current, button.rect); return end
    end
    error("modal button not found: " .. tostring(id), 2)
end

local function inspectorRow(targetContext, current, key)
    updateWorkshop(targetContext)
    local offset = 0
    for _, field in ipairs(current.inspectorFields or {}) do
        if field.key == key then
            current.view.inspectorScroll = math.min(offset, current.view.inspectorScrollMax or offset)
            updateWorkshop(targetContext)
            for _, row in ipairs(current.controls.inspectorRows or {}) do
                if row.field.key == key then return row end
            end
            break
        end
        offset = offset + (field.kind == "section" and 38 or 52)
    end
    local fields, rows = {}, {}
    for _, field in ipairs(current.inspectorFields or {}) do fields[#fields + 1] = tostring(field.key) end
    for _, row in ipairs(current.controls.inspectorRows or {}) do rows[#rows + 1] = tostring(row.field.key) end
    error("inspector row not found: " .. tostring(key)
        .. " fields=" .. table.concat(fields, ",") .. " rows=" .. table.concat(rows, ","), 2)
end

local function replaceTextAndCommit(targetContext, current, value)
    expect(current.textEdit ~= nil, "text editor was not opened")
    targetContext.HandleWorkshopTextInput("TextInput", {
        GetString = function(_, _) return value end,
    })
    input.pressedKey = KEY_RETURN
    updateWorkshop(targetContext)
    expect(current.textEdit == nil, "text editor did not commit with Return")
end

local function dragWorkspace(targetContext, current, fromX, fromY, toX, toY)
    local rawFromX, rawFromY = rawPoint(current, fromX, fromY)
    local rawToX, rawToY = rawPoint(current, toX, toY)
    updateWorkshop(targetContext, {
        x = rawFromX, y = rawFromY, down = true, pressed = true, released = false,
    })
    updateWorkshop(targetContext, {
        x = rawToX, y = rawToY, down = true, pressed = false, released = false,
    })
    updateWorkshop(targetContext, {
        x = rawToX, y = rawToY, down = false, pressed = false, released = true,
    })
end

expect(context.screen_ == "workshop" and workshop.entryId == "official:level_01",
    "official entry selection mismatch")
expect(workshop.readOnly and #workshop.entries == 2, "official repository was not read-only or complete")

expect(context.WorkshopCopyCurrent(), "official level copy failed")
expect(not workshop.readOnly and workshop.document.levelId == "custom_001" and workshop.dirty,
    "official copy did not become an isolated custom document")
local copiedBaselines = workshop.draftStore:LoadCustomLevels()
expect(#copiedBaselines == 1 and copiedBaselines[1].document.levelId == "custom_001",
    "newly copied custom level did not persist its restart baseline immediately")

local restartedContext = State.New({
    DesignSpace = designStub,
    Rules = Rules,
    ReplayMode = { NONE = 0 },
    LevelData = LevelData,
    LevelDocument = LevelDocument,
}, { CONFIG = { pixelsPerMeter = 100, levelCount = 2 } })
restartedContext.frame_ = context.frame_
Controller.Install(restartedContext)
expect(restartedContext.OpenLevelWorkshop("level_01"), "workshop restart initialization failed")
expect(restartedContext.workshopState_.repository:GetEntry("custom:custom_001") ~= nil
    and #restartedContext.workshopState_.entries == 3,
    "copied custom level was orphaned after a simulated restart")
local officialName = workshop.repository:Open("official:level_01").name
workshop.document.name = "主策编辑版"
expect(context.SaveWorkshopCurrent(), "custom level formal save failed")
expect(not workshop.dirty and workshop.repository:Open("official:level_01").name == officialName,
    "custom save polluted official data")

local countBefore = #workshop.document.objects
context.WorkshopAddObject("wall")
expect(#workshop.document.objects == countBefore + 1 and workshop.selectedObjectId == "wall_002",
    "object creation or stable ID allocation failed")
context.WorkshopDuplicateSelected()
expect(#workshop.document.objects == countBefore + 2 and workshop.selectedObjectId == "wall_003",
    "object duplication or ID allocation failed")
context.WorkshopUndo()
expect(#workshop.document.objects == countBefore + 1, "undo did not restore document snapshot")
context.WorkshopRedo()
expect(#workshop.document.objects == countBefore + 2, "redo did not restore document snapshot")

context.HandleWorkshopScreenMode()
local draft = workshop.draftStore:LoadDraft("custom_001")
expect(draft and #draft.document.objects == countBefore + 2, "dirty document was not saved to a draft slot")

local snapshotName = workshop.document.name
local snapshotCount = #workshop.document.objects
expect(context.BeginWorkshopPreview(), "formal runtime preview did not start")
expect(context.screen_ == "workshop_preview" and context.level_ ~= workshop.document,
    "preview did not isolate runtime document")
context.level_.name = "runtime contamination"
context.level_.objects[1].transform.x = -999
context.failureCountsByLevel_.custom_001 = 7
context.resultReportClearCounts_.custom_001 = 3
context.resultReportHistory_.einstein[1] = { id = "preview-only" }
context.resultReportNextId_ = 99
expect(context.ExitWorkshopPreview("escape"), "preview exit failed")
expect(context.screen_ == "workshop" and renderer.viewports == 0 and releaseCount == 1,
    "preview runtime was not destroyed")
expect(workshop.document.name == snapshotName and #workshop.document.objects == snapshotCount
    and workshop.document.objects[1].transform.x ~= -999,
    "preview runtime state polluted the editor snapshot")
expect(context.failureCountsByLevel_.custom_001 == nil and context.resultReportClearCounts_.custom_001 == nil
    and #context.resultReportHistory_.einstein == 0 and context.resultReportNextId_ == 0,
    "preview progress or report state escaped the runtime session")

local successfulRuntimeStart = context.StartRuntimeSessionFromDocument
context.StartRuntimeSessionFromDocument = function(document, options)
    context.scene_, context.level_ = {}, LevelDocument.Clone(document)
    context.screen_ = options.screen
    context.failureCountsByLevel_.custom_001 = 11
    error("factory failed after scene creation")
end
expect(not context.BeginWorkshopPreview(), "partial runtime factory failure was accepted")
expect(context.screen_ == "workshop" and context.scene_ == nil
    and context.failureCountsByLevel_.custom_001 == nil and releaseCount == 2,
    "partial preview failure was not cleaned up and restored")
context.StartRuntimeSessionFromDocument = successfulRuntimeStart

expect(context.SaveWorkshopCurrent(), "post-preview save failed")
expect(context.WorkshopOpenEntry("official:level_02"), "clean custom level could not switch to official level")
expect(workshop.entryId == "official:level_02" and workshop.readOnly, "level switch mixed source kinds")

expect(context.WorkshopOpenEntry("custom:custom_001"), "saved custom level could not be reopened")
context.WorkshopAddObject("wall")
expect(not context.WorkshopOpenEntry("official:level_02") and workshop.modal.kind == "dirtySwitch",
    "dirty level switch did not require a decision")
context.WorkshopResolveModal("cancel")
expect(workshop.entryId == "custom:custom_001" and workshop.dirty and workshop.modal == nil,
    "canceling a dirty switch changed the active level")
context.WorkshopOpenEntry("official:level_02")
context.WorkshopResolveModal("discard")
expect(workshop.entryId == "official:level_02" and workshop.readOnly,
    "discarding a dirty switch did not open the target level")

expect(context.WorkshopOpenEntry("custom:custom_001"), "custom level could not reopen for save-switch coverage")
local formalObjectCount = #workshop.repository:Open("custom:custom_001").objects
context.WorkshopAddObject("wall")
context.WorkshopOpenEntry("official:level_02")
context.WorkshopResolveModal("save")
expect(workshop.entryId == "official:level_02" and not workshop.dirty,
    "draft-save-and-switch did not open the target level")
local switchedDraft = workshop.draftStore:LoadDraft("custom_001")
expect(switchedDraft and #switchedDraft.document.objects == formalObjectCount + 1
    and #workshop.repository:Open("custom:custom_001").objects == formalObjectCount,
    "draft-save-and-switch did not isolate the unfinished draft from the formal custom level")

local importedDocument = LevelDocument.New("external_level", "剪贴板导入")
importedDocument.objects[#importedDocument.objects + 1] = LevelDocument.NewObject("wall", "wall_001", 500, 300)
ui.clipboard = cjson.encode(importedDocument)
expect(context.WorkshopOpenImport() and context.WorkshopPasteImport(),
    "clipboard import modal could not ingest JSON")
expect(workshop.textEdit and workshop.textEdit.value == ui.clipboard
    and workshop.modal.textMetrics and workshop.modal.textMetrics.byteCount == #ui.clipboard,
    "clipboard import did not update text or scrolling metrics")
local pastedValue = workshop.textEdit.value
context.HandleWorkshopTextInput("TextInput", { GetString = function() return pastedValue end })
expect(workshop.textEdit.value == pastedValue,
    "browser clipboard TextInput echo duplicated the imported JSON")
expect(context.WorkshopConfirmImport(), "clipboard JSON was not imported")
expect(workshop.document.name == "剪贴板导入" and workshop.document.levelId == "custom_002"
    and not workshop.dirty,
    "imported JSON was not isolated and formally saved as a custom level")

-- Drive the actual pointer and text-input surface for the primary editing path.
updateWorkshop(context)
local editedWall = nil
for _, object in ipairs(workshop.document.objects) do
    if object.type == "wall" then editedWall = object; break end
end
expect(editedWall ~= nil, "imported test document has no wall")
local transform = workshop.controls.canvasTransform
local wallX, wallY = Interaction.LevelToScreen(transform, editedWall.transform.x, editedWall.transform.y)
local originalWallX, originalWallY = editedWall.transform.x, editedWall.transform.y
dragWorkspace(context, workshop, wallX, wallY, wallX + 54, wallY + 26)
expect(workshop.selectedObjectId == editedWall.id
    and (editedWall.transform.x ~= originalWallX or editedWall.transform.y ~= originalWallY),
    "canvas drag did not select and move the wall")

clickRect(context, workshop, inspectorRow(context, workshop, "object.name").rect)
replaceTextAndCommit(context, workshop, "主策测试墙")
expect(workshop.selectedObject.name == "主策测试墙", "Inspector text edit did not update object name")

clickRect(context, workshop, inspectorRow(context, workshop, "transform.width").rect)
replaceTextAndCommit(context, workshop, "180")
expect(workshop.selectedObject.transform.width == 180, "Inspector number edit did not update width")

local collisionBefore = workshop.selectedObject.properties.collisionEnabled
clickRect(context, workshop, inspectorRow(context, workshop, "properties.collisionEnabled").rect)
expect(workshop.selectedObject.properties.collisionEnabled ~= collisionBefore,
    "Inspector boolean edit did not toggle collision")

updateWorkshop(context)
local springPalette = nil
for _, row in ipairs(workshop.controls.paletteRows) do
    if row.objectType == "spring" then springPalette = row; break end
end
clickRect(context, workshop, springPalette.rect)
expect(workshop.selectedObject and workshop.selectedObject.type == "spring",
    "palette click did not add and select a spring")
local spring = workshop.selectedObject

clickRect(context, workshop, inspectorRow(context, workshop, "properties.enabledChannel").rect)
replaceTextAndCommit(context, workshop, "channel-main")
expect(spring.properties.enabledChannel == "channel-main", "Inspector mechanism text edit failed")

clickRect(context, workshop, inspectorRow(context, workshop, "properties.impulseStrength").rect)
replaceTextAndCommit(context, workshop, "640")
expect(spring.properties.impulseStrength == 640, "Inspector mechanism number edit failed")

local oneShotBefore = spring.properties.oneShot
clickRect(context, workshop, inspectorRow(context, workshop, "properties.oneShot").rect)
expect(spring.properties.oneShot ~= oneShotBefore, "Inspector mechanism boolean edit failed")

local directionBefore = spring.properties.direction
clickRect(context, workshop, inspectorRow(context, workshop, "properties.direction").rect)
expect(spring.properties.direction ~= directionBefore, "Inspector enum edit did not cycle direction")

updateWorkshop(context)
local springTransform = workshop.controls.canvasTransform
local springX, springY = Interaction.LevelToScreen(springTransform, spring.transform.x, spring.transform.y)
local beforeMoveX, beforeMoveY = spring.transform.x, spring.transform.y
dragWorkspace(context, workshop, springX, springY, springX + 62, springY + 34)
expect(spring.transform.x ~= beforeMoveX or spring.transform.y ~= beforeMoveY,
    "selected-object move gesture did not update transform")

updateWorkshop(context)
local beforeWidth, beforeHeight = spring.transform.width, spring.transform.height
local resizeHandle = workshop.controls.handles.resize
dragWorkspace(context, workshop, resizeHandle.x, resizeHandle.y, resizeHandle.x + 48, resizeHandle.y + 36)
expect(spring.transform.width ~= beforeWidth or spring.transform.height ~= beforeHeight,
    "resize handle gesture did not update dimensions")

updateWorkshop(context)
local beforeRotation = spring.transform.rotation
local rotateHandle = workshop.controls.handles.rotate
local centerX, centerY = Interaction.LevelToScreen(workshop.controls.canvasTransform,
    spring.transform.x, spring.transform.y)
dragWorkspace(context, workshop, rotateHandle.x, rotateHandle.y, centerX + 100, centerY)
expect(spring.transform.rotation ~= beforeRotation, "rotation handle gesture did not update angle")

local countBeforeDelete = #workshop.document.objects
clickControl(context, workshop, "deleteObject")
expect(#workshop.document.objects == countBeforeDelete - 1 and workshop.selectedObjectId == nil,
    "delete-object control did not remove the selected object")

clickControl(context, workshop, "export")
expect(workshop.modal and workshop.modal.kind == "export", "export control did not open JSON panel")
local exportedText = workshop.modal.payload.text
clickModalButton(context, workshop, "copy")
expect(ui.clipboard == exportedText and workshop.status:find("已复制", 1, true),
    "verified clipboard export did not report success")
clickModalButton(context, workshop, "close")

local readClipboard = ui.GetClipboardText
ui.GetClipboardText = function() return "clipboard-mismatch" end
clickControl(context, workshop, "export")
clickModalButton(context, workshop, "copy")
expect(workshop.status:find("未确认写入", 1, true),
    "clipboard read-back mismatch was reported as success")
ui.GetClipboardText = readClipboard
clickModalButton(context, workshop, "close")

context.WorkshopOpenImport()
workshop.textEdit.value, workshop.textEdit.selectAll = "not-json", false
clickModalButton(context, workshop, "confirm")
expect(workshop.modal and workshop.modal.kind == "import"
    and workshop.status:find("导入失败", 1, true),
    "malformed JSON closed the import panel or reported success")
clickModalButton(context, workshop, "cancel")

context.WorkshopOpenImport()
workshop.textEdit.value, workshop.textEdit.selectAll = string.rep("x", 1024 * 1024 + 1), false
clickModalButton(context, workshop, "confirm")
expect(workshop.modal and workshop.modal.kind == "import"
    and workshop.status:find("超过", 1, true),
    "oversized JSON bypassed the import limit")
clickModalButton(context, workshop, "cancel")

local documentBeforeCompletion = LevelDocument.Clone(workshop.document)
expect(context.BeginWorkshopPreview(), "completion preview did not start")
context.success_, context.failed_ = true, false
expect(context.ExitWorkshopPreview("complete") and context.screen_ == "workshop"
    and workshop.status:find("预览已完成", 1, true)
    and workshop.document.levelId == documentBeforeCompletion.levelId,
    "preview completion did not return to the isolated editor snapshot")
expect(context.BeginWorkshopPreview(), "failure preview did not start")
context.success_, context.failed_ = false, true
expect(context.ExitWorkshopPreview("failed") and context.screen_ == "workshop"
    and workshop.status:find("恢复编辑快照", 1, true),
    "preview failure did not return to edit mode")

context.WorkshopAddObject("wall")
context.HandleWorkshopScreenMode()
local continueContext = newTestContext(context.frame_)
expect(continueContext.OpenLevelWorkshop("level_01")
    and continueContext.WorkshopOpenEntry("custom:custom_002"),
    "draft continuation context could not open the custom level")
expect(continueContext.workshopState_.modal
    and continueContext.workshopState_.modal.kind == "recovery",
    "draft continuation did not offer recovery choices")
local continuedDraftCount = #continueContext.workshopState_.modal.draft.document.objects
continueContext.WorkshopResolveModal("continue")
expect(continueContext.workshopState_.modal == nil and continueContext.workshopState_.dirty
    and #continueContext.workshopState_.document.objects == continuedDraftCount,
    "continue-editing did not restore the draft document")

local recoveryContext = State.New({
    DesignSpace = designStub,
    Rules = Rules,
    ReplayMode = { NONE = 0 },
    LevelData = LevelData,
    LevelDocument = LevelDocument,
}, { CONFIG = { pixelsPerMeter = 100, levelCount = 2 } })
recoveryContext.frame_ = context.frame_
Controller.Install(recoveryContext)
expect(recoveryContext.OpenLevelWorkshop("level_01")
    and recoveryContext.WorkshopOpenEntry("custom:custom_002"),
    "saved draft could not be discovered after restart")
expect(recoveryContext.workshopState_.modal and recoveryContext.workshopState_.modal.kind == "recovery",
    "restart did not offer draft recovery choices")
recoveryContext.WorkshopResolveModal("saveAs")
expect(recoveryContext.workshopState_.document.levelId == "custom_003"
    and #recoveryContext.workshopState_.draftStore:LoadCustomLevels() == 3,
    "draft save-as did not persist a restart-safe custom baseline")

local recoveredLevelId = recoveryContext.workshopState_.document.levelId
recoveryContext.HandleWorkshopScreenMode()
local discardContext = newTestContext(context.frame_)
expect(discardContext.OpenLevelWorkshop("level_01")
    and discardContext.WorkshopOpenEntry("custom:" .. recoveredLevelId),
    "draft discard context could not open the recovered custom level")
expect(discardContext.workshopState_.modal
    and discardContext.workshopState_.modal.kind == "recovery",
    "discard coverage did not discover the saved draft")
discardContext.WorkshopResolveModal("discard")
expect(discardContext.workshopState_.modal == nil and not discardContext.workshopState_.dirty
    and discardContext.workshopState_.draftStore:LoadDraft(recoveredLevelId) == nil,
    "discard-draft did not delete the draft or retain the formal baseline")

local entriesBeforeFailedImport = #workshop.repository:List()
local saveCustom = workshop.draftStore.SaveCustom
workshop.draftStore.SaveCustom = function() return false, "injected persistence failure" end
context.WorkshopOpenImport()
workshop.textEdit.value = cjson.encode(importedDocument)
workshop.textEdit.selectAll = false
expect(not context.WorkshopConfirmImport()
    and #workshop.repository:List() == entriesBeforeFailedImport
    and workshop.modal and workshop.modal.kind == "import"
    and workshop.status:find("导入失败", 1, true),
    "failed import persistence left a repository entry or reported success")
workshop.draftStore.SaveCustom = saveCustom
clickModalButton(context, workshop, "cancel")

local platformFunction = GetPlatform
function GetPlatform() return "Web" end
local managementContext = newTestContext(context.frame_)
expect(managementContext.OpenLevelWorkshop("level_01"),
    "memory-only management context could not open the workshop")
GetPlatform = platformFunction
local management = managementContext.workshopState_
clickControl(managementContext, management, "file_new")
local managedEntryId, managedLevelId = management.entryId, management.document.levelId
expect(managedEntryId:match("^custom:") and management.dirty,
    "new-level control did not create an editable custom level")
clickControl(managementContext, management, "file_rename")
expect(management.modal and management.modal.kind == "rename", "rename control did not open its modal")
replaceTextAndCommit(managementContext, management, "主策命名关卡")
expect(management.document.name == "主策命名关卡" and management.dirty,
    "rename text input did not update the active custom level")
clickControl(managementContext, management, "save")
expect(not management.dirty
    and management.repository:Open(managedEntryId).name == "主策命名关卡",
    "renamed custom level was not formally saved")
clickControl(managementContext, management, "file_delete")
expect(management.modal and management.modal.kind == "confirmDelete",
    "delete-level control did not request confirmation")
clickModalButton(managementContext, management, "confirm")
expect(management.repository:GetEntry(managedEntryId) == nil
    and management.draftStore:LoadDraft(managedLevelId) == nil
    and management.entryId:match("^official:"),
    "confirmed custom-level deletion left repository or draft state behind")

context.frame_ = {
    systemLogicalWidth = 800, systemLogicalHeight = 450,
    logicalWidth = 1880, logicalHeight = 1057.5,
}
workshop.view.drawerMode = nil
context.UpdateLevelWorkshop(0, { x = 0, y = 0, down = false, pressed = false, released = false })
expect(workshop.layout.supported and workshop.layout.mobileCompact,
    "common phone landscape size was rejected by the workshop")
local fileTab = workshop.layout.drawerTabs.files
local pointerScale = workshop.layout.coordinateScale
context.UpdateLevelWorkshop(0, {
    x = (fileTab.x + fileTab.w * 0.5) / pointerScale,
    y = (fileTab.y + fileTab.h * 0.5) / pointerScale,
    down = true, pressed = true, released = false,
})
expect(workshop.view.drawerMode == "files",
    "phone landscape pointer conversion missed the file drawer tab")
local inspectorTab = workshop.layout.drawerTabs.inspector
clickRect(context, workshop, inspectorTab)
expect(workshop.view.drawerMode == "inspector" and workshop.layout.right and not workshop.layout.left,
    "phone top tabs did not switch from files to Inspector")
inspectorTab = workshop.layout.drawerTabs.inspector
clickRect(context, workshop, inspectorTab)
expect(workshop.view.drawerMode == nil and not workshop.layout.right and not workshop.layout.left,
    "phone Inspector tab could not collapse the open drawer")
fileTab = workshop.layout.drawerTabs.files
clickRect(context, workshop, fileTab)
expect(workshop.view.drawerMode == "files" and workshop.layout.left and not workshop.layout.right,
    "phone file tab could not reopen the file drawer")

context.frame_ = {
    systemLogicalWidth = 567, systemLogicalHeight = 299,
    logicalWidth = 1880, logicalHeight = 993,
}
workshop.dirty = true
input.pressedKey = KEY_ESCAPE
context.UpdateLevelWorkshop(0, { x = 0, y = 0, down = false, pressed = false, released = false })
expect(context.screen_ == "catalog" and not workshop.dirty
    and workshop.draftStore:LoadDraft(workshop.document.levelId) ~= nil,
    "unsupported-size escape trapped the editor or lost its dirty draft")

print(string.format('{"mode":"WORKSHOP_CONTROLLER","checks":%d,"status":"pass"}', checks))
