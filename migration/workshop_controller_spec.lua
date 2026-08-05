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
function input:GetKeyDown(_) return false end
KEY_ESCAPE, KEY_CTRL, KEY_S, KEY_Z, KEY_Y, KEY_D, KEY_DELETE = 27, 1000, 83, 90, 89, 68, 127
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
        local decoded = cjson.decode(text)
        local normalized = LevelDocument.Normalize(decoded)
        local valid, errors = LevelDocument.Validate(normalized)
        if not valid then return nil, table.concat(errors, ";") end
        return normalized
    end,
}
local designStub = { New = function() return {} end }
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

context.WorkshopAddObject("wall")
context.HandleWorkshopScreenMode()
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
