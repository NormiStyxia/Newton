package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local function expect(condition, message)
    if not condition then error(message, 2) end
end

local Animator = require("green_assistant.GreenAssistAnimator")
local AnimationSource = require("green_assistant.GreenAssistAnimationSource")
local Interaction = require("green_assistant.GreenAssistInteraction")
local function SourceFrame(texture, width, height, semanticAnchors)
    return {
        texture = texture,
        sourceRect = { x = 0, y = 0, width = width, height = height },
        sourceOffset = { x = 0, y = 0 },
        frameWidth = width,
        frameHeight = height,
        visualBounds = { x = 0, y = 0, width = width, height = height },
        footAnchor = { x = width * 0.5, y = height, normalizedX = 0.5, normalizedY = 1 },
        semanticAnchors = semanticAnchors,
    }
end
local RuntimeManifest = {
    schemaVersion = 1,
    variants = {
        runtime_512 = {
            clips = {
                idle = { fps = 8, loop = true, frames = { SourceFrame("idle", 256, 512) } },
                blink = { fps = 12, loop = false, frames = { SourceFrame("blink", 256, 512) } },
                move = { fps = 10, loop = true, frames = { SourceFrame("move", 256, 512) } },
                drag = { fps = 16, loop = true, frames = {
                    SourceFrame("drag", 360, 512, {
                        dragGrab = { x = 242, y = 87, normalizedX = 242 / 360, normalizedY = 87 / 512 },
                    }),
                } },
                takeover_raise = { fps = 10, loop = false, frames = {
                    SourceFrame("raise-1", 320, 512), SourceFrame("raise-2", 320, 512),
                } },
                takeover_loop = { fps = 10, loop = true, frames = {
                    SourceFrame("loop-1", 320, 512), SourceFrame("loop-2", 320, 512),
                } },
                takeover_finish = { fps = 10, loop = false, frames = {
                    SourceFrame("finish-1", 320, 512), SourceFrame("finish-2", 320, 512),
                } },
            },
        },
    },
}
local sourceConfig = {
    assets = {},
    animations = {
        idle = { assetClip = "idle", frames = { "fallback" }, fps = 8, loop = true },
        blink = { assetClip = "blink", frames = { "fallback" }, fps = 12, loop = false },
        walk = { assetClip = "move", frames = { "fallback" }, fps = 10, loop = true },
        drag = { assetClip = "drag", frames = { "fallback" }, fps = 16, loop = true },
        takeover_raise = { assetClip = "takeover_raise", frames = { "fallback" }, fps = 10, loop = false },
        takeover_loop = { assetClip = "takeover_loop", frames = { "fallback" }, fps = 10, loop = true },
        takeover_finish = { assetClip = "takeover_finish", frames = { "fallback" }, fps = 10, loop = false },
    },
}
expect(AnimationSource.Apply(sourceConfig, RuntimeManifest, "runtime_512"),
    "runtime animation manifest did not apply")
expect(sourceConfig.animations.idle.frames[1].frameHeight == 512,
    "runtime FrameDescriptor height mismatch")
expect(sourceConfig.animations.idle.frames[1].texture ~= nil
    and sourceConfig.animations.idle.frames[1].sourceRect ~= nil,
    "portable texture/sourceRect FrameDescriptor fields are missing")
expect(sourceConfig.animations.idle.frames[1].anchorY == 1,
    "runtime foot anchor was not preserved")
expect(sourceConfig.animations.drag.frames[1].semanticAnchors.dragGrab.x == 242,
    "runtime semantic drag hotspot was not preserved")
local animatorEvents = {}
local animator = Animator.new({
    fallbackAnimation = "idle",
    onAnimationChanged = function(name) animatorEvents[#animatorEvents + 1] = name end,
})
animator:registerAnimation("idle", { frames = { "idle-1", "idle-2" }, fps = 10, loop = true })
animator:registerAnimation("move", { frames = { "move-1", "move-2", "move-3" }, fps = 5, loop = true })
local blinkFinished = false
animator:registerAnimation("blink", { frames = { "blink-1", "blink-2" }, fps = 10, loop = false })
expect(animator:play("idle"), "idle animation did not start")
animator:update(.11)
expect(animator:getCurrentFrame() == "idle-2", "looping frame advance failed")
expect(animator:play("missing"), "fallback animation was not used")
expect(animator:getCurrentAnimation() == "idle", "fallback animation mismatch")
animator:play("blink", { restart = true, onFinished = function() blinkFinished = true end })
animator:update(.21)
expect(animator:isFinished() and blinkFinished, "non-looping animation completion failed")
expect(#animatorEvents >= 2, "animation change callback missing")

local interactionRolls = { 0.1, 0.1, 0.2, 0.9 }
local interactionRollIndex = 0
local interaction = Interaction.new({
    retriggerCooldown = 0.3,
    consecutiveWindow = 1,
    pokeLines = { "tap" },
    tapAnimations = { "tap_react_a", "tap_react_b" },
}, {
    random = function()
        interactionRollIndex = interactionRollIndex + 1
        return interactionRolls[interactionRollIndex]
    end,
})
local _, firstPokeCount, firstTapAnimation = interaction:poke(0)
expect(firstPokeCount == 1 and firstTapAnimation == "tap_react_a",
    "first semantic tap animation was not selected")
local blockedLine, blockedCount, blockedAnimation, blockedReason = interaction:poke(0.29)
expect(blockedLine == nil and blockedCount == 1 and blockedAnimation == nil and blockedReason == "cooldown",
    "tap animation retriggered inside the 0.3 second cooldown")
local _, secondPokeCount, secondTapAnimation = interaction:poke(0.3)
expect(secondPokeCount == 2 and secondTapAnimation == "tap_react_b",
    "second semantic tap animation was not randomly selectable after cooldown")

local mockView = {
    message = nil,
    choice = nil,
    x = 0,
    y = 0,
    hitCharacter = false,
}
function mockView:setFrame(frame) self.frame = frame end
function mockView:getHomePosition() return 76, 822 end
function mockView:getRoamBounds() return 42, 238, 722, 822 end
function mockView:getCompanionZone()
    return { left = 0, right = 300, top = 740, bottom = 824, baselineY = 822, fallbackX = 76 }
end
function mockView:setPosition(x, y) self.x, self.y = x, y end
function mockView:setFacingRight(value) self.facingRight = value end
function mockView:setVisible(value) self.visible = value end
function mockView:setEnabled(value) self.enabled = value end
function mockView:showMessage(text) self.message, self.choice = text, nil end
function mockView:showChoice(text, choices) self.message, self.choice = text, choices end
function mockView:hideMessage() self.message, self.choice = nil, nil end
function mockView:hitTestCharacter() return self.hitCharacter end
function mockView:hitTestBubble() return false end
function mockView:hitTestChoice() return nil, nil end
function mockView:render() end
function mockView:destroy() self.destroyed = true end

local adapter = { finished = false, assisted = false, locked = false }
function adapter:canTakeover() return true end
function adapter:lockPlayerInput() self.locked = true end
function adapter:unlockPlayerInput() self.locked = false end
function adapter:prepareTakeoverScene() self.prepared = true end
function adapter:getAssistReplay() return { samples = { { t = 0 }, { t = 100 } } } end
function adapter:beginTakeoverReplay() self.began = true; return true end
function adapter:updateTakeover() end
function adapter:isTakeoverFinished() return self.finished end
function adapter:finishTakeover() self.assisted = true end
function adapter:cancelTakeover() self.cancelled = true end

local GreenAssistant = require("green_assistant.GreenAssistant")
local events = {}
local assistant = GreenAssistant.new({
    view = mockView,
    adapter = adapter,
    config = {
        features = { roam = false },
        companion = { dragThreshold = 2, settleDuration = .05 },
        animations = {
            idle = { frames = { "idle-1", "idle-2" }, fps = 10, loop = true },
            move = { frames = { "move-1", "move-2" }, fps = 10, loop = true },
            blink = { frames = { "blink-1", "blink-2" }, fps = 10, loop = false },
            takeover_raise = { frames = { "raise-1", "raise-2" }, fps = 10, loop = false },
            takeover_loop = { frames = { "loop-1", "loop-2" }, fps = 10, loop = true },
            takeover_finish = { frames = { "finish-1", "finish-2" }, fps = 10, loop = false },
        },
        blink = { enabled = true, animation = "blink", minInterval = .05, maxInterval = .05 },
        interaction = { duration = .05, consecutiveWindow = 1, pokeLines = { "在。", "别戳。" } },
        failureAssist = {
            observeDuration = .05,
            observeLines = { "一", "二" },
            offerText = "需要我接管吗？",
            declineText = "不用",
            acceptText = "交给你",
            successText = "好了。",
            unavailableText = "不可用",
        },
    },
    events = {
        onBehaviorChanged = function(_, state) events[#events + 1] = state end,
    },
})

assistant:update(.06, { logicalWidth = 1880, logicalHeight = 840 })
expect(assistant.animator:getCurrentAnimation() == "blink", "idle blink did not interrupt idle animation")
assistant:update(.21)
expect(assistant.animator:getCurrentAnimation() == "idle_base", "blink did not restore semantic idle animation")
mockView.hitCharacter = true
local dragPointerX, dragPointerY = mockView.x, mockView.y
expect(assistant:handlePointer(dragPointerX, dragPointerY,
    { down = true, pressed = true, released = false }), "pointer down was not captured")
expect(assistant:getBehavior() == GreenAssistant.Behavior.IDLE,
    "pointer down must remain a tap candidate until the hold threshold is crossed")
assistant:update(.26)
expect(assistant:getBehavior() == GreenAssistant.Behavior.DRAGGING,
    "GreenAssistant did not enter DRAGGING after the hold threshold")
expect(assistant:handlePointer(dragPointerX + 4, dragPointerY - 10,
    { down = true, pressed = false, released = false }), "drag movement was not captured")
expect(assistant:getBehavior() == GreenAssistant.Behavior.DRAGGING, "GreenAssistant did not mirror DRAGGING behavior")
expect(assistant.animator:getCurrentAnimation() == "drag" and assistant.animator.playbackSpeed == 1,
    "DRAGGING did not play the registered drag sequence")
assistant:handlePointer(dragPointerX + 4, dragPointerY - 10, { down = false, pressed = false, released = true })
expect(assistant:getBehavior() == GreenAssistant.Behavior.IDLE, "drag release did not enter IDLE immediately")
assistant:update(.06)
expect(assistant:getBehavior() == GreenAssistant.Behavior.IDLE, "drag settle did not return GreenAssistant to IDLE")
mockView.hitCharacter = false
assistant:poke()
expect(assistant:getBehavior() == GreenAssistant.Behavior.INTERACT, "poke behavior missing")
expect(assistant.animator:getCurrentAnimation() == "tap_react_a"
    or assistant.animator:getCurrentAnimation() == "tap_react_b",
    "poke did not play either registered tap reaction")
expect(not assistant:poke(), "poke retriggered inside the 0.3 second cooldown")
assistant:update(.06)
expect(assistant:getBehavior() == GreenAssistant.Behavior.IDLE, "poke did not return to idle")

assistant:onAttemptSucceeded()
expect(assistant:getBehavior() == GreenAssistant.Behavior.IDLE,
    "normal success must keep the companion in an interactive behavior")
expect(assistant.animator:getCurrentAnimation() ~= "takeover_finish",
    "normal success incorrectly played the takeover finish animation")
expect(mockView.message == "好了。", "normal success message was not shown")
assistant:update(1.81)
expect(mockView.message == nil and assistant:getBehavior() == GreenAssistant.Behavior.IDLE,
    "normal success message did not expire without locking the companion")
expect(assistant.failureAssist:canOfferOnPoke(),
    "normal success did not retain the post-clear demonstration entry")
mockView.hitCharacter = true
local replayPokeX, replayPokeY = mockView.x, mockView.y
expect(assistant:handlePointer(replayPokeX, replayPokeY,
    { down = true, pressed = true, released = false }),
    "post-clear character press was not captured")
expect(assistant:handlePointer(replayPokeX, replayPokeY,
    { down = false, pressed = false, released = true }),
    "post-clear character release was not captured")
expect(assistant:getBehavior() == GreenAssistant.Behavior.OFFER and mockView.choice ~= nil,
    "post-clear character click did not reopen the demonstration offer")
expect(assistant:declineTakeover() and assistant:getBehavior() == GreenAssistant.Behavior.IDLE,
    "post-clear demonstration decline did not return to idle")
mockView.hitCharacter = false
assistant:onAttemptSucceeded()
mockView.hitCharacter = true
local reportDragX, reportDragY = mockView.x, mockView.y
expect(assistant:handlePointer(reportDragX, reportDragY,
    { down = true, pressed = true, released = false }),
    "normal success character did not accept a drag candidate")
assistant:update(.26)
expect(assistant:getBehavior() == GreenAssistant.Behavior.DRAGGING and mockView.message == nil,
    "normal success message locked report-page dragging")
assistant:handlePointer(reportDragX + 6, reportDragY - 10,
    { down = false, pressed = false, released = true })
assistant:update(.06)
expect(assistant:getBehavior() == GreenAssistant.Behavior.IDLE,
    "normal success character did not settle after report-page dragging")
mockView.hitCharacter = false

assistant:onLevelChanged("level_01")
expect(not assistant.failureAssist:canOfferOnPoke(),
    "changing levels did not clear the post-clear demonstration entry")
assistant:onAttemptFailed({ reason = "A" })
expect(assistant:getBehavior() == GreenAssistant.Behavior.OBSERVE, "first failure must observe")
assistant:update(.06)
assistant:onAttemptFailed({ reason = "B" })
expect(assistant:getBehavior() == GreenAssistant.Behavior.OBSERVE, "second failure must observe")
assistant:update(.06)
assistant:onAttemptFailed({ reason = "C" })
expect(assistant:getBehavior() == GreenAssistant.Behavior.OFFER, "third failure must offer takeover")
expect(assistant.failureAssist.hasOfferedThisLevel, "offer flag was not retained")
expect(assistant:declineTakeover(), "takeover decline failed")
expect(assistant:getBehavior() == GreenAssistant.Behavior.IDLE, "decline did not return to idle")
expect(assistant:poke() and assistant:getBehavior() == GreenAssistant.Behavior.OFFER,
    "first poke after decline did not reopen the takeover offer")
expect(assistant.animator:getCurrentAnimation() == "tap_react_a"
    or assistant.animator:getCurrentAnimation() == "tap_react_b",
    "poke that reopened the takeover offer did not play a tap reaction")
local reopenedMessage, reopenedChoice = mockView.message, mockView.choice
assistant:update(.31)
mockView.hitCharacter = true
expect(assistant:handlePointer(mockView.x, mockView.y,
    { down = true, pressed = true, released = false }),
    "offer-page character poke was not captured")
expect(assistant:getBehavior() == GreenAssistant.Behavior.OFFER
    and mockView.message == reopenedMessage and mockView.choice == reopenedChoice,
    "offer-page character poke replaced or closed the takeover choice")
expect(assistant.animator:getCurrentAnimation() == "tap_react_a"
    or assistant.animator:getCurrentAnimation() == "tap_react_b",
    "offer-page character poke did not play a tap reaction")
mockView.hitCharacter = false
assistant:update(.31)
expect(assistant:declineTakeover(), "reopened takeover decline failed")
expect(assistant:poke() and assistant:getBehavior() == GreenAssistant.Behavior.OFFER,
    "repeated poke after decline did not reopen the takeover offer")
expect(assistant:acceptTakeover(), "takeover acceptance failed")
expect(assistant:getBehavior() == GreenAssistant.Behavior.TAKEOVER and adapter.locked and adapter.began,
    "takeover did not lock input and start replay")
expect(assistant.animator:getCurrentAnimation() == "takeover_raise",
    "takeover did not begin with the raise animation")
assistant:update(.21)
expect(assistant:getBehavior() == GreenAssistant.Behavior.TAKEOVER
    and assistant.animator:getCurrentAnimation() == "takeover_loop",
    "takeover raise did not transition into the looping animation")
adapter.finished = true
assistant:update(.016)
expect(adapter.assisted and not adapter.locked, "takeover did not finish assisted and unlock input")
expect(assistant:getBehavior() == GreenAssistant.Behavior.SUCCESS, "takeover did not enter success behavior")
expect(assistant.animator:getCurrentAnimation() == "takeover_finish",
    "takeover completion did not begin the finish animation")
mockView.hitCharacter = true
local successDragX, successDragY = mockView.x, mockView.y
expect(assistant:handlePointer(successDragX, successDragY,
    { down = true, pressed = true, released = false }),
    "success character did not accept a drag candidate")
expect(assistant:getBehavior() == GreenAssistant.Behavior.IDLE,
    "pressing the success character did not release the timed success lock")
assistant:update(.26)
expect(assistant:getBehavior() == GreenAssistant.Behavior.DRAGGING,
    "success character could not be dragged after the report opened")
expect(assistant:handlePointer(successDragX + 8, successDragY - 12,
    { down = false, pressed = false, released = true }),
    "success character drag release was not consumed")
assistant:update(.06)
expect(assistant:getBehavior() == GreenAssistant.Behavior.IDLE,
    "success character did not settle after report-page dragging")
mockView.hitCharacter = false
assistant:onLevelChanged("level_02")
expect(assistant.failureAssist.failureCount == 0 and not assistant.failureAssist.hasOfferedThisLevel,
    "new level did not reset failure assist")
expect(assistant:hasAnimation("blink"), "public animation registry is unavailable")
assistant:setBehaviorAnimation("INTERACT", "blink")
expect(assistant.animationState:getBehaviorAnimation("INTERACT") == "blink", "behavior animation hot-swap failed")
assistant:destroy()
expect(mockView.destroyed, "assistant view was not destroyed")

print("GREEN_ASSISTANT_CONTRACT_OK")
