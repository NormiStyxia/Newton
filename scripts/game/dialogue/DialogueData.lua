local DialogueData = {}

DialogueData.FIRST_LEVEL_ID = "level_01"
DialogueData.SECOND_LEVEL_ID = "level_02"
DialogueData.THIRD_LEVEL_ID = "level_03"
DialogueData.FOURTH_LEVEL_ID = "level_04"
DialogueData.FIFTH_LEVEL_ID = "level_05"
DialogueData.SIXTH_LEVEL_ID = "level_06"
DialogueData.ANGER_THRESHOLDS = { 25, 50, 75, 100 }

local FIRST_LEVEL_INTRO = {
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "欢迎来到经典力学实验室。",
        style = "NEWTON",
    },
    {
        speaker = "green",
        side = "left",
        displayName = "绿毛同事",
        avatarText = "绿",
        text = "第一项很简单：先把苹果发射出去。",
        style = "GREEN",
    },
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "拖住苹果，向后拉，然后松开。",
        style = "NEWTON",
    },
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "轨迹不必完美，先让它动起来。",
        style = "NEWTON",
    },
    {
        speaker = "einstein",
        side = "left",
        displayName = "爱因斯坦",
        avatarText = "爱",
        text = "那么，实验室那头那个“宏伟”的建筑，作用是？",
        style = "EINSTEIN",
    },
    {
        speaker = "nomi",
        side = "right",
        displayName = "诺米",
        avatarText = "诺",
        text = "很壮观，不是吗？",
        style = "NOMI",
    },
    {
        speaker = "green",
        side = "left",
        displayName = "绿毛同事",
        avatarText = "绿",
        text = "翻译：没有任何作用。",
        style = "GREEN",
    },
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "这东西违反的不是物理学，是实验室管理条例。",
        style = "NEWTON",
    },
}

local ANGER_MESSAGES = {
    [25] = "苹果终于动了。别急着庆祝，这只是开始。",
    [50] = "规则越改越多，经典力学可不会替你收拾残局。",
    [75] = "你正在把实验室变成悖论展览馆。",
    [100] = "够了。把苹果放回牛顿能理解的宇宙里。",
}

local SECOND_LEVEL_INTRO = {
    {
        speaker = "einstein",
        side = "left",
        displayName = "爱因斯坦",
        avatarText = "爱",
        text = "嚯，奇观年代，今天的更壮观了。",
        style = "EINSTEIN",
    },
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "……",
        style = "NEWTON",
    },
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "本次实验需要稍微修改一下实验条件。",
        style = "NEWTON",
    },
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "绿色的是场地牌。它会改变实验场本身的规则，并持续生效。",
        style = "NEWTON",
        tutorialMarker = "level02_feather_gravity_action",
    },
}

local THIRD_LEVEL_INTRO = {
    {
        speaker = "einstein",
        side = "left",
        displayName = "爱因斯坦",
        avatarText = "爱",
        text = "上一关已经学会改实验规则了。",
        style = "EINSTEIN",
    },
    {
        speaker = "einstein",
        side = "left",
        displayName = "爱因斯坦",
        avatarText = "爱",
        text = "不过有时候，规则改完以后还得改回来。",
        style = "EINSTEIN",
    },
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "……你还打算自己决定什么时候恢复物理定律？",
        style = "NEWTON",
    },
    {
        speaker = "nomi",
        side = "right",
        displayName = "诺米",
        avatarText = "诺",
        text = "当然。不然这个按钮留着干嘛。",
        style = "NOMI",
        tutorialMarker = "level03_side_gravity_action",
    },
}

local FOURTH_LEVEL_INTRO = {
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "你最好解释一下墙体为什么飘在空中。",
        style = "NEWTON",
    },
    {
        speaker = "einstein",
        side = "left",
        displayName = "爱因斯坦",
        avatarText = "爱",
        text = "学院新型磁悬浮技术。",
        style = "EINSTEIN",
    },
    {
        speaker = "nomi",
        side = "right",
        displayName = "诺米",
        avatarText = "诺",
        text = "就是钉在墙上了而已啊。",
        style = "NOMI",
    },
    {
        speaker = "green",
        side = "left",
        displayName = "绿毛同事",
        avatarText = "绿",
        text = "总结：学院新型磁悬浮技术的核心部件，是钉子。",
        style = "GREEN",
    },
}

local FIFTH_LEVEL_INTRO = {
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "……所以这次的实验内容是什么？",
        style = "NEWTON",
    },
    {
        speaker = "nomi",
        side = "right",
        displayName = "诺米",
        avatarText = "诺",
        text = "墙。",
        style = "NOMI",
    },
    {
        speaker = "einstein",
        side = "left",
        displayName = "爱因斯坦",
        avatarText = "爱",
        text = "墙。",
        style = "EINSTEIN",
    },
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "我没瞎。",
        style = "NEWTON",
    },
    {
        speaker = "nomi",
        side = "right",
        displayName = "诺米",
        avatarText = "诺",
        text = "墙存在。",
        style = "NOMI",
    },
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "……",
        style = "NEWTON",
    },
    {
        speaker = "einstein",
        side = "left",
        displayName = "爱因斯坦",
        avatarText = "爱",
        text = "你看，实验结论非常稳定不是吗？",
        style = "EINSTEIN",
    },
}

local FIFTH_LEVEL_FIRST_WALL_IMPACT = {
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "很好。至少这次墙还遵守墙的基本职业道德。",
        style = "NEWTON",
    },
    {
        speaker = "green",
        side = "left",
        displayName = "绿毛同事",
        avatarText = "绿",
        text = "检测完成：墙确实很墙。",
        style = "GREEN",
    },
}

local SIXTH_LEVEL_INTRO = {
    {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = "等等，这些墙为什么是紫色的。",
        style = "NEWTON",
    },
    {
        speaker = "einstein",
        side = "left",
        displayName = "爱因斯坦",
        avatarText = "爱",
        text = "我们实验室拉来的新产品",
        style = "EINSTEIN",
    },
    {
        speaker = "nomi",
        side = "right",
        displayName = "诺米",
        avatarText = "诺",
        text = "像果冻，能吃吗？",
        style = "NOMI",
        tutorialMarker = "level06_quantum_phase_action",
    },
}

function DialogueData.Intro(levelId)
    if levelId == DialogueData.SECOND_LEVEL_ID then return SECOND_LEVEL_INTRO end
    if levelId == DialogueData.THIRD_LEVEL_ID then return THIRD_LEVEL_INTRO end
    if levelId == DialogueData.FOURTH_LEVEL_ID then return FOURTH_LEVEL_INTRO end
    if levelId == DialogueData.FIFTH_LEVEL_ID then return FIFTH_LEVEL_INTRO end
    if levelId == DialogueData.SIXTH_LEVEL_ID then return SIXTH_LEVEL_INTRO end
    if levelId ~= DialogueData.FIRST_LEVEL_ID then return {} end
    return FIRST_LEVEL_INTRO
end

function DialogueData.FirstWallImpact(levelId)
    if levelId == DialogueData.FIFTH_LEVEL_ID then return FIFTH_LEVEL_FIRST_WALL_IMPACT end
    return {}
end

function DialogueData.AngerMessage(threshold)
    local text = ANGER_MESSAGES[threshold]
    if not text then return nil end
    return {
        speaker = "newton",
        side = "left",
        displayName = "牛顿",
        avatarText = "牛",
        text = text,
        style = "NEWTON",
        angerThreshold = threshold,
    }
end

return DialogueData
