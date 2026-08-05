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
local TextTransfer = require("game.workshop.TextTransfer")
local ExperimentCatalog = require("ui.ExperimentCatalog")

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
expect(custom.levelId == "custom_001" and customMetadata.sourceKind == "custom", "official copy did not isolate ID")
custom.name = "主策草稿"
expect(repository:ReplaceCustom(customMetadata.entryId, custom), "custom replacement failed")
expect(repository:Open("official:level_01").name == "官方关卡 1", "custom edit polluted official document")

local secondCustom = repository:CreateCustom("第二份草稿")
expect(secondCustom.levelId == "custom_002", "custom level IDs are not monotonic")
expect(repository:NextObjectId(custom, "wall") == "wall_002", "object ID generation collided")
expect(repository:DeleteCustom(customMetadata.entryId), "custom delete failed")
expect(repository:Open(customMetadata.entryId) == nil, "deleted custom level remained addressable")

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
local imported = fakeJson.decode(exportPayload.text)
expect(imported._editor == nil and imported.levelId == "custom_export", "export polluted runtime document")

local fullLayout = Layout.Resolve({
    systemLogicalWidth = 1880, systemLogicalHeight = 840,
    logicalWidth = 1880, logicalHeight = 840,
}, { drawerMode = "files" })
expect(fullLayout.supported and fullLayout.mode == "full" and fullLayout.left and fullLayout.right,
    "1880x840 workshop layout is not full mode")
expect(fullLayout.toolbar.draft and fullLayout.toolbar.save
    and fullLayout.toolbar.draft.x + fullLayout.toolbar.draft.w < fullLayout.toolbar.save.x,
    "draft and formal-save controls are missing or overlapping")
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
expect(safeLayout.toolbar.exit.x == 80 and safeLayout.toolbar.exit.y == 30
    and safeLayout.right.x + safeLayout.right.w == 1840
    and safeLayout.bottom.y == 786,
    "physical safe-area insets were not converted into Mode A workshop coordinates")
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
local minimumLayout = Layout.Resolve({
    systemLogicalWidth = 960, systemLogicalHeight = 540,
    logicalWidth = 1880, logicalHeight = 1057.5,
}, { drawerMode = nil })
expect(minimumLayout.supported and minimumLayout.mode == "folded"
    and minimumLayout.canvasViewport.w > 0 and minimumLayout.toolbar.preview.x >= 0,
    "minimum candidate landscape size lost critical workshop controls")
local belowMinimumLayout = Layout.Resolve({
    systemLogicalWidth = 959, systemLogicalHeight = 539,
    logicalWidth = 1880, logicalHeight = 1056,
}, {})
expect(not belowMinimumLayout.supported and belowMinimumLayout.mode == "unsupported",
    "below-minimum landscape was accepted")
local portraitLayout = Layout.Resolve({
    systemLogicalWidth = 720, systemLogicalHeight = 1280,
    logicalWidth = 1880, logicalHeight = 3342,
}, {})
expect(not portraitLayout.supported and portraitLayout.mode == "portrait",
    "portrait workshop layout was accepted")

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
