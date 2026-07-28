local Rules = {}

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
        mirrorAxis = nil,
        upImpulseUsed = false,
    }
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
    for id in pairs(state.selectedFields) do state.activeFields[id] = true end
    return true
end

function Rules.UseDecision(state, id)
    if not state.launched then return false end
    if state.usedDecisions[id] then return false end
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
    return true
end

function Rules.GetGravity(state, base)
    local gravity = { x = base.x, y = base.y, strength = base.strength }
    if state.activeFields["feather-gravity"] then gravity.strength = gravity.strength * 0.55 end
    if state.activeFields["side-gravity"] then gravity.x = state.sideGravity.x; gravity.y = state.sideGravity.y end
    return gravity
end

function Rules.CardHand(count, centerX, centerY, playfieldWidth)
    local presets = {
        [1] = { { 0, 0, 0 } },
        [2] = { { -78, 1, -1.5 }, { 78, 1, 1.5 } },
        [3] = { { -138, 4, -2.5 }, { 0, 0, 0 }, { 138, 4, 2.5 } },
        [4] = { { -207, 7, -3.5 }, { -69, 1, -1.2 }, { 69, 1, 1.2 }, { 207, 7, 3.5 } },
        [5] = { { -262, 10, -4.5 }, { -133, 3, -2 }, { 0, 0, 0 }, { 133, 3, 2 }, { 262, 10, 4.5 } },
        [6] = { { -313, 12, -6 }, { -189, 4, -3 }, { -63, 0, -1 }, { 63, 0, 1 }, { 189, 4, 3 }, { 313, 12, 6 } },
    }
    local result = {}
    count = math.max(0, math.min(10, math.floor(count)))
    if count == 0 then return result end
    if count <= 6 then
        for i, pose in ipairs(presets[count]) do
            result[i] = { x = centerX + pose[1], y = centerY + pose[2], angle = pose[3], depth = 54 + i }
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
