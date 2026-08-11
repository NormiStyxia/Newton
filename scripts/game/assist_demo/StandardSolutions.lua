local StandardSolutions = {}

local function WaitX(x, direction, timeout, prepareTarget)
    return {
        type = "WAIT_CONDITION",
        condition = "APPLE_CROSSED_X",
        x = x,
        direction = direction,
        timeout = timeout or 6.0,
        prepareTarget = prepareTarget,
    }
end

local function WaitY(y, direction, timeout, prepareTarget)
    return {
        type = "WAIT_CONDITION",
        condition = "APPLE_CROSSED_Y",
        y = y,
        direction = direction,
        timeout = timeout or 6.0,
        prepareTarget = prepareTarget,
    }
end

local function WaitStopped(timeout, prepareTarget, speedThreshold, settleDuration)
    return {
        type = "WAIT_CONDITION",
        condition = "APPLE_STOPPED",
        timeout = timeout or 6.0,
        speedThreshold = speedThreshold or 0.10,
        settleDuration = settleDuration or 0.15,
        prepareTarget = prepareTarget,
    }
end

local function Side(direction)
    return {
        type = "PLAY_CARD",
        cardId = "side-gravity",
        parameter = direction,
        cursorDuration = 0.2,
        approachDuration = 0.12,
    }
end

local function Phase()
    return {
        type = "PLAY_CARD",
        cardId = "quantum-phase",
        cursorDuration = 0.2,
        approachDuration = 0.12,
    }
end

local function Card(cardId, parameter)
    return {
        type = "PLAY_CARD",
        cardId = cardId,
        parameter = parameter,
        cursorDuration = 0.2,
        approachDuration = 0.12,
    }
end

local function CardTarget(cardId)
    return { type = "CARD", cardId = cardId, duration = 0.14 }
end

local function BaseActions(message)
    return {
        { type = "RESET_LEVEL" },
        { type = "SHOW_MESSAGE", text = message or "我来试一次。", duration = 0.8 },
    }
end

local function Append(actions, ...)
    for index = 1, select("#", ...) do actions[#actions + 1] = select(index, ...) end
    return actions
end

local SOLUTIONS = {
    level_01 = {
        levelId = "level_01",
        actions = Append(BaseActions(),
            { type = "LAUNCH", pullX = -70, pullY = 63, cursorDuration = 0.65 },
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 10.0 }
        ),
    },

    level_02 = {
        levelId = "level_02",
        actions = Append(BaseActions(),
            {
                type = "PLAY_CARD",
                cardId = "feather-gravity",
                cursorDuration = 0.2,
                approachDuration = 0.12,
            },
            { type = "LAUNCH", pullX = -72, pullY = 77, cursorDuration = 0.65 },
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 12.0 }
        ),
    },

    level_03 = {
        levelId = "level_03",
        actions = Append(BaseActions(),
            Side("RIGHT"),
            { type = "LAUNCH", pullX = 0, pullY = 60, cursorDuration = 0.65 },
            WaitStopped(6.0, { type = "NEWTON_PUNCH", duration = 0.14 }),
            { type = "NEWTON_PUNCH", cursorDuration = 0.12 },
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 8.0 }
        ),
    },

    level_04 = {
        levelId = "level_04",
        actions = Append(BaseActions(),
            { type = "LAUNCH", pullX = -64.8, pullY = 4.6, cursorDuration = 0.65 },
            WaitX(350, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(1050, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitY(210, "UP", 6.0, CardTarget("side-gravity")),
            Side("LEFT"),
            WaitX(980, "LEFT", 6.0, { type = "NEWTON_PUNCH", duration = 0.14 }),
            { type = "NEWTON_PUNCH", cursorDuration = 0.12 },
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 10.0 }
        ),
    },

    level_05 = {
        levelId = "level_05",
        actions = Append(BaseActions(),
            Side("LEFT"),
            { type = "LAUNCH", pullX = -25, pullY = 50, cursorDuration = 0.65 },
            WaitY(170, "UP", 8.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitY(105, "UP", 8.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(390, "RIGHT", 8.0, CardTarget("side-gravity")),
            WaitX(385, "LEFT", 8.0, CardTarget("side-gravity")),
            WaitX(403, "RIGHT", 8.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitStopped(8.0, CardTarget("side-gravity"), 0.12, 0.2),
            Side("RIGHT"),
            WaitX(500, "RIGHT", 8.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitStopped(8.0, CardTarget("side-gravity"), 0.12, 0.2),
            Side("RIGHT"),
            WaitX(660, "RIGHT", 8.0, CardTarget("side-gravity")),
            Side("LEFT"),
            WaitX(620, "LEFT", 8.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitStopped(4.0, CardTarget("side-gravity"), 0.18, 0.016),
            Side("DOWN"),
            WaitStopped(8.0, CardTarget("side-gravity"), 0.12, 0.2),
            Side("RIGHT"),
            WaitX(680, "RIGHT", 8.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitY(460, "UP", 8.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitY(430, "DOWN", 8.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(850, "RIGHT", 8.0, CardTarget("side-gravity")),
            WaitStopped(8.0, CardTarget("side-gravity"), 0.12, 0.2),
            Side("DOWN"),
            WaitStopped(8.0, CardTarget("side-gravity"), 0.12, 0.2),
            Side("RIGHT"),
            WaitX(950, "RIGHT", 8.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitStopped(8.0, CardTarget("side-gravity"), 0.12, 0.2),
            Side("UP"),
            WaitStopped(8.0, CardTarget("side-gravity"), 0.12, 0.2),
            Side("RIGHT"),
            WaitX(1025, "RIGHT", 8.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitStopped(8.0, CardTarget("side-gravity"), 0.12, 0.2),
            Side("RIGHT"),
            WaitX(1310, "RIGHT", 8.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitStopped(8.0, CardTarget("side-gravity"), 0.12, 0.2),
            Side("LEFT"),
            WaitX(1100, "LEFT", 8.0, CardTarget("side-gravity")),
            Side("UP"),
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 12.0 }
        ),
    },

    level_06 = {
        levelId = "level_06",
        actions = Append(BaseActions(),
            -- Bottom route: phase wall_01, wall_03 and wall_17, then rise
            -- past wall_08 and phase wall_10 into the observation dish.
            Side("RIGHT"),
            { type = "LAUNCH", pullX = -24, pullY = -10, cursorDuration = 0.65 },
            WaitX(280, "RIGHT", 6.0, CardTarget("quantum-phase")),
            Phase(),
            WaitX(470, "RIGHT", 6.0, CardTarget("quantum-phase")),
            Phase(),
            WaitX(750, "RIGHT", 6.0, CardTarget("quantum-phase")),
            Phase(),
            WaitX(855, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitX(945, "RIGHT", 4.0, CardTarget("quantum-phase")),
            Phase(),
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 8.0 }
        ),
    },

    level_07 = {
        levelId = "level_07",
        actions = Append(BaseActions(),
            -- A shallow launch lands on the spring. Hooke's response supplies
            -- enough height to press the upper button and open the goal bay.
            Card("hooke-bounce"),
            { type = "LAUNCH", pullX = -73, pullY = 10, cursorDuration = 0.65 },
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 10.0 }
        ),
    },

    level_08 = {
        levelId = "level_08",
        actions = Append(BaseActions(),
            -- Thread the natural spring corridor first. On the descending pass
            -- through the sensor, cancel just enough fall speed to hold overlap.
            { type = "LAUNCH", pullX = -76, pullY = 46, cursorDuration = 0.65 },
            WaitX(1100, "RIGHT", 8.0),
            WaitY(320, "DOWN", 6.0, CardTarget("up-impulse")),
            Card("up-impulse"),
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 8.0 }
        ),
    },

    level_09 = {
        levelId = "level_09",
        actions = Append(BaseActions(),
            -- Reproduce the authored ten-intervention route. Crossings handle
            -- open corridors; stopped checks hand control over at each wall or
            -- closed door so the route stays stable when contacts settle.
            { type = "LAUNCH", pullX = -76, pullY = 30, cursorDuration = 0.65 },
            WaitX(500, "RIGHT", 8.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(850, "RIGHT", 8.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitStopped(8.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(1180, "RIGHT", 8.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitStopped(10.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitStopped(8.0, CardTarget("side-gravity")),
            Side("LEFT"),
            WaitX(1000, "LEFT", 8.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitStopped(8.0, CardTarget("side-gravity")),
            Side("LEFT"),
            WaitStopped(8.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitStopped(8.0, CardTarget("side-gravity")),
            Side("LEFT"),
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 8.0 }
        ),
    },
}

function StandardSolutions.Get(levelId)
    return SOLUTIONS[levelId]
end

function StandardSolutions.Has(levelId)
    return SOLUTIONS[levelId] ~= nil
end

return StandardSolutions
