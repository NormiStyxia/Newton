package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local LevelDocument = require("game.level.LevelDocument")
local LevelData = require("game.level.LevelData")

local disposed = false
cache = {
    GetFile = function()
        return {
            IsOpen = function() return true end,
            ReadString = function() return "{}" end,
            Dispose = function() disposed = true end,
        }
    end,
    Exists = function() return false end,
}
cjson = {
    decode = function()
        return LevelDocument.New("resource_probe", "Resource probe")
    end,
}

local loaded, loadError = LevelData.Load("Data/Levels/level_01.json")
expect(loaded ~= nil and loadError == nil, "readable level was rejected by an Exists false negative")
expect(loaded.levelId == "resource_probe", "loaded document was not decoded and normalized")
expect(disposed, "level resource file was not disposed")

cache.GetFile = function() return nil end
local missing, missingError = LevelData.Load("Data/Levels/missing.json")
expect(missing == nil and missingError == "关卡资源不存在：Data/Levels/missing.json",
    "missing level diagnostic changed")

print(string.format("LEVEL_RESOURCE_CONTRACT\t%d checks", checks))
