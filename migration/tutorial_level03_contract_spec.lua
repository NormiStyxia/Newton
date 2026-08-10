package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local Rules = require("game.gameplay.Rules")
local Tutorial = require("game.tutorial.Controller")

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
        stalledMs_ = 0,
        success_ = false,
        failed_ = false,
    }
    context.AppendDialogueMessages = function(levelId, messages)
        appended[#appended + 1] = { levelId = levelId, messages = messages }
        return true
    end
    return context, appended
end

local function deploySideGravity(context)
    context.rules_.sideGravity = { x = 1, y = 0 }
    Rules.DeployField(context.rules_, "side-gravity")
end

do
    local context, appended = newContext()
    local controller = Tutorial.Controller.New(context)
    controller:ResetForLevel("level_03")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_MARKER, "level 03 did not wait for its first marker")
    expect(controller:GetRenderModel().visible == false, "tutorial rendered before the first marker")

    expect(controller:BeginAction("level03_side_gravity_action"), "field-card marker was rejected")
    local model = controller:GetRenderModel()
    expect(model.visible and model.targetType == "card" and model.targetId == "side-gravity",
        "level 03 did not target the configured Field Card")

    controller:ObserveFieldRuleActivated("feather-gravity")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_ACTION,
        "an unrelated Field Card completed the side-gravity step")
    deploySideGravity(context)
    controller:ObserveFieldRuleActivated("side-gravity")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_MARKER and #appended == 1,
        "real side-gravity activation did not advance exactly one step")

    expect(controller:BeginAction("level03_newton_punch_action"), "Newton Punch marker was rejected")
    expect(controller:GetRenderModel().visible == false,
        "Punch highlight appeared before the apple was launched")
    context.launched_ = true
    context.stalledMs_ = 149
    expect(controller:GetRenderModel().visible == false,
        "Punch highlight appeared before the configured settle duration")
    context.stalledMs_ = 150
    expect(controller:GetRenderModel().visible == true,
        "Punch highlight did not appear when real Punch readiness and timing were satisfied")

    local removedRules = { "side-gravity" }
    expect(Rules.Punch(context.rules_), "authoritative Newton Punch failed in the standard path")
    controller:ObserveNewtonPunchExecuted(removedRules)
    expect(controller.state == Tutorial.STATE.COMPLETED and #appended == 2,
        "real Field reset did not complete the Punch step")
    local gravity = Rules.GetGravity(context.rules_, context.level_.rules.initialGravity)
    local baseline = Rules.GetGravity(Rules.NewState(), context.level_.rules.initialGravity)
    expect(gravity.x == baseline.x and gravity.y == baseline.y and gravity.strength == baseline.strength,
        "Newton Punch did not leave the logical gravity at the level baseline")
end

do
    local context, appended = newContext()
    local controller = Tutorial.Controller.New(context)
    controller:ResetForLevel("level_03")

    deploySideGravity(context)
    controller:ObserveFieldRuleActivated("side-gravity")
    expect(Rules.Punch(context.rules_), "fast-player Punch setup failed")
    controller:ObserveNewtonPunchExecuted({ "side-gravity" })
    expect(controller:BeginAction("level03_side_gravity_action"), "fast-player card marker was rejected")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_MARKER and #appended == 1,
        "early Field activation was not recognized at marker time")
    expect(controller:BeginAction("level03_newton_punch_action"), "fast-player Punch marker was rejected")
    expect(controller.state == Tutorial.STATE.COMPLETED and #appended == 2,
        "early successful Punch produced a stale action prompt")
end

do
    local context = newContext()
    local controller = Tutorial.Controller.New(context)
    controller:ResetForLevel("level_03")
    controller:ObserveNewtonPunchExecuted({})
    controller:BeginAction("level03_side_gravity_action")
    deploySideGravity(context)
    controller:ObserveFieldRuleActivated("side-gravity")
    controller:BeginAction("level03_newton_punch_action")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_ACTION,
        "an ineffective pre-Field Punch completed the Punch tutorial")

    context.success_ = true
    controller:Update(0.016)
    expect(controller.state == Tutorial.STATE.CANCELLED and controller:GetRenderModel().visible == false,
        "Victory did not cancel and clear the tutorial")

    context.success_ = false
    controller:ResetForLevel("level_03")
    expect(next(controller.observedFieldActivations) == nil and next(controller.observedPunchResets) == nil,
        "Restart retained per-attempt tutorial observations")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_MARKER and controller:GetRenderModel().visible == false,
        "Restart retained a stale action target")

    controller:BeginAction("level03_side_gravity_action")
    context.failed_ = true
    controller:Update(0.016)
    expect(controller.state == Tutorial.STATE.CANCELLED,
        "failure flow did not cancel the current tutorial overlay")
end

do
    local context, appended = newContext()
    local controller = Tutorial.Controller.New(context)
    controller:ResetForLevel("level_02")
    controller:BeginAction("level02_feather_gravity_action")
    Rules.DeployField(context.rules_, "feather-gravity")
    controller:ObserveFieldRuleActivated("feather-gravity")
    expect(controller.state == Tutorial.STATE.COMPLETED and #appended == 1,
        "the sequential runner regressed the level 02 tutorial")
end

do
    local context, appended = newContext()
    local controller = Tutorial.Controller.New(context)
    controller:ResetForLevel("level_03")
    controller:BeginAction("level03_side_gravity_action")
    deploySideGravity(context)
    controller:ObserveFieldRuleActivated("side-gravity")
    controller:BeginAction("level03_newton_punch_action")
    expect(#appended == 1, "restart setup did not append the first follow-up dialogue")

    context.rules_ = Rules.NewState()
    context.launched_ = false
    context.stalledMs_ = 0
    controller:RestartAttempt("level_03")
    local cardModel = controller:GetRenderModel()
    expect(cardModel.visible and cardModel.targetId == "side-gravity",
        "restart lost the card prompt after its dialogue marker had already been consumed")

    deploySideGravity(context)
    controller:ObserveFieldRuleActivated("side-gravity")
    expect(controller.state == Tutorial.STATE.WAITING_FOR_ACTION
        and controller.step and controller.step.targetId == "newton_punch",
        "restart did not resume the already revealed Newton Punch marker")
    expect(#appended == 1,
        "restart duplicated follow-up dialogue that was already present in the communication log")
end

print(string.format('{"mode":"TUTORIAL_LEVEL03","checks":%d,"status":"pass"}', checks))
