-- render/WorldView: private runtime functions installed into the App context.
local M = {}

function M.Install(context)
    local _ENV = context
    function DrawPrediction(direction, alpha, x, y, velocityX, velocityY)
        if not apple_ or not level_ then return end
        if x == nil or y == nil then x, y = AppleScreenPosition() end
        if velocityX == nil or velocityY == nil then
            local velocity = apple_.body.linearVelocity
            local conversion = CurrentMatterVelocityToWorld()
            velocityX = velocity.x / conversion
            velocityY = -velocity.y / conversion
        end
        local gravity = Rules.GetGravity(rules_, level_.rules.initialGravity)
        local gravityX, gravityY = gravity.x * gravity.strength, gravity.y * gravity.strength
        if direction then
            gravityX, gravityY = 0, 0
            if direction == "LEFT" then gravityX = -gravity.strength
            elseif direction == "RIGHT" then gravityX = gravity.strength
            elseif direction == "UP" then gravityY = -gravity.strength
            else gravityY = gravity.strength end
        end
        local points = TrajectoryPrediction.PredictFreeFlight({
            x = x,
            y = y,
            velocityX = velocityX,
            velocityY = velocityY,
            gravityX = gravityX,
            gravityY = gravityY,
            frictionAir = apple_.baseFrictionAir or MatterCalibration.APPLE_FRICTION_AIR,
            forceScale = 0.001,
            maxSpeed = 25,
            steps = 30,
            sampleEvery = 3,
        })
        for _, point in ipairs(points) do
            if point.x < frame_.playfieldX or point.x > frame_.playfieldX + frame_.playfieldWidth
                or point.y < frame_.playfieldY or point.y > frame_.playfieldY + frame_.playfieldHeight then break end
            local pointAlpha = math.max(0.18, math.min(alpha, alpha - point.frame / 75))
            painter_:Circle(point.x, point.y, point.frame % 6 == 0 and 3.5 or 2, Renderer2D.COLORS.primary, nil, nil, math.floor(pointAlpha * 255))
        end
    end
    function DrawAim()
        if not draggedApple_ or not aimPreview_ then return end
        -- Phaser updates the dotted prediction and launcher tether together from
        -- the same aim state. Keeping the call here prevents the visual pair from
        -- diverging when the input path changes.
        DrawAimPrediction(aimPreview_)
        local x, y = aimPreview_.x, aimPreview_.y
        local lx, ly = aimPreview_.launcherX, aimPreview_.launcherY
        nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 224)); nvgStrokeWidth(painter_.vg, 6)
        nvgBeginPath(painter_.vg)
        nvgMoveTo(painter_.vg, lx - 18, ly + 4)
        nvgLineTo(painter_.vg, x, y)
        nvgLineTo(painter_.vg, lx + 18, ly + 4)
        nvgStroke(painter_.vg)
    end

    -- Phaser keeps the dotted trajectory on depth 14 and the launcher tether on
    -- depth 15. Keep them separate so the tether remains visible above its
    -- prediction and parameter cards reuse DrawPrediction without a second solver.
    function DrawAimPrediction(preview)
        preview = preview or aimPreview_
        if not preview then return end
        local x, y = preview.x, preview.y
        local lx, ly = preview.launcherX, preview.launcherY
        DrawPrediction(nil, 0.55, x, y, -(x - lx) * .165, -(y - ly) * .165)
    end
    function DrawCardPrediction()
        if not activeCardId_ or not cardParameterStart_ or not cardCandidate_ then return end
        local x, y = AppleScreenPosition()
        if activeCardId_ == "side-gravity" then
            DrawPrediction(cardCandidate_, 0.88, x, y)
        elseif activeCardId_ == "mirror-motion" then
            local velocity = apple_.body.linearVelocity
            local conversion = CurrentMatterVelocityToWorld()
            local vx = velocity.x / conversion
            local vy = -velocity.y / conversion
            if cardCandidate_ == "HORIZONTAL" then vx = -vx else vy = -vy end
            DrawPrediction(nil, 0.88, x, y, vx, vy)
        end
    end
    function DrawLaunchHint()
        if launched_ or draggedApple_ or absorbing_ or success_ or failed_ or not apple_ then return end
        local launcher = apple_.launcher
        local launcherWorldX, launcherWorldY = mapper_:LevelToWorld(launcher.spawnLevelX, launcher.spawnLevelY)
        local lx, ly = design_:WorldToLogical(launcherWorldX, launcherWorldY)
        local hintX, hintY = lx + 76, ly - 60
        painter_:RoundedRect(hintX - 78, hintY - 18, 156, 36, 0, Renderer2D.COLORS.panel, nil, nil, 232)
        painter_:Text(hintX, hintY - 7, "拖动苹果，松开发射", 14, Renderer2D.COLORS.secondary, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local pulse = (math.sin(uiElapsed_ * math.pi * 2 / .9) + 1) * .5
        painter_:Circle(lx + 20 - pulse * 60, ly + 16 + pulse * 18, 5, Renderer2D.COLORS.primaryActive, nil, nil, math.floor(208 - pulse * 170))
    end
    function DrawTrail()
        for i, point in ipairs(trail_) do
            local progress = i / #trail_
            painter_:Circle(point.x, point.y, 1.5 + progress * 3, Renderer2D.COLORS.primary, nil, nil, math.floor(progress * .32 * 255))
        end
    end
    function DrawVelocityArrow()
        if not apple_ then return end
        local x, y = AppleScreenPosition()
        local velocity = apple_.body.linearVelocity
        local conversion = CurrentMatterVelocityToWorld()
        local vx = velocity.x / conversion
        local vy = -velocity.y / conversion
        local length = math.min(58, math.sqrt(vx * vx + vy * vy) * 3.4)
        if length < 8 then return end
        local angle = math.atan(vy, vx)
        local endX, endY = x + math.cos(angle) * length, y + math.sin(angle) * length
        nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 184)); nvgStrokeWidth(painter_.vg, 3)
        nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, x, y); nvgLineTo(painter_.vg, endX, endY); nvgStroke(painter_.vg)
        nvgFillColor(painter_.vg, nvgRGBA(95, 143, 104, 204)); nvgBeginPath(painter_.vg)
        nvgMoveTo(painter_.vg, endX, endY)
        nvgLineTo(painter_.vg, endX - math.cos(angle - .55) * 10, endY - math.sin(angle - .55) * 10)
        nvgLineTo(painter_.vg, endX - math.cos(angle + .55) * 10, endY - math.sin(angle + .55) * 10)
        nvgClosePath(painter_.vg); nvgFill(painter_.vg)
    end
    function DrawRulePulse()
        if not rulePulse_ then return end
        local progress = math.max(0, math.min(1, rulePulse_.elapsed / rulePulse_.duration))
        painter_:FillRect(
            frame_.playfieldX,
            frame_.playfieldY,
            frame_.playfieldWidth,
            frame_.playfieldHeight,
            rulePulse_.color,
            math.floor((1 - progress) * .13 * 255)
        )
    end
    function DrawRuleFlash()
        if not ruleFlash_ or not apple_ then return end
        local progress = math.max(0, math.min(1, ruleFlash_.elapsed / ruleFlash_.duration))
        local x, y = AppleScreenPosition()
        local scale = 1 + progress * .2
        nvgSave(painter_.vg)
        nvgTranslate(painter_.vg, x, y - 18 - progress * 72)
        nvgScale(painter_.vg, .78 * scale, .78 * scale)
        painter_:DrawCardSymbol(ruleFlash_.cardId, 0, 0, ruleFlash_.color, math.floor((1 - progress) * 255))
        nvgRestore(painter_.vg)
    end
end

return M
