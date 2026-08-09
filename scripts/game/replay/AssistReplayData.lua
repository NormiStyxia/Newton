local AssistReplayData = {}

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function AssistReplayData.Validate(data, expectedLevelId)
    if type(data) ~= "table" then return false, "assist replay root must be an object" end
    if data.schemaVersion ~= 1 then return false, "unsupported assist replay schemaVersion" end
    if data.levelId ~= expectedLevelId then return false, "assist replay levelId mismatch" end
    if data.coordinateSpace ~= "level" and data.coordinateSpace ~= "world" then
        return false, "assist replay coordinateSpace must be level or world"
    end
    if type(data.samples) ~= "table" or #data.samples < 2 then
        return false, "assist replay requires at least two samples"
    end
    local previousTime = -math.huge
    for index, sample in ipairs(data.samples) do
        if type(sample) ~= "table" or not IsFinite(sample.t) or not IsFinite(sample.x) or not IsFinite(sample.y) then
            return false, "invalid assist replay sample at index " .. tostring(index)
        end
        if sample.t <= previousTime then return false, "assist replay samples must be strictly ordered" end
        if sample.angle ~= nil and not IsFinite(sample.angle) then return false, "invalid sample angle" end
        previousTime = sample.t
    end
    return true
end

function AssistReplayData.Load(resourcePath, expectedLevelId)
    if not cache:Exists(resourcePath) then return nil, "assist replay resource not found: " .. resourcePath end
    local file = cache:GetFile(resourcePath)
    if not file or not file:IsOpen() then return nil, "assist replay resource could not be opened: " .. resourcePath end
    local content = file:ReadString()
    file:Dispose()
    local ok, data = pcall(cjson.decode, content)
    if not ok then return nil, "assist replay JSON decode failed: " .. tostring(data) end
    local valid, errorMessage = AssistReplayData.Validate(data, expectedLevelId)
    if not valid then return nil, errorMessage end
    return data
end

function AssistReplayData.ToRuntime(data, mapper)
    local samples = {}
    for index, sample in ipairs(data.samples) do
        local x, y = sample.x, sample.y
        if data.coordinateSpace == "level" then x, y = mapper:LevelToWorld(x, y) end
        samples[index] = {
            t = sample.t,
            x = x,
            y = y,
            vx = sample.vx or 0,
            vy = sample.vy or 0,
            angle = sample.angle or 0,
        }
    end
    local events = {}
    for index, event in ipairs(data.events or {}) do
        local converted = {}
        for key, value in pairs(event) do converted[key] = value end
        if data.coordinateSpace == "level" and type(event.x) == "number" and type(event.y) == "number" then
            converted.x, converted.y = mapper:LevelToWorld(event.x, event.y)
        end
        events[index] = converted
    end
    return {
        schemaVersion = data.schemaVersion,
        levelId = data.levelId,
        source = data.source or "assist-solution",
        samples = samples,
        events = events,
    }
end

return AssistReplayData
