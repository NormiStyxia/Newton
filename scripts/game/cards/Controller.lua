-- cards/Controller: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local Rules = context.Rules
    local CARD_RENDER_WIDTH = context.CARD_RENDER_WIDTH
    local CARD_RENDER_HEIGHT = context.CARD_RENDER_HEIGHT
    local _ENV = context
    function InitializeCards()
        cardStates_ = {}
        cardDeckById_ = {}
        handOrder_ = {}
        hoveredCardId_ = nil
        cardHoverStates_ = {}
        cardHomeMotions_ = {}
        cardHandReordering_ = false
        if not level_ or not level_.cardDeck then return end
        local ordered = {}
        for _, card in ipairs(level_.cardDeck.cards or {}) do
            ordered[#ordered + 1] = card
            cardStates_[card.cardId] = {
                remainingUses = math.max(0, card.count or 0),
                usageMode = card.usageMode or "SINGLE_USE",
                consumed = false,
            }
            cardDeckById_[card.cardId] = card
        end
        table.sort(ordered, function(a, b) return (a.order or 0) < (b.order or 0) end)
        for _, card in ipairs(ordered) do handOrder_[#handOrder_ + 1] = card.cardId end
    end
    function BurnProgress(burn)
        local animationElapsed = math.max(0, burn.elapsed - burn.delay)
        local linear = math.max(0, math.min(1, animationElapsed / burn.duration))
        return 1 - math.cos(linear * math.pi * .5)
    end
    function BurnNoise(seed, salt)
        return .5 + .5 * math.sin(seed * 12.9898 + salt * 78.233)
    end
    function EmitBurnParticles(burn, burst)
        local idSeed = 0
        for index = 1, #burn.id do idSeed = idSeed + string.byte(burn.id, index) * index end
        for index = 0, 4 do
            local seed = idSeed + burst * 17 + index * 7
            local ash = index >= 3
            local leftRight = BurnNoise(seed, 1) * 2 - 1
            local vertical = BurnNoise(seed, 2) * 2 - 1
            cardBurnParticles_[#cardBurnParticles_ + 1] = {
                x = burn.x + leftRight * 68,
                y = burn.y - 101 + BurnProgress(burn) * 202 + vertical * 4,
                dx = (BurnNoise(seed, 3) * 2 - 1) * 24,
                dy = -(42 + BurnNoise(seed, 4) * (ash and 46 or 76)),
                radius = ash and (2 + math.floor(BurnNoise(seed, 5) * 3)) or (2 + math.floor(BurnNoise(seed, 5) * 2)),
                alpha = ash and .65 or .96,
                color = ash and Renderer2D.COLORS.ash or (index % 2 == 0 and Renderer2D.COLORS.burnEdge or Renderer2D.COLORS.spark),
                scaleTarget = ash and .45 or .15,
                delay = 10 + math.floor(BurnNoise(seed, 6) * 81),
                duration = 260 + math.floor(BurnNoise(seed, 7) * 261),
                elapsed = 0,
            }
        end
    end
    function QueueCardResolution(id, x, y, candidate, pose)
        burningCardIds_[id] = true
        cardBurns_[#cardBurns_ + 1] = {
            id = id,
            x = x,
            y = y,
            candidate = candidate,
            elapsed = 0,
            applyAt = 100,
            delay = 55,
            duration = 690,
            totalDuration = 745,
            emittedBursts = 0,
            applied = false,
            startScale = (pose and pose.scale) or 1.05,
            startAngle = (pose and pose.angle) or 0,
        }
        SetStatus("CARD RESOLVING · 燃烧")
    end
    function CardEntries()
        local result = {}
        for _, id in ipairs(handOrder_) do
            local card = cardDeckById_[id]
            local state = cardStates_[card.cardId]
            if card.enabled and state and not state.consumed and (state.usageMode == "REUSABLE" or state.remainingUses > 0) then result[#result + 1] = card end
        end
        return result
    end
    function CardPose(index, count)
        local entries = CardEntries()
        local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
        return entries[index], poses[index]
    end
    function CardHomePose(id)
        local entries = CardEntries()
        local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
        for i, card in ipairs(entries) do
            if card.cardId == id then return poses[i] end
        end
        return nil
    end

    -- Phaser leaves a dragged card under the pointer while the rest of the hand
    -- moves to its new slots over 160 ms. Keep the target layout in handOrder_,
    -- and retain only the transient visual interpolation here.
    function CardDisplayedPose(id, pose)
        local motion = cardHomeMotions_[id]
        if not motion then
            return { x = pose.x, y = pose.y, angle = pose.angle, depth = pose.depth, scale = 1 }
        end
        local t = motion.duration > 0 and math.min(1, motion.elapsed / motion.duration) or 1
        local eased = 1 - (1 - t) ^ 3
        return {
            x = motion.fromX + (motion.toX - motion.fromX) * eased,
            y = motion.fromY + (motion.toY - motion.fromY) * eased,
            angle = motion.fromAngle + (motion.toAngle - motion.fromAngle) * eased,
            depth = pose.depth,
            scale = motion.fromScale + (motion.toScale - motion.fromScale) * eased,
        }
    end

    -- Every card-facing system must agree on the same transient pose. In
    -- particular, a primed card is not at its nominal hand slot: Phaser lifts it
    -- by 10 px, scales it to 1.04 and raises it above the hand before hit testing.
    function CardVisualPose(id, pose)
        local displayed = CardDisplayedPose(id, pose)
        local visual = {
            x = displayed.x,
            y = displayed.y,
            angle = displayed.angle,
            depth = displayed.depth,
            scale = displayed.scale or 1,
        }
        if activeCardId_ == id then
            visual.depth = 73
            local pressProgress = activeCardPressedAt_ and math.max(0, math.min(1, (uiElapsed_ - activeCardPressedAt_) / .09)) or 1
            local pressEase = 1 - (1 - pressProgress) ^ 3
            local pressPose = activeCardPressPose_ or visual
            visual.angle = (pressPose.angle or 0) * (1 - pressEase)
            visual.scale = (pressPose.scale or 1) + (1.05 - (pressPose.scale or 1)) * pressEase
            if cardParameterStart_ then
                visual.x, visual.y = cardParameterStart_.x, cardParameterStart_.y
            elseif activeCardDragged_ and activeCardPointer_ then
                visual.x, visual.y = activeCardPointer_.x, activeCardPointer_.y
            else
                -- POINTER_DOWN preserves the card's rendered pose. A direct
                -- touch therefore scales in place; only a prior hover carries
                -- Phaser's 18 px lift into the press.
                visual.x, visual.y = pressPose.x, pressPose.y
            end
            if activeCardDragged_ then visual.angle = 0; visual.scale = 1.05 end
            return visual
        end
        if primedCardId_ == id then
            visual.y = visual.y - 10
            visual.angle = 0
            visual.depth = 73
            visual.scale = visual.scale * 1.04
            return visual
        end
        local hoverState = cardHoverStates_[id]
        local hoverProgress = hoverState and hoverState.value or 0
        if hoverProgress > .001 then
            visual.y = visual.y - 18 * hoverProgress
            visual.angle = 0
            visual.depth = 72
            visual.scale = visual.scale * (1 + hoverProgress * .05)
        end
        return visual
    end
    function CurrentCardVisualPose(id)
        local entries = CardEntries()
        local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
        for index, card in ipairs(entries) do
            if card.cardId == id and poses[index] then return CardVisualPose(id, poses[index]) end
        end
        return nil
    end
    function PrimedCardPose(id)
        local home = CardHomePose(id)
        if not home then return nil end
        return { x = home.x, y = home.y - 10, angle = 0, depth = 73, scale = 1.04 }
    end
    function UpdateCardHomeMotions(dt)
        for id, motion in pairs(cardHomeMotions_) do
            motion.elapsed = motion.elapsed + dt
            if motion.elapsed >= motion.duration then cardHomeMotions_[id] = nil end
        end
    end
    function AnimateCardToHome(id, from, duration)
        local home = CardHomePose(id)
        if not home or not from then return end
        cardHomeMotions_[id] = {
            fromX = from.x,
            fromY = from.y,
            fromAngle = from.angle or 0,
            fromScale = from.scale or 1,
            toX = home.x,
            toY = home.y,
            toAngle = home.angle,
            toScale = 1,
            elapsed = 0,
            duration = duration,
        }
    end

    ---@param id string
    ---@param targetIndex integer
    ---@return boolean
    function MoveCardToHandSlot(id, targetIndex)
        local entries = CardEntries()
        local currentIndex = nil
        local currentPoses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
        local displayed = {}
        for i, card in ipairs(entries) do
            local pose = currentPoses[i]
            if card.cardId == id then currentIndex = i end
            if pose then displayed[card.cardId] = CardDisplayedPose(card.cardId, pose) end
        end
        if not currentIndex or currentIndex == targetIndex then return false end

        targetIndex = math.max(1, math.min(#entries, targetIndex))
        local desired = {}
        for i, card in ipairs(entries) do desired[i] = card.cardId end
        table.remove(desired, currentIndex)
        table.insert(desired, targetIndex, id)

        -- handOrder_ also retains cards that may no longer be drawable. Rewrite
        -- only the active entries so those hidden cards preserve their positions.
        local available = {}
        for _, card in ipairs(entries) do available[card.cardId] = true end
        local nextDesired = 1
        for index, cardId in ipairs(handOrder_) do
            if available[cardId] then
                handOrder_[index] = desired[nextDesired]
                nextDesired = nextDesired + 1
            end
        end

        local reordered = CardEntries()
        local targetPoses = Rules.CardHand(#reordered, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
        for i, card in ipairs(reordered) do
            if card.cardId ~= id then
                local from = displayed[card.cardId] or targetPoses[i]
                local target = targetPoses[i]
                if from and target then
                    cardHomeMotions_[card.cardId] = {
                        fromX = from.x,
                        fromY = from.y,
                        fromAngle = from.angle,
                        fromScale = from.scale or 1,
                        toX = target.x,
                        toY = target.y,
                        toAngle = target.angle,
                        toScale = 1,
                        elapsed = 0,
                        duration = .16,
                    }
                end
            end
        end
        return true
    end
    function UpdateCardHoverStates(dt)
        for _, card in ipairs(CardEntries()) do
            local state = cardHoverStates_[card.cardId]
            if state then
                state.elapsed = math.min(state.duration, state.elapsed + dt)
                local t = state.duration > 0 and state.elapsed / state.duration or 1
                local eased = 1 - (1 - t) ^ 3
                state.value = state.from + (state.target - state.from) * eased
            end
        end
    end
    function SetHoveredCard(id)
        if hoveredCardId_ == id then return end
        hoveredCardId_ = id
        for _, card in ipairs(CardEntries()) do
            local state = cardHoverStates_[card.cardId] or { value = 0, from = 0, target = 0, elapsed = 0, duration = .11 }
            local target = card.cardId == id and 1 or 0
            if state.target ~= target then
                state.from = state.value
                state.target = target
                state.elapsed = 0
                state.duration = .11
            end
            cardHoverStates_[card.cardId] = state
        end
    end
    function CardHoverProgress(id)
        local state = cardHoverStates_[id]
        return state and state.value or 0
    end
    function FindTopCardAt(x, y)
        local entries = CardEntries()
        local poses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth / 2, frame_.cardHandY, frame_.playfieldWidth)
        local found, foundDepth, foundIndex = nil, -math.huge, -math.huge
        for i, card in ipairs(entries) do
            local pose = CardVisualPose(card.cardId, poses[i])
            if pose and not burningCardIds_[card.cardId] then
                local radians = math.rad(-pose.angle)
                local dx, dy = x - pose.x, y - pose.y
                local scale = pose.scale or 1
                local localX = (math.cos(radians) * dx - math.sin(radians) * dy) / scale
                local localY = (math.sin(radians) * dx + math.cos(radians) * dy) / scale
                if math.abs(localX) <= CARD_RENDER_WIDTH * .5 and math.abs(localY) <= CARD_RENDER_HEIGHT * .5
                    and (pose.depth > foundDepth or (pose.depth == foundDepth and i > foundIndex)) then
                    found, foundDepth, foundIndex = card, pose.depth, i
                end
            end
        end
        return found
    end
    function TryCardPress(x, y)
        -- CARD_RESOLVING owns the full hand until its burn timeline completes.
        -- Without this guard a second card can be picked up while the first one
        -- is still clipping away, unlike Phaser's cardPointerId interaction lock.
        if #cardBurns_ > 0 then return false end
        local card = FindTopCardAt(x, y)
        if not card then return false end
        local pressPose = CurrentCardVisualPose(card.cardId)
        if primedCardId_ and primedCardId_ ~= card.cardId then
            local previous = primedCardId_
            primedCardId_ = nil
            AnimateCardToHome(previous, PrimedCardPose(previous), .12)
        end
        activeCardId_ = card.cardId
        activeCardStart_ = { x = x, y = y }
        activeCardPointer_ = { x = x, y = y }
        activeCardDragged_ = false
        activeCardDeploying_ = false
        activeCardPressedAt_ = uiElapsed_
        activeCardPressPose_ = pressPose
        cardHandReordering_ = false
        cardParameterStart_ = nil
        cardDeployEnteredMs_ = nil
        cardLastMotionAtMs_ = nil
        cardPointerSamples_ = {}
        cardCandidate_ = nil
        cardGestureDistance_ = 0
        SetHoveredCard(nil)
        SetStatus("CARD · 按住拖动或再次点击预备")
        return true
    end
    function ClearCardInteraction()
        activeCardStart_ = nil
        activeCardPointer_ = nil
        activeCardDragged_ = false
        activeCardDeploying_ = false
        activeCardPressedAt_ = nil
        activeCardPressPose_ = nil
        cardHandReordering_ = false
        cardParameterStart_ = nil
        cardDeployEnteredMs_ = nil
        cardLastMotionAtMs_ = nil
        cardPointerSamples_ = {}
        cardCandidate_ = nil
        cardGestureDistance_ = 0
    end
    function UpdateCardParameter(dt)
        if not activeCardId_ or not activeCardPointer_ or not activeCardDeploying_ then return end
        if activeCardId_ ~= "side-gravity" and activeCardId_ ~= "mirror-motion" then return end
        local pointer = activeCardPointer_
        -- Before settling, Phaser requires the pointer to be in the playfield.
        -- Once the anchor exists, POINTER_UP_OUTSIDE still resolves from that
        -- fixed anchor; releasing outside must not destroy an already valid gesture.
        if not cardParameterStart_ and not PointerInPlayfield(pointer.x, pointer.y) then
            cardParameterStart_ = nil
            cardDeployEnteredMs_ = nil
            cardLastMotionAtMs_ = nil
            cardPointerSamples_ = {}
            cardCandidate_ = nil
            cardGestureDistance_ = 0
            return
        end
        if not cardParameterStart_ then
            local now = uiElapsed_ * 1000
            if not cardDeployEnteredMs_ then
                cardDeployEnteredMs_ = now
                cardLastMotionAtMs_ = now
                cardPointerSamples_ = { { x = pointer.x, y = pointer.y, at = now } }
                return
            end
            local previous = cardPointerSamples_[#cardPointerSamples_]
            local elapsed = math.max(1, now - previous.at)
            local stepX, stepY = pointer.x - previous.x, pointer.y - previous.y
            if math.sqrt(stepX * stepX + stepY * stepY) / elapsed > .08 then cardLastMotionAtMs_ = now end
            cardPointerSamples_[#cardPointerSamples_ + 1] = { x = pointer.x, y = pointer.y, at = now }
            local cutoff = now - 140
            while #cardPointerSamples_ > 2 and cardPointerSamples_[2].at < cutoff do table.remove(cardPointerSamples_, 1) end
            local recentDistance = 0
            for i = 2, #cardPointerSamples_ do
                local from, to = cardPointerSamples_[i - 1], cardPointerSamples_[i]
                local dx, dy = to.x - from.x, to.y - from.y
                recentDistance = recentDistance + math.sqrt(dx * dx + dy * dy)
            end
            local sampleSpan = now - cardPointerSamples_[1].at
            if now - cardDeployEnteredMs_ >= 100 and sampleSpan >= 112
                and recentDistance <= 8 and now - cardLastMotionAtMs_ >= 150 then
                cardParameterStart_ = { x = pointer.x, y = pointer.y }
                cardCandidate_ = nil
                cardGestureDistance_ = 0
                SetStatus(activeCardId_ == "side-gravity" and "PARAMETER · 四向滑动选择重力" or "PARAMETER · 滑动选择镜像轴")
            end
            return
        end
        local dx, dy = pointer.x - cardParameterStart_.x, pointer.y - cardParameterStart_.y
        cardGestureDistance_ = math.sqrt(dx * dx + dy * dy)
        if cardGestureDistance_ < 28 then
            cardCandidate_ = nil
        elseif activeCardId_ == "side-gravity" then
            local horizontal = cardCandidate_ and math.abs(math.abs(dx) - math.abs(dy)) < 8
                and (cardCandidate_ == "LEFT" or cardCandidate_ == "RIGHT") or math.abs(dx) >= math.abs(dy)
            if horizontal then cardCandidate_ = dx >= 0 and "RIGHT" or "LEFT" else cardCandidate_ = dy >= 0 and "DOWN" or "UP" end
        else
            if not (cardCandidate_ and math.abs(math.abs(dx) - math.abs(dy)) < 8) then
                cardCandidate_ = math.abs(dx) >= math.abs(dy) and "HORIZONTAL" or "VERTICAL"
            end
        end
    end
    function ResolveActiveCard(x, y)
        local id = activeCardId_
        if not id then return end
        local candidate = cardCandidate_
        local gestureDistance = cardGestureDistance_
        local wasDragged = activeCardDragged_
        local wasDeploying = activeCardDeploying_
        if not wasDragged then
            -- Phaser's primed transition starts from the nominal slot, not an
            -- interrupted hand-reorder tween.
            cardHomeMotions_[id] = nil
            if primedCardId_ == id then
                local from = PrimedCardPose(id)
                primedCardId_ = nil
                activeCardId_ = nil
                AnimateCardToHome(id, from, .12)
                SetStatus(launched_ and "RUNNING · 实验进行中" or "READY · 等待发射")
            else
                activeCardId_ = nil
                primedCardId_ = id
                SetStatus("BULLET TIME · 0.05")
            end
            ClearCardInteraction()
            return
        end
        primedCardId_ = nil
        if not wasDeploying then
            local from = CurrentCardVisualPose(id)
            activeCardId_ = nil
            AnimateCardToHome(id, from, cardHandReordering_ and .12 or .18)
            ClearCardInteraction()
            return
        end
        local needsParameter = id == "side-gravity" or id == "mirror-motion"
        local deployment = needsParameter and cardParameterStart_ or { x = x, y = y }
        if not deployment or not PointerInPlayfield(deployment.x, deployment.y) then
            local from = CurrentCardVisualPose(id)
            activeCardId_ = nil
            AnimateCardToHome(id, from, .18)
            ClearCardInteraction()
            return
        end
        if id == "side-gravity" and (not candidate or gestureDistance < 48) then
            SetStatus("CARD · 定向引力需要明确的方向手势")
            local from = CurrentCardVisualPose(id)
            activeCardId_ = nil
            AnimateCardToHome(id, from, .18)
            ClearCardInteraction()
            return
        end
        if id == "mirror-motion" and (not candidate or gestureDistance < 48) then
            SetStatus("CARD · 运动镜像需要明确的方向手势")
            local from = CurrentCardVisualPose(id)
            activeCardId_ = nil
            AnimateCardToHome(id, from, .18)
            ClearCardInteraction()
            return
        end
        if Rules.CARDS[id].kind == "decision" and not launched_ then
            SetStatus("CARD · 当前没有已发射的实验对象")
            local from = CurrentCardVisualPose(id)
            activeCardId_ = nil
            AnimateCardToHome(id, from, .18)
            ClearCardInteraction()
            return
        end
        local burnPose = CurrentCardVisualPose(id)
        activeCardId_ = nil
        QueueCardResolution(id, deployment.x, deployment.y, candidate, burnPose)
        ClearCardInteraction()
    end
    function CaptureHandVisualPoses(removedId)
        local entries = CardEntries()
        local currentPoses = Rules.CardHand(#entries, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
        local displayed = {}
        for i, card in ipairs(entries) do
            if card.cardId ~= removedId and currentPoses[i] then
                displayed[card.cardId] = CardVisualPose(card.cardId, currentPoses[i])
            end
        end
        return displayed
    end
    function AnimateHandAfterBurn(displayed)
        local remaining = CardEntries()
        local targetPoses = Rules.CardHand(#remaining, frame_.playfieldX + frame_.playfieldWidth * .5, frame_.cardHandY, frame_.playfieldWidth)
        for i, card in ipairs(remaining) do
            local from, target = displayed[card.cardId], targetPoses[i]
            if from and target then
                cardHomeMotions_[card.cardId] = {
                    fromX = from.x,
                    fromY = from.y,
                    fromAngle = from.angle,
                    fromScale = from.scale or 1,
                    toX = target.x,
                    toY = target.y,
                    toAngle = target.angle,
                    toScale = 1,
                    elapsed = 0,
                    duration = .16,
                }
            end
        end
    end

    function UpdateCardAnimations(dt)
        UpdateCardHomeMotions(dt)
        UpdateCardHoverStates(dt)
        for i = #cardBurns_, 1, -1 do
            local burn = cardBurns_[i]
            burn.elapsed = burn.elapsed + dt * 1000
            local thresholds = { .2, .5, .78 }
            local progress = BurnProgress(burn)
            while burn.emittedBursts < #thresholds and progress >= thresholds[burn.emittedBursts + 1] do
                burn.emittedBursts = burn.emittedBursts + 1
                EmitBurnParticles(burn, burn.emittedBursts)
            end
            if not burn.applied and burn.elapsed >= burn.applyAt then
                burn.applied = ApplyCardResolution(burn.id, burn.candidate)
            end
            if burn.elapsed >= burn.totalDuration then
                local shouldReflow = burn.applied and cardStates_[burn.id]
                    and cardStates_[burn.id].usageMode ~= "REUSABLE"
                local displayed = shouldReflow and CaptureHandVisualPoses(burn.id) or nil
                if burn.applied then
                    local cardState = cardStates_[burn.id]
                    if cardState and cardState.usageMode ~= "REUSABLE" then
                        cardState.remainingUses = math.max(0, cardState.remainingUses - 1)
                        cardState.consumed = cardState.remainingUses == 0
                    end
                end
                if displayed then AnimateHandAfterBurn(displayed) end
                burningCardIds_[burn.id] = nil
                table.remove(cardBurns_, i)
            end
        end
        for i = #cardBurnParticles_, 1, -1 do
            local particle = cardBurnParticles_[i]
            particle.elapsed = particle.elapsed + dt * 1000
            if particle.elapsed >= particle.delay + particle.duration then table.remove(cardBurnParticles_, i) end
        end
    end

    -- Box2D reports a begin contact once and an update contact every solver step.
    -- The source keeps its Sensor alive through Matter's collisionactive event.
end

return M
