local CONFIG = {
    title = "牛顿看了想打人",
    pixelsPerMeter = 100,
    matterFramesPerSecond = 60,
    bulletTimeScale = 0.05,
    levelCount = 9,
    replaySampleMs = 1000 / 30,
}

-- Phaser paints a 124 x 174 design face and uniformly scales it to 144 x 202.
-- Keep paint and hit geometry derived from that one transform so the card does
-- not become a mismatched rectangle at any responsive scale.
local CARD_DESIGN_WIDTH = 124
local CARD_DESIGN_HEIGHT = 174
local CARD_TEXT_SCALE = 144 / CARD_DESIGN_WIDTH
local CARD_RENDER_WIDTH = CARD_DESIGN_WIDTH * CARD_TEXT_SCALE
local CARD_RENDER_HEIGHT = CARD_DESIGN_HEIGHT * CARD_TEXT_SCALE
local GOAL_CONTACT_SKIN = .005

-- Matter stores velocity in pixels per 60 Hz frame, while Box2D uses metres
-- per second. These constants keep the migrated runtime on the source scale.
CONFIG.matterVelocityToWorld = CONFIG.matterFramesPerSecond / CONFIG.pixelsPerMeter
CONFIG.maxAppleSpeed = 25 * CONFIG.matterVelocityToWorld

local LEVEL_META = {
    level_01 = { name = "第一颗苹果", objective = "让苹果进入观察皿", observation = "先观察抛物线，再谈万有引力。" },
    level_02 = { name = "羽毛般落下", objective = "用轻羽引力越过矮台", observation = "减弱重力，轨迹会被拉得更长。" },
    level_03 = { name = "世界向右落", objective = "利用横向引力，再让世界归位", observation = "苹果记得已经获得的速度。" },
    level_04 = { name = "半空中的推手", objective = "在挡板前施加向上冲量", observation = "一次恰当的冲量胜过持续用力。" },
    level_05 = { name = "让世界归位", objective = "越墙后用牛顿拳恢复经典物理", observation = "重置规则，不重置结果。" },
    level_06 = { name = "墙不存在", objective = "在薄墙前开启量子隧穿", observation = "这不是穿墙，只是暂时不承认墙。" },
    level_07 = { name = "镜中的抛物线", objective = "反转水平速度，回到左侧观察皿", observation = "镜像改变方向，却不抹去速度。" },
    level_08 = { name = "胡克的台阶", objective = "借高弹性平台完成二次起跳", observation = "反弹越漂亮，牛顿的眉头越紧。" },
    level_09 = { name = "两条路", objective = "穿墙或折返，寻找自己的解法", observation = "同一个终点不要求同一条证明。" },
}

local Config = {}
function Config.LegacyConstants()
    return { CONFIG = CONFIG, CARD_DESIGN_WIDTH = CARD_DESIGN_WIDTH, CARD_DESIGN_HEIGHT = CARD_DESIGN_HEIGHT,
        CARD_TEXT_SCALE = CARD_TEXT_SCALE, CARD_RENDER_WIDTH = CARD_RENDER_WIDTH,
        CARD_RENDER_HEIGHT = CARD_RENDER_HEIGHT, GOAL_CONTACT_SKIN = GOAL_CONTACT_SKIN, LEVEL_META = LEVEL_META }
end

return Config
