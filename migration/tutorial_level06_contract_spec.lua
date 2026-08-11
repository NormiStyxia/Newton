package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local Rules = require("game.gameplay.Rules")
local Tutorial = require("game.tutorial.Controller")
local DialogueData = require("game.dialogue.DialogueData")

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local function newContext()
    local appended = {}
    local context = {
        Rules = Rules,
        rules_ = Rules.NewState(),
        level_ = { rules = { initialGravity = { x = 0, y = 1, strength = 1 } } },
        launched_ = false,
        success_ = false,
        failed_ = false,
    }
    context.AppendDialogueMessages = function(levelId, messages)
        appended[#appended + 1] = { levelId = levelId, messages = messages }
        return true
    end
    return context, appended
end

local intro = DialogueData.Intro("level_06")
expect(#intro == 3, "level 06 intro does not contain exactly three messages")
expect(intro[1].speaker == "newton" and intro[1].text == "等等，这些墙为什么是紫色的。",
    "level 06 Newton intro changed")
expect(intro[2].speaker == "einstein" and intro[2].text == "我们实验室拉来的新产品",
    "level 06 Einstein intro changed")
expect(intro[3].speaker == "nomi" and intro[3].text == "像果冻，能吃吗？"
    and intro[3].tutorialMarker == "level06_quantum_phase_action",
    "level 06 Nomi intro or tutorial marker changed")

local config = Tutorial.ACTION_CONFIGS.level_06
expect(config ~= nil and #config.steps == 2, "level 06 did not reuse the sequential Tutorial Runner")
expect(config.steps[1].targetId == "quantum-phase"
    and config.steps[1].instruction == "拖出「量子相位」"
    and config.steps[1].hint == "给苹果量子充能",
    "level 06 card target or two-line instruction changed")
expect(config.steps[2].targetType == "event"
    and config.steps[2].targetId == "phase_wall_traversed",
    "level 06 first-traversal observation step changed")

do
    local context, appended = newContext()
    local controller = Tutorial.Controller.New(context)
    controller:ResetForLevel("level_06")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_MARKER,
        "level 06 did not wait for its dialogue marker")
    expect(controller:BeginAction("level06_quantum_phase_action"),
        "level 06 quantum-phase marker was rejected")
    local model = controller:GetRenderModel()
    expect(model.visible and model.targetType == "card" and model.targetId == "quantum-phase",
        "level 06 did not highlight the real quantum-phase card")

    controller:ObserveDecisionCardApplied("mirror-motion")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_ACTION,
        "an unrelated Decision Card completed the quantum-phase step")
    Rules.ChargeQuantumPhase(context.rules_)
    controller:ObserveDecisionCardApplied("quantum-phase")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_ACTION
        and controller.step and controller.step.targetId == "phase_wall_traversed",
        "real quantum charge did not advance to the hidden traversal observer")
    expect(#appended == 1 and #appended[1].messages == 7,
        "quantum charge did not append the seven explanation messages exactly once")
    expect(controller:GetRenderModel().visible == false,
        "the passive phase-traversal observer rendered a blocking tutorial target")

    controller:ObserveGameplayEvent("wall_impact")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_ACTION,
        "an unrelated gameplay event completed the phase traversal step")
    controller:ObserveGameplayEvent("phase_wall_traversed")
    expect(controller.state == Tutorial.STATE.COMPLETED,
        "the first authoritative phase traversal did not complete level 06 onboarding")
    expect(#appended == 2 and #appended[2].messages == 5,
        "the first phase traversal did not append the five follow-up messages")
    controller:ObserveGameplayEvent("phase_wall_traversed")
    expect(#appended == 2, "a repeated phase traversal duplicated the follow-up dialogue")
end

do
    local context, appended = newContext()
    local controller = Tutorial.Controller.New(context)
    controller:ResetForLevel("level_06")
    Rules.ChargeQuantumPhase(context.rules_)
    controller:ObserveDecisionCardApplied("quantum-phase")
    controller:ObserveGameplayEvent("phase_wall_traversed")
    expect(controller:BeginAction("level06_quantum_phase_action"),
        "fast-player quantum-phase marker was rejected")
    expect(controller.state == Tutorial.STATE.COMPLETED and #appended == 2,
        "early charge and traversal produced stale level 06 tutorial steps")
    expect(#appended[1].messages == 7 and #appended[2].messages == 5,
        "fast-player catch-up inverted the explanation and traversal dialogue order")
end

do
    local context = newContext()
    local controller = Tutorial.Controller.New(context)
    controller:ResetForLevel("level_06")
    controller:ObserveDecisionCardApplied("quantum-phase")
    controller:ObserveGameplayEvent("phase_wall_traversed")
    controller:ResetForLevel("level_06")
    expect(next(controller.observedDecisionCardApplications) == nil
        and next(controller.observedGameplayEvents) == nil,
        "level 06 re-entry retained runtime tutorial observations")
    context.success_ = true
    controller:Update(0.016)
    expect(controller.state == Tutorial.STATE.CANCELLED
        and controller:GetRenderModel().visible == false,
        "Victory did not cancel the level 06 tutorial")
end

local allMessages = {}
for _, message in ipairs(intro) do allMessages[#allMessages + 1] = message end
for _, step in ipairs(config.steps) do
    for _, message in ipairs(step.afterMessages or {}) do allMessages[#allMessages + 1] = message end
end
expect(#allMessages == 15, "level 06 communication does not contain the requested fifteen messages")
local expectedMessages = {
    { "newton", "等等，这些墙为什么是紫色的。" },
    { "einstein", "我们实验室拉来的新产品" },
    { "nomi", "像果冻，能吃吗？" },
    { "einstein", "这是特殊的决策牌——「量子相位」。" },
    { "einstein", "和其他决策牌一样，不会永久修改整个场地。但它可以在发射以前预先充能。" },
    { "nomi", "充能？" },
    { "green", "翻译：次数可以累计，场地规则里可以看见。" },
    { "einstein", "苹果碰到这种紫色墙体时，会消耗一次相位充能。" },
    { "einstein", "然后——穿过去。" },
    { "einstein", "暂时。" },
    { "newton", "所以它们互相当对方不存在？" },
    { "green", "理解正确。" },
    { "newton", "……我想把某些人请出实验室了" },
    { "nomi", "那去哪，食堂？" },
    { "einstein", "给我带份小炒肉。" },
}
for index, message in ipairs(allMessages) do
    expect(message.speaker == expectedMessages[index][1]
        and message.text == expectedMessages[index][2],
        "level 06 speaker/text order changed at message " .. tostring(index))
    expect(not string.find(message.text, "“", 1, true)
        and not string.find(message.text, "”", 1, true)
        and not string.find(message.text, '"', 1, true),
        "level 06 runtime dialogue retained decorative double quotes")
end

print(string.format('{"mode":"TUTORIAL_LEVEL06","checks":%d,"status":"pass"}', checks))
