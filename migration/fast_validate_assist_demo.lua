package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local Runner = require("game.assist_demo.Runner")
local State = require("game.assist_demo.State")
local StandardSolutions = require("game.assist_demo.StandardSolutions")
local FixedStepClock = require("game.assist_demo.FixedStepClock")
local GameAdapter = require("game.assist_demo.GameAdapter")
local CursorView = require("game.assist_demo.CursorView")
local AssistDemoController = require("game.assist_demo.Controller")

local function Expect(condition, message)
    if not condition then error(message, 2) end
end

local function NewView()
    local view = { motionFinished = true }
    function view:open() self.opened = true end
    function view:close() self.closed = true end
    function view:update() end
    function view:setMessage(message) self.message = message end
    function view:setTarget(target) self.target = target end
    function view:moveTo(x, y) self.x, self.y, self.motionFinished = x, y, true end
    function view:getPosition() return self.x, self.y end
    function view:isMotionFinished() return self.motionFinished end
    function view:startDrag() self.dragging = true end
    function view:endDrag() self.dragging = false end
    function view:click() self.clicked = true end
    return view
end

local function NewAdapter(alwaysWait)
    local adapter = { calls = {}, conditionCounts = {} }
    local function Call(self, name) self.calls[#self.calls + 1] = name end
    function adapter:beginSession() Call(self, "begin") end
    function adapter:resetLevel() Call(self, "reset"); return true end
    function adapter:isLevelFailed() return false end
    function adapter:getLauncherTarget() return { x = 100, y = 100, shape = "circle", radius = 30 } end
    function adapter:getCardTarget() return { x = 200, y = 300, w = 80, h = 120, shape = "rect" } end
    function adapter:getCardDropTarget() return { x = 500, y = 300 } end
    function adapter:getPunchTarget() return { x = 700, y = 600, shape = "circle", radius = 40 } end
    function adapter:launch() Call(self, "launch"); return true end
    function adapter:previewLaunch() self.launchPreviewed = true; return true end
    function adapter:playCard() Call(self, "card"); return true end
    function adapter:newtonPunch() Call(self, "punch"); return true end
    function adapter:holdSimulation(held) self.simulationHeld = held == true end
    function adapter:testCondition(action)
        local key = action.condition
        self.conditionCounts[key] = (self.conditionCounts[key] or 0) + 1
        return not alwaysWait and self.conditionCounts[key] >= 2
    end
    return adapter
end

local statusFrame = { playfieldX = 210, playfieldWidth = 1500 }
local statusView = CursorView.New({})
statusView.active, statusView.presence = true, 1
statusView:setMessage("我来试一次。")
local statusRect = statusView:getStatusRect(statusFrame)
Expect(statusRect.width == 500 and statusRect.height == 88 and statusRect.y == 28,
    "assist status panel did not use the enlarged, lowered geometry")
Expect(statusView:containsStatusPoint(statusFrame,
    statusRect.x + statusRect.width * 0.5, statusRect.y + statusRect.height * 0.5),
    "assist status panel center is not clickable")
Expect(not statusView:containsStatusPoint(statusFrame, statusRect.x - 1, statusRect.y),
    "assist status panel accepted an outside point")

for _, isTouch in ipairs({ false, true }) do
    local abortReason
    local pointerContext = {
        assistSceneActive_ = true,
        assistDemoView_ = statusView,
        frame_ = statusFrame,
        AbortGreenAssistantTakeover = function(reason)
            abortReason = reason
            return true
        end,
    }
    AssistDemoController.Install(pointerContext)
    local consumed = pointerContext.HandleAssistDemoPointer({
        x = statusRect.x + statusRect.width * 0.5,
        y = statusRect.y + statusRect.height * 0.5,
        pressed = true,
        isTouch = isTouch,
    })
    Expect(consumed and abortReason == "pointer",
        (isTouch and "touch" or "mouse") .. " did not exit through the assist status panel")
end

local adapter = NewAdapter(false)
local runner = Runner.New(adapter, NewView())
local started, errorMessage = runner:start(StandardSolutions.Get("level_09"), { x = 0, y = 0 })
Expect(started, errorMessage or "runner did not start")
for _ = 1, 200 do
    runner:update(0.05)
    if State.IsTerminal(runner:getState()) then break end
end
Expect(runner:getState() == State.COMPLETED, "standard solution did not complete")
Expect(table.concat(adapter.calls, ",") == "begin,reset,launch,card,card,punch", "semantic action order changed")

local timeoutRunner = Runner.New(NewAdapter(true), NewView())
Expect(timeoutRunner:start({ actions = {
    { type = "RESET_LEVEL" },
    { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 0.15 },
} }))
for _ = 1, 10 do timeoutRunner:update(0.05) end
Expect(timeoutRunner:getState() == State.FAILED, "condition timeout did not fail")

local abortRunner = Runner.New(NewAdapter(false), NewView())
Expect(abortRunner:start({ actions = { { type = "RESET_LEVEL" } } }))
Expect(abortRunner:abort("escape"), "active runner did not abort")
Expect(abortRunner:getState() == State.ABORTED, "abort state was not preserved")

local invalidWaitRunner = Runner.New(NewAdapter(false), NewView())
local invalidWaitStarted = invalidWaitRunner:start({ actions = {
    { type = "WAIT_CONDITION", condition = "GOAL_REACHED" },
} })
Expect(not invalidWaitStarted, "WAIT_CONDITION without a timeout was accepted")

for levelIndex = 1, 5 do
    local levelId = string.format("level_%02d", levelIndex)
    local solution = StandardSolutions.Get(levelId)
    Expect(solution ~= nil and solution.levelId == levelId,
        "missing standard solution for " .. levelId)
    Expect(type(solution.actions) == "table" and #solution.actions >= 4,
        "standard solution is incomplete for " .. levelId)
    for actionIndex, action in ipairs(solution.actions) do
        if action.type == "WAIT_CONDITION" then
            Expect(type(action.timeout) == "number" and action.timeout > 0,
                string.format("%s action %d has no timeout", levelId, actionIndex))
        end
    end
end

local conditionPosition = { x = 400, y = 100 }
local conditionContext = {
    CONFIG = { matterFramesPerSecond = 60 },
    apple_ = {
        node = { position2D = conditionPosition },
        body = { linearVelocity = { x = 0, y = 0 } },
    },
    mapper_ = {
        WorldToLevel = function(_, x, y) return x, y end,
    },
}
local conditionAdapter = GameAdapter.New(conditionContext)
local crossedX = { condition = "APPLE_CROSSED_X", x = 350, direction = "RIGHT" }
local xMemory = {}
Expect(not conditionAdapter:testCondition(crossedX, xMemory, 1 / 60, {}),
    "APPLE_CROSSED_X matched its first sample")
Expect(not conditionAdapter:testCondition(crossedX, xMemory, 1 / 60, {}),
    "APPLE_CROSSED_X matched without crossing")
conditionPosition.x = 340
Expect(not conditionAdapter:testCondition(crossedX, xMemory, 1 / 60, {}),
    "APPLE_CROSSED_X matched the opposite direction")
conditionPosition.x = 360
Expect(conditionAdapter:testCondition(crossedX, xMemory, 1 / 60, {}),
    "APPLE_CROSSED_X missed a real crossing")

conditionPosition.y = 250
local crossedY = { condition = "APPLE_CROSSED_Y", y = 200, direction = "UP" }
local yMemory = {}
Expect(not conditionAdapter:testCondition(crossedY, yMemory, 1 / 60, {}),
    "APPLE_CROSSED_Y matched its first sample")
conditionPosition.y = 190
Expect(conditionAdapter:testCondition(crossedY, yMemory, 1 / 60, {}),
    "APPLE_CROSSED_Y missed a real crossing")

local physicsAdapter = NewAdapter(false)
function physicsAdapter:isPhysicsCondition(action)
    return action.condition == "APPLE_CROSSED_X"
end
local physicsRunner = Runner.New(physicsAdapter, NewView())
Expect(physicsRunner:start({ actions = {
    { type = "RESET_LEVEL" },
    { type = "LAUNCH", pullX = -70, pullY = 60, postDelay = 0 },
    { type = "WAIT_CONDITION", condition = "APPLE_CROSSED_X", x = 350, timeout = 2 },
    { type = "PLAY_CARD", cardId = "up-impulse" },
} }))
for _ = 1, 12 do physicsRunner:update(0.05) end
Expect((physicsAdapter.conditionCounts.APPLE_CROSSED_X or 0) == 0,
    "physics condition was polled by the render-frame update")
Expect(not physicsRunner:afterPhysicsStep(1 / 60),
    "physics condition latched before the threshold-crossing step")
Expect(physicsRunner:afterPhysicsStep(1 / 60), "physics condition was not latched post-step")
Expect(physicsAdapter.conditionCounts.APPLE_CROSSED_X == 2,
    "physics condition was not sampled exactly once per physics step")
Expect(physicsAdapter.simulationHeld == true,
    "next semantic action did not pause on the threshold-crossing step")

local burnAdapter = NewAdapter(false)
burnAdapter.cardFinished = false
function burnAdapter:isCardActionFinished() return self.cardFinished end
local burnRunner = Runner.New(burnAdapter, NewView())
Expect(burnRunner:start({ actions = {
    { type = "PLAY_CARD", cardId = "up-impulse", postDelay = 0 },
    { type = "WAIT_VISUAL", duration = 0 },
} }))
for _ = 1, 8 do burnRunner:update(0.1) end
Expect(burnAdapter.simulationHeld == true,
    "card burn released deterministic simulation before the visual lifecycle finished")
burnAdapter.cardFinished = true
burnRunner:update(0.1)
Expect(burnAdapter.simulationHeld == false,
    "card burn completion did not release deterministic simulation")

local function FixedStepResult(renderStep)
    local running = true
    local position = 0
    local updates = 0
    local scene = { updateEnabled = true }
    function scene:SetUpdateEnabled(enabled) self.updateEnabled = enabled end
    function scene:IsUpdateEnabled() return self.updateEnabled end
    function scene:Update(dt)
        Expect(math.abs(dt - 1 / 60) < 0.0000001, "fixed-step clock used a variable delta")
        updates = updates + 1
        position = position + 10
        if position >= 50 then running = false end
    end
    local clock = FixedStepClock.New({ step = 1 / 60 })
    clock:start(scene)
    for _ = 1, 120 do
        clock:advance(renderStep, function() return running end)
        if not running then break end
    end
    clock:stop()
    Expect(scene.updateEnabled, "fixed-step clock did not restore automatic scene updates")
    return position, updates
end

for _, renderStep in ipairs({ 1 / 30, 1 / 60, 1 / 120 }) do
    local position, updates = FixedStepResult(renderStep)
    Expect(position == 50 and updates == 5,
        "assist trajectory threshold changed with render frame rate")
end

print("AssistDemo FAST_VALIDATE passed")
