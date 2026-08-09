local TextEditor = {}

local function characters(value)
    value = tostring(value or "")
    local result = {}
    if utf8 and utf8.codes and utf8.char then
        local ok = pcall(function()
            for _, codepoint in utf8.codes(value) do result[#result + 1] = utf8.char(codepoint) end
        end)
        if ok then return result end
        result = {}
    end
    for index = 1, #value do result[#result + 1] = value:sub(index, index) end
    return result
end

local function clampCursor(edit, valueCharacters)
    edit.cursor = math.max(0, math.min(tonumber(edit.cursor) or #valueCharacters, #valueCharacters))
    return edit.cursor
end

function TextEditor.Length(value)
    return #characters(value)
end

function TextEditor.Initialize(edit, selectAll, elapsed)
    edit.value = tostring(edit.value or "")
    edit.cursor = TextEditor.Length(edit.value)
    edit.selectAll = selectAll == true
    edit.scrollX = 0
    edit.blinkStartedAt = tonumber(elapsed) or 0
    return edit
end

function TextEditor.Begin(field, value, mode, elapsed, importLimit)
    return TextEditor.Initialize({
        field = field,
        fieldKey = field and field.key or mode,
        value = tostring(value == nil and "" or value),
        maxLength = field and field.maxLength or (mode == "import" and importLimit or 256),
        mode = mode or "field",
    }, true, elapsed)
end

function TextEditor.ResetBlink(edit, elapsed)
    edit.blinkStartedAt = tonumber(elapsed) or 0
end

function TextEditor.CursorVisible(edit, elapsed)
    local age = math.max(0, (tonumber(elapsed) or 0) - (tonumber(edit.blinkStartedAt) or 0))
    return age % 1 < 0.5
end

function TextEditor.SelectAll(edit, elapsed)
    edit.selectAll = true
    edit.cursor = TextEditor.Length(edit.value)
    TextEditor.ResetBlink(edit, elapsed)
end

function TextEditor.Prefix(value, cursor)
    local chars = characters(value)
    cursor = math.max(0, math.min(tonumber(cursor) or #chars, #chars))
    local prefix = {}
    for index = 1, cursor do prefix[index] = chars[index] end
    return table.concat(prefix)
end

function TextEditor.Insert(edit, value, maxBytes, elapsed)
    if type(edit) ~= "table" or type(value) ~= "string" or value == "" then return true, nil end
    local chars = characters(edit.value)
    local cursor = clampCursor(edit, chars)
    local before, after = {}, {}
    if not edit.selectAll then
        for index = 1, cursor do before[#before + 1] = chars[index] end
        for index = cursor + 1, #chars do after[#after + 1] = chars[index] end
    end
    local nextValue = table.concat(before) .. value .. table.concat(after)
    local limit = tonumber(maxBytes) or math.huge
    if #nextValue > limit then return false, "输入文本超过 " .. tostring(limit) .. " 字节限制" end
    edit.value = nextValue
    edit.cursor = #before + TextEditor.Length(value)
    edit.selectAll = false
    TextEditor.ResetBlink(edit, elapsed)
    return true, nil
end

local function replaceCharacters(edit, chars, cursor)
    edit.value = table.concat(chars)
    edit.cursor = math.max(0, math.min(cursor, #chars))
    edit.selectAll = false
end

function TextEditor.Backspace(edit, elapsed)
    local chars = characters(edit.value)
    local cursor = clampCursor(edit, chars)
    if edit.selectAll then
        replaceCharacters(edit, {}, 0)
    elseif cursor > 0 then
        table.remove(chars, cursor)
        replaceCharacters(edit, chars, cursor - 1)
    end
    TextEditor.ResetBlink(edit, elapsed)
end

function TextEditor.Delete(edit, elapsed)
    local chars = characters(edit.value)
    local cursor = clampCursor(edit, chars)
    if edit.selectAll then
        replaceCharacters(edit, {}, 0)
    elseif cursor < #chars then
        table.remove(chars, cursor + 1)
        replaceCharacters(edit, chars, cursor)
    end
    TextEditor.ResetBlink(edit, elapsed)
end

function TextEditor.Move(edit, delta, elapsed)
    local length = TextEditor.Length(edit.value)
    if edit.selectAll then
        edit.cursor = delta < 0 and 0 or length
    else
        edit.cursor = math.max(0, math.min((tonumber(edit.cursor) or length) + delta, length))
    end
    edit.selectAll = false
    TextEditor.ResetBlink(edit, elapsed)
end

function TextEditor.Home(edit, elapsed)
    edit.cursor, edit.selectAll = 0, false
    TextEditor.ResetBlink(edit, elapsed)
end

function TextEditor.End(edit, elapsed)
    edit.cursor, edit.selectAll = TextEditor.Length(edit.value), false
    TextEditor.ResetBlink(edit, elapsed)
end

function TextEditor.KeyAction(edit, source, elapsed, directClipboard)
    if source:GetKeyDown(KEY_CTRL) and source:GetKeyPress(KEY_A) then
        TextEditor.SelectAll(edit, elapsed); return "handled"
    end
    if edit.mode == "import" and source:GetKeyDown(KEY_CTRL) and source:GetKeyPress(KEY_V) then
        return directClipboard and "paste" or "active"
    end
    if source:GetKeyPress(KEY_BACKSPACE) then TextEditor.Backspace(edit, elapsed); return "handled" end
    if source:GetKeyPress(KEY_DELETE) then TextEditor.Delete(edit, elapsed); return "handled" end
    if source:GetKeyPress(KEY_LEFT) then TextEditor.Move(edit, -1, elapsed); return "handled" end
    if source:GetKeyPress(KEY_RIGHT) then TextEditor.Move(edit, 1, elapsed); return "handled" end
    if source:GetKeyPress(KEY_HOME) then TextEditor.Home(edit, elapsed); return "handled" end
    if source:GetKeyPress(KEY_END) then TextEditor.End(edit, elapsed); return "handled" end
    if source:GetKeyPress(KEY_ESCAPE) then return "cancel" end
    if edit.mode ~= "import" and source:GetKeyPress(KEY_RETURN) then return "commit" end
    return "active"
end

function TextEditor.SetCursorFromX(edit, targetX, measure, elapsed)
    local chars = characters(edit.value)
    local previousWidth = 0
    local prefix = {}
    for index, character in ipairs(chars) do
        prefix[index] = character
        local width = measure(table.concat(prefix))
        if targetX < (previousWidth + width) * 0.5 then
            edit.cursor, edit.selectAll = index - 1, false
            TextEditor.ResetBlink(edit, elapsed)
            return edit.cursor
        end
        previousWidth = width
    end
    edit.cursor, edit.selectAll = #chars, false
    TextEditor.ResetBlink(edit, elapsed)
    return edit.cursor
end

function TextEditor.UpdateHorizontalScroll(edit, availableWidth, measure)
    local cursorWidth = measure(TextEditor.Prefix(edit.value, edit.cursor))
    local totalWidth = measure(edit.value)
    local scroll = math.max(0, tonumber(edit.scrollX) or 0)
    if cursorWidth - scroll > availableWidth then scroll = cursorWidth - availableWidth + 2
    elseif cursorWidth < scroll then scroll = cursorWidth end
    scroll = math.max(0, math.min(scroll, math.max(0, totalWidth - availableWidth)))
    edit.scrollX = scroll
    return scroll, cursorWidth, totalWidth
end

return TextEditor
