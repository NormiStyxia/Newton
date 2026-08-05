local State = {
    IDLE = "IDLE",
    READY = "READY",
    RESETTING = "RESETTING",
    EXECUTING = "EXECUTING",
    COMPLETED = "COMPLETED",
    ABORTED = "ABORTED",
    FAILED = "FAILED",
}

local VALID = {}
for _, value in pairs(State) do VALID[value] = true end

function State.IsValid(value)
    return VALID[value] == true
end

function State.IsTerminal(value)
    return value == State.COMPLETED or value == State.ABORTED or value == State.FAILED
end

function State.IsActive(value)
    return value == State.READY or value == State.RESETTING or value == State.EXECUTING
end

return State
