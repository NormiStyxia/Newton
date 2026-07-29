local M = {}

function M.Install(Renderer, COLORS, color, tint)
    function Renderer:DrawBackground(frame)
        self:FillRect(0, 0, frame.logicalWidth, frame.logicalHeight, COLORS.background)
        self:FillRect(0, 0, frame.logicalWidth, 94, COLORS.panel, 250)
        self:FillRect(0, 92, frame.logicalWidth, 2, COLORS.greenLight, 230)
        self:RoundedRect(frame.workspaceX - 55, -18, 448, 112, 20, COLORS.darkPrimary)
        self:RoundedRect(frame.newtonX + 6, frame.newtonY + 6, frame.newtonWidth, frame.newtonHeight, 7, COLORS.floor, nil, nil, 20)
        self:RoundedRect(frame.playfieldX + 7, frame.playfieldY + 9, frame.playfieldWidth, frame.playfieldHeight, 7, COLORS.floor, nil, nil, 20)
        self:RoundedRect(frame.playfieldX, frame.playfieldY, frame.playfieldWidth, frame.playfieldHeight, 7, COLORS.playfield, COLORS.darkPrimary, 4)
        self:RoundedRect(frame.playfieldX + 8, frame.playfieldY + 8, frame.playfieldWidth - 16, frame.playfieldHeight - 16, 5, nil, COLORS.greenLight, 2)
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
    end

    function Renderer:DrawNewton(frame, level, anger, observation)
        local x, y, w, h = frame.newtonX, frame.newtonY, frame.newtonWidth, frame.newtonHeight
        self:RoundedRect(x, y, w, h, 7, COLORS.panel, COLORS.greenLight, 2)
        self:RoundedRect(x + 8, y + 8, w - 16, h - 16, 5, nil, COLORS.panelSecondary, 1)
        self:RoundedRect(x + 18, y + 12, w - 36, 58, 6, COLORS.dark)
        self:Text(x + 30, y + 21, "ISAAC NEWTON", 11, COLORS.warningLow)
        self:Text(x + 30, y + 41, "牛顿 · 经典定律维护者", 18, COLORS.white, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, "maker-display")
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
        self:TextBox(x + 36, y + 95, w - 66, "“" .. (observation or (level and level.observation) or "先观察抛物线，再谈万有引力。") .. "”", 13, COLORS.body)
        nvgStrokeColor(self.vg, color(COLORS.greenLight, 163)); nvgStrokeWidth(self.vg, 2)
        nvgBeginPath(self.vg); nvgMoveTo(self.vg, x + 34, y + 472); nvgLineTo(self.vg, x + w - 34, y + 472); nvgStroke(self.vg)
        self:Text(x + 24, y + h - 112, "牛顿怒气", 12, COLORS.secondary)
        self:RoundedRect(x + 24, y + h - 86, w - 48, 12, 5, COLORS.warningSoft, COLORS.warningLow, 1)
        self:RoundedRect(x + 27, y + h - 84, math.max(0, w - 54) * math.max(0, math.min(1, anger / 100)), 7, 3, COLORS.warningActive)
        self:Text(x + w - 24, y + h - 114, string.format("%d%%", math.floor(anger + 0.5)), 12, COLORS.warning, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        self:Text(x + 24, y + h - 58, "修正拳：恢复持续规则，保留运动状态", 11, COLORS.secondary)
    end

    function Renderer:DrawGround(frame)
        self:FillRect(frame.playfieldX + 17, frame.groundY + 7, frame.playfieldWidth - 34, 14, COLORS.floor)
        self:FillRect(frame.playfieldX + 17, frame.groundY + 2, frame.playfieldWidth - 34, 4, COLORS.darkSecondary)
    end

    local GOAL_SCANNER_SEGMENTS = {
        { .03, .48, "strong" }, { .72, .24, "soft" }, { 1.12, .66, "normal" }, { 2.04, .31, "strong" },
        { 2.62, .86, "normal" }, { 3.77, .39, "soft" }, { 4.43, .58, "strong" }, { 5.34, .47, "normal" },
    }

    local GOAL_INNER_SEGMENTS = {
        { .36, .28, "soft" }, { 1.78, .42, "normal" }, { 3.5, .24, "soft" }, { 4.82, .36, "normal" },
    }

    local function goalSegmentStyle(emphasis, inner)
        if emphasis == "strong" then return inner and 1.8 or 3.1, COLORS.greenLight, inner and .7 or .94 end
        if emphasis == "normal" then return inner and 1.5 or 2.4, COLORS.greenStrong, inner and .58 or .8 end
        return inner and 1.2 or 1.7, COLORS.darkSecondary, inner and .42 or .52
    end

    function Renderer:DrawGoalFallbackPortrait(x, y, radius, active, progress)
        self:Circle(x, y, radius, active and COLORS.greenSoft or COLORS.greenSoft, nil, nil, math.floor((.72 + progress * .22) * 255))
        local hair = COLORS.wall
        self:Circle(x - radius * .56, y - radius * .38, radius * .3, hair)
        self:Circle(x + radius * .56, y - radius * .38, radius * .3, hair)
        self:Circle(x - radius * .35, y - radius * .66, radius * .27, hair)
        self:Circle(x + radius * .35, y - radius * .66, radius * .27, hair)
        self:Circle(x, y - radius * .72, radius * .3, hair)
        nvgBeginPath(self.vg); nvgEllipse(self.vg, x, y, radius * 1.2, radius * 1.42); nvgFillColor(self.vg, color(COLORS.panel)); nvgFill(self.vg)
        nvgStrokeColor(self.vg, color(COLORS.darkSecondary, 199)); nvgStrokeWidth(self.vg, 1.2); nvgStroke(self.vg)
        nvgStrokeColor(self.vg, color(COLORS.dark, 214)); nvgStrokeWidth(self.vg, 1.4)
        nvgBeginPath(self.vg); nvgMoveTo(self.vg, x - radius * .34, y - radius * .18); nvgLineTo(self.vg, x - radius * .1, y - radius * .22); nvgMoveTo(self.vg, x + radius * .1, y - radius * .22); nvgLineTo(self.vg, x + radius * .34, y - radius * .18); nvgStroke(self.vg)
        self:Circle(x - radius * .22, y - radius * .08, math.max(1.1, radius * .055), COLORS.dark, nil, nil, 230)
        self:Circle(x + radius * .22, y - radius * .08, math.max(1.1, radius * .055), COLORS.dark, nil, nil, 230)
        nvgStrokeColor(self.vg, color(COLORS.darkSecondary, 184)); nvgStrokeWidth(self.vg, 1.2)
        nvgBeginPath(self.vg); nvgMoveTo(self.vg, x, y - radius * .02); nvgLineTo(self.vg, x - radius * .05, y + radius * .18); nvgStroke(self.vg)
        nvgBeginPath(self.vg); nvgEllipse(self.vg, x - radius * .13, y + radius * .25, radius * .32, radius * .15); nvgFillColor(self.vg, color(COLORS.darkSecondary, 230)); nvgFill(self.vg)
        nvgBeginPath(self.vg); nvgEllipse(self.vg, x + radius * .13, y + radius * .25, radius * .32, radius * .15); nvgFillColor(self.vg, color(COLORS.darkSecondary, 230)); nvgFill(self.vg)
    end

    function Renderer:DrawGoalSensor(x, y, w, h, state)
        local usableDiameter = math.max(48, math.min(w * .8, h))
        local outerRadius = usableDiameter * .5
        local scannerRadius, innerRadius, portraitRadius = outerRadius * .77, outerRadius * .64, outerRadius * .62
        local active = state.active == true
        local progress = state.contactProgress or 0
        self:Circle(x, y, outerRadius, COLORS.panel, COLORS.dark, 3, 117)
        self:Circle(x, y, outerRadius - 5, nil, COLORS.greenLight, 1, 163)
        nvgStrokeColor(self.vg, color(COLORS.darkSecondary, 184)); nvgStrokeWidth(self.vg, 2)
        for _, a in ipairs({ -1.18, .42, 2.42 }) do
            nvgBeginPath(self.vg); nvgMoveTo(self.vg, x + math.cos(a) * (outerRadius + 2), y + math.sin(a) * (outerRadius + 2)); nvgLineTo(self.vg, x + math.cos(a) * (outerRadius + 6), y + math.sin(a) * (outerRadius + 6)); nvgStroke(self.vg)
        end
        local outerAlpha = active and 1 or .68
        for _, segment in ipairs(GOAL_SCANNER_SEGMENTS) do
            local width, c, alpha = goalSegmentStyle(segment[3], false)
            nvgStrokeColor(self.vg, color(c, math.floor(alpha * outerAlpha * 255))); nvgStrokeWidth(self.vg, width)
            nvgBeginPath(self.vg); nvgArc(self.vg, x, y, scannerRadius, segment[1] + (state.sensorAngle or 0), segment[1] + segment[2] + (state.sensorAngle or 0), NVG_CW); nvgStroke(self.vg)
        end
        local innerAlpha = active and .76 or .48
        for _, segment in ipairs(GOAL_INNER_SEGMENTS) do
            local width, c, alpha = goalSegmentStyle(segment[3], true)
            nvgStrokeColor(self.vg, color(c, math.floor(alpha * innerAlpha * 255))); nvgStrokeWidth(self.vg, width)
            nvgBeginPath(self.vg); nvgArc(self.vg, x, y, innerRadius, segment[1] - (state.sensorAngle or 0) * .58, segment[1] + segment[2] - (state.sensorAngle or 0) * .58, NVG_CW); nvgStroke(self.vg)
        end
        self:Circle(x + scannerRadius, y, 2.2, COLORS.playfieldAccent, nil, nil, 214)
        self:Circle(x - scannerRadius * .72, y + scannerRadius * .69, 1.7, COLORS.greenLight, nil, nil, 209)
        self:DrawGoalFallbackPortrait(x, y, portraitRadius, active, progress)
        self:Circle(x, y, portraitRadius + 1, nil, COLORS.darkSecondary, 2, active and 224 or 189)
        self:Circle(x, y, portraitRadius - 3, nil, COLORS.greenLight, 1, active and 173 or 135)
        if state.goalPulseProgress ~= nil then
            local progress = math.max(0, math.min(1, state.goalPulseProgress))
            self:Circle(x, y, outerRadius * .88 * (1 + progress * .22), nil, COLORS.primaryActive, 2, math.floor(.78 * (1 - progress) * 255))
        end
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
        local rotation = object.node and math.rad(object.node.rotation2D) or math.rad(-(t.rotation or 0))
        if object.type == "wall" then
            local fill = object.phaseable and COLORS.glass or COLORS.wall
            local edge = object.phaseable and COLORS.glassEdge or COLORS.wallEdge
            nvgSave(self.vg)
            nvgTranslate(self.vg, x, y)
            nvgRotate(self.vg, rotation)
            self:FillRect(-w * .5, -h * .5, w, h, fill, object.phaseable and 173 or 255)
            self:StrokeRect(-w * .5, -h * .5, w, h, edge, 3, 240)
            self:FillRect(-w * .28 - 2, -math.max(12, h - 16) * .5, 4, math.max(12, h - 16), object.phaseable and COLORS.glass or COLORS.panel, 97)
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
            self:DrawGoalSensor(x, y, w, h, { active = object.active, contactProgress = object.contactProgress, sensorAngle = state.sensorAngle, goalPulseProgress = state.goalPulseProgress })
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
        local angle = apple.node.rotation2D and math.rad(apple.node.rotation2D) or 0
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
