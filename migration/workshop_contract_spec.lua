package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local LevelDocument = require("game.level.LevelDocument")
local Repository = require("game.workshop.Repository")
local History = require("game.workshop.History")
local DraftStore = require("game.workshop.DraftStore")
local Export = require("game.workshop.Export")
local Layout = require("game.workshop.Layout")
local Interaction = require("game.workshop.Interaction")
local Selection = require("game.workshop.Selection")
local TextTransfer = require("game.workshop.TextTransfer")
local TextEditor = require("game.workshop.TextEditor")
local Numeric = require("game.workshop.Numeric")
local TouchScroller = require("game.workshop.TouchScroller")
local Inspector = require("game.workshop.Inspector")
local DocumentActions = require("game.workshop.DocumentActions")
local View = require("game.workshop.View")
local ExperimentCatalog = require("ui.ExperimentCatalog")
local WorldPrimitives = require("game.render.WorldPrimitives")

local function validLevel(id, name)
    local document = LevelDocument.New(id, name)
    document.objects[#document.objects + 1] = LevelDocument.NewObject("wall", "wall_001", 500, 300)
    return document
end

local legacy = validLevel("legacy", "Legacy")
legacy.objects[1].properties.launchAngle, legacy.objects[1].properties.launchPower = 35, 0.8
legacy.objects[2].properties.requiredStayTime, legacy.objects[2].properties.targetTag = 700, "apple"
legacy.objects[3].properties.friction, legacy.objects[3].properties.restitution = 0.62, 0.32
local legacyButton = LevelDocument.NewObject("button", "button_001", 700, 300)
legacyButton.properties.activationType = "apple"
legacy.objects[#legacy.objects + 1] = legacyButton
local normalizedLegacy, legacyMigrations = LevelDocument.Normalize(legacy)
expect(normalizedLegacy.objects[1].properties.launchAngle == nil
    and normalizedLegacy.objects[1].properties.launchPower == nil
    and normalizedLegacy.objects[2].properties.targetTag == nil
    and normalizedLegacy.objects[2].properties.requiredStayTime == 1000
    and normalizedLegacy.objects[3].properties.friction == nil
    and normalizedLegacy.objects[3].properties.restitution == nil
    and normalizedLegacy.objects[4].properties.activationType == nil
    and #legacyMigrations >= 7,
    "deprecated Phaser-only fields were retained or the 1000ms goal contract changed")

local repository = Repository.New({ LevelDocument = LevelDocument })
local errors = repository:InitializeOfficial(2, function(index)
    return validLevel(string.format("level_%02d", index), "官方关卡 " .. tostring(index))
end)
expect(#errors == 0, "official repository initialization failed")
expect(#repository:List() == 2, "official repository list count")

local official = repository:Open("official:level_01")
official.name = "非法修改"
expect(repository:Open("official:level_01").name ~= "非法修改", "official document leaked mutable reference")
local officialReplace, officialError = repository:ReplaceCustom("official:level_01", official)
expect(not officialReplace and officialError == "官方关卡为只读", "official overwrite was accepted")

local custom, customMetadata = repository:CopyAsCustom("official:level_01")
expect(custom.levelId == "custom_001" and customMetadata.sourceKind == "custom"
    and custom.originLevelId == "level_01" and custom.sourceKind == nil,
    "official copy did not isolate runtime identity or preserve provenance")
custom.name = "主策草稿"
expect(repository:ReplaceCustom(customMetadata.entryId, custom), "custom replacement failed")
expect(repository:Open("official:level_01").name == "官方关卡 1", "custom edit polluted official document")

local importRepository = Repository.New({ LevelDocument = LevelDocument })
local officialLookingImport = validLevel("level_02", "Imported official-looking JSON")
officialLookingImport.sourceKind = "official"
local importedCustom, importedMetadata = importRepository:ImportAsCustom(officialLookingImport)
expect(importedCustom and importedCustom.levelId == "custom_001"
    and importedCustom.sourceKind == nil and importedMetadata.sourceKind == "custom",
    "imported JSON was allowed to grant itself official runtime identity")

local precisionRepository = Repository.New({ LevelDocument = LevelDocument })
local precisionOfficial = validLevel("precision_official", "Precision official")
precisionOfficial.objects[3].transform.x = 1219.8025366858
precisionOfficial.objects[3].transform.rotation = -0.0004
expect(#precisionRepository:InitializeOfficial(1, function() return precisionOfficial end) == 0,
    "precision official fixture failed to initialize")
local openedPrecisionOfficial = precisionRepository:Open("official:precision_official")
expect(math.abs(openedPrecisionOfficial.objects[3].transform.x - 1219.8025366858) < 1e-10
    and openedPrecisionOfficial.objects[3].transform.rotation == -0.0004,
    "loading an old JSON changed transform precision")
local copiedPrecision = precisionRepository:CopyAsCustom("official:precision_official")
expect(copiedPrecision and math.abs(copiedPrecision.objects[3].transform.x - 1219.803) < 1e-9
    and copiedPrecision.objects[3].transform.rotation == 0,
    "new custom copy did not normalize transform precision")

local secondCustom = repository:CreateCustom("第二份草稿")
expect(secondCustom.levelId == "custom_002", "custom level IDs are not monotonic")
expect(repository:NextObjectId(custom, "wall") == "wall_002", "object ID generation collided")
expect(repository:DeleteCustom(customMetadata.entryId), "custom delete failed")
expect(repository:Open(customMetadata.entryId) == nil, "deleted custom level remained addressable")

local levelInspectorFields = Inspector.Build({
    document = validLevel("custom_inspector", "Inspector"),
    readOnly = false,
    selectedObject = nil,
}, LevelDocument, { CARDS = {} }, {})
local forbiddenInspectorKeys = {
    ["playfield.width"] = true, ["playfield.height"] = true,
    ["gravity.x"] = true, ["gravity.y"] = true, ["gravity.strength"] = true,
}
local exposedWorldField = nil
for _, field in ipairs(levelInspectorFields) do
    if forbiddenInspectorKeys[field.key] then exposedWorldField = field.key; break end
end
expect(exposedWorldField == nil,
    "playfield dimensions or initial gravity were exposed through the level Inspector")

local function objectInspectorKeys(object)
    local keys = {}
    local fields = Inspector.Build({ document = validLevel("field_filter", "Field Filter"),
        readOnly = false, selectedObject = object }, LevelDocument, { CARDS = {} }, {})
    for _, field in ipairs(fields) do keys[field.key] = field end
    return keys
end
local springForInspector = LevelDocument.NewObject("spring", "spring_filter", 500, 300)
local springKeys = objectInspectorKeys(springForInspector)
expect(springKeys["properties.direction"]
    and springKeys["properties.impulseStrength"]
    and not springKeys["properties.cooldown"]
    and not springKeys["properties.oneShot"] and not springKeys["properties.enabled"]
    and not springKeys["properties.enabledChannel"] and springForInspector.properties.impulseStrength ~= nil,
    "spring Inspector did not expose impulse strength while hiding the requested controls")
local goalForInspector = LevelDocument.NewObject("goal_sensor", "goal_filter", 500, 300)
local goalKeys = objectInspectorKeys(goalForInspector)
expect(goalKeys["transform.x"] and goalKeys["transform.y"]
    and not goalKeys["transform.width"] and not goalKeys["transform.height"]
    and not goalKeys["transform.rotation"] and not goalKeys["properties.requiredStayTime"]
    and goalForInspector.properties.requiredStayTime == 1000,
    "goal Inspector did not hide size/rotation/stay-time controls while preserving runtime data")
local buttonKeys = objectInspectorKeys(LevelDocument.NewObject("button", "button_labels", 500, 300))
expect(buttonKeys["properties.mode"].valueLabels.HOLD == "持续按压"
    and buttonKeys["properties.mode"].valueLabels.TOGGLE == "切换"
    and View.FieldValue(buttonKeys["properties.mode"]) == "持续按压",
    "runtime enum values were not translated for Inspector display")
local levelIdField = nil
for _, field in ipairs(levelInspectorFields) do if field.key == "level.id" then levelIdField = field end end
expect(levelIdField and levelIdField.label == "关卡 ID", "exposed levelId label was not localized")

local edit = TextEditor.Initialize({ value = "甲乙C" }, false, 0)
TextEditor.Move(edit, -1, 0)
expect(TextEditor.Insert(edit, "中", 64) and edit.value == "甲乙中C" and edit.cursor == 3,
    "UTF-8 insertion did not respect the cursor")
TextEditor.Backspace(edit, 0)
expect(edit.value == "甲乙C" and edit.cursor == 2, "UTF-8 Backspace removed the wrong character")
TextEditor.Home(edit, 0)
TextEditor.Delete(edit, 0)
expect(edit.value == "乙C" and edit.cursor == 0, "Delete/Home did not operate at the UTF-8 cursor")
TextEditor.End(edit, 0)
TextEditor.Move(edit, -1, 0)
expect(edit.cursor == 1, "Left/Right/End cursor navigation is inconsistent")
TextEditor.SetCursorFromX(edit, 4, function(value) return TextEditor.Length(value) * 10 end, 0)
expect(edit.cursor == 0, "pointer-to-cursor positioning missed the nearest UTF-8 boundary")

local gesture, touchResult = TouchScroller.Update(nil,
    { x = 20, y = 80, down = true, pressed = true, released = false, isTouch = true },
    { { id = "inspector", rect = { x = 0, y = 0, w = 100, h = 100 }, value = 0, maximum = 200 } }, 8)
expect(gesture and touchResult.consume and not touchResult.tap, "touch scroll did not defer the initial tap")
gesture, touchResult = TouchScroller.Update(gesture,
    { x = 20, y = 40, down = true, pressed = false, released = false, isTouch = true }, {}, 8)
expect(touchResult.value == 40 and touchResult.target == "inspector",
    "touch scroll distance was not mapped to panel offset")
gesture, touchResult = TouchScroller.Update(gesture,
    { x = 20, y = 40, down = false, pressed = false, released = true, isTouch = true }, {}, 8)
expect(not gesture and touchResult.consume and not touchResult.tap,
    "completed touch swipe leaked through as a row click")

local history = History.New({ clone = LevelDocument.Clone, limit = 4 })
local historyDocument = validLevel("custom_history", "A")
history:Reset(historyDocument, { selectedObjectId = "wall_001" })
historyDocument.name = "B"
history:Push(historyDocument, { selectedObjectId = "goal_main" }, "rename")
historyDocument.name = "C"
history:Push(historyDocument, { selectedObjectId = "launcher_main" }, "rename again")
local undoDocument, undoView = history:Undo()
expect(undoDocument.name == "B" and undoView.selectedObjectId == "goal_main", "undo snapshot mismatch")
local redoDocument, redoView = history:Redo()
expect(redoDocument.name == "C" and redoView.selectedObjectId == "launcher_main", "redo snapshot mismatch")

local codecStore, codecIndex = {}, 0
local fakeJson = {}
function fakeJson.encode(value)
    codecIndex = codecIndex + 1
    local token = "json-" .. tostring(codecIndex)
    codecStore[token] = LevelDocument.Clone(value)
    return token
end
function fakeJson.decode(token)
    assert(codecStore[token], "unknown JSON token")
    return LevelDocument.Clone(codecStore[token])
end

local precisionDisplay = { key = "transform.x", kind = "number", value = 1219.8025366858 }
expect(View.FieldValue(precisionDisplay) == "1219.80"
    and View.FieldValue({ key = "transform.rotation", kind = "number", value = -0.0004 }) == "0.00",
    "Inspector transform values were not formatted to two decimals without negative zero")
expect(Numeric.FormatEditValue("transform.x", 1219.8025366858) == "1219.803"
    and Numeric.Round(-1.2345, 3) == -1.235,
    "numeric edit formatting or negative rounding is incorrect")
local precisionDocument = validLevel("precision_document", "Precision document")
precisionDocument.objects[3].transform.x = 1219.8025366858
precisionDocument.objects[3].transform.y = -0.0004
local precisionSnapshot = Numeric.NormalizeDocument(LevelDocument.Clone(precisionDocument))
expect(math.abs(precisionSnapshot.objects[3].transform.x - 1219.803) < 1e-9
    and precisionSnapshot.objects[3].transform.y == 0
    and precisionDocument.objects[3].transform.x == 1219.8025366858,
    "document normalization mutated the source or mishandled negative zero")

local precisionDraftStore = DraftStore.New({ clone = LevelDocument.Clone, json = fakeJson })
local precisionDraft = validLevel("precision_draft", "Precision draft")
precisionDraft.objects[3].transform.x = 1219.8025366858
precisionDraft.objects[3].transform.rotation = -0.0004
expect(precisionDraftStore:SaveDraft(precisionDraft.levelId, precisionDraft, {}, "custom"),
    "precision draft save failed")
local savedPrecisionDraft = precisionDraftStore:LoadDraft(precisionDraft.levelId)
expect(savedPrecisionDraft and math.abs(savedPrecisionDraft.document.objects[3].transform.x - 1219.803) < 1e-9
    and savedPrecisionDraft.document.objects[3].transform.rotation == 0
    and precisionDraft.objects[3].transform.x == 1219.8025366858,
    "draft persistence did not normalize only its saved transform snapshot")

local precisionCustom = validLevel("precision_custom", "Precision custom")
precisionCustom.objects[3].transform.y = -42.98765
expect(precisionDraftStore:SaveCustom(precisionCustom), "precision custom save failed")
local savedPrecisionCustom = precisionDraftStore:LoadCustomLevels()[1]
expect(savedPrecisionCustom and math.abs(savedPrecisionCustom.document.objects[3].transform.y - (-42.988)) < 1e-9
    and precisionCustom.objects[3].transform.y == -42.98765,
    "custom persistence did not normalize only its saved transform snapshot")

local precisionExport = validLevel("precision_export", "Precision export")
precisionExport.objects[3].transform.x = 1219.8025366858
precisionExport.objects[3].transform.rotation = -0.0004
local precisionExportPayload = Export.Prepare(precisionExport, LevelDocument, fakeJson)
local decodedPrecisionExport = precisionExportPayload and fakeJson.decode(precisionExportPayload.text)
expect(decodedPrecisionExport and math.abs(decodedPrecisionExport.objects[3].transform.x - 1219.803) < 1e-9
    and decodedPrecisionExport.objects[3].transform.rotation == 0
    and precisionExport.objects[3].transform.x == 1219.8025366858,
    "export did not normalize serialized transform precision without mutating the source")

local fakeFiles = {}
local fakeAdapter = { kind = "contract-slot" }
function fakeAdapter:createDir(_) return true end
function fakeAdapter:exists(path) return fakeFiles[path] ~= nil end
function fakeAdapter:delete(path) fakeFiles[path] = nil; return true end
function fakeAdapter:rename(source, destination)
    if fakeFiles[source] == nil then return false end
    fakeFiles[destination], fakeFiles[source] = fakeFiles[source], nil
    return true
end
function fakeAdapter:write(path, text) fakeFiles[path] = text; return true end
function fakeAdapter:read(path) return fakeFiles[path] end
function fakeAdapter:list(path, _)
    local names = {}
    local prefix = path .. "/"
    for key in pairs(fakeFiles) do
        local name = key:sub(1, #prefix) == prefix and key:sub(#prefix + 1) or nil
        if name and name:match("%.json$") then names[#names + 1] = name end
    end
    return names
end

local savedPlatform, savedFile, savedFileSystem = _G.GetPlatform, _G.File, _G.fileSystem
local savedRead, savedWrite, savedScan = _G.FILE_READ, _G.FILE_WRITE, _G.SCAN_FILES
_G.GetPlatform = function() return "Web" end
_G.File, _G.fileSystem, _G.FILE_READ, _G.FILE_WRITE = function() end, {}, 1, 2
expect(DraftStore.CreateLocalAdapter() == nil,
    "Web memory filesystem was advertised as durable persistence")

local localFileClosed = false
_G.GetPlatform = function() return "Windows" end
_G.fileSystem = {
    CreateDir = function() return true end,
    FileExists = function() return false end,
    Delete = function() return true end,
    Rename = function() return true end,
    ScanDir = function() return {} end,
}
_G.File = function()
    return {
        IsOpen = function() return true end,
        WriteString = function() return false end,
        Close = function() localFileClosed = true end,
    }
end
_G.SCAN_FILES = 0
local localAdapter = DraftStore.CreateLocalAdapter()
expect(localAdapter and not localAdapter:write("slot.json", "payload") and localFileClosed,
    "File:WriteString failure was ignored or the file was not closed")
_G.GetPlatform, _G.File, _G.fileSystem = savedPlatform, savedFile, savedFileSystem
_G.FILE_READ, _G.FILE_WRITE, _G.SCAN_FILES = savedRead, savedWrite, savedScan

local now = 1000
local store = DraftStore.New({
    clone = LevelDocument.Clone,
    json = fakeJson,
    adapter = fakeAdapter,
    clock = function() now = now + 1; return now end,
})
local draftDocument = validLevel("custom_draft", "未完成")
local saved, saveResult = store:SaveDraft(draftDocument.levelId, draftDocument, { zoom = 1.2 }, "custom")
expect(saved and saveResult.persisted, "draft did not persist through adapter")
draftDocument.name = "运行时变更"
local loadedDraft = store:LoadDraft("custom_draft")
expect(loadedDraft.document.name == "未完成" and loadedDraft.viewState.zoom == 1.2, "draft leaked mutable state")
expect(#store:ListDrafts() == 1, "draft list mismatch")

loadedDraft.document.name = "第二版"
expect(store:SaveDraft("custom_draft", loadedDraft.document, { zoom = 1.4 }, "custom"),
    "second draft save failed")
fakeFiles["level-workshop/drafts/custom_draft.json"] = "corrupted-token"
local recoveryStore = DraftStore.New({
    clone = LevelDocument.Clone,
    json = fakeJson,
    adapter = fakeAdapter,
    clock = function() return now end,
})
local recoveredDraft = recoveryStore:LoadDraft("custom_draft")
expect(recoveredDraft and recoveredDraft.document.name == "未完成",
    "corrupted primary draft did not recover its previous backup")
fakeFiles["level-workshop/drafts/custom_draft.json"] = fakeFiles["level-workshop/drafts/custom_draft.json.bak"]

expect(store:SaveCustom(loadedDraft.document), "custom level save failed")
local restoredLevels = store:LoadCustomLevels()
expect(#restoredLevels == 1 and restoredLevels[1].document.levelId == "custom_draft", "custom level restore mismatch")
store:DeleteCustom("custom_draft")
expect(#store:LoadCustomLevels() == 0 and #store:ListDrafts() == 0, "custom delete left persistent state")

local failingAdapter = { kind = "failing-slot" }
function failingAdapter:createDir(_) return false end
function failingAdapter:exists(_) return false end
function failingAdapter:delete(_) return false end
function failingAdapter:rename(_, _) return false end
function failingAdapter:write(_, _) return false end
function failingAdapter:read(_) return nil end
function failingAdapter:list(_, _) error("list unavailable") end
local failureStore = DraftStore.New({ clone = LevelDocument.Clone, json = fakeJson, adapter = failingAdapter })
local memorySaved, memoryResult = failureStore:SaveDraft("custom_memory", validLevel("custom_memory", "内存草稿"), {})
expect(memorySaved and memoryResult.memory and not memoryResult.persisted,
    "persistent write failure also discarded the runtime memory draft")
expect(#failureStore:ListDrafts() == 1,
    "persistent list failure hid the runtime memory draft")

local deleteFiles, failDelete = {}, false
local deleteFailureAdapter = { kind = "delete-failure-slot" }
function deleteFailureAdapter:createDir(_) return true end
function deleteFailureAdapter:exists(path) return deleteFiles[path] ~= nil end
function deleteFailureAdapter:delete(path)
    if failDelete then return false end
    deleteFiles[path] = nil
    return true
end
function deleteFailureAdapter:rename(source, destination)
    if deleteFiles[source] == nil then return false end
    deleteFiles[destination], deleteFiles[source] = deleteFiles[source], nil
    return true
end
function deleteFailureAdapter:write(path, text) deleteFiles[path] = text; return true end
function deleteFailureAdapter:read(path) return deleteFiles[path] end
function deleteFailureAdapter:list(_, _) return {} end
local deleteFailureStore = DraftStore.New({
    clone = LevelDocument.Clone, json = fakeJson, adapter = deleteFailureAdapter,
})
local deleteDocument = validLevel("custom_delete_failure", "删除失败")
expect(deleteFailureStore:SaveDraft(deleteDocument.levelId, deleteDocument, {}),
    "delete failure fixture draft save failed")
expect(deleteFailureStore:SaveCustom(deleteDocument),
    "delete failure fixture custom save failed")
failDelete = true
local draftDeleted, draftDeleteError = deleteFailureStore:DeleteDraft(deleteDocument.levelId)
expect(not draftDeleted and draftDeleteError:match("删除失败") and #deleteFailureStore:ListDrafts() == 1,
    "persistent draft deletion failure was hidden or discarded the memory fallback")
local customDeleted, customDeleteError = deleteFailureStore:DeleteCustom(deleteDocument.levelId)
expect(not customDeleted and customDeleteError:match("删除失败") and #deleteFailureStore:LoadCustomLevels() == 1,
    "persistent custom deletion failure was hidden or discarded the memory fallback")

local exportPayload, exportError = Export.Prepare(validLevel("custom_export", "导出"), LevelDocument, fakeJson)
expect(exportPayload and not exportError, "export preparation failed")
expect(exportPayload.objectCount == 3 and exportPayload.schemaVersion == 1, "export statistics mismatch")
expect(Export.MAX_JSON_BYTES == Export.MAX_IMPORT_BYTES
    and Export.MAX_JSON_BYTES == Export.MAX_EXPORT_BYTES
    and exportPayload.maxBytes == Export.MAX_JSON_BYTES,
    "import and export did not expose one shared JSON byte limit")
local imported = fakeJson.decode(exportPayload.text)
expect(imported._editor == nil and imported.levelId == "custom_export", "export polluted runtime document")
local oversizedExport, oversizedExportError = Export.Prepare(validLevel("oversized_export", "超大导出"), LevelDocument, {
    encode = function() return string.rep("x", Export.MAX_JSON_BYTES + 1) end,
})
expect(not oversizedExport and oversizedExportError:match("导出 JSON") and oversizedExportError:match("超过"),
    "oversized JSON export remained available even though import rejects it")

local fullLayout = Layout.Resolve({
    systemLogicalWidth = 1880, systemLogicalHeight = 840,
    logicalWidth = 1880, logicalHeight = 840,
}, { drawerMode = "files" })
expect(fullLayout.supported and fullLayout.mode == "full" and fullLayout.left and fullLayout.right,
    "1880x840 workshop layout is not full mode")
expect(fullLayout.toolbar.draft and fullLayout.toolbar.save and fullLayout.toolbar.copyObject
    and fullLayout.toolbar.draft.x + fullLayout.toolbar.draft.w < fullLayout.toolbar.save.x,
    "draft, formal-save, or object-copy controls are missing or overlapping")
local catalogLayout = ExperimentCatalog.ResolveLayout({ logicalWidth = 1880, logicalHeight = 840 })
expect(catalogLayout.workshopButton.x >= catalogLayout.right.x
    and catalogLayout.workshopButton.x + catalogLayout.workshopButton.w <= catalogLayout.right.x + catalogLayout.right.w
    and catalogLayout.startButton.x + catalogLayout.startButton.w < catalogLayout.workshopButton.x,
    "pre-game workshop entry overlaps the start action or leaves its catalog panel")
local safeLayout = Layout.Resolve({
    systemLogicalWidth = 1880, systemLogicalHeight = 840,
    logicalWidth = 1880, logicalHeight = 840, dpr = 2, renderScale = 0.5,
    safeAreaInsets = { left = 80, top = 30, right = 40, bottom = 20 },
}, {})
expect(safeLayout.toolbar.exit.x == 40 and safeLayout.toolbar.exit.y == 16
    and safeLayout.right.x + safeLayout.right.w == 1860
    and safeLayout.bottom.y == 786,
    "physical safe-area insets were not converted into system logical coordinates")
local foldedLayout = Layout.Resolve({
    systemLogicalWidth = 1280, systemLogicalHeight = 640,
    logicalWidth = 1880, logicalHeight = 940,
}, { drawerMode = "inspector" })
expect(foldedLayout.supported and foldedLayout.mode == "folded" and foldedLayout.right and not foldedLayout.left,
    "narrow landscape workshop layout did not use inspector drawer")
local standardNarrowLayout = Layout.Resolve({
    systemLogicalWidth = 1366, systemLogicalHeight = 768,
    logicalWidth = 1880, logicalHeight = 1057,
}, { drawerMode = "files" })
expect(standardNarrowLayout.supported and standardNarrowLayout.mode == "folded"
    and standardNarrowLayout.left and standardNarrowLayout.canvasViewport.w > 0,
    "1366x768 workshop layout did not preserve an accessible canvas and file drawer")
local function checkMobileLandscape(width, height)
    local renderScale = math.min(width / 1880, height / 840)
    local layout = Layout.Resolve({
        systemLogicalWidth = width, systemLogicalHeight = height,
        logicalWidth = width / renderScale, logicalHeight = height / renderScale,
        renderScale = renderScale,
    }, { drawerMode = "files" })
    expect(layout.supported and layout.mode == "folded" and layout.mobileCompact,
        string.format("%dx%d mobile landscape was not accepted in compact mode", width, height))
    expect(layout.canvasViewport.w > 0 and layout.canvasViewport.h > 0,
        string.format("%dx%d mobile landscape lost the canvas viewport", width, height))
    expect(layout.toolbar.preview.x + layout.toolbar.preview.w + 6 <= layout.drawerTabs.files.x,
        string.format("%dx%d compact toolbar overlaps the drawer tabs", width, height))
    expect(layout.left and layout.paletteViewport
        and layout.paletteViewport.x >= layout.left.x
        and layout.paletteViewport.y >= layout.left.y
        and layout.paletteViewport.x + layout.paletteViewport.w <= layout.left.x + layout.left.w
        and layout.paletteViewport.y + layout.paletteViewport.h <= layout.left.y + layout.left.h,
        string.format("%dx%d object palette escaped the file drawer", width, height))

    local controlState = {
        entries = {}, supportedTypes = { "wall", "launcher", "goal_sensor", "spring", "button", "door" },
        view = {}, document = nil, inspectorFields = {},
    }
    local controls = View.BuildControls(controlState, layout, Interaction)
    expect(controls.byId.canvasTool
        and controls.byId.snap.x + controls.byId.snap.w < controls.byId.canvasTool.x
        and controls.byId.canvasTool.x + controls.byId.canvasTool.w < controls.byId.deleteObject.x,
        string.format("%dx%d canvas tool overlaps adjacent controls", width, height))
    local paletteRowsInside = #controls.paletteRows == #controlState.supportedTypes
    for _, row in ipairs(controls.paletteRows) do
        paletteRowsInside = paletteRowsInside
            and row.rect.x >= layout.paletteViewport.x
            and row.rect.y >= layout.paletteViewport.y
            and row.rect.x + row.rect.w <= layout.paletteViewport.x + layout.paletteViewport.w
            and row.rect.y + row.rect.h <= layout.paletteViewport.y + layout.paletteViewport.h
    end
    expect(paletteRowsInside,
        string.format("%dx%d object palette controls overflow or become inaccessible", width, height))

    local designX, designY = width * 0.5 / renderScale, height * 0.5 / renderScale
    local workspaceX, workspaceY = Layout.PointerToWorkspace(layout, designX, designY)
    expect(math.abs(workspaceX - width * 0.5) < 1e-9 and math.abs(workspaceY - height * 0.5) < 1e-9,
        string.format("%dx%d pointer conversion did not match workshop rendering", width, height))
    return layout
end

local minimumLayout = checkMobileLandscape(720, 360)
checkMobileLandscape(800, 360)
checkMobileLandscape(844, 390)
expect(minimumLayout.full.w == 720 and minimumLayout.full.h == 360,
    "minimum mobile landscape did not use system logical dimensions")
local ultraCompactLayout = checkMobileLandscape(568, 300)
checkMobileLandscape(640, 320)
expect(ultraCompactLayout.ultraCompact
    and ultraCompactLayout.canvasViewport.w > 0
    and ultraCompactLayout.canvasViewport.h > 0
    and ultraCompactLayout.fileViewport.h >= 0,
    "minimum ultra-compact phone landscape lost an accessible workspace")
local drawerProbeX, drawerProbeY = minimumLayout.drawer.x + 20, minimumLayout.drawer.y + 20
expect(not View.ControlHitAllowed(minimumLayout, "canvas", drawerProbeX, drawerProbeY)
    and not View.ControlHitAllowed(minimumLayout, "deleteObject", drawerProbeX, drawerProbeY)
    and View.ControlHitAllowed(minimumLayout, "file_new", drawerProbeX, drawerProbeY),
    "open mobile drawer did not occlude covered canvas input")
local standardToolbarLayout = Layout.Resolve({
    systemLogicalWidth = 960, systemLogicalHeight = 540,
    logicalWidth = 1880, logicalHeight = 1057.5,
    renderScale = 960 / 1880,
}, { drawerMode = nil })
expect(standardToolbarLayout.supported and not standardToolbarLayout.mobileCompact
    and standardToolbarLayout.canvasViewport.w > 0
    and standardToolbarLayout.title.x + standardToolbarLayout.title.w + 12
        <= standardToolbarLayout.drawerTabs.files.x,
    "960x540 standard toolbar or title overlaps the drawer tabs")
local notchedPhoneLayout = Layout.Resolve({
    systemLogicalWidth = 844, systemLogicalHeight = 390,
    logicalWidth = 1880, logicalHeight = 869,
    renderScale = 844 / 1880, dpr = 3,
    safeAreaInsets = { left = 141, top = 0, right = 141, bottom = 63 },
}, { drawerMode = "files" })
expect(notchedPhoneLayout.supported
    and notchedPhoneLayout.safeInsets.left == 47
    and notchedPhoneLayout.safeInsets.right == 47
    and notchedPhoneLayout.safeInsets.bottom == 21
    and notchedPhoneLayout.canvasViewport.w > 0
    and notchedPhoneLayout.toolbar.preview.x + notchedPhoneLayout.toolbar.preview.w + 6
        <= notchedPhoneLayout.drawerTabs.files.x,
    "phone safe-area simulation clips critical workshop controls")
local belowMinimumLayout = Layout.Resolve({
    systemLogicalWidth = 567, systemLogicalHeight = 299,
    logicalWidth = 1880, logicalHeight = 993,
    renderScale = 567 / 1880,
}, {})
expect(not belowMinimumLayout.supported and belowMinimumLayout.mode == "unsupported"
    and belowMinimumLayout.full.w == 567 and belowMinimumLayout.full.h == 299
    and belowMinimumLayout.renderScaleCompensation > 1,
    "below-minimum landscape was accepted or rendered in the wrong coordinate space")
local portraitLayout = Layout.Resolve({
    systemLogicalWidth = 720, systemLogicalHeight = 1280,
    logicalWidth = 1880, logicalHeight = 3342,
}, {})
expect(not portraitLayout.supported and portraitLayout.mode == "portrait",
    "portrait workshop layout was accepted")

local fakeRendererType = {}
function fakeRendererType:NineSlice(_, _, _, _, _, _, alpha)
    self.wallArtCalls = self.wallArtCalls + 1
    self.lastNineSliceAlpha = alpha
end
function fakeRendererType:Image(image, _, _, _, _, _, _, _, _)
    if image == 21 then self.launcherArtCalls = self.launcherArtCalls + 1
    elseif image == 22 then self.goalArtCalls = self.goalArtCalls + 1 end
end
function fakeRendererType:Circle() end
local previousNvgSave, previousNvgTranslate = nvgSave, nvgTranslate
local previousNvgRotate, previousNvgRestore = nvgRotate, nvgRestore
nvgSave, nvgTranslate, nvgRotate, nvgRestore = function() end, function() end, function() end, function() end
WorldPrimitives.Install(fakeRendererType, {}, function() return {} end, function() return {} end)
local fakeRenderer = setmetatable({
    vg = {}, wallArtCalls = 0, launcherArtCalls = 0, goalArtCalls = 0,
    images = { launcher = 21, goalObserver = 22 },
    skins = {
        wall = { topLeft = 1, top = 1, topRight = 1, left = 1, center = 1,
            right = 1, bottomLeft = 1, bottom = 1, bottomRight = 1 },
        wallNarrow = { topLeft = 2, top = 2, topRight = 2, left = 2, center = 2,
            right = 2, bottomLeft = 2, bottom = 2, bottomRight = 2 },
        door = { topLeft = 3, top = 3, topRight = 3, left = 3, center = 3,
            right = 3, bottomLeft = 3, bottom = 3, bottomRight = 3 },
        doorNarrow = { topLeft = 4, top = 4, topRight = 4, left = 4, center = 4,
            right = 4, bottomLeft = 4, bottom = 4, bottomRight = 4 },
    },
}, { __index = fakeRendererType })
expect(fakeRenderer:DrawWorkshopObjectArt(LevelDocument.NewObject("wall", "art_wall", 100, 100),
    0, 0, 120, 32, 0, .9), "workshop wall art did not reuse the runtime nine-slice skin")
expect(fakeRenderer:DrawWorkshopObjectArt(LevelDocument.NewObject("door", "art_door", 100, 100),
    0, 0, 70, 210, 0, .9), "workshop door art did not reuse the runtime nine-slice skin")
local runtimeDoorData = LevelDocument.NewObject("door", "runtime_door", 100, 100)
local runtimeDoor = {
    type = "door",
    data = runtimeDoorData,
    node = { position2D = { x = 100, y = 100 }, rotation2D = 0 },
    openness = 1,
}
local identityDesign = {
    WorldToLogical = function(_, x, y) return x, y end,
    WorldSizeToLogical = function(_, w, h) return w, h end,
}
local identityMapper = {
    LevelToWorld = function(_, x, y) return x, y end,
    LevelSizeToWorld = function(_, w, h) return w, h end,
}
fakeRenderer:DrawObject({}, runtimeDoor, {}, identityDesign, identityMapper)
expect(fakeRenderer.lastNineSliceAlpha == 51,
    "open runtime door did not preserve the nine-slice transparency state")
expect(fakeRenderer:DrawWorkshopObjectArt(LevelDocument.NewObject("launcher", "art_launcher", 100, 100),
    0, 0, 90, 90, 0, .9), "workshop launcher art did not reuse the runtime PNG handle")
expect(fakeRenderer:DrawWorkshopObjectArt(LevelDocument.NewObject("goal_sensor", "art_goal", 100, 100),
    0, 0, 100, 100, 0, .9), "workshop goal art did not reuse the runtime observer handle")
local phaseArt = LevelDocument.NewObject("wall", "art_phase", 100, 100)
phaseArt.properties.isPhaseable = true
expect(not fakeRenderer:DrawWorkshopObjectArt(phaseArt, 0, 0, 120, 32, 0, .9),
    "phase wall incorrectly claimed an image asset that the runtime does not have")
expect(fakeRenderer.wallArtCalls == 3 and fakeRenderer.launcherArtCalls == 1
    and fakeRenderer.goalArtCalls == 1,
    "workshop art helper did not route through the shared runtime image handles")
nvgSave, nvgTranslate, nvgRotate, nvgRestore =
    previousNvgSave, previousNvgTranslate, previousNvgRotate, previousNvgRestore

local mappingDocument = validLevel("mapping", "Mapping")
local transform = Interaction.CanvasTransform(mappingDocument,
    { x = 100, y = 100, w = 1000, h = 500 }, { zoom = 1, panX = 0, panY = 0 })
local screenX, screenY = Interaction.LevelToScreen(transform, 500, 300)
local levelX, levelY = Interaction.ScreenToLevel(transform, screenX, screenY)
expect(math.abs(levelX - 500) < 1e-9 and math.abs(levelY - 300) < 1e-9,
    "workshop canvas coordinate mapping is not reversible")
local rotated = LevelDocument.NewObject("wall", "rotated", 500, 300)
rotated.transform.width, rotated.transform.height, rotated.transform.rotation = 200, 20, 45
expect(Interaction.HitObject(rotated, 500, 300), "rotated object center was not selectable")
expect(not Interaction.HitObject(rotated, 700, 500), "rotated object hit test accepted a remote point")
local rotatedCorners = Interaction.ObjectScreenCorners(rotated, transform)
local cornerRect = { x = rotatedCorners[1].x - 3, y = rotatedCorners[1].y - 3, w = 6, h = 6 }
expect(Interaction.ObjectIntersectsScreenRect(rotated, transform, cornerRect),
    "marquee intersection missed a rotated object corner")
local forwardRect = Selection.MarqueeRect(120, 130, 300, 280, { x = 100, y = 100, w = 300, h = 220 })
local reverseRect = Selection.MarqueeRect(300, 280, 120, 130, { x = 100, y = 100, w = 300, h = 220 })
expect(forwardRect.x == reverseRect.x and forwardRect.y == reverseRect.y
    and forwardRect.w == reverseRect.w and forwardRect.h == reverseRect.h,
    "reverse-direction marquee did not normalize to the same rectangle")
local leftGroupWall = LevelDocument.NewObject("wall", "group_left", 100, 300)
local rightGroupWall = LevelDocument.NewObject("wall", "group_right", 100, 300)
rightGroupWall.transform.x = mappingDocument.playfield.width - rightGroupWall.transform.width * 0.5
local groupDeltaX, groupDeltaY = Interaction.ClampGroupDelta(mappingDocument, {
    { object = leftGroupWall, x = leftGroupWall.transform.x, y = leftGroupWall.transform.y },
    { object = rightGroupWall, x = rightGroupWall.transform.x, y = rightGroupWall.transform.y },
}, 20, 15)
expect(groupDeltaX == 0 and groupDeltaY == 15,
    "group boundary clamp did not preserve one shared movement delta")
local copyDocument = validLevel("copy_names", "Copy names")
local legacyCopy = LevelDocument.NewObject("wall", "wall_legacy", 400, 260)
legacyCopy.name = "墙体 副本 副本"
local numberedCopy = LevelDocument.NewObject("wall", "wall_numbered", 600, 260)
numberedCopy.name = "墙体 副本3"
copyDocument.objects[#copyDocument.objects + 1] = legacyCopy
copyDocument.objects[#copyDocument.objects + 1] = numberedCopy
local copied = DocumentActions.DuplicateObjects({ document = copyDocument }, {
    NextObjectId = function() return "wall_generated" end,
}, LevelDocument, Interaction, { legacyCopy })
expect(copied[1] and copied[1].name == "墙体 副本4",
    "legacy repeated copy suffix was not normalized before allocating the next number")
expect(Interaction.Snap(24, 10) == 20 and Interaction.Snap(26, 10) == 30,
    "grid snapping is unstable")

local unsafeDocument = validLevel("unsafe", "Unsafe")
unsafeDocument.metadata = { resourcePath = "Models/Arbitrary.mdl" }
expect(not LevelDocument.ValidateDetailed(unsafeDocument).valid,
    "untrusted JSON arbitrary resource reference was accepted")
local oversizedImport, oversizedError = Export.Deserialize(string.rep("x", Export.MAX_IMPORT_BYTES + 1), {})
expect(not oversizedImport and oversizedError:match("超过"), "oversized JSON import was accepted")

local clipboardValue = "{\"name\":\"中文关卡\"}"
local clipboard = { value = clipboardValue }
function clipboard:SetUseSystemClipboard(value) self.enabled = value end
function clipboard:SetClipboardText(value) self.value = value end
function clipboard:GetClipboardText() return self.value end
local clipboardRead = TextTransfer.ReadClipboard(clipboard, Export.MAX_IMPORT_BYTES)
expect(clipboardRead == clipboardValue and clipboard.enabled,
    "clipboard JSON read did not use the confirmed system clipboard API")
expect(TextTransfer.WriteClipboard(clipboard, "export-json") and clipboard.value == "export-json",
    "clipboard JSON write was not verified")
clipboard.value = string.rep("x", Export.MAX_IMPORT_BYTES + 1)
local oversizedClipboard, oversizedClipboardError = TextTransfer.ReadClipboard(clipboard, Export.MAX_IMPORT_BYTES)
expect(not oversizedClipboard and oversizedClipboardError:match("超过"),
    "oversized clipboard import bypassed the byte limit")

local modal = { scroll = 0 }
local virtualText = string.rep("0123456789", 80) .. "\n中文末尾"
TextTransfer.UpdateModal(modal, virtualText, { w = 140, h = 64 }, 12, 1.35)
expect(modal.scrollMax > 0 and #modal.previewText < #virtualText,
    "large JSON preview was not virtualized")
modal.scroll = modal.scrollMax
TextTransfer.UpdateModal(modal, virtualText, { w = 140, h = 64 }, 12, 1.35)
expect(modal.previewText:match("中文末尾") and modal.previewLastLine == #modal.textMetrics.lines,
    "virtual JSON preview could not reach the complete text tail")
local scoredDocument = validLevel("scored", "Scored")
scoredDocument.scoring = {
    profileId = "custom", metric = "ruleDeployCount",
    tiers = { { score = 100, maxInterventions = 1 }, { score = 60 } },
}
expect(LevelDocument.ValidateDetailed(scoredDocument).valid, "valid inline scoring was rejected")
scoredDocument.scoring.tiers[2].score = 101
expect(not LevelDocument.ValidateDetailed(scoredDocument).valid, "invalid inline score was accepted")

print(string.format('{"mode":"WORKSHOP_CONTRACT","checks":%d,"status":"pass"}', checks))
