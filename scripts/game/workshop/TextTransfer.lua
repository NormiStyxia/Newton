local TextTransfer = {}

local function enableSystemClipboard(clipboard)
    if not clipboard then return false, "剪贴板接口不可用" end
    local ok, errorMessage = pcall(function()
        if clipboard.SetUseSystemClipboard then
            clipboard:SetUseSystemClipboard(true)
        else
            clipboard.useSystemClipboard = true
        end
    end)
    return ok, ok and nil or tostring(errorMessage)
end

function TextTransfer.WriteClipboard(clipboard, value)
    if type(value) ~= "string" then return false, "没有可复制的文本" end
    local enabled, enableError = enableSystemClipboard(clipboard)
    if not enabled then return false, enableError end
    local ok, readBack = pcall(function()
        clipboard:SetClipboardText(value)
        return clipboard:GetClipboardText()
    end)
    if not ok then return false, tostring(readBack) end
    if readBack ~= value then return false, "剪贴板写入后校验不一致" end
    return true, nil
end

function TextTransfer.ReadClipboard(clipboard, maxBytes)
    local enabled, enableError = enableSystemClipboard(clipboard)
    if not enabled then return nil, enableError end
    local ok, value = pcall(clipboard.GetClipboardText, clipboard)
    if not ok then return nil, tostring(value) end
    if type(value) ~= "string" or value == "" then return nil, "剪贴板中没有文本" end
    if maxBytes and #value > maxBytes then
        return nil, "剪贴板文本超过 " .. tostring(maxBytes) .. " 字节限制"
    end
    return value, nil
end

function TextTransfer.AppendInput(edit, value, maxBytes)
    if type(edit) ~= "table" or type(value) ~= "string" or value == "" then return true, nil end
    local echo = edit.clipboardEchoRemaining
    if type(echo) == "string" and echo ~= "" then
        if echo:sub(1, #value) == value then
            edit.clipboardEchoRemaining = echo:sub(#value + 1)
            return true, nil
        end
        edit.clipboardEchoRemaining = nil
    end
    if edit.selectAll then edit.value, edit.selectAll = "", false end
    local limit = tonumber(maxBytes) or math.huge
    if #(edit.value or "") + #value > limit then
        return false, "输入文本超过 " .. tostring(limit) .. " 字节限制"
    end
    edit.value = (edit.value or "") .. value
    return true, nil
end

local function addLine(lines, firstByte, lastByte)
    lines[#lines + 1] = { firstByte = firstByte, lastByte = math.max(firstByte - 1, lastByte) }
end

local function buildUtf8Lines(value, columns)
    local ok, lines = pcall(function()
        local result, firstByte = {}, 1
        local nextNewline = value:find("\n", firstByte, true)
        while firstByte <= #value do
            local wrapByte = utf8.offset(value, columns + 1, firstByte) or (#value + 1)
            if nextNewline and nextNewline <= wrapByte then
                local lastByte = nextNewline - 1
                if lastByte >= firstByte and value:byte(lastByte) == 13 then lastByte = lastByte - 1 end
                addLine(result, firstByte, lastByte)
                firstByte = nextNewline + 1
                nextNewline = value:find("\n", firstByte, true)
            else
                addLine(result, firstByte, wrapByte - 1)
                firstByte = wrapByte
            end
        end
        if #value == 0 or value:sub(-1) == "\n" then addLine(result, #value + 1, #value) end
        return result
    end)
    return ok and lines or nil
end

local function buildByteLines(value, columns)
    local lines = {}
    local firstByte, columnsUsed = 1, 0
    for byteIndex = 1, #value do
        local byte = value:byte(byteIndex)
        if byte == 10 then
            local lastByte = byteIndex - 1
            if lastByte >= firstByte and value:byte(lastByte) == 13 then lastByte = lastByte - 1 end
            addLine(lines, firstByte, lastByte)
            firstByte, columnsUsed = byteIndex + 1, 0
        else
            local units = byte == 9 and 4 or 1
            if columnsUsed + units > columns and byteIndex > firstByte then
                addLine(lines, firstByte, byteIndex - 1)
                firstByte, columnsUsed = byteIndex, 0
            end
            columnsUsed = columnsUsed + units
        end
    end
    addLine(lines, firstByte, #value)
    return lines
end

local function characterCount(value)
    if utf8 and utf8.len then
        local ok, count = pcall(utf8.len, value)
        if ok and count then return count end
    end
    return #value
end

function TextTransfer.BuildMetrics(value, width, height, fontSize, lineHeightFactor)
    value = type(value) == "string" and value or ""
    fontSize = math.max(1, tonumber(fontSize) or 12)
    local lineHeight = fontSize * (tonumber(lineHeightFactor) or 1.35)
    local columns = math.max(8, math.floor(math.max(1, width) / fontSize))
    local lines = utf8 and utf8.offset and buildUtf8Lines(value, columns) or nil
    lines = lines or buildByteLines(value, columns)
    return {
        source = value,
        width = width,
        height = height,
        columns = columns,
        lineHeight = lineHeight,
        lines = lines,
        byteCount = #value,
        characterCount = characterCount(value),
        scrollMax = math.max(0, #lines * lineHeight - math.max(0, height)),
    }
end

function TextTransfer.UpdateModal(modal, value, body, fontSize, lineHeightFactor)
    if not modal or not body then return end
    value = type(value) == "string" and value or ""
    local width, height = math.max(1, body.w - 20), math.max(1, body.h - 20)
    local metrics = modal.textMetrics
    if not metrics or metrics.source ~= value or metrics.width ~= width or metrics.height ~= height then
        metrics = TextTransfer.BuildMetrics(value, width, height, fontSize, lineHeightFactor)
        modal.textMetrics = metrics
    end
    modal.scrollMax = metrics.scrollMax
    modal.scroll = math.max(0, math.min(modal.scroll or 0, modal.scrollMax))
    local firstLine = math.floor(modal.scroll / metrics.lineHeight) + 1
    local visibleCount = math.ceil(height / metrics.lineHeight) + 2
    local lastLine = math.min(#metrics.lines, firstLine + visibleCount - 1)
    local visible = {}
    for index = firstLine, lastLine do
        local line = metrics.lines[index]
        visible[#visible + 1] = value:sub(line.firstByte, line.lastByte)
    end
    modal.previewText = table.concat(visible, "\n")
    modal.previewOffsetY = modal.scroll - (firstLine - 1) * metrics.lineHeight
    modal.previewFirstLine, modal.previewLastLine = firstLine, lastLine
end

return TextTransfer
