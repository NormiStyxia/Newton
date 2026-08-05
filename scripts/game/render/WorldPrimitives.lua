local M = {}
local PhaseWallEffects = require("game.render.PhaseWallEffects")
local EinsteinObserver = require("game.render.EinsteinObserver")

function M.Install(Renderer, COLORS, color, tint)
    local function imageReady(image)
        return image ~= nil and image >= 0
    end

    local function skinReady(skin)
        return skin and imageReady(skin.topLeft) and imageReady(skin.top)
            and imageReady(skin.topRight) and imageReady(skin.left)
            and imageReady(skin.center) and imageReady(skin.right)
            and imageReady(skin.bottomLeft) and imageReady(skin.bottom)
            and imageReady(skin.bottomRight)
    end

    local GAMEPLAY_BORDER = { left = 155, right = 146, top = 167, bottom = 159 }
    local HUD_SCALE = 94 / 121
    local HUD_BORDER = {
        left = 60 * HUD_SCALE,
        right = 66 * HUD_SCALE,
        top = 45 * HUD_SCALE,
        bottom = 50 * HUD_SCALE,
    }
    local WALL_SCALE = 80 / 230
    local WALL_BORDER = {
        left = 74 * WALL_SCALE,
        right = 65 * WALL_SCALE,
        top = 67 * WALL_SCALE,
        bottom = 72 * WALL_SCALE,
    }
    local NARROW_WALL_SCALE = 17 / 49
    local NARROW_WALL_BORDER = {
        left = 80 * NARROW_WALL_SCALE,
        right = 78 * NARROW_WALL_SCALE,
        top = 24 * NARROW_WALL_SCALE,
        bottom = 25 * NARROW_WALL_SCALE,
    }
    local NARROW_WALL_MAX_THICKNESS = 40

    local function wallVisualSize(width, height, border)
        -- Phaser keeps the fixed corner bands at their authored size and grows
        -- the visual rectangle when a wall is thinner than their minimum span.
        -- Keep this purely visual; the physics body remains at the source size.
        return math.max(width, border.left + border.right),
            math.max(height, border.top + border.bottom)
    end

    local function drawGameplayFrameOverlay(self, frame)
        local x, y, w, h = frame.playfieldX, frame.playfieldY, frame.playfieldWidth, frame.playfieldHeight
        nvgLineCap(self.vg, NVG_ROUND); nvgLineJoin(self.vg, NVG_ROUND)
        nvgStrokeColor(self.vg, color(COLORS.darkPrimary, 255)); nvgStrokeWidth(self.vg, 3)
        nvgBeginPath(self.vg); nvgRoundedRect(self.vg, x + 2, y + 2, w - 4, h - 4, 10); nvgStroke(self.vg)
        nvgStrokeColor(self.vg, color(COLORS.fieldCardBorder, 255)); nvgStrokeWidth(self.vg, 2)
        nvgBeginPath(self.vg); nvgRoundedRect(self.vg, x + 10, y + 10, w - 20, h - 20, 7); nvgStroke(self.vg)
        nvgStrokeColor(self.vg, color(COLORS.wallBrassEdge, 122)); nvgStrokeWidth(self.vg, 2)
        nvgBeginPath(self.vg); nvgRoundedRect(self.vg, x + 17, y + 17, w - 34, h - 34, 5); nvgStroke(self.vg)

        nvgStrokeColor(self.vg, color(COLORS.wallBrassEdge, 128)); nvgStrokeWidth(self.vg, 2)
        nvgBeginPath(self.vg)
        nvgMoveTo(self.vg, x + 18, y + 18); nvgLineTo(self.vg, x + 46, y + 18); nvgLineTo(self.vg, x + 18, y + 46)
        nvgMoveTo(self.vg, x + w - 18, y + 18); nvgLineTo(self.vg, x + w - 46, y + 18); nvgLineTo(self.vg, x + w - 18, y + 46)
        nvgMoveTo(self.vg, x + 18, y + h - 18); nvgLineTo(self.vg, x + 46, y + h - 18); nvgLineTo(self.vg, x + 18, y + h - 46)
        nvgMoveTo(self.vg, x + w - 18, y + h - 18); nvgLineTo(self.vg, x + w - 46, y + h - 18); nvgLineTo(self.vg, x + w - 18, y + h - 46)
        nvgStroke(self.vg)

        local centerX = x + w * .5
        nvgStrokeColor(self.vg, color(COLORS.instant, 255)); nvgStrokeWidth(self.vg, 2)
        nvgBeginPath(self.vg)
        nvgMoveTo(self.vg, centerX - 18, y + 10); nvgLineTo(self.vg, centerX + 18, y + 10)
        nvgMoveTo(self.vg, centerX - 18, y + h - 10); nvgLineTo(self.vg, centerX + 18, y + h - 10)
        nvgStroke(self.vg)
        nvgBeginPath(self.vg)
        nvgMoveTo(self.vg, centerX - 8, y + 10); nvgLineTo(self.vg, centerX, y + 2); nvgLineTo(self.vg, centerX + 8, y + 10)
        nvgLineTo(self.vg, centerX, y + 18); nvgClosePath(self.vg)
        nvgMoveTo(self.vg, centerX - 8, y + h - 10); nvgLineTo(self.vg, centerX, y + h - 18); nvgLineTo(self.vg, centerX + 8, y + h - 10)
        nvgLineTo(self.vg, centerX, y + h - 2); nvgClosePath(self.vg)
        nvgFillColor(self.vg, color(COLORS.playfieldAccent, 255)); nvgFill(self.vg)
        nvgStroke(self.vg)
    end

    function Renderer:DrawBackground(frame)
        self:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight, COLORS.background)
        if skinReady(self.skins and self.skins.hud) then
            self:NineSlice(self.skins.hud, 0, 0, frame.logicalWidth, 94, HUD_BORDER)
        elseif imageReady(self.images.ui and self.images.ui.hudFrame) then
            self:ImageRect(self.images.ui.hudFrame, 0, 0, frame.logicalWidth, 94, 1)
        else
            self:FillRect(0, 0, frame.logicalWidth, 94, COLORS.panel, 250)
            self:FillRect(0, 92, frame.logicalWidth, 2, COLORS.greenLight, 230)
        end
        if imageReady(self.images.ui and self.images.ui.titlePlaque) then
            self:ImageRect(self.images.ui.titlePlaque, frame.workspaceX - 55, -18, 448, 112, 1)
        else
            self:RoundedRect(frame.workspaceX - 55, -18, 448, 112, 20, COLORS.darkPrimary)
        end
        self:RoundedRect(frame.newtonX + 6, frame.newtonY + 6, frame.newtonWidth, frame.newtonHeight, 7, COLORS.floor, nil, nil, 20)
        self:RoundedRect(frame.playfieldX + 7, frame.playfieldY + 9, frame.playfieldWidth, frame.playfieldHeight, 7, COLORS.floor, nil, nil, 20)
        if imageReady(self.images.ui and self.images.ui.gameplayFrame) then
            self:ImageRect(self.images.ui.gameplayFrame, frame.playfieldX, frame.playfieldY,
                frame.playfieldWidth, frame.playfieldHeight, 1)
        else
            self:RoundedRect(frame.playfieldX, frame.playfieldY, frame.playfieldWidth, frame.playfieldHeight, 7, COLORS.playfield, COLORS.darkPrimary, 4)
            self:RoundedRect(frame.playfieldX + 8, frame.playfieldY + 8, frame.playfieldWidth - 16, frame.playfieldHeight - 16, 5, nil, COLORS.greenLight, 2)
        end
        self:DrawGrid(frame)
        self:DrawFormulas(frame)
    end

    function Renderer:DrawGrid(frame)
        local x, y, w, h = frame.playfieldX, frame.playfieldY, frame.playfieldWidth, frame.playfieldHeight
        nvgStrokeColor(self.vg, color(COLORS.greenStrong, 26)); nvgStrokeWidth(self.vg, 1)
        for px = x + 40, x + w - 10, 48 do
            nvgBeginPath(self.vg); nvgMoveTo(self.vg, px, y + 10); nvgLineTo(self.vg, px, y + h - 10); nvgStroke(self.vg)
        end
        for py = y + 38, y + h - 10, 42 do
            nvgBeginPath(self.vg); nvgMoveTo(self.vg, x + 10, py); nvgLineTo(self.vg, x + w - 10, py); nvgStroke(self.vg)
        end
        nvgStrokeColor(self.vg, color(COLORS.darkPrimary, 33)); nvgStrokeWidth(self.vg, 1)
        for px = x + 136, x + w - 10, 192 do
            nvgBeginPath(self.vg); nvgMoveTo(self.vg, px, y + 10); nvgLineTo(self.vg, px, y + h - 10); nvgStroke(self.vg)
        end
        for py = y + 122, y + h - 10, 168 do
            nvgBeginPath(self.vg); nvgMoveTo(self.vg, x + 10, py); nvgLineTo(self.vg, x + w - 10, py); nvgStroke(self.vg)
        end
    end

    local function formulaPoint(frame, rx, ry)
        local innerX, innerY = frame.playfieldX + 26, frame.playfieldY + 24
        local innerW, innerH = frame.playfieldWidth - 52, frame.playfieldHeight - 70
        return innerX + rx * innerW, innerY + ry * innerH, innerW, innerH
    end

    function Renderer:DrawFormulaDiagram(frame, kind, rx, ry, rw, rh, rotation, alpha)
        local x, y, innerW, innerH = formulaPoint(frame, rx, ry)
        local w, h = (rw or 0) * innerW, (rh or 0) * innerH
        nvgSave(self.vg); nvgTranslate(self.vg, x, y); nvgRotate(self.vg, rotation or 0)
        local light = math.floor(255 * alpha)
        local strong = math.floor(255 * math.min(1, alpha * 1.2))
        if kind == "orbit" then
            local radius = (rw or 0) * math.min(innerW, innerH)
            nvgStrokeColor(self.vg, color(COLORS.dark, strong)); nvgStrokeWidth(self.vg, 2)
            nvgBeginPath(self.vg); nvgCircle(self.vg, 0, 0, radius * .72); nvgStroke(self.vg)
            nvgBeginPath(self.vg); nvgEllipse(self.vg, 0, 0, radius * 1.1, radius * .41); nvgStroke(self.vg)
            nvgSave(self.vg); nvgRotate(self.vg, math.pi / 3)
            nvgBeginPath(self.vg); nvgEllipse(self.vg, 0, 0, radius * 1.1, radius * .41); nvgStroke(self.vg)
            nvgRestore(self.vg)
            self:Circle(radius * .78, -radius * .2, 3, COLORS.dark, nil, nil, strong)
        elseif kind == "cone" then
            nvgStrokeColor(self.vg, color(COLORS.dark, strong)); nvgStrokeWidth(self.vg, 2)
            nvgBeginPath(self.vg); nvgMoveTo(self.vg, 0, -h / 2); nvgLineTo(self.vg, -w / 2, h * .32); nvgMoveTo(self.vg, 0, -h / 2); nvgLineTo(self.vg, w / 2, h * .32); nvgEllipse(self.vg, 0, h * .32, w / 2, h * .15); nvgStroke(self.vg)
            nvgStrokeColor(self.vg, color(COLORS.greenStrong, light)); nvgStrokeWidth(self.vg, 1)
            nvgBeginPath(self.vg); nvgMoveTo(self.vg, 0, -h * .6); nvgLineTo(self.vg, 0, h * .58); nvgMoveTo(self.vg, -w * .52, h * .32); nvgLineTo(self.vg, w * .52, h * .32); nvgStroke(self.vg)
        elseif kind == "orbit-map" then
            nvgStrokeColor(self.vg, color(COLORS.greenStrong, light)); nvgStrokeWidth(self.vg, 1)
            nvgBeginPath(self.vg); nvgEllipse(self.vg, 0, 0, w / 2, h * .26); nvgEllipse(self.vg, 0, 0, w * .36, h * .39); nvgCircle(self.vg, 0, 0, math.min(w, h) * .18); nvgMoveTo(self.vg, -w * .58, 0); nvgLineTo(self.vg, w * .58, 0); nvgMoveTo(self.vg, 0, -h * .55); nvgLineTo(self.vg, 0, h * .55); nvgStroke(self.vg)
            self:Circle(w * .39, -h * .11, 3, COLORS.dark, nil, nil, strong)
        elseif kind == "shaded-wave" then
            local function sample(progress)
                local phase = progress * math.pi * 2
                local modulation = .82 + math.sin(phase * 2 - .4) * .18
                return (math.sin(phase * 3) + math.sin(phase * 7 + .7) * .5 + math.cos(phase * 11) * .25) * modulation * h * .25
            end
            nvgStrokeColor(self.vg, color(COLORS.greenStrong, light)); nvgStrokeWidth(self.vg, 1)
            nvgBeginPath(self.vg); nvgMoveTo(self.vg, -w / 2, 0); nvgLineTo(self.vg, w / 2, 0); nvgMoveTo(self.vg, -w / 2, h * .48); nvgLineTo(self.vg, -w / 2, -h * .48); nvgStroke(self.vg)
            nvgStrokeColor(self.vg, color(COLORS.dark, strong)); nvgStrokeWidth(self.vg, 2); nvgBeginPath(self.vg)
            for step = 0, 96 do
                local progress = step / 96
                local px, py = -w / 2 + w * progress, sample(progress)
                if step == 0 then nvgMoveTo(self.vg, px, py) else nvgLineTo(self.vg, px, py) end
            end
            nvgStroke(self.vg)
        elseif kind == "parabola" then
            nvgStrokeColor(self.vg, color(COLORS.greenStrong, light)); nvgStrokeWidth(self.vg, 1)
            nvgBeginPath(self.vg); nvgMoveTo(self.vg, -w / 2, h * .45); nvgLineTo(self.vg, w / 2, h * .45); nvgMoveTo(self.vg, -w * .28, h * .58); nvgLineTo(self.vg, -w * .28, -h * .58); nvgStroke(self.vg)
            nvgStrokeColor(self.vg, color(COLORS.dark, strong)); nvgStrokeWidth(self.vg, 2); nvgBeginPath(self.vg)
            for step = 0, 48 do
                local progress = step / 48
                local normalizedX = progress * 1.4 - .35
                local px = -w * .28 + normalizedX * w * .68
                local py = h * .45 - normalizedX * normalizedX * h * .72
                if step == 0 then nvgMoveTo(self.vg, px, py) else nvgLineTo(self.vg, px, py) end
            end
            nvgStroke(self.vg)
        end
        nvgRestore(self.vg)
    end

    function Renderer:DrawFormulas(frame)
        -- Keep all notice-board writing inside the central public-wall area.
        -- The surrounding instruments and lower ruler remain illustration-only.
        local noticeX = frame.playfieldX + frame.playfieldWidth * .06
        local noticeY = frame.playfieldY + frame.playfieldHeight * .08
        local noticeW = frame.playfieldWidth * .88
        local noticeH = frame.playfieldHeight * .70
        nvgSave(self.vg)
        nvgScissor(self.vg, noticeX, noticeY, noticeW, noticeH)

        local c = COLORS.greenStrong
        local formulas = {
            { "s = ½gt²", .08, .08, 18, -.025, .15 }, { "v = v₀ + gt", .08, .16, 16, .018, .14 },
            { "F = ma", .35, .15, 25, -.025, .19, true }, { "y = ½gt²", .59, .08, 19, .018, .15 },
            { "E = mc²", .94, .16, 18, .018, .14 }, { "ΣF = ma", .12, .38, 20, .025, .16 },
            { "ΣF = ma", .45, .3, 21, -.02, .16 }, { "F_g = Gm₁m₂ / r²", .72, .39, 20, -.018, .17, true },
            { "a = Δv / Δt", .92, .36, 18, .02, .15 }, { "y = sin 3t + ½sin(7t + φ) + ¼cos 11t", .36, .73, 14, .015, .13 },
            { "v² = v₀² + 2aΔx", .58, .8, 19, -.018, .16 }, { "y = kx²", .91, .55, 17, -.018, .14 },
        }
        self:DrawFormulaDiagram(frame, "cone", .2, .12, .09, .16, -.018, .12)
        self:DrawFormulaDiagram(frame, "orbit", .82, .12, .07, nil, .04, .13)
        self:DrawFormulaDiagram(frame, "orbit-map", .12, .64, .13, .16, -.025, .12)
        self:DrawFormulaDiagram(frame, "shaded-wave", .36, .59, .21, .12, -.015, .13)
        self:DrawFormulaDiagram(frame, "parabola", .9, .7, .14, .18, .012, .13)
        for _, f in ipairs(formulas) do
            local x, y = formulaPoint(frame, f[2], f[3])
            nvgSave(self.vg)
            nvgTranslate(self.vg, x, y)
            nvgRotate(self.vg, f[5])
            self:Text(0, 0, f[1], f[4], f[7] and COLORS.darkPrimary or c, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display", math.floor(f[6] * 255))
            nvgRestore(self.vg)
        end

        local lineArt = self.images.ui and self.images.ui.noticeLineArt
        if imageReady(lineArt) then
            -- Keep the source line art's authored 957x999 aspect ratio. The
            -- previous independent height caused visible vertical squashing.
            local lineArtWidth = frame.playfieldWidth * .15
            local lineArtHeight = lineArtWidth * 999 / 957
            local lineArtX = frame.playfieldX + frame.playfieldWidth * .56
            local lineArtY = frame.playfieldY + frame.playfieldHeight * .37
            self:Image(lineArt, lineArtX, lineArtY, lineArtWidth, lineArtHeight, .58)
        end

        nvgRestore(self.vg)
    end

    function Renderer:DrawNewton(frame, level, anger, observation)
        local x, y, w, h = frame.newtonX, frame.newtonY, frame.newtonWidth, frame.newtonHeight
        local angerLevel = math.max(0, math.min(100, anger or 0))
        local angerKey = angerLevel >= 100 and 100 or angerLevel >= 75 and 75 or angerLevel >= 50 and 50 or angerLevel >= 25 and 25 or 0
        local angerPanel = self.images.newtonAnger and self.images.newtonAnger[angerKey]
        if imageReady(angerPanel) then
            -- Phaser aligns the panel's border lines, so the source artwork
            -- intentionally extends beyond the logical panel bounds.
            local sourceWidth, sourceHeight = 346, 785
            local assetPadding, bottomBorderY = 8, 745
            local verticalScale = h / (bottomBorderY - assetPadding)
            local horizontalScale = h / (sourceHeight - assetPadding * 2)
            local imageY = y + (sourceHeight * .5 - assetPadding) * verticalScale
            self:Image(angerPanel, x + w * .5, imageY,
                sourceWidth * horizontalScale, sourceHeight * verticalScale, 1, nil, .5, .5)
            self:Text(x + 26, y + 38, "ISAAC NEWTON", 12, COLORS.ash)
            self:Text(x + 26, y + 55, "牛顿 · 经典定律维护者", 20, COLORS.darkPrimary, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
            self:TextBox(x + 26, y + 128, w - 52, "“" .. (observation or (level and level.observation) or "先观察抛物线，再谈万有引力。") .. "”", 16, COLORS.body, nil, nil, 1.25)
            if angerLevel >= 50 and imageReady(self.images.newtonAnger.icon) then
                self:Image(self.images.newtonAnger.icon, x + 82, y + 216, 34, 35, 1)
            end
            self:Text(x + 24, y + h - 105, "牛顿怒气", 18, COLORS.darkPrimary)
            self:RoundedRect(x + 44, y + 529, 162, 12, 6, COLORS.greenSoft)
            self:RoundedRect(x + 44, y + 529, 162, 12, 6, nil, COLORS.darkSecondary, 2, 230)
            self:RoundedRect(x + 47, y + 532, 156 * angerLevel / 100, 7, 3, COLORS.newtonAngerProgress)
            if imageReady(self.images.apple) then
                self:Image(self.images.apple, x + 47 + 156 * angerLevel / 100, y + 535, 34, 34, 1)
            end
            self:Text(x + w - 24, y + h - 105, string.format("%d%%", math.floor(angerLevel + .5)), 18, COLORS.warning, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            return
        end
        self:RoundedRect(x, y, w, h, 7, COLORS.panel, COLORS.greenLight, 2)
        self:RoundedRect(x + 8, y + 8, w - 16, h - 16, 5, nil, COLORS.panelSecondary, 1)
        self:RoundedRect(x + 18, y + 12, w - 36, 58, 6, COLORS.dark)
        self:Text(x + 24, y + 20, "ISAAC NEWTON", 12, COLORS.warningLow)
        self:Text(x + 24, y + 40, "牛顿 · 经典定律维护者", 20, COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
        if self.images.portrait and self.images.portrait >= 0 then
            -- The Phaser source crops the portrait to its first 620 source pixels.
            nvgSave(self.vg)
            nvgScissor(self.vg, x + 8, y + 134, w - 16, 322)
            self:Image(self.images.portrait, x + w * .5 + 2, y + 134, 311, 535, 1, nil, .5, 0)
            nvgRestore(self.vg)
        else
            self:Circle(x + w * .5, y + 242, 94, COLORS.greenSoft, COLORS.greenLight, 2)
        end
        nvgStrokeColor(self.vg, color(COLORS.warningLow, 180)); nvgStrokeWidth(self.vg, 3)
        nvgBeginPath(self.vg); nvgMoveTo(self.vg, x + 22, y + 90); nvgLineTo(self.vg, x + 22, y + 140); nvgStroke(self.vg)
        self:TextBox(x + 26, y + 95, w - 52, "“" .. (observation or (level and level.observation) or "先观察抛物线，再谈万有引力。") .. "”", 16, COLORS.body, nil, nil, 1.25)
        nvgStrokeColor(self.vg, color(COLORS.greenLight, 163)); nvgStrokeWidth(self.vg, 2)
        nvgBeginPath(self.vg); nvgMoveTo(self.vg, x + 34, y + 472); nvgLineTo(self.vg, x + w - 34, y + 472); nvgStroke(self.vg)
        self:Text(x + 24, y + h - 114, "牛顿怒气", 18, COLORS.secondary)
        self:RoundedRect(x + 24, y + h - 86, w - 48, 12, 5, COLORS.warningSoft, COLORS.warningLow, 1)
        self:RoundedRect(x + 27, y + h - 84, math.max(0, w - 54) * math.max(0, math.min(1, anger / 100)), 7, 3, COLORS.warningActive)
        self:Text(x + w - 24, y + h - 114, string.format("%d%%", math.floor(anger + 0.5)), 18, COLORS.warning, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        self:Text(x + 24, y + h - 58, "修正拳：恢复持续规则，保留运动状态", 11, COLORS.secondary)
    end

    function Renderer:DrawGround(frame)
        local x, y = frame.playfieldX + 17, frame.groundY
        local w = frame.playfieldWidth - 34
        local h = frame.playfieldY + frame.playfieldHeight - 17 - y
        if w <= 0 or h <= 0 then return end
        local sx, sy = w / 1500, h / 106
        local rulerHeight = 27 * sy
        local strokeScale = (sx + sy) * .5
        local ground = { 237, 226, 194, 255 }
        local ruler = { 217, 201, 149, 255 }
        local rulerTick = { 111, 102, 93, 255 }
        local gold = { 159, 137, 84, 255 }

        self:FillRect(x, y + rulerHeight, w, h - rulerHeight, ground, 235)
        self:FillRect(x, y, w, rulerHeight, ruler)

        nvgStrokeColor(self.vg, color(rulerTick, 219)); nvgStrokeWidth(self.vg, 1.4 * strokeScale)
        nvgBeginPath(self.vg)
        for offset = 0, 1500, 24 do
            local px = x + offset * sx
            nvgMoveTo(self.vg, px, y + 3 * sy); nvgLineTo(self.vg, px, y + 23 * sy)
            if offset + 6 <= 1500 then nvgMoveTo(self.vg, px + 6 * sx, y + 3 * sy); nvgLineTo(self.vg, px + 6 * sx, y + 11 * sy) end
            if offset + 12 <= 1500 then nvgMoveTo(self.vg, px + 12 * sx, y + 3 * sy); nvgLineTo(self.vg, px + 12 * sx, y + 16 * sy) end
            if offset + 18 <= 1500 then nvgMoveTo(self.vg, px + 18 * sx, y + 3 * sy); nvgLineTo(self.vg, px + 18 * sx, y + 11 * sy) end
        end
        nvgStroke(self.vg)
        nvgStrokeColor(self.vg, color(gold, 179)); nvgStrokeWidth(self.vg, strokeScale)
        nvgBeginPath(self.vg)
        for offset = 0, 1500, 12 do
            local px = x + offset * sx
            nvgMoveTo(self.vg, px, y + 15 * sy); nvgLineTo(self.vg, px, y + 25 * sy)
            if offset + 6 <= 1500 then nvgMoveTo(self.vg, px + 6 * sx, y + 15 * sy); nvgLineTo(self.vg, px + 6 * sx, y + 20 * sy) end
        end
        nvgStroke(self.vg)

        nvgStrokeColor(self.vg, color(COLORS.darkPrimary, 255)); nvgStrokeWidth(self.vg, 3 * strokeScale)
        nvgBeginPath(self.vg); nvgMoveTo(self.vg, x, y + sy); nvgLineTo(self.vg, x + w, y + sy); nvgMoveTo(self.vg, x, y + 26 * sy); nvgLineTo(self.vg, x + w, y + 26 * sy); nvgStroke(self.vg)
        nvgStrokeColor(self.vg, color(gold, 255)); nvgStrokeWidth(self.vg, 1.5 * strokeScale)
        nvgBeginPath(self.vg); nvgMoveTo(self.vg, x, y + 4 * sy); nvgLineTo(self.vg, x + w, y + 4 * sy); nvgMoveTo(self.vg, x, y + 22 * sy); nvgLineTo(self.vg, x + w, y + 22 * sy); nvgStroke(self.vg)
        nvgStrokeColor(self.vg, color(gold, 148)); nvgStrokeWidth(self.vg, 2 * strokeScale)
        nvgBeginPath(self.vg); nvgMoveTo(self.vg, x, y + 34 * sy); nvgLineTo(self.vg, x + w, y + 34 * sy); nvgMoveTo(self.vg, x, y + 98 * sy); nvgLineTo(self.vg, x + w, y + 98 * sy); nvgStroke(self.vg)
        nvgStrokeColor(self.vg, color(COLORS.white, 133)); nvgStrokeWidth(self.vg, 2 * strokeScale)
        nvgBeginPath(self.vg); nvgMoveTo(self.vg, x, y + 40 * sy); nvgLineTo(self.vg, x + w, y + 40 * sy); nvgMoveTo(self.vg, x, y + 92 * sy); nvgLineTo(self.vg, x + w, y + 92 * sy); nvgStroke(self.vg)
        drawGameplayFrameOverlay(self, frame)
    end

    function Renderer:DrawGameplayFrameChrome(frame)
        if skinReady(self.skins and self.skins.gameplay) then
            self:NineSlice(self.skins.gameplay, frame.playfieldX, frame.playfieldY,
                frame.playfieldWidth, frame.playfieldHeight, GAMEPLAY_BORDER)
        end
    end

    function Renderer:DrawGameplayDecor(frame)
        local overlay = self.images.ui and self.images.ui.gameplayDecorOverlay
        if not imageReady(overlay) then return end
        local scale = frame.logicalWidth / 2559
        self:Image(overlay, 0, 0, 2559 * scale, 1149 * scale, 1, 0, 0, 0)
    end

    function Renderer:DrawGoalSensor(x, y, w, h, state)
        local usableDiameter = math.max(48, math.min(w * .8, h))
        local outerRadius = usableDiameter * .5
        local active = state.active == true
        local requiredStayTime = math.max(1, state.requiredStayTime or 1000)
        local contactMs = math.max(0, state.contactMs or 0)
        local remainingMs = math.max(0, requiredStayTime - contactMs)
        self:Text(x, y - outerRadius - 20, string.format("%.1fs", remainingMs / 1000), 14,
            active and COLORS.primaryActive or COLORS.secondary,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "maker-display", 240)
        if state.goalPulseProgress ~= nil then
            local progress = math.max(0, math.min(1, state.goalPulseProgress))
            -- The portrait now fills the sensor diameter. Keep the success
            -- pulse on its outer edge instead of hiding it behind the image.
            self:Circle(x, y, outerRadius * (1 + progress * .088), nil, COLORS.primaryActive, 2, math.floor(.78 * (1 - progress) * 255))
        end
        EinsteinObserver.Draw(self, self.images.goalObserver, x, y, usableDiameter, state.observer)
    end

    function Renderer:DrawObject(frame, object, state, design, mapper)
        if not object or not object.data then return end
        local t = object.data.transform
        local position = object.node and object.node.position2D or nil
        local worldX, worldY
        if position then
            worldX, worldY = position.x, position.y
        else
            worldX, worldY = mapper:LevelToWorld(t.x, t.y)
        end
        local x, y = design:WorldToLogical(worldX, worldY)
        local worldWidth, worldHeight = mapper:LevelSizeToWorld(t.width, t.height)
        local w, h = design:WorldSizeToLogical(worldWidth, worldHeight)
        -- UrhoX stores node angles in Y-up world space; NanoVG and Phaser use
        -- Y-down screen space, so presentation needs the opposite angle.
        local rotation = object.node and math.rad(-object.node.rotation2D) or math.rad(t.rotation or 0)
        if object.type == "wall" then
            local fill = object.phaseable and COLORS.glass or COLORS.wall
            local edge = object.phaseable and COLORS.glassEdge or COLORS.wallEdge
            nvgSave(self.vg)
            nvgTranslate(self.vg, x, y)
            nvgRotate(self.vg, rotation)
            local isNarrow = math.min(t.width or 0, t.height or 0) <= NARROW_WALL_MAX_THICKNESS
            local wallSkin = isNarrow and self.skins.wallNarrow or self.skins.wall
            local wallBorder = isNarrow and NARROW_WALL_BORDER or WALL_BORDER
            if object.phaseable then
                -- Keep the readable glass body rectangular. PhaseWallEffects
                -- rebuilds only the membrane border and transient feedback.
                self:FillRect(-w * .5, -h * .5, w, h, fill, 158)
                self:FillRect(-w * .28 - 2, -math.max(12, h - 16) * .5,
                    4, math.max(12, h - 16), COLORS.panel, 82)
                PhaseWallEffects.Draw(self, object, w, h, COLORS)
            elseif skinReady(wallSkin) then
                -- The narrow source PNG is horizontal. Match Phaser's
                -- WallObject by composing it in source orientation and
                -- rotating only vertical narrow walls by 90 degrees.
                if isNarrow and t.height > t.width then
                    nvgSave(self.vg)
                    nvgRotate(self.vg, math.pi * .5)
                    local visualWidth, visualHeight = wallVisualSize(h, w, wallBorder)
                    self:NineSlice(wallSkin, -visualWidth * .5, -visualHeight * .5, visualWidth, visualHeight, wallBorder)
                    nvgRestore(self.vg)
                else
                    local visualWidth, visualHeight = wallVisualSize(w, h, wallBorder)
                    self:NineSlice(wallSkin, -visualWidth * .5, -visualHeight * .5, visualWidth, visualHeight, wallBorder)
                end
            else
                self:FillRect(-w * .5, -h * .5, w, h, fill, object.phaseable and 173 or 255)
                self:StrokeRect(-w * .5, -h * .5, w, h, edge, 3, 240)
                self:FillRect(-w * .28 - 2, -math.max(12, h - 16) * .5, 4, math.max(12, h - 16), object.phaseable and COLORS.glass or COLORS.panel, 97)
            end
            nvgRestore(self.vg)
        elseif object.type == "door" then
            local alpha = object.openness == 1 and 51 or 255
            nvgSave(self.vg)
            nvgTranslate(self.vg, x, y)
            nvgRotate(self.vg, rotation)
            self:FillRect(-w * .5, -h * .5, w, h, COLORS.darkSecondary, alpha)
            self:StrokeRect(-w * .5, -h * .5, w, h, COLORS.darkPrimary, 3, alpha)
            nvgRestore(self.vg)
        elseif object.type == "launcher" then
            self:Image(self.images.launcher, x, y, w, w * 190 / 150, 1, rotation, .5, 36 / 190)
        elseif object.type == "goal_sensor" then
            self:DrawGoalSensor(x, y, w, h, {
                active = object.active,
                contactProgress = object.contactProgress,
                contactMs = object.contactMs,
                requiredStayTime = object.requiredStayTime,
                goalPulseProgress = state.goalPulseProgress,
                observer = object,
            })
        elseif object.type == "spring" then
            nvgSave(self.vg); nvgTranslate(self.vg, x, y); nvgRotate(self.vg, rotation)
            if object.pulseElapsedMs ~= nil then
                local phase = math.max(0, math.min(1, object.pulseElapsedMs / 70))
                if object.pulseElapsedMs > 70 then phase = math.max(0, math.min(1, (140 - object.pulseElapsedMs) / 70)) end
                local compression = math.sin(phase * math.pi * .5)
                nvgScale(self.vg, 1 - compression * .12, 1 - compression * .28)
            end
            nvgStrokeColor(self.vg, color(COLORS.warningActive)); nvgStrokeWidth(self.vg, 4); nvgBeginPath(self.vg)
            for i = 0, 8 do
                local px = -w / 2 + w * i / 8
                local py = 0
                if i ~= 0 and i ~= 8 then py = i % 2 == 0 and -h * .36 or h * .36 end
                if i == 0 then nvgMoveTo(self.vg, px, py) else nvgLineTo(self.vg, px, py) end
            end
            nvgStroke(self.vg)
            nvgStrokeColor(self.vg, color(COLORS.darkPrimary)); nvgStrokeWidth(self.vg, 3); nvgBeginPath(self.vg); nvgMoveTo(self.vg, -w * .5, h * .5); nvgLineTo(self.vg, w * .5, h * .5); nvgStroke(self.vg)
            nvgRestore(self.vg)
        elseif object.type == "button" then
            local visualState = object.active and "ACTIVE" or (object.contactCount > 0 and not object.conditionSatisfied and "CONTACT_INVALID" or "IDLE")
            nvgSave(self.vg); nvgTranslate(self.vg, x, y); nvgRotate(self.vg, rotation)
            self:FillRect(-w * .5, -h * .5, w, h, COLORS.darkPrimary)
            self:StrokeRect(-w * .5, -h * .5, w, h, COLORS.darkSecondary, 2)
            local plateY = object.active and 1 or -h * .18
            local plate = visualState == "ACTIVE" and COLORS.primaryActive or (visualState == "CONTACT_INVALID" and COLORS.playfieldAccent or COLORS.warningActive)
            self:FillRect(-math.max(12, w - 12) * .5, plateY - math.max(6, h * .45) * .5, math.max(12, w - 12), math.max(6, h * .45), plate)
            if visualState == "CONTACT_INVALID" then self:FillRect(-math.max(10, w - 20) * .5, h * .3 - 1, math.max(10, w - 20), 2, COLORS.greenStrong, 184) end
            nvgRestore(self.vg)
        end
    end

    function Renderer:DrawApple(frame, apple, scale, alpha, design)
        if not apple or not apple.node then return end
        local p = apple.node.position2D
        local x, y = design:WorldToLogical(p.x, p.y)
        local r = (apple.displayRadius or 32) * (scale or 1)
        -- UrhoX stores the apple angle in Y-up world space, while NanoVG
        -- renders in screen-space Y-down. Flip only the presentation angle so
        -- the apple keeps its physics state but visibly turns clockwise like
        -- Phaser's Matter sprite.
        local angle = apple.node.rotation2D and math.rad(-apple.node.rotation2D) or 0
        if self.images.apple and self.images.apple >= 0 then self:Image(self.images.apple, x, y, r * 2, r * 2, alpha or 1, angle) else self:Circle(x, y, r, COLORS.warningActive, COLORS.warning, nil, math.floor((alpha or 1) * 255)) end
    end

    -- Original fist.svg is a two-path, self-contained vector. Keep the source SVG
    -- read-only and reproduce its viewBox paths at the same 128-unit scale here.
    function Renderer:DrawFist(x, y, size, tintColor, alpha)
        local scale = size / 128
        local opacity = alpha or 255
        nvgSave(self.vg)
        nvgTranslate(self.vg, x - size * .5, y - size * .5)
        nvgScale(self.vg, scale, scale)
        nvgLineJoin(self.vg, NVG_ROUND)
        nvgBeginPath(self.vg)
        nvgMoveTo(self.vg, 29, 56)
        nvgLineTo(self.vg, 29, 34)
        nvgBezierTo(self.vg, 29, 26, 42, 25, 44, 33)
        nvgLineTo(self.vg, 44, 22)
        nvgBezierTo(self.vg, 44, 13, 58, 13, 59, 22)
        nvgLineTo(self.vg, 59, 32)
        nvgLineTo(self.vg, 59, 17)
        nvgBezierTo(self.vg, 59, 8, 73, 8, 74, 17)
        nvgLineTo(self.vg, 74, 34)
        nvgLineTo(self.vg, 74, 23)
        nvgBezierTo(self.vg, 74, 14, 88, 14, 89, 23)
        nvgLineTo(self.vg, 89, 60)
        nvgLineTo(self.vg, 96, 50)
        nvgBezierTo(self.vg, 102, 41, 115, 48, 110, 58)
        nvgLineTo(self.vg, 86, 92)
        nvgBezierTo(self.vg, 80, 104, 70, 112, 56, 112)
        nvgLineTo(self.vg, 43, 112)
        nvgBezierTo(self.vg, 25, 112, 14, 100, 14, 83)
        nvgLineTo(self.vg, 14, 62)
        nvgBezierTo(self.vg, 14, 52, 29, 51, 29, 61)
        nvgClosePath(self.vg)
        nvgFillColor(self.vg, color(tint({ 241, 223, 189, 255 }, tintColor), opacity))
        nvgFill(self.vg)
        nvgStrokeColor(self.vg, color(tint({ 24, 33, 30, 255 }, tintColor), opacity))
        nvgStrokeWidth(self.vg, 7)
        nvgStroke(self.vg)
        nvgLineCap(self.vg, NVG_ROUND)
        nvgBeginPath(self.vg)
        nvgMoveTo(self.vg, 29, 56); nvgLineTo(self.vg, 29, 74)
        nvgMoveTo(self.vg, 44, 32); nvgLineTo(self.vg, 44, 63)
        nvgMoveTo(self.vg, 59, 32); nvgLineTo(self.vg, 59, 63)
        nvgMoveTo(self.vg, 74, 34); nvgLineTo(self.vg, 74, 63)
        nvgMoveTo(self.vg, 31, 77); nvgLineTo(self.vg, 74, 77)
        nvgStrokeColor(self.vg, color(tint({ 142, 96, 72, 255 }, tintColor), opacity))
        nvgStrokeWidth(self.vg, 5)
        nvgStroke(self.vg)
        nvgRestore(self.vg)
    end
end

return M
