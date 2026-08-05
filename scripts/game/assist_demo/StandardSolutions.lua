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
            { type = "LAUNCH", pullX = -46, pullY = 77, cursorDuration = 0.65 },
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 12.0 }
        ),
    },

    level_03 = {
        levelId = "level_03",
        actions = Append(BaseActions(),
            { type = "LAUNCH", pullX = -52.5, pullY = 32.3, cursorDuration = 0.65 },
            WaitX(350, "RIGHT", 5.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 12.0 }
        ),
    },

    level_04 = {
        levelId = "level_04",
        actions = Append(BaseActions(),
            { type = "LAUNCH", pullX = -64.8, pullY = 4.6, cursorDuration = 0.65 },
            WaitX(700, "RIGHT", 6.0, CardTarget("side-gravity")),
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
            WaitY(170, "UP", 6.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitX(96, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(390, "RIGHT"),
            WaitX(385, "LEFT"),
            WaitX(403, "RIGHT"),
            WaitX(402, "LEFT"),
            WaitX(404, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitY(528, "UP", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(500, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitY(125, "UP", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(660, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("LEFT"),
            WaitX(620, "LEFT", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(584, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitY(220, "DOWN", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitStopped(6.0, CardTarget("side-gravity"), 0.12, 0.12),
            Side("LEFT"),
            WaitX(720, "LEFT", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(680, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitY(460, "UP", 6.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitY(430, "DOWN", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(855, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitY(540, "UP", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitStopped(6.0, CardTarget("side-gravity")),
            Side("UP"),
            WaitY(115, "UP", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(1015, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("LEFT"),
            WaitX(1035, "LEFT", 6.0, CardTarget("side-gravity")),
            Side("RIGHT"),
            WaitX(1058, "RIGHT", 6.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitStopped(6.0, CardTarget("side-gravity")),
            Side("LEFT"),
            WaitX(970, "LEFT", 6.0, CardTarget("side-gravity")),
            Side("DOWN"),
            WaitY(430, "DOWN", 6.0, CardTarget("side-gravity")),
            Side("UP"),
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 10.0 }
        ),
    },

    level_09 = {
        levelId = "level_09",
        assistRegions = {
            passage_exit = { x = 645, y = 210, width = 120, height = 125 },
        },
        actions = {
            { type = "RESET_LEVEL" },
            { type = "SHOW_MESSAGE", text = "我来试一次。", duration = 0.8 },
            { type = "LAUNCH", pullX = -70, pullY = 60, cursorDuration = 0.65 },
            {
                type = "WAIT_CONDITION",
                condition = "APPLE_CROSSED_X",
                x = 350,
                direction = "RIGHT",
                timeout = 5.0,
                prepareTarget = { type = "CARD", cardId = "up-impulse", duration = 0.14 },
            },
            {
                type = "PLAY_CARD",
                cardId = "up-impulse",
                cursorDuration = 0.2,
                approachDuration = 0.12,
            },
            {
                type = "WAIT_CONDITION",
                condition = "APPLE_ENTER_REGION",
                regionId = "passage_exit",
                timeout = 5.0,
                prepareTarget = { type = "CARD", cardId = "side-gravity", duration = 0.24 },
            },
            {
                type = "PLAY_CARD",
                cardId = "side-gravity",
                parameter = "RIGHT",
                cursorDuration = 0.2,
                approachDuration = 0.12,
            },
            {
                type = "WAIT_CONDITION",
                condition = "APPLE_CROSSED_X",
                x = 850,
                direction = "RIGHT",
                timeout = 5.0,
                prepareTarget = { type = "NEWTON_PUNCH", duration = 0.2 },
            },
            { type = "NEWTON_PUNCH", cursorDuration = 0.12 },
            { type = "WAIT_CONDITION", condition = "GOAL_REACHED", timeout = 8.0 },
        },
    },
}

function StandardSolutions.Get(levelId)
    return SOLUTIONS[levelId]
end

function StandardSolutions.Has(levelId)
    return SOLUTIONS[levelId] ~= nil
end

return StandardSolutions
