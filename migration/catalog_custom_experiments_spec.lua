package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local CatalogTransition = require("ui.ExperimentCatalogTransition")
local ExperimentCatalog = require("ui.ExperimentCatalog")
local LevelDocument = require("game.level.LevelDocument")
local LevelPresentation = require("game.level.Presentation")
local Rules = require("game.gameplay.Rules")
local SemanticActions = require("game.input.SemanticActions")

local function level(levelId, name)
    local document = LevelDocument.New(levelId, name)
    document.objects[#document.objects + 1] = LevelDocument.NewObject("wall", "wall_001", 500, 300)
    return document
end

local official = {
    level("level_01", "学院实验一"),
    level("level_02", "学院实验二"),
}
local custom = {
    { entryId = "custom:custom_001", document = level("custom_001", "自制实验一") },
    { entryId = "custom:custom_002", document = level("custom_002", "自制实验二") },
}
for index = 3, 9 do
    custom[#custom + 1] = {
        entryId = string.format("custom:custom_%03d", index),
        document = level(string.format("custom_%03d", index), "自制实验" .. tostring(index)),
    }
end
custom[1].document.author = ""
custom[1].document.description = ""
custom[2].document.author = "实验员乙"
custom[2].document.description = "第二份自制实验介绍"

local navigation = CatalogTransition.NewEntrance()
navigation:SetCatalogIdle()
local runtimeSession = nil
local openedWorkshopEntry = nil
local builtOfficialIndex = nil
local startedCustom = nil

local context
context = {
    CONFIG = { levelCount = #official },
    Rules = Rules,
    LevelPresentation = LevelPresentation,
    LEVEL_SCORE_PROFILES = {
        intervention_standard = {
            metric = "ruleDeployCount",
            tiers = {
                { score = 100, maxInterventions = 1, title = "精准实验", description = "一次干预" },
                { score = 60, title = "观测成立", description = "完成观测" },
            },
        },
    },
    DEFAULT_LEVEL_SCORE_PROFILE = "intervention_standard",
    catalogState_ = {
        category = "official",
        selectedIndex = 1,
        selectedOfficialIndex = 1,
        selectedCustomIndex = 1,
        levels = {}, officialLevels = {}, customLevels = {}, customEntries = {},
        scroll = 0, scrollMax = 0,
        listScroll = 0, listScrollMax = 0,
        officialListScroll = 0, customListScroll = 0,
        toastTime = 0,
    },
    experimentProgress_ = {
        ClearPendingFeedback = function() end,
        ConsumeFeedback = function() return nil end,
    },
    navigationTransition_ = navigation,
    input = {
        mouseMoveWheel = 0,
        GetKeyPress = function() return false end,
    },
    frame_ = {
        logicalWidth = 1880, logicalHeight = 840,
        physicalWidth = 1880, physicalHeight = 840,
    },
    screen_ = "catalog",
    levelIndex_ = 1,
    KEY_ESCAPE = 27,
    KEY_UP = 38,
    KEY_DOWN = 40,
    KEY_RETURN = 13,
    LoadLevelDefinition = function(index) return LevelDocument.Clone(official[index]), index end,
    WorkshopListCustomExperiments = function()
        local result = {}
        for _, record in ipairs(custom) do
            result[#result + 1] = {
                entryId = record.entryId,
                levelId = record.document.levelId,
                name = record.document.name,
                metadata = { entryId = record.entryId, sourceKind = "custom" },
                document = LevelDocument.Clone(record.document),
            }
        end
        return result
    end,
    WorkshopOpenCustomExperiment = function(entryId)
        for _, record in ipairs(custom) do
            if record.entryId == entryId then
                return LevelDocument.Clone(record.document), { entryId = entryId, sourceKind = "custom" }
            end
        end
        return nil, "missing custom experiment"
    end,
    StartRuntimeSessionFromDocument = function(document, options)
        startedCustom = { document = document, options = options }
        runtimeSession = { sourceKind = options.sourceKind, customLevelId = document.levelId }
        context.screen_ = options.screen
        return runtimeSession, nil
    end,
    GetRuntimeSession = function() return runtimeSession end,
    BuildLevel = function(index) builtOfficialIndex = index; context.screen_ = "game" end,
    OpenLevelWorkshop = function(entryId) openedWorkshopEntry = entryId; return true end,
    ReleaseLevelRuntime = function() runtimeSession = nil end,
    playUIClick = function() end,
}
setmetatable(context, { __index = _G })

ExperimentCatalog.Install(context)
context.InitializeExperimentCatalog()
expect(context.catalogState_.category == "official" and context.catalogState_.levels[1].levelId == "level_01",
    "catalog did not default to academy experiments")
expect(#context.catalogState_.customLevels == 9, "catalog did not read saved custom experiments")

local layout = ExperimentCatalog.ResolveLayout(context.frame_)
expect(math.abs(layout.listViewport.h / layout.listItemHeight - 8) < 1e-9,
    "catalog list does not reserve exactly eight visible rows")
context.UpdateExperimentCatalog(.016, {
    x = layout.categoryTabs.custom.x + layout.categoryTabs.custom.w * .5,
    y = layout.categoryTabs.custom.y + layout.categoryTabs.custom.h * .5,
    down = true, pressed = true, released = false,
})
expect(context.catalogState_.category == "custom" and context.catalogState_.levels[1].levelId == "custom_001",
    "custom category did not replace the active list")

local wheelPointer = SemanticActions.Attach({
    x = layout.listViewport.x + 60, y = layout.listViewport.y + 30,
    down = false, pressed = false, released = false,
}, {
    source = "mouse", hover = true, scrollY = -1,
})
context.UpdateExperimentCatalog(.016, wheelPointer)
expect(math.abs(context.catalogState_.listScroll - layout.listItemHeight * .42) < 1e-9,
    "catalog mouse wheel step is faster than the intended partial-row movement")
local scrollbarTrack = layout.listScrollbarTrack
context.UpdateExperimentCatalog(.016, {
    x = scrollbarTrack.x + scrollbarTrack.w * .5,
    y = scrollbarTrack.y + scrollbarTrack.h - 2,
    down = true, pressed = true, released = false,
})
expect(context.catalogState_.listScroll > context.catalogState_.listScrollMax * .9
    and context.catalogState_.listScrollbarDragOffset ~= nil,
    "catalog scrollbar track did not move or capture the draggable thumb")
context.UpdateExperimentCatalog(.016, {
    x = scrollbarTrack.x + scrollbarTrack.w * .5,
    y = scrollbarTrack.y + scrollbarTrack.h - 2,
    down = false, pressed = false, released = true,
})
expect(context.catalogState_.listScrollbarDragOffset == nil,
    "catalog scrollbar drag state was not released")
context.catalogState_.listScroll, context.catalogState_.customListScroll = 0, 0

local secondY = layout.listTop + layout.listItemHeight * 1.5
context.UpdateExperimentCatalog(.016, {
    x = layout.listViewport.x + 60, y = secondY,
    down = true, pressed = true, released = false,
})
context.UpdateExperimentCatalog(.016, {
    x = layout.listViewport.x + 60, y = secondY,
    down = false, pressed = false, released = true,
})
expect(context.catalogState_.selectedIndex == 2 and context.catalogState_.selectedCustomIndex == 2,
    "custom list selection did not update independently")
context.catalogState_.transition:Reset(2)

context.UpdateExperimentCatalog(.016, {
    x = layout.workshopButton.x + layout.workshopButton.w * .5,
    y = layout.workshopButton.y + layout.workshopButton.h * .5,
    down = true, pressed = true, released = false,
})
expect(openedWorkshopEntry == "custom:custom_002", "custom Workshop entry lost its repository identity")

expect(context.RequestStartLevel(2), "custom experiment failed to start")
expect(startedCustom and startedCustom.document.levelId == "custom_002"
    and startedCustom.options.sourceKind == "custom" and startedCustom.options.screen == "game",
    "custom experiment did not use the normal custom Runtime session")
expect(builtOfficialIndex == nil, "custom experiment incorrectly called BuildLevel")

expect(context.RequestReturnToCatalog(nil, true), "custom Runtime failed to return to catalog")
expect(context.catalogState_.category == "custom" and context.catalogState_.selectedIndex == 2,
    "returning from custom Runtime did not restore custom catalog selection")

context.UpdateExperimentCatalog(.016, {
    x = layout.categoryTabs.official.x + layout.categoryTabs.official.w * .5,
    y = layout.categoryTabs.official.y + layout.categoryTabs.official.h * .5,
    down = true, pressed = true, released = false,
})
expect(context.catalogState_.category == "official" and context.catalogState_.selectedIndex == 1,
    "academy category did not restore its independent selection")
expect(context.RequestStartLevel(2) and builtOfficialIndex == 2,
    "academy experiment no longer uses BuildLevel")

print(string.format('{"mode":"CATALOG_CUSTOM_EXPERIMENTS","checks":%d,"status":"pass"}', checks))
