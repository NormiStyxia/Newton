local M = {}

local function hash(value)
    local result = 2166136261
    for index = 1, #value do
        result = (result ~ string.byte(value, index)) & 0x7fffffff
        result = (result * 16777619) & 0x7fffffff
    end
    return result
end

local function nextRandom(state)
    state.value = (state.value * 1103515245 + 12345) & 0x7fffffff
    return state.value
end

local function shuffled(pool, seedKey, excluded)
    local candidates = {}
    for index, value in ipairs(pool or {}) do
        if not excluded[value] then candidates[#candidates + 1] = { index = index, value = value } end
    end
    local state = { value = hash(tostring(seedKey or "result")) }
    for index = #candidates, 2, -1 do
        local swap = (nextRandom(state) % index) + 1
        candidates[index], candidates[swap] = candidates[swap], candidates[index]
    end
    return candidates
end

function M.SampleUnique(pool, count, seedKey)
    local selected = {}
    local seen = {}
    for _, entry in ipairs(shuffled(pool, seedKey, {})) do
        if not seen[entry.value] then
            selected[#selected + 1] = entry.value
            seen[entry.value] = true
            if #selected >= count then break end
        end
    end
    return selected
end

function M.SampleReview(pool, recent, recentLimit, seedKey)
    local excluded = {}
    local history = recent or {}
    local start = math.max(1, #history - (recentLimit or 2) + 1)
    for index = start, #history do excluded[history[index]] = true end
    local candidates = shuffled(pool, seedKey, excluded)
    if #candidates == 0 then candidates = shuffled(pool, seedKey .. ":fallback", {}) end
    return candidates[1] and candidates[1].value or "暂无评语。"
end

function M.PushRecent(recent, value, limit)
    if not value then return end
    recent[#recent + 1] = value
    while #recent > (limit or 2) do table.remove(recent, 1) end
end

return M
