-- render/CardView: private runtime functions installed into the App context.
local M = {}

function M.Install(context)
    local _ENV = context
    function CardUseLabel(usage, remaining)
        return usage == "REUSABLE" and "可重复" or (tostring(remaining) .. " 次")
    end
    function CardBadgeText(id, usage, remaining)
        if burningCardIds_[id] then return "燃烧" end
        if activeCardId_ == id then
            if cardHandReordering_ then return "排序" end
            if activeCardDeploying_ then
                local needsParameter = id == "side-gravity" or id == "mirror-motion"
                if not needsParameter then
                    return activeCardPointer_ and PointerInPlayfield(activeCardPointer_.x, activeCardPointer_.y) and "可部署" or "移入场地"
                end
                if cardParameterStart_ then
                    if cardGestureDistance_ >= 48 then return "松手确认" end
                    return cardCandidate_ and "继续滑动" or "滑动选方向"
                end
                if activeCardPointer_ and PointerInPlayfield(activeCardPointer_.x, activeCardPointer_.y) then return "停稳后选方向" end
                return cardDeployEnteredMs_ and "移回场地" or "移入场地"
            end
        end
        if primedCardId_ == id then return "0.05" end
        return usage == "REUSABLE" and "∞" or tostring(remaining)
    end
    function DrawCardBadge(value, edge)
        local size = 10 * CARD_TEXT_SCALE
        local horizontalPadding = 5 * CARD_TEXT_SCALE
        nvgFontFace(painter_.vg, "maker-body")
        nvgFontSize(painter_.vg, size)
        local width = math.max(25, nvgTextBounds(painter_.vg, 0, 0, value) + horizontalPadding * 2)
        local right = 51 * CARD_TEXT_SCALE
        painter_:RoundedRect(right - width, -94, width, 20, 4, edge)
        painter_:Text(right - width * .5, -91, value, size, Renderer2D.COLORS.white, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
    function DrawCardSurface(id, def, card, cardState, badgeText, active, hovered)
        local field = def.kind == "field"
        local usage = cardState and cardState.usageMode or card.usageMode
        local remaining = cardState and cardState.remainingUses or card.count
        local fill = id == "quantum-phase" and (hovered and Renderer2D.COLORS.quantumCardSurfaceHover or Renderer2D.COLORS.quantumSoft)
            or (field and (hovered and Renderer2D.COLORS.fieldCardSurfaceHover or Renderer2D.COLORS.fieldCardSurface)
                or (hovered and Renderer2D.COLORS.decisionCardSurfaceHover or Renderer2D.COLORS.decisionCardSurface))
        local edge = id == "quantum-phase" and Renderer2D.COLORS.quantum or (field and Renderer2D.COLORS.fieldCardBorder or Renderer2D.COLORS.decisionCardBorder)
        local titleColor = field and Renderer2D.COLORS.text or Renderer2D.COLORS.decisionCardText
        local bodyColor = field and Renderer2D.COLORS.body or Renderer2D.COLORS.decisionCardBody
        local scale = CARD_TEXT_SCALE
        painter_:RoundedRect(-60 * scale, -83 * scale, CARD_DESIGN_WIDTH * scale, CARD_DESIGN_HEIGHT * scale, 7 * scale, Renderer2D.COLORS.dark, nil, nil, hovered and 41 or 26)
        painter_:RoundedRect(-62 * scale, -87 * scale, CARD_DESIGN_WIDTH * scale, CARD_DESIGN_HEIGHT * scale, 7 * scale, edge)
        painter_:RoundedRect(-57 * scale, -82 * scale, 114 * scale, 164 * scale, 5 * scale, fill)
        painter_:RoundedRect(-57 * scale, -82 * scale, 114 * scale, 21 * scale, 5 * scale, edge, nil, nil, 36)
        painter_:RoundedRect(-49 * scale, -32 * scale, 98 * scale, 76 * scale, 4 * scale, Renderer2D.COLORS.panel, edge, 1 * scale, 107)
        painter_:StrokeRect(-49 * scale, 51 * scale, 98 * scale, 0, edge, 1 * scale, 133)
        painter_:RoundedRect(-62 * scale, -87 * scale, CARD_DESIGN_WIDTH * scale, CARD_DESIGN_HEIGHT * scale, 7 * scale, nil, active and Renderer2D.COLORS.primaryActive or edge, (active and 3 or 2) * scale)
        painter_:Text(-58, -85, (field and "场地 · " or "决策 · ") .. CardUseLabel(usage, remaining), 9 * CARD_TEXT_SCALE, edge)
        painter_:Text(0, -58, def.name, 16 * CARD_TEXT_SCALE, titleColor, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
        nvgSave(painter_.vg)
        nvgScale(painter_.vg, CARD_TEXT_SCALE, CARD_TEXT_SCALE)
        painter_:DrawCardSymbol(id, 0, 7, titleColor)
        nvgRestore(painter_.vg)
        -- Phaser uses a 10 px description with 2 px lineSpacing before the card
        -- container scale is applied. Its final NanoVG line-height is 1.2.
        painter_:TextBox(-51 * scale, 59 * scale, 102 * scale, def.description, 10 * scale, bodyColor, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", 1.2)
        DrawCardBadge(badgeText or CardBadgeText(id, usage, remaining), edge)
    end

    -- Cards and the direction selector occupy distinct Phaser depth bands. Keep
    -- the selector above the ordinary hand, but below a hovered or active card.
    function DrawCards(minimumDepth, maximumDepth, includePunch)
        local entries = CardEntries()
        local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
        local drawEntries = {}
        for i, card in ipairs(entries) do
            if not burningCardIds_[card.cardId] then
                local pose = CardVisualPose(card.cardId, poses[i])
                if pose and (minimumDepth == nil or pose.depth >= minimumDepth)
                    and (maximumDepth == nil or pose.depth <= maximumDepth) then
                    drawEntries[#drawEntries + 1] = {
                        card = card,
                        pose = pose,
                        index = i,
                        depth = pose.depth,
                    }
                end
            end
        end
        table.sort(drawEntries, function(a, b)
            if a.depth == b.depth then return a.index < b.index end
            return a.depth < b.depth
        end)
        for _, entry in ipairs(drawEntries) do
                local card, pose = entry.card, entry.pose
                local active = activeCardId_ == card.cardId
                local primed = primedCardId_ == card.cardId
                local hovered = hoveredCardId_ == card.cardId and not active and not primed
                nvgSave(painter_.vg); nvgTranslate(painter_.vg, pose.x, pose.y); nvgRotate(painter_.vg, math.rad(pose.angle)); nvgScale(painter_.vg, pose.scale or 1, pose.scale or 1)
                local cardState = cardStates_[card.cardId]
                local usage = cardState and cardState.usageMode or card.usageMode
                local remaining = cardState and cardState.remainingUses or card.count
                local faceActive = primed or (active and activeCardDeploying_)
                DrawCardSurface(card.cardId, Rules.CARDS[card.cardId], card, cardState, CardBadgeText(card.cardId, usage, remaining), faceActive, hovered)
                nvgRestore(painter_.vg)
        end
        if not includePunch then return end
        local cx = frame_.playfieldX + frame_.playfieldWidth - 58
        local cy = frame_.cardHandY + 23
        -- Phaser-equivalent ability face with the original fist.svg path rendered
        -- directly by NanoVG rather than a fallback glyph or geometry substitute.
        painter_:Circle(cx, cy, 42, Renderer2D.COLORS.background)
        local punchReady = Rules.CanPunch(rules_) and not success_ and not failed_ and not replayActive_
        local punchAlpha = punchReady and 255 or math.floor(255 * .62)
        local punchColor = punchReady and Renderer2D.COLORS.warningActive or Renderer2D.COLORS.warning
        painter_:Circle(cx + 2, cy + 3, 40, Renderer2D.COLORS.darkPrimary, nil, nil, math.floor(punchAlpha * .12))
        painter_:Circle(cx, cy, 35, punchReady and punchHovered_ and Renderer2D.COLORS.warningSoft or Renderer2D.COLORS.playfield, nil, nil, punchAlpha)
        painter_:Circle(cx, cy, 37.5, nil, Renderer2D.COLORS.warningLow, 5, math.floor(punchAlpha * .42))
        if anger_ > 0 then
            local progress = math.max(0, math.min(1, anger_ / 100))
            nvgStrokeColor(painter_.vg, nvgRGBA(Renderer2D.COLORS.warningActive[1], Renderer2D.COLORS.warningActive[2], Renderer2D.COLORS.warningActive[3], math.floor(punchAlpha * (punchReady and 1 or .72))))
            nvgStrokeWidth(painter_.vg, 5)
            nvgBeginPath(painter_.vg)
            nvgArc(painter_.vg, cx, cy, 37.5, -math.pi * .5, -math.pi * .5 + math.pi * 2 * progress, NVG_CW)
            nvgStroke(painter_.vg)
        end
        painter_:Circle(cx, cy, 32, nil, punchReady and Renderer2D.COLORS.warningActive or Renderer2D.COLORS.warningLow, punchReady and 2 or 1, punchAlpha)
        painter_:DrawFist(cx, cy - 5, 46, punchColor, punchAlpha)
        local punchStatus = punchReady and "可修正" or (rules_.punchUsed and "已使用" or "未就绪")
        painter_:Text(cx, cy + 42, punchStatus, 10, punchColor, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display", punchAlpha)
    end
    function DrawSelectorArrow(x, y, direction, active, alpha)
        local function fillArrow(drawX, drawY, color, opacity, shaftWidth, headHalf, extent)
            nvgFillColor(painter_.vg, nvgRGBA(color[1], color[2], color[3], math.floor(opacity * 255)))
            local shaftLength = extent + 2
            if direction == "RIGHT" then
                nvgBeginPath(painter_.vg); nvgRect(painter_.vg, drawX - extent, drawY - shaftWidth * .5, shaftLength, shaftWidth); nvgFill(painter_.vg)
                nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, drawX + 2, drawY - headHalf); nvgLineTo(painter_.vg, drawX + extent, drawY); nvgLineTo(painter_.vg, drawX + 2, drawY + headHalf); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
            elseif direction == "LEFT" then
                nvgBeginPath(painter_.vg); nvgRect(painter_.vg, drawX - 2, drawY - shaftWidth * .5, shaftLength, shaftWidth); nvgFill(painter_.vg)
                nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, drawX - 2, drawY - headHalf); nvgLineTo(painter_.vg, drawX - extent, drawY); nvgLineTo(painter_.vg, drawX - 2, drawY + headHalf); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
            elseif direction == "UP" then
                nvgBeginPath(painter_.vg); nvgRect(painter_.vg, drawX - shaftWidth * .5, drawY - 2, shaftWidth, shaftLength); nvgFill(painter_.vg)
                nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, drawX - headHalf, drawY - 2); nvgLineTo(painter_.vg, drawX, drawY - extent); nvgLineTo(painter_.vg, drawX + headHalf, drawY - 2); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
            else
                nvgBeginPath(painter_.vg); nvgRect(painter_.vg, drawX - shaftWidth * .5, drawY - extent, shaftWidth, shaftLength); nvgFill(painter_.vg)
                nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, drawX - headHalf, drawY + 2); nvgLineTo(painter_.vg, drawX, drawY + extent); nvgLineTo(painter_.vg, drawX + headHalf, drawY + 2); nvgClosePath(painter_.vg); nvgFill(painter_.vg)
            end
        end
        if active then fillArrow(x + 2, y + 2, Renderer2D.COLORS.darkPrimary, .38, 10, 13, 22) end
        fillArrow(x, y, active and Renderer2D.COLORS.greenLight or Renderer2D.COLORS.darkSecondary, alpha, active and 10 or 9, active and 13 or 12, active and 22 or 20)
    end
    function DrawCardParameterSelector()
        if not activeCardId_ or not cardParameterStart_ or not activeCardPointer_ then return end
        local anchor, pointer = cardParameterStart_, activeCardPointer_
        nvgStrokeColor(painter_.vg, nvgRGBA(95, 143, 104, 61)); nvgStrokeWidth(painter_.vg, 2)
        nvgBeginPath(painter_.vg); nvgMoveTo(painter_.vg, anchor.x, anchor.y); nvgLineTo(painter_.vg, pointer.x, pointer.y); nvgStroke(painter_.vg)
        painter_:Circle(anchor.x, anchor.y, 3.5, Renderer2D.COLORS.greenStrong, nil, nil, 184)
        local function clamp(value, minimum, maximum)
            return math.max(minimum, math.min(maximum, value))
        end
        local function position(offsetX, offsetY)
            return clamp(anchor.x + offsetX, 30, frame_.logicalWidth - 30), clamp(anchor.y + offsetY, 30, frame_.logicalHeight - 30)
        end
        if activeCardId_ == "side-gravity" then
            local hasCandidate = cardCandidate_ ~= nil
            local upX, upY = position(0, -116)
            local leftX, leftY = position(-98, 0)
            local rightX, rightY = position(98, 0)
            local downX, downY = position(0, 116)
            DrawSelectorArrow(upX, upY, "UP", cardCandidate_ == "UP", cardCandidate_ == "UP" and 1 or (hasCandidate and .58 or .86))
            DrawSelectorArrow(leftX, leftY, "LEFT", cardCandidate_ == "LEFT", cardCandidate_ == "LEFT" and 1 or (hasCandidate and .58 or .86))
            DrawSelectorArrow(rightX, rightY, "RIGHT", cardCandidate_ == "RIGHT", cardCandidate_ == "RIGHT" and 1 or (hasCandidate and .58 or .86))
            DrawSelectorArrow(downX, downY, "DOWN", cardCandidate_ == "DOWN", cardCandidate_ == "DOWN" and 1 or (hasCandidate and .58 or .86))
        else
            local horizontal = cardCandidate_ == "HORIZONTAL"
            local vertical = cardCandidate_ == "VERTICAL"
            local hasCandidate = horizontal or vertical
            local horizontalX, horizontalY = position(-98, 0)
            local verticalX, verticalY = position(98, 0)
            DrawSelectorArrow(horizontalX, horizontalY, "LEFT", horizontal, horizontal and 1 or (hasCandidate and .58 or .86))
            DrawSelectorArrow(horizontalX, horizontalY, "RIGHT", horizontal, horizontal and 1 or (hasCandidate and .58 or .86))
            DrawSelectorArrow(verticalX, verticalY, "UP", vertical, vertical and 1 or (hasCandidate and .58 or .86))
            DrawSelectorArrow(verticalX, verticalY, "DOWN", vertical, vertical and 1 or (hasCandidate and .58 or .86))
        end
    end
    function DrawCardBurns()
        for _, burn in ipairs(cardBurns_) do
            local progress = BurnProgress(burn)
            local def = Rules.CARDS[burn.id]
            local card = cardDeckById_[burn.id]
            local cardState = cardStates_[burn.id]
            local top = burn.y - 101 + progress * 202
            local visibleHeight = math.max(0, 202 * (1 - progress))
            local edgePoints = {}
            for i = 0, 12 do
                local x = burn.x - 68 + i * (136 / 12)
                local y = top + math.sin(i * 1.73) * 3.6 + math.sin(i * .67 + .8) * 2.2
                edgePoints[i + 1] = { x = x, y = math.min(burn.y + 101, y) }
            end
            if visibleHeight > 1 and def and card then
                local shakeProgress = math.max(0, math.min(1, burn.elapsed / 70))
                local shakeEase = 1 - (1 - shakeProgress) ^ 3
                local targetAngle = BurnNoise(#burn.id, 8) * 1.6 - .8
                local angle = (burn.startAngle or 0) + (targetAngle - (burn.startAngle or 0)) * shakeEase
                local scale = (burn.startScale or 1.05) + (1.02 - (burn.startScale or 1.05)) * shakeEase
                local clipPoints = { { x = burn.x - 72, y = edgePoints[1].y } }
                for _, point in ipairs(edgePoints) do clipPoints[#clipPoints + 1] = point end
                clipPoints[#clipPoints + 1] = { x = burn.x + 72, y = edgePoints[#edgePoints].y }

                -- NanoVG only clips rectangular regions. Consecutive strips along
                -- the source's 13-point edge reproduce the GeometryMask silhouette
                -- instead of retaining the previous rectangular burn cutoff.
                for index = 1, #clipPoints - 1 do
                    local left, right = clipPoints[index], clipPoints[index + 1]
                    local width = math.max(1, right.x - left.x + 1)
                    local height = math.max(0, burn.y + 101 - left.y)
                    if height > 0 then
                        nvgSave(painter_.vg)
                        nvgScissor(painter_.vg, left.x, left.y, width, height)
                        nvgTranslate(painter_.vg, burn.x, burn.y)
                        nvgRotate(painter_.vg, math.rad(angle))
                        nvgScale(painter_.vg, scale, scale)
                        DrawCardSurface(burn.id, def, card, cardState, "燃烧", true, false)
                        nvgRestore(painter_.vg)
                    end
                end
            end
            if progress > .04 then
                local function drawBurnEdge(color, width, alpha, offset)
                    nvgStrokeColor(painter_.vg, nvgRGBA(color[1], color[2], color[3], math.floor(alpha * 255)))
                    nvgStrokeWidth(painter_.vg, width)
                    nvgBeginPath(painter_.vg)
                    for index, point in ipairs(edgePoints) do
                        if index == 1 then nvgMoveTo(painter_.vg, point.x, point.y + offset) else nvgLineTo(painter_.vg, point.x, point.y + offset) end
                    end
                    nvgStroke(painter_.vg)
                end
                drawBurnEdge(Renderer2D.COLORS.ash, 4, .46, 2)
                drawBurnEdge(Renderer2D.COLORS.burnEdge, 5, .38, 0)
                drawBurnEdge(Renderer2D.COLORS.burnCore, 2, .96, -1)
                nvgFillColor(painter_.vg, nvgRGBA(Renderer2D.COLORS.burnCore[1], Renderer2D.COLORS.burnCore[2], Renderer2D.COLORS.burnCore[3], math.floor(.54 * 255)))
                for index = 3, #edgePoints - 1, 3 do
                    local point = edgePoints[index]
                    local flameHeight = 4 + ((index - 1) * 3) % 5
                    nvgBeginPath(painter_.vg)
                    nvgMoveTo(painter_.vg, point.x - 3, point.y)
                    nvgLineTo(painter_.vg, point.x, point.y - flameHeight)
                    nvgLineTo(painter_.vg, point.x + 3, point.y)
                    nvgClosePath(painter_.vg)
                    nvgFill(painter_.vg)
                end
            end
        end
    end
    function DrawCardBurnParticles()
        for _, particle in ipairs(cardBurnParticles_) do
            local elapsed = particle.elapsed - particle.delay
            if elapsed >= 0 then
                local progress = math.max(0, math.min(1, elapsed / particle.duration))
                local eased = 1 - (1 - progress) ^ 3
                local radius = particle.radius * (1 + (particle.scaleTarget - 1) * eased)
                painter_:Circle(
                    particle.x + particle.dx * eased,
                    particle.y + particle.dy * eased,
                    radius,
                    particle.color,
                    nil,
                    nil,
                    math.floor(particle.alpha * 255 * (1 - progress))
                )
            end
        end
    end
end

return M
