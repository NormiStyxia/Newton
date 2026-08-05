package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local Runner = require("game.assist_demo.Runner")
local State = require("game.assist_demo.State")
local StandardSolutions = require("game.assist_demo.StandardSolutions")

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

print("AssistDemo FAST_VALIDATE passed")
