-- Shared data for the title-screen character archive. Rendering and transition
-- behavior stay in TitleScreen; adding a profile only requires data and art.
local M = {}

local function color(r, g, b, a)
    return { r, g, b, a or 255 }
end

local profiles = {
    green_archive = {
        id = "green_archive",
        nameCn = "绿毛同事",
        nameEn = "ARCHIVE",
        subTitle = "ARCHIVE INTERFACE / RECORD SUPERVISOR",
        frameColors = {
            left = { base = color(40, 91, 82) },
            top = { base = color(63, 125, 112) },
            right = { base = color(99, 162, 143) },
            bottom = { base = color(140, 196, 168) },
        },
        accentColor = color(99, 162, 143),
        archiveColors = {
            ink = color(40, 91, 82, 232),
            inkStrong = color(40, 91, 82),
            body = color(48, 73, 65, 245),
            bodyMuted = color(77, 103, 91, 215),
            warm = color(63, 125, 112, 245),
        },
        assets = {
            directory = "image/title_screen/profile_green_archive",
            body = "body.png",
            head = "head.png",
            backdrop = "backdrop.png",
            infoBase = "info_base.png",
            doodle = "doodle.png",
            signature = "signature.png",
            back = "back.png",
        },
        root = {
            pivotX = 460.49, pivotY = 806.43,
            startOffsetX = -60.49, startOffsetY = -31.32,
            startScale = .6718, targetScale = 1,
        },
        backdropPivot = { x = 489, y = 431 },
        doodlePivot = { x = 438, y = 420 },
        academyRecord = {
            { label = "所属", value = "档案与记录维护处" },
            { label = "职务", value = "资料记录员" },
            { label = "负责事项", value = "整理实验记录、核对信息来源，\n以及在推断开始之前保存上下文" },
        },
        introText = "对来源、版本与上下文有近乎刻板的重视。负责区分已经发生的事实、仍待确认的信息，以及实验人员自己脑补出来的部分。",
        quoteText = "“青春绿毛同事不会梦见加需求的诺米”",
        quoteFont = "report-green",
        noteText = "学院备注：可以装猫娘skill",
        observationTitle = "档案观测样本",
    },
    nomi = {
        id = "nomi",
        nameCn = "诺米",
        nameEn = "NORMI",
        subTitle = "EXPERIMENT DESIGN / FIELD CREATOR",
        frameColors = {
            left = { base = color(49, 91, 137) },
            top = { base = color(66, 125, 178) },
            right = { base = color(98, 163, 208) },
            bottom = { base = color(145, 200, 226) },
        },
        accentColor = color(98, 163, 208),
        archiveColors = {
            ink = color(49, 91, 137, 232),
            inkStrong = color(49, 91, 137),
            body = color(52, 69, 88, 245),
            bodyMuted = color(76, 94, 113, 215),
            warm = color(66, 125, 178, 245),
        },
        assets = {
            directory = "image/title_screen/profile_nomi",
            body = "body.png",
            head = "head.png",
            backdrop = "backdrop.png",
            infoBase = "info_base.png",
            doodle = "doodle.png",
            signature = "signature.png",
            back = "back.png",
        },
        root = {
            pivotX = 447.86, pivotY = 804.56,
            startOffsetX = 190.14, startOffsetY = -34.94,
            startScale = .5896, targetScale = 1,
        },
        backdropPivot = { x = 489, y = 431 },
        doodlePivot = { x = 404, y = 421 },
        academyRecord = {
            { label = "所属", value = "实验创作部" },
            { label = "职务", value = "实验员" },
            { label = "负责事项", value = "设计关卡、修改规则，以及在自然规律\n已经失控以后继续尝试新的方案" },
        },
        introText = "对新规则、新机关和一切可以拖进编辑器的东西保持高度兴趣。遇到异常时通常先尝试解决，解决不了再记录下来，最后决定先让它能跑。",
        quoteText = "“东食堂昨天的黄焖鸡做咸了。”",
        quoteFont = "nomi-font",
        noteText = "学院备注：……已反馈食堂",
        observationTitle = "行为观测样本",
    },
    newton = {
        id = "newton",
        nameCn = "牛顿",
        nameEn = "NEWTON",
        subTitle = "CLASSICAL MECHANICS / SUPERVISOR",
        frameColors = {
            left = {
                base = color(146, 42, 26),
                start = color(142, 39, 24), finish = color(150, 45, 28),
            },
            top = {
                base = color(236, 64, 0),
                start = color(232, 61, 0), finish = color(240, 67, 2),
            },
            right = {
                base = color(255, 108, 0),
                start = color(252, 104, 0), finish = color(255, 112, 2),
            },
            bottom = {
                base = color(249, 131, 0),
                start = color(246, 127, 0), finish = color(252, 135, 3),
            },
        },
        accentColor = color(255, 108, 0),
        archiveColors = {
            ink = color(112, 47, 35, 232),
            inkStrong = color(104, 43, 31),
            body = color(75, 55, 43, 245),
            bodyMuted = color(103, 77, 58, 215),
            warm = color(173, 86, 38, 245),
        },
        assets = {
            directory = "image/title_screen/profile_newton",
            body = "body.png",
            bodySettled = "body_settled.png",
            head = "head.png",
            headSettled = "head_settled.png",
            backdrop = "backdrop.png",
            infoBase = "info_base.png",
            infoFrame = "info_frame.png",
            doodle = "doodle.png",
            signature = "signature.png",
            back = "back.png",
        },
        root = {
            pivotX = 438.3, pivotY = 774.0,
            startOffsetX = 431.2, startOffsetY = 1.2,
            startScale = .64, targetScale = 1,
        },
        backdropPivot = { x = 470, y = 416 },
        doodlePivot = { x = 441, y = 446 },
        academyRecord = {
            { label = "所属", value = "经典力学维护处" },
            { label = "职务", value = "实验监督员" },
            { label = "负责事项", value = "苹果、重力，以及阻止实验人员\n擅自修改自然规律" },
        },
        introText = "对实验秩序、测量精度与因果关系有严格要求。通常保持克制，直到有人开始把重力方向、弹性响应和运动轨迹当作可编辑参数。",
        quoteText = "“请先解释为什么它在往右掉。”",
        quoteFont = "report-newton",
        noteText = "学院备注：该问题尚未得到实验人员充分重视。",
        observationTitle = "情绪观测样本",
    },
    einstein = {
        id = "einstein",
        nameCn = "爱因斯坦",
        nameEn = "EINSTEIN",
        subTitle = "THEORETICAL PHYSICS / VISITING SCHOLAR",
        frameColors = {
            left = { base = color(85, 69, 117) },
            top = { base = color(112, 90, 152) },
            right = { base = color(144, 119, 184) },
            bottom = { base = color(180, 160, 210) },
        },
        accentColor = color(144, 119, 184),
        archiveColors = {
            ink = color(85, 69, 117, 232),
            inkStrong = color(85, 69, 117),
            body = color(65, 57, 76, 245),
            bodyMuted = color(91, 80, 105, 215),
            warm = color(112, 90, 152, 245),
        },
        assets = {
            directory = "image/title_screen/profile_einstein",
            body = "body.png",
            head = "head.png",
            backdrop = "backdrop.png",
            infoBase = "info_base.png",
            doodle = "doodle.png",
            signature = "signature.png",
            back = "back.png",
        },
        root = {
            pivotX = 436.65, pivotY = 819.51,
            startOffsetX = 673.36, startOffsetY = -44.16,
            startScale = .6446, targetScale = 1,
        },
        backdropPivot = { x = 489, y = 430 },
        doodlePivot = { x = 443, y = 419 },
        academyRecord = {
            { label = "所属", value = "理论物理研究室" },
            { label = "职务", value = "特邀研究员" },
            { label = "负责事项", value = "相对论、光，以及对部分量子解释\n持续提出一些不太配合的问题" },
        },
        introText = "对漂亮的理论与反常的实验结果同样感兴趣。相比立即纠正异常，更愿意先观察它究竟能够偏离常识到什么程度。",
        quoteText = "昨天苹果精准飞到牛顿头上的时候，我看到了光",
        quoteFont = "report-einstein",
        noteText = "学院备注：检测到异常能量波动",
        observationTitle = "思维观测样本",
    },
}

M.ORDER = { "green_archive", "nomi", "newton", "einstein" }

M.COMMON = {
    plateColor = color(251, 234, 212),
    enter = {
        sketchFlipStart = 0, sketchFlipEnd = .16,
        formalFlipStart = .16, formalFlipEnd = .31,
        moveStart = .31, moveEnd = .71,
        plateEnd = .30,
        backdropStart = .36, backdropEnd = .74,
        frameStart = .55, frameDuration = .17, frameStagger = .09,
        doodleStart = .91, doodleEnd = 1.07,
        signatureStart = .99, signatureEnd = 1.19,
        backStart = 1.08, backEnd = 1.22,
        total = 1.22,
    },
    exit = {
        backStart = 0, backEnd = .12,
        signatureStart = .05, signatureEnd = .22,
        doodleStart = .12, doodleEnd = .30,
        backdropStart = .28, backdropEnd = .56,
        frameStart = .24, frameDuration = .13, frameStagger = .07,
        moveStart = .56, moveEnd = .96,
        formalFlipStart = .96, formalFlipEnd = 1.11,
        sketchFlipStart = 1.11, sketchFlipEnd = 1.27,
        plateFadeStart = .96, plateFadeEnd = 1.27,
        total = 1.27,
    },
    signatureOffset = 16,
    backPivot = { x = 134, y = 79 },
    backHit = { x = 30, y = 20, w = 230, h = 125 },
}

M.FRAME_GEOMETRY = (function()
    local function band(centerX, centerY, length, angleDegrees, t1, t2, colorKey, reverse)
        local angle = angleDegrees * math.pi / 180
        local halfLength = length * .5
        local dx, dy = math.cos(angle) * halfLength, math.sin(angle) * halfLength
        local x1, y1 = centerX - dx, centerY - dy
        local x2, y2 = centerX + dx, centerY + dy
        if reverse then x1, y1, x2, y2 = x2, y2, x1, y1 end
        return { x1 = x1, y1 = y1, x2 = x2, y2 = y2, t1 = t1, t2 = t2, colorKey = colorKey }
    end
    return {
        band(456, 85, 758, -13, 116, 112, "top", true),
        band(126, 399, 836, 77, 114, 118, "left"),
        band(481, 778, 732, -13, 122, 118, "bottom"),
        band(830, 456, 816, 77, 108, 104, "right", true),
    }
end)()

function M.Get(characterId)
    return profiles[characterId]
end

function M.Ordered()
    local ordered = {}
    for _, characterId in ipairs(M.ORDER) do
        ordered[#ordered + 1] = profiles[characterId]
    end
    return ordered
end

return M
