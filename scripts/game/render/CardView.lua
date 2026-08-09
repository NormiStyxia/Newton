-- render/CardView: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local CARD_TEXT_SCALE = context.CARD_TEXT_SCALE
    local CARD_RENDER_WIDTH = context.CARD_RENDER_WIDTH
    local CARD_RENDER_HEIGHT = context.CARD_RENDER_HEIGHT
    local _ENV = context
    local singleLineSizeCache = {}
    local textBoxSizeCache = {}

    local function RemainingUses(remaining)
        return math.max(0, math.floor(tonumber(remaining) or 0))
    end

    function CardUseLabel(usage, remaining)
        return usage == "REUSABLE" and "可重复" or (tostring(RemainingUses(remaining)) .. "次")
    end

    function CardBadgeText(usage, remaining)
        return usage == "REUSABLE" and "∞" or ("×" .. tostring(RemainingUses(remaining)))
    end

    local function FitSingleLine(value, font, preferredSize, minimumSize, maximumWidth)
        local key = table.concat({ font, value, preferredSize, minimumSize, maximumWidth }, "|")
        if singleLineSizeCache[key] then return singleLineSizeCache[key] end
        painter_:UseFont(font)
        nvgFontSize(painter_.vg, preferredSize)
        local width = nvgTextBounds(painter_.vg, 0, 0, value) or 0
        local size = preferredSize
        if width > maximumWidth and width > 0 then
            size = math.max(minimumSize, preferredSize * maximumWidth / width)
        end
        singleLineSizeCache[key] = size
        return size
    end

    local function FitTextBox(value, font, preferredSize, minimumSize, width, maximumHeight, lineHeight)
        local key = table.concat({ font, value, preferredSize, minimumSize, width, maximumHeight, lineHeight }, "|")
        if textBoxSizeCache[key] then return textBoxSizeCache[key] end
        painter_:UseFont(font)
        nvgTextAlign(painter_.vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgTextLineHeight(painter_.vg, lineHeight)
        local size = preferredSize
        while size > minimumSize do
            nvgFontSize(painter_.vg, size)
            local bounds = nvgTextBoxBounds(painter_.vg, 0, 0, width, value)
            local height = bounds and bounds[4] and bounds[2] and (bounds[4] - bounds[2]) or size
            if height <= maximumHeight then
                textBoxSizeCache[key] = size
                return size
            end
            size = math.max(minimumSize, size - .5)
        end
        textBoxSizeCache[key] = size
        return size
    end

    function DrawCardBadge(value, alpha)
        local opacity = math.floor((alpha or 1) * 255)
        local size = FitSingleLine(value, "report-green", 12, 8, CARD_RENDER_WIDTH * .2)
        local left = -CARD_RENDER_WIDTH * .5
        local top = -CARD_RENDER_HEIGHT * .5
        painter_:Text(left + CARD_RENDER_WIDTH * .852, top + CARD_RENDER_HEIGHT * .092,
            value, size, Renderer2D.COLORS.white,
            NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, "report-green", opacity)
    end

    function DrawCardSurface(id, def, card, cardState, active, hovered, alpha)
        local field = def.kind == "field"
        local usage = cardState and cardState.usageMode or card.usageMode
        local remaining = cardState and cardState.remainingUses or card.count
        local fill = id == "quantum-phase" and (hovered and Renderer2D.COLORS.quantumCardSurfaceHover or Renderer2D.COLORS.quantumSoft)
            or (field and (hovered and Renderer2D.COLORS.fieldCardSurfaceHover or Renderer2D.COLORS.fieldCardSurface)
                or (hovered and Renderer2D.COLORS.decisionCardSurfaceHover or Renderer2D.COLORS.decisionCardSurface))
        local edge = id == "quantum-phase" and Renderer2D.COLORS.quantum or (field and Renderer2D.COLORS.fieldCardBorder or Renderer2D.COLORS.decisionCardBorder)
        local accent = def.accent or (id == "quantum-phase" and Renderer2D.COLORS.quantum or (field and Renderer2D.COLORS.primary or Renderer2D.COLORS.instant))
        local titleColor = field and Renderer2D.COLORS.text or Renderer2D.COLORS.decisionCardText
        local bodyColor = field and Renderer2D.COLORS.body or Renderer2D.COLORS.decisionCardBody
        local scale = CARD_TEXT_SCALE
        local opacity = alpha or 1
        local opaque = math.floor(opacity * 255)
        local function alphaValue(value)
            return math.floor((value or 255) * opacity)
        end
        local illustratedSkin = painter_.images.ui.cardFaces and painter_.images.ui.cardFaces[id]
        local hasIllustratedSkin = illustratedSkin and illustratedSkin >= 0
        local cardSkin = hasIllustratedSkin and illustratedSkin
            or (id == "quantum-phase" and painter_.images.ui.cardQuantum
                or (field and painter_.images.ui.cardField or painter_.images.ui.cardDecision))
        local left = -CARD_RENDER_WIDTH * .5
        local top = -CARD_RENDER_HEIGHT * .5
        if not cardSkin or cardSkin < 0 then
            painter_:RoundedRect(left, top, CARD_RENDER_WIDTH, CARD_RENDER_HEIGHT, 7 * scale,
                fill, edge, 2 * scale, opaque)
        else
            painter_:Image(cardSkin, 0, 0, CARD_RENDER_WIDTH, CARD_RENDER_HEIGHT,
                (hovered and 1 or .98) * opacity)
        end
        if active or hovered or not cardSkin or cardSkin < 0 then
            local borderAlpha = active and 255 or (hovered and 190 or 90)
            painter_:RoundedRect(left + 2, top + 2, CARD_RENDER_WIDTH - 4, CARD_RENDER_HEIGHT - 4,
                7 * scale, nil, active and Renderer2D.COLORS.primaryActive or edge,
                (active and 3 or 2) * scale, alphaValue(borderAlpha))
        end

        local titleSize = FitSingleLine(def.name, "maker-display", 16, 11, CARD_RENDER_WIDTH * .52)
        painter_:Text(0, top + CARD_RENDER_HEIGHT * .065, def.name, titleSize, titleColor,
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display", opaque)

        local useText = (field and "场地 · " or "决策 · ") .. CardUseLabel(usage, remaining)
        local useSize = FitSingleLine(useText, "maker-body", 8.5, 7, CARD_RENDER_WIDTH * .62)
        painter_:Text(0, top + CARD_RENDER_HEIGHT * .14, useText, useSize, accent,
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", opaque)

        if not hasIllustratedSkin then
            nvgSave(painter_.vg)
            nvgScale(painter_.vg, CARD_TEXT_SCALE, CARD_TEXT_SCALE)
            painter_:DrawCardSymbol(id, 0, 7, titleColor, opaque)
            nvgRestore(painter_.vg)
        end

        local descriptionWidth = CARD_RENDER_WIDTH * .78
        local descriptionHeight = CARD_RENDER_HEIGHT * .10
        local descriptionSize = FitTextBox(def.description, "maker-body", 9.5, 7.5,
            descriptionWidth, descriptionHeight, 1.15)
        painter_:TextBox(-descriptionWidth * .5, top + CARD_RENDER_HEIGHT * .873,
            descriptionWidth, def.description, descriptionSize, bodyColor,
            NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-body", 1.15, opaque)
        DrawCardBadge(CardBadgeText(usage, remaining), opacity)
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
                local faceActive = primed or (active and activeCardDeploying_)
                local cardAlpha = (success_ or failed_) and .48 or 1
                DrawCardSurface(card.cardId, Rules.CARDS[card.cardId], card, cardState,
                    faceActive, hovered, cardAlpha)
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
        local punchSkin = painter_.images.ui and painter_.images.ui.punchMedallion
        if punchSkin and punchSkin >= 0 then
            painter_:Image(punchSkin, cx, cy, 80, 80, punchAlpha / 255)
            if punchHovered_ and punchReady then
                painter_:Circle(cx, cy, 31, Renderer2D.COLORS.warningSoft, nil, nil, 82)
            end
        else
            painter_:Circle(cx + 2, cy + 3, 40, Renderer2D.COLORS.darkPrimary, nil, nil, math.floor(punchAlpha * .12))
            painter_:Circle(cx, cy, 35, punchReady and punchHovered_ and Renderer2D.COLORS.warningSoft or Renderer2D.COLORS.playfield, nil, nil, punchAlpha)
            painter_:Circle(cx, cy, 37.5, nil, Renderer2D.COLORS.warningLow, 5, math.floor(punchAlpha * .42))
        end
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
        painter_:Text(cx, cy + 42, punchStatus, 14, punchColor, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display", punchAlpha)
    end

    -- Draw the selected hand instance at a larger scale in the reserved strip
    -- just inside the laboratory edge. The same surface renderer supplies the
    -- artwork, definition text and live usage badge as the hand card.
    function DrawSelectedCardDetail()
        if not selectedCardId_ or screen_ ~= "game" or isPaused_ or replayActive_ or success_ or failed_
            or context.assistantInputLocked_ or assistSceneActive_
            or (dialogueController_ and dialogueController_:IsActive())
            or (IsResultOverlayVisible and IsResultOverlayVisible())
            or (IsResultReportVisible and IsResultReportVisible()) then
            return
        end
        local card, cardState, def = SelectedCardData()
        if not card or not cardState or not def then return end

        local detailScale = 1.70
        local width = CARD_RENDER_WIDTH * detailScale
        local height = CARD_RENDER_HEIGHT * detailScale
        local top = frame_.playfieldY + 8
        local bottomLimit = (frame_.groundY or (frame_.playfieldY + frame_.playfieldHeight)) - 18
        top = math.min(top, bottomLimit - height)
        top = math.max(frame_.playfieldY + 10, top)
        local x = frame_.playfieldX + width * .5 + 14
        local y = top + height * .5

        local progress = math.max(0, math.min(1, (selectedCardDetailAge_ or 0) / .14))
        local eased = 1 - (1 - progress) ^ 3
        local alpha = .70 + .30 * eased
        local animatedScale = detailScale * (.96 + .04 * eased)
        local animatedX = x - 12 * (1 - eased)

        nvgSave(painter_.vg)
        nvgTranslate(painter_.vg, animatedX, y)
        nvgScale(painter_.vg, animatedScale, animatedScale)
        DrawCardSurface(card.cardId, def, card, cardState, true, false, alpha)
        nvgRestore(painter_.vg)
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
                        DrawCardSurface(burn.id, def, card, cardState, true, false)
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
