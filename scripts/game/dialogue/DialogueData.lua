local DialogueData = {}

DialogueData.FIRST_LEVEL_ID = "level_01"
DialogueData.ANGER_THRESHOLDS = { 25, 50, 75, 100 }

local FIRST_LEVEL_INTRO = {
    {
        speaker = "newton",
        displayName = "牛顿",
        avatarText = "牛",
        text = "欢迎来到经典力学实验室。",
        style = "NEWTON",
    },
    {
        speaker = "green",
        displayName = "绿毛同事",
        avatarText = "绿",
        text = "第一项很简单：先把苹果发射出去。",
        style = "GREEN",
    },
    {
        speaker = "newton",
        displayName = "牛顿",
        avatarText = "牛",
        text = "拖住苹果，向后拉，然后松开。",
        style = "NEWTON",
    },
    {
        speaker = "green",
        displayName = "绿毛同事",
        avatarText = "绿",
        text = "轨迹不必完美，先让它动起来。",
        style = "GREEN",
    },
}

local ANGER_MESSAGES = {
    [25] = "苹果终于动了。别急着庆祝，这只是开始。",
    [50] = "规则越改越多，经典力学可不会替你收拾残局。",
    [75] = "你正在把实验室变成悖论展览馆。",
    [100] = "够了。把苹果放回牛顿能理解的宇宙里。",
}

function DialogueData.Intro(levelId)
    if levelId ~= DialogueData.FIRST_LEVEL_ID then return {} end
    return FIRST_LEVEL_INTRO
end

function DialogueData.AngerMessage(threshold)
    local text = ANGER_MESSAGES[threshold]
    if not text then return nil end
    return {
        speaker = "newton",
        displayName = "牛顿",
        avatarText = "牛",
        text = text,
        style = "NEWTON",
        angerThreshold = threshold,
    }
end

return DialogueData
