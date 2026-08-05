local StandardSolutions = {}

local SOLUTIONS = {
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
