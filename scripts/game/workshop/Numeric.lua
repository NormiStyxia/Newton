local Numeric = {}

Numeric.INSPECTOR_DECIMALS = 2
Numeric.PERSISTENCE_DECIMALS = 3

local TRANSFORM_FIELDS = {
    x = true, y = true, width = true, height = true, rotation = true,
}

local function finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function Numeric.IsTransformField(fieldKey)
    if type(fieldKey) ~= "string" then return false end
    local field = fieldKey:match("^transform%.(.+)$")
    return field ~= nil and TRANSFORM_FIELDS[field] == true
end

function Numeric.Round(value, decimals)
    if not finite(value) then return value end
    local digits = math.max(0, math.floor(tonumber(decimals) or 0))
    local factor = 10 ^ digits
    local scaled = value * factor
    local rounded = scaled >= 0 and math.floor(scaled + 0.5) or math.ceil(scaled - 0.5)
    local result = rounded / factor
    return result == 0 and 0 or result
end

local function fixed(value, decimals)
    local rounded = Numeric.Round(value, decimals)
    if not finite(rounded) then return tostring(value == nil and "" or value) end
    return string.format("%." .. tostring(decimals) .. "f", rounded)
end

local function trimmed(value, decimals)
    local text = fixed(value, decimals)
    text = text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return text == "-0" and "0" or text
end

function Numeric.FormatInspectorValue(fieldKey, value)
    if Numeric.IsTransformField(fieldKey) then
        return fixed(value, Numeric.INSPECTOR_DECIMALS)
    end
    return tostring(value == nil and "" or value)
end

function Numeric.FormatEditValue(fieldKey, value)
    if Numeric.IsTransformField(fieldKey) then
        return trimmed(value, Numeric.PERSISTENCE_DECIMALS)
    end
    return tostring(value == nil and "" or value)
end

function Numeric.NormalizeInspectorValue(fieldKey, value)
    if Numeric.IsTransformField(fieldKey) then
        return Numeric.Round(value, Numeric.PERSISTENCE_DECIMALS)
    end
    return value
end

function Numeric.NormalizeDocument(document)
    if type(document) ~= "table" or type(document.objects) ~= "table" then return document end
    for _, object in ipairs(document.objects) do
        local transform = type(object) == "table" and object.transform or nil
        if type(transform) == "table" then
            for field in pairs(TRANSFORM_FIELDS) do
                if finite(transform[field]) then
                    transform[field] = Numeric.Round(transform[field], Numeric.PERSISTENCE_DECIMALS)
                end
            end
        end
    end
    return document
end

return Numeric
