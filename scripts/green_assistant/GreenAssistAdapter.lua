local Adapter = {}
Adapter.__index = Adapter

function Adapter.New()
    return setmetatable({}, Adapter)
end

Adapter.new = Adapter.New

function Adapter:canTakeover()
    return false
end

function Adapter:lockPlayerInput() end
function Adapter:unlockPlayerInput() end
function Adapter:prepareTakeoverScene() end
function Adapter:getAssistReplay() return nil end
function Adapter:beginTakeoverReplay() return false end
function Adapter:updateTakeover() end
function Adapter:isTakeoverFinished() return false end
function Adapter:finishTakeover() end
function Adapter:cancelTakeover() end

return Adapter
