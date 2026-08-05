local Rules = {}

local PRESET_X_SCALE = .92
local DEFAULT_GRAVITY_MAGNITUDE = 1.05

---@class CardHandOffset
---@field x number
---@field y number
---@field angle number

Rules.CARDS = {
    ["feather-gravity"] = { kind = "field", name = "轻羽引力", short = "轻羽", symbol = "g½", description = "重力强度降至标准值的 55%", accent = { 95, 143, 104 } },
    ["side-gravity"] = { kind = "field", name = "定向引力", short = "定向", symbol = "g→", description = "滑动选择四个方向的场地重力", accent = { 95, 143, 104 } },
    ["hooke-bounce"] = { kind = "field", name = "弹性响应", short = "高弹性", symbol = "↟", description = "提高弹簧的弹射倍率", accent = { 95, 143, 104 } },
    ["up-impulse"] = { kind = "decision", name = "向上冲量", short = "上冲", symbol = "↑", description = "立即施加一次向上冲量", accent = { 180, 147, 69 } },
    ["mirror-motion"] = { kind = "decision", name = "运动镜像", short = "镜像", symbol = "⇆", description = "滑动选择水平或垂直速度镜像", accent = { 180, 147, 69 } },
    ["quantum-phase"] = { kind = "decision", name = "量子相位", short = "相位", symbol = "∿", description = "下一次穿过可相位墙体", accent = { 128, 118, 181 } },
}

function Rules.NewState()
    return {
        selectedFields = {},
        activeFields = {},
        usedDecisions = {},
        launched = false,
        phaseActive = false,
        punchUsed = false,
        sideGravity = { x = 0, y = 1 },
        restitutionMultiplier = 1,
        mirrorAxis = nil,
        upImpulseUsed = false,
    }
end

function Rules.DeployField(state, id)
    state.activeFields[id] = true
    if id == "hooke-bounce" then
        state.restitutionMultiplier = 0.88 / 0.36
    end
end

function Rules.ToggleField(state, id)
    if state.launched then return false end
    state.selectedFields[id] = not state.selectedFields[id]
    return true
end

function Rules.PrepareFields(state, cards)
    if state.launched then return end
    state.selectedFields = {}
    for _, id in ipairs(cards or {}) do state.selectedFields[id] = true end
end

function Rules.Launch(state)
    if state.launched then return false end
    state.launched = true
    for id in pairs(state.selectedFields) do Rules.DeployField(state, id) end
    return true
end

function Rules.EndPhase(state)
    state.phaseActive = false
end

function Rules.UseDecision(state, id, allowRepeat)
    if not state.launched then return false end
    if state.usedDecisions[id] and not allowRepeat then return false end
    state.usedDecisions[id] = true
    if id == "quantum-phase" then state.phaseActive = true end
    if id == "up-impulse" then state.upImpulseUsed = true end
    return true
end

function Rules.Punch(state)
    if not Rules.CanPunch(state) then return false end
    state.punchUsed = true
    state.activeFields = {}
    state.phaseActive = false
    state.sideGravity = { x = 0, y = 1 }
    state.restitutionMultiplier = 1
    return true
end

function Rules.CanPunch(state)
    return not state.punchUsed and (next(state.activeFields) ~= nil or state.phaseActive)
end

function Rules.GetRestitutionMultiplier(state)
    return state.restitutionMultiplier or 1
end

function Rules.GetGravity(state, base)
    local gravity = {
        x = base.x,
        y = base.y,
        strength = (base.strength or 1) * DEFAULT_GRAVITY_MAGNITUDE,
    }
    if state.activeFields["feather-gravity"] then gravity.strength = gravity.strength * 0.55 end
    if state.activeFields["side-gravity"] then gravity.x = state.sideGravity.x; gravity.y = state.sideGravity.y end
    return gravity
end

function Rules.GetGravityMultiplier(state, base)
    local multiplier = base.strength or 1
    if state.activeFields["feather-gravity"] then multiplier = multiplier * 0.55 end
    return multiplier
end

---@param state table
---@return table[]
function Rules.ActiveRuleList(state)
    local result = {}
    local order = { "feather-gravity", "side-gravity", "hooke-bounce" }
    local seen = {}
    local function append(id)
        if not state.activeFields[id] or seen[id] then return end
        seen[id] = true
        local definition = Rules.CARDS[id]
        local label = definition and definition.name or id
        if id == "side-gravity" then
            local direction = state.sideGravity or { x = 0, y = 1 }
            local directionLabel = direction.x < 0 and "向左" or direction.x > 0 and "向右"
                or direction.y < 0 and "向上" or "向下"
            label = label .. " · " .. directionLabel
        end
        result[#result + 1] = { id = id, label = label }
    end
    for _, id in ipairs(order) do append(id) end
    local remaining = {}
    for id in pairs(state.activeFields) do
        if not seen[id] then remaining[#remaining + 1] = id end
    end
    table.sort(remaining)
    for _, id in ipairs(remaining) do append(id) end
    if state.phaseActive then
        result[#result + 1] = { id = "quantum-phase", label = "量子相位 · 已充能" }
    end
    return result
end

function Rules.CardHand(count, centerX, centerY, playfieldWidth)
    ---@type table<integer, CardHandOffset[]>
    local presets = {
        [1] = { { x = 0, y = 0, angle = 0 } },
        [2] = { { x = -85, y = 1, angle = -1.5 }, { x = 85, y = 1, angle = 1.5 } },
        [3] = { { x = -150, y = 4, angle = -2.5 }, { x = 0, y = 0, angle = 0 }, { x = 150, y = 4, angle = 2.5 } },
        [4] = { { x = -225, y = 7, angle = -3.5 }, { x = -75, y = 1, angle = -1.2 }, { x = 75, y = 1, angle = 1.2 }, { x = 225, y = 7, angle = 3.5 } },
        [5] = { { x = -285, y = 10, angle = -4.5 }, { x = -145, y = 3, angle = -2 }, { x = 0, y = 0, angle = 0 }, { x = 145, y = 3, angle = 2 }, { x = 285, y = 10, angle = 4.5 } },
        [6] = { { x = -340, y = 12, angle = -6 }, { x = -205, y = 4, angle = -3 }, { x = -68, y = 0, angle = -1 }, { x = 68, y = 0, angle = 1 }, { x = 205, y = 4, angle = 3 }, { x = 340, y = 12, angle = 6 } },
    }
    local result = {}
    count = math.max(0, math.min(10, math.floor(count)))
    if count == 0 then return result end
    if count <= 6 then
        local center = (count - 1) * .5
        for i, pose in ipairs(presets[count]) do
            local normalized = math.abs(i - 1 - center) / math.max(center, 1)
            result[i] = {
                x = centerX + pose.x * PRESET_X_SCALE,
                y = centerY + pose.y,
                angle = pose.angle,
                depth = 54 + (1 - normalized) * 4,
            }
        end
        return result
    end
    local ratio = ({ [7] = 0.68, [8] = 0.73, [9] = 0.77, [10] = 0.8 })[count]
    local maxDrop = ({ [7] = 13, [8] = 14, [9] = 15, [10] = 16 })[count]
    local maxAngle = ({ [7] = 6, [8] = 7, [9] = 7.5, [10] = 8 })[count]
    local step = (playfieldWidth * ratio - 144) / math.max(1, count - 1)
    local center = (count - 1) * 0.5
    for i = 1, count do
        local signed = (i - 1 - center) / math.max(center, 1)
        local normalized = math.abs(signed)
        result[i] = {
            x = centerX + (i - 1 - center) * step,
            y = centerY + normalized ^ 1.6 * maxDrop,
            angle = signed * maxAngle,
            depth = 54 + (1 - normalized) * 4,
        }
    end
    return result
end

return Rules
