local ReplayMode = {
    NONE = 0,
    PLAYER_REPLAY = 1,
    ASSIST_TAKEOVER = 2,
}

function ReplayMode.IsValid(value)
    return value == ReplayMode.NONE or value == ReplayMode.PLAYER_REPLAY or value == ReplayMode.ASSIST_TAKEOVER
end

function ReplayMode.Name(value)
    if value == ReplayMode.PLAYER_REPLAY then return "PLAYER_REPLAY" end
    if value == ReplayMode.ASSIST_TAKEOVER then return "ASSIST_TAKEOVER" end
    return "NONE"
end

return ReplayMode
