local CONFIG = {
    title = "牛顿看了想打人",
    pixelsPerMeter = 100,
    matterFramesPerSecond = 60,
    bulletTimeScale = 0.05,
    levelCount = 9,
    replaySampleMs = 1000 / 30,
}

-- The illustrated card source is 840 x 1280. Keep the established 202 px hand
-- height and derive the width from the source aspect ratio so the artwork and
-- hit geometry are never stretched.
local CARD_DESIGN_WIDTH = 124
local CARD_DESIGN_HEIGHT = CARD_DESIGN_WIDTH * 1280 / 840
local CARD_TEXT_SCALE = 202 / CARD_DESIGN_HEIGHT
local CARD_RENDER_WIDTH = CARD_DESIGN_WIDTH * CARD_TEXT_SCALE
local CARD_RENDER_HEIGHT = CARD_DESIGN_HEIGHT * CARD_TEXT_SCALE
local GOAL_CONTACT_SKIN = .005

-- Matter stores velocity in pixels per 60 Hz frame, while Box2D uses metres
-- per second. These constants keep the migrated runtime on the source scale.
CONFIG.matterVelocityToWorld = CONFIG.matterFramesPerSecond / CONFIG.pixelsPerMeter
CONFIG.maxAppleSpeed = 25 * CONFIG.matterVelocityToWorld

local LEVEL_SCORE_PROFILES = {
    intervention_standard = {
        metric = "ruleDeployCount",
        tiers = {
            { score = 100, maxInterventions = 1, title = "精准实验", description = "仅使用 1 次有效干预完成观测" },
            { score = 80, maxInterventions = 3, title = "有效实验", description = "不超过 3 次有效干预完成观测" },
            { score = 60, title = "观测成立", description = "使苹果稳定进入观察皿" },
        },
    },
    intervention_level_04 = {
        metric = "ruleDeployCount",
        tiers = {
            { score = 100, maxInterventions = 4, title = "精准实验", description = "不超过 4 次有效干预完成观测" },
            { score = 80, maxInterventions = 8, title = "有效实验", description = "不超过 8 次有效干预完成观测" },
            { score = 60, title = "观测成立", description = "使苹果稳定进入观察皿" },
        },
    },
    intervention_level_05 = {
        metric = "ruleDeployCount",
        tiers = {
            { score = 100, maxInterventions = 20, title = "精准实验", description = "不超过 20 次有效干预完成观测" },
            { score = 80, maxInterventions = 30, title = "有效实验", description = "不超过 30 次有效干预完成观测" },
            { score = 60, title = "观测成立", description = "使苹果稳定进入观察皿" },
        },
    },
}

-- Names and available cards stay in level JSON. This table owns presentation
-- fields that schemaVersion 1 does not yet provide and can later migrate into
-- user-authored level files without changing either catalog view.
local LEVEL_META = {
    level_01 = {
        objective = "让苹果进入观察皿",
        observation = "先观察抛物线，再谈万有引力。",
        description = "校准发射方向与力度，使苹果稳定落入观察皿。",
    },
    level_02 = {
        objective = "用轻羽引力越过矮台",
        observation = "减弱重力，轨迹会被拉得更长。",
        description = "部署轻羽引力延长滞空时间，从连续台阶上方抵达观察皿。",
    },
    level_03 = {
        objective = "利用定向引力，再让世界归位",
        observation = "苹果记得已经获得的速度。",
        description = "改变场地受力方向推动苹果穿过通道，并在合适时机恢复经典规则。",
    },
    level_04 = {
        objective = "测试苹果在受力快速变化下的稳态",
        observation = "一次恰当的冲量胜过持续用力。",
        description = "改变苹果的受力方向，使其绕过障碍后进入观察皿",
        scoreProfile = "intervention_level_04",
    },
    level_05 = {
        objective = "让苹果连续越过复杂障碍",
        observation = "重置规则，不重置结果。",
        description = "改变苹果移动路径越过迷宫",
        scoreProfile = "intervention_level_05",
    },
    level_06 = {
        objective = "在薄墙前开启量子隧穿",
        observation = "这不是穿墙，只是暂时不承认墙。",
        description = "为苹果准备多次相位充能，在关键位置穿过阻隔并完成观测。",
    },
    level_07 = {
        objective = "测试一下新实验仪器——弹簧，按钮，门",
        observation = "镜像改变方向，却不抹去速度。",
        description = "这个苹果可以不只有一种想法地落入观察皿",
    },
    level_08 = {
        objective = "在弹簧构成的通道里到达观察皿",
        observation = "反弹越漂亮，牛顿的眉头越紧。",
        description = "利用弹簧积累高度和水平速度，并控制落点稳定在观察皿附近",
    },
    level_09 = {
        objective = "怀疑是蓄意报复",
        observation = "同一个终点不要求同一条证明。",
        description = "上次看到这么多门还是家具城",
    },
}

local Config = {}
function Config.LegacyConstants()
    return { CONFIG = CONFIG, CARD_DESIGN_WIDTH = CARD_DESIGN_WIDTH, CARD_DESIGN_HEIGHT = CARD_DESIGN_HEIGHT,
        CARD_TEXT_SCALE = CARD_TEXT_SCALE, CARD_RENDER_WIDTH = CARD_RENDER_WIDTH,
        CARD_RENDER_HEIGHT = CARD_RENDER_HEIGHT, GOAL_CONTACT_SKIN = GOAL_CONTACT_SKIN,
        LEVEL_META = LEVEL_META, LEVEL_SCORE_PROFILES = LEVEL_SCORE_PROFILES,
        DEFAULT_LEVEL_SCORE_PROFILE = "intervention_standard" }
end

return Config
