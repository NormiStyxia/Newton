local Rules = {}

---@class CardHandOffset
---@field x number
---@field y number
---@field angle number

Rules.CARDS = {
    ["feather-gravity"] = { kind = "field", name = "轻羽引力", short = "轻羽", symbol = "g½", description = "重力强度降至标准值的 55%", accent = { 95, 143, 104 } },
    ["side-gravity"] = { kind = "field", name = "横向引力", short = "横引力", symbol = "g→", description = "滑动选择四个方向的场地重力", accent = { 95, 143, 104 } },
    ["hooke-bounce"] = { kind = "field", name = "弹性响应", short = "高弹性", symbol = "↟", description = "提高苹果与普通墙体的反弹系数", accent = { 95, 143, 104 } },
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
    if state.punchUsed then return false end
    if not state.launched and next(state.activeFields) == nil and not state.phaseActive then return false end
    state.punchUsed = true
    state.activeFields = {}
    state.phaseActive = false
    state.sideGravity = { x = 0, y = 1 }
    state.restitutionMultiplier = 1
    return true
end

function Rules.GetRestitutionMultiplier(state)
    return state.restitutionMultiplier or 1
end

function Rules.GetGravity(state, base)
    local gravity = { x = base.x, y = base.y, strength = base.strength }
    if state.activeFields["feather-gravity"] then gravity.strength = gravity.strength * 0.55 end
    if state.activeFields["side-gravity"] then gravity.x = state.sideGravity.x; gravity.y = state.sideGravity.y end
    return gravity
end

function Rules.CardHand(count, centerX, centerY, playfieldWidth)
    ---@type table<integer, CardHandOffset[]>
    local presets = {
        [1] = { { x = 0, y = 0, angle = 0 } },
        [2] = { { x = -78, y = 1, angle = -1.5 }, { x = 78, y = 1, angle = 1.5 } },
        [3] = { { x = -138, y = 4, angle = -2.5 }, { x = 0, y = 0, angle = 0 }, { x = 138, y = 4, angle = 2.5 } },
        [4] = { { x = -207, y = 7, angle = -3.5 }, { x = -69, y = 1, angle = -1.2 }, { x = 69, y = 1, angle = 1.2 }, { x = 207, y = 7, angle = 3.5 } },
        [5] = { { x = -262, y = 10, angle = -4.5 }, { x = -133, y = 3, angle = -2 }, { x = 0, y = 0, angle = 0 }, { x = 133, y = 3, angle = 2 }, { x = 262, y = 10, angle = 4.5 } },
        [6] = { { x = -313, y = 12, angle = -6 }, { x = -189, y = 4, angle = -3 }, { x = -63, y = 0, angle = -1 }, { x = 63, y = 0, angle = 1 }, { x = 189, y = 4, angle = 3 }, { x = 313, y = 12, angle = 6 } },
    }
    local result = {}
    count = math.max(0, math.min(10, math.floor(count)))
    if count == 0 then return result end
    if count <= 6 then
        for i, pose in ipairs(presets[count]) do
            result[i] = { x = centerX + pose.x, y = centerY + pose.y, angle = pose.angle, depth = 54 + i }
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
