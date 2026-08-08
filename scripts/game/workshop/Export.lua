local Export = {}
local Numeric = require("game.workshop.Numeric")
-- Import, export, clipboard and text editing must share one byte-based limit.
Export.MAX_JSON_BYTES = 1024 * 1024
Export.MAX_IMPORT_BYTES = Export.MAX_JSON_BYTES -- compatibility for existing callers
Export.MAX_EXPORT_BYTES = Export.MAX_JSON_BYTES -- explicit name for export callers

function Export.CheckSize(text, operation)
    if type(text) ~= "string" then return false, "JSON 文本必须是字符串" end
    if #text > Export.MAX_JSON_BYTES then
        return false, tostring(operation or "JSON") .. " JSON 超过 " .. tostring(Export.MAX_JSON_BYTES) .. " 字节限制"
    end
    return true, nil
end

local function characterCount(text)
    if utf8 and utf8.len then
        local ok, count = pcall(utf8.len, text)
        if ok and count then return count end
    end
    return #text
end

function Export.Serialize(document, levelDocument, json)
    if type(document) ~= "table" then return nil, "没有可导出的关卡" end
    local normalized = levelDocument.Normalize(document)
    Numeric.NormalizeDocument(normalized)
    local report = levelDocument.ValidateDetailed(normalized)
    if not report.valid then
        local errors = {}
        for _, issue in ipairs(report.errors) do errors[#errors + 1] = issue.path .. "：" .. issue.message end
        return nil, table.concat(errors, "；"), report
    end
    local clean = levelDocument.Clone(normalized)
    clean._editor = nil
    local ok, text = pcall(json.encode, clean)
    if not ok or type(text) ~= "string" then return nil, "JSON 序列化失败：" .. tostring(text), report end
    local withinLimit, sizeError = Export.CheckSize(text, "导出")
    if not withinLimit then return nil, sizeError, report end
    return text, nil, report
end

function Export.Prepare(document, levelDocument, json)
    local text, errorMessage, report = Export.Serialize(document, levelDocument, json)
    if not text then return nil, errorMessage, report end
    return {
        text = text,
        byteCount = #text,
        characterCount = characterCount(text),
        maxBytes = Export.MAX_JSON_BYTES,
        objectCount = #(document.objects or {}),
        schemaVersion = document.schemaVersion,
        levelId = document.levelId,
    }, nil, report
end

function Export.Deserialize(text, levelData)
    if type(text) ~= "string" or text == "" then return nil, "导入文本为空" end
    local withinLimit, sizeError = Export.CheckSize(text, "导入")
    if not withinLimit then return nil, sizeError end
    return levelData.Decode(text)
end

return Export
