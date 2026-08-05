local Export = {}
Export.MAX_IMPORT_BYTES = 1024 * 1024

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
    return text, nil, report
end

function Export.Prepare(document, levelDocument, json)
    local text, errorMessage, report = Export.Serialize(document, levelDocument, json)
    if not text then return nil, errorMessage, report end
    return {
        text = text,
        byteCount = #text,
        characterCount = characterCount(text),
        objectCount = #(document.objects or {}),
        schemaVersion = document.schemaVersion,
        levelId = document.levelId,
    }, nil, report
end

function Export.Deserialize(text, levelData)
    if type(text) ~= "string" or text == "" then return nil, "导入文本为空" end
    if #text > Export.MAX_IMPORT_BYTES then
        return nil, "导入 JSON 超过 " .. tostring(Export.MAX_IMPORT_BYTES) .. " 字节限制"
    end
    return levelData.Decode(text)
end

return Export
