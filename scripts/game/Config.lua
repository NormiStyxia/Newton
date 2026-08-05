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
            { score = 100, maxInterventions = 1, title = "精准实验", description = "以不超过 1 次有效干预完成观测" },
            { score = 80, maxInterventions = 3, title = "有效实验", description = "以不超过 3 次有效干预完成观测" },
            { score = 60, title = "观测成立", description = "让苹果稳定进入观察皿" },
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
        description = "校准发射方向与力度，让第一颗苹果稳定落入观察皿。",
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
        objective = "在挡板前施加向上冲量",
        observation = "一次恰当的冲量胜过持续用力。",
        description = "在苹果接近挡板时调整受力，越过障碍后进入右侧观察皿。",
    },
    level_05 = {
        objective = "越墙后用牛顿拳恢复经典物理",
        observation = "重置规则，不重置结果。",
        description = "先借持续规则越过高墙，再用牛顿修正拳清除场地规则并保留速度。",
    },
    level_06 = {
        objective = "在薄墙前开启量子隧穿",
        observation = "这不是穿墙，只是暂时不承认墙。",
        description = "为苹果准备一次相位充能，在关键位置穿过阻隔并完成观测。",
    },
    level_07 = {
        objective = "反转水平速度，回到左侧观察皿",
        observation = "镜像改变方向，却不抹去速度。",
        description = "让苹果越过观察皿后镜像水平速度，从右侧折返回目标区域。",
    },
    level_08 = {
        objective = "借高弹性平台完成二次起跳",
        observation = "反弹越漂亮，牛顿的眉头越紧。",
        description = "利用弹簧台阶积累高度，越过门控结构并落入观察皿。",
    },
    level_09 = {
        objective = "穿墙或折返，寻找自己的解法",
        observation = "同一个终点不要求同一条证明。",
        description = "综合使用已解锁的规则牌，在穿墙与折返两种路线之间完成最终观测。",
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
