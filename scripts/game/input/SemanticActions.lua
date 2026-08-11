-- Thin semantic action layer shared by mouse, touch, and keyboard adapters.
-- Pointer coordinates remain owned by game.input.Pointer / DesignSpace.
local SemanticActions = {
    PRIMARY_PRESS = "PRIMARY_PRESS",
    PRIMARY_MOVE = "PRIMARY_MOVE",
    PRIMARY_RELEASE = "PRIMARY_RELEASE",
    CANCEL = "CANCEL",
    SCROLL = "SCROLL",
    BOX_SELECT_BEGIN = "BOX_SELECT_BEGIN",
    BOX_SELECT_UPDATE = "BOX_SELECT_UPDATE",
    BOX_SELECT_END = "BOX_SELECT_END",
    PAUSE_TOGGLE = "PAUSE_TOGGLE",
}

local debugEnabled = false

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function copyModifiers(modifiers)
    modifiers = modifiers or {}
    return {
        ctrl = modifiers.ctrl == true,
        shift = modifiers.shift == true,
        alt = modifiers.alt == true,
    }
end

local function trace(prefix, event, consumer)
    if not debugEnabled or not event then return end
    local suffix = consumer and (" -> " .. tostring(consumer)) or ""
    print(string.format("[InputAction] %s %s source=%s%s",
        prefix, tostring(event.action), tostring(event.source or "unknown"), suffix))
end

function SemanticActions.SetDebugEnabled(enabled)
    debugEnabled = enabled == true
end

function SemanticActions.Add(pointerFrame, action, payload)
    if not pointerFrame or not action then return nil end
    pointerFrame.actions = pointerFrame.actions or {}
    payload = payload or {}
    local event = {}
    for key, value in pairs(payload) do event[key] = value end
    event.action = action
    event.source = event.source or pointerFrame.source or "unknown"
    event.pointerId = event.pointerId ~= nil and event.pointerId or pointerFrame.pointerId
    event.modifiers = event.modifiers or copyModifiers(pointerFrame.modifiers)
    pointerFrame.actions[#pointerFrame.actions + 1] = event
    trace("SEMANTIC", event)
    return event
end

function SemanticActions.Find(pointerFrame, action, scope)
    for _, event in ipairs(pointerFrame and pointerFrame.actions or {}) do
        if event.action == action and not event.consumedBy
            and (scope == nil or event.scope == scope) then
            return event
        end
    end
    return nil
end

function SemanticActions.Consume(event, consumer)
    if not event or event.consumedBy then return false end
    event.consumedBy = consumer or "unknown"
    trace("CONSUMED", event, event.consumedBy)
    return true
end

function SemanticActions.Ensure(pointerFrame)
    if not pointerFrame or pointerFrame.actions then return pointerFrame end
    return SemanticActions.Attach(pointerFrame, {
        source = pointerFrame.isTouch and "touch" or "mouse",
        hover = pointerFrame.isTouch ~= true,
        directScroll = pointerFrame.isTouch == true,
    })
end

function SemanticActions.Attach(pointerFrame, raw)
    raw = raw or {}
    pointerFrame.actions = {}
    pointerFrame.source = raw.source or (pointerFrame.isTouch and "touch" or "mouse")
    pointerFrame.pointerId = raw.pointerId
    pointerFrame.modifiers = copyModifiers(raw.modifiers)
    pointerFrame.capabilities = {
        hover = raw.hover == true,
        directScroll = raw.directScroll == true,
    }

    local primaryPayload = {
        x = pointerFrame.x,
        y = pointerFrame.y,
        source = pointerFrame.source,
        pointerId = pointerFrame.pointerId,
    }
    if pointerFrame.pressed then
        SemanticActions.Add(pointerFrame, SemanticActions.PRIMARY_PRESS, primaryPayload)
    elseif pointerFrame.down then
        SemanticActions.Add(pointerFrame, SemanticActions.PRIMARY_MOVE, primaryPayload)
    end
    if pointerFrame.released then
        SemanticActions.Add(pointerFrame, SemanticActions.PRIMARY_RELEASE, primaryPayload)
    end

    if raw.cancelInteraction then
        SemanticActions.Add(pointerFrame, SemanticActions.CANCEL, {
            scope = "interaction",
            source = raw.cancelSource or pointerFrame.source,
            raw = raw.cancelRaw,
        })
    end
    if raw.cancelNavigation then
        SemanticActions.Add(pointerFrame, SemanticActions.CANCEL, {
            scope = "navigation",
            source = raw.navigationSource or "keyboard",
            raw = raw.navigationRaw or "keyboard.escape",
        })
    end
    if raw.scrollY and raw.scrollY ~= 0 then
        -- Wheel deltas remain discrete here. Each scroll region converts its
        -- established wheel step to logical pixels before applying the action.
        SemanticActions.Add(pointerFrame, SemanticActions.SCROLL, {
            deltaX = tonumber(raw.scrollX) or 0,
            deltaY = -(tonumber(raw.scrollY) or 0),
            unit = "wheel",
            source = raw.scrollSource or "mouse",
            raw = raw.scrollRaw or "mouse.wheel",
        })
    end
    if raw.pauseToggle then
        SemanticActions.Add(pointerFrame, SemanticActions.PAUSE_TOGGLE, {
            source = raw.pauseSource or pointerFrame.source,
            pointerId = raw.pausePointerId,
            feedback = raw.pauseFeedback ~= false,
            raw = raw.pauseRaw,
        })
    end
    if raw.boxSelect then SemanticActions.PromotePrimaryToBoxSelect(pointerFrame) end
    return pointerFrame
end

function SemanticActions.SupportsHover(pointerFrame)
    return pointerFrame and pointerFrame.capabilities
        and pointerFrame.capabilities.hover == true
end

function SemanticActions.SupportsDirectScroll(pointerFrame)
    return pointerFrame and pointerFrame.capabilities
        and pointerFrame.capabilities.directScroll == true
end

function SemanticActions.PromotePrimaryToBoxSelect(pointerFrame)
    SemanticActions.Ensure(pointerFrame)
    local primary = SemanticActions.Find(pointerFrame, SemanticActions.PRIMARY_PRESS)
    local action = SemanticActions.BOX_SELECT_BEGIN
    if not primary then
        primary = SemanticActions.Find(pointerFrame, SemanticActions.PRIMARY_MOVE)
        action = SemanticActions.BOX_SELECT_UPDATE
    end
    if not primary then
        primary = SemanticActions.Find(pointerFrame, SemanticActions.PRIMARY_RELEASE)
        action = SemanticActions.BOX_SELECT_END
    end
    if not primary or SemanticActions.Find(pointerFrame, action) then return nil end
    return SemanticActions.Add(pointerFrame, action, {
        x = primary.x,
        y = primary.y,
        source = primary.source,
        pointerId = primary.pointerId,
    })
end

function SemanticActions.AddScroll(pointerFrame, deltaX, deltaY, payload)
    payload = payload or {}
    payload.deltaX = tonumber(deltaX) or 0
    payload.deltaY = tonumber(deltaY) or 0
    payload.unit = payload.unit or "logical"
    return SemanticActions.Add(pointerFrame, SemanticActions.SCROLL, payload)
end

function SemanticActions.ScrollDelta(event, wheelStep, wheelLimit)
    if not event then return 0, 0 end
    local deltaX = tonumber(event.deltaX) or 0
    local deltaY = tonumber(event.deltaY) or 0
    if event.unit == "wheel" then
        if wheelLimit then
            deltaX = clamp(deltaX, -wheelLimit, wheelLimit)
            deltaY = clamp(deltaY, -wheelLimit, wheelLimit)
        end
        local scale = tonumber(wheelStep) or 1
        deltaX, deltaY = deltaX * scale, deltaY * scale
    end
    return deltaX, deltaY
end

-- Resolve a direct-manipulation scroll gesture only after a scrollable region
-- opts in. This prevents card/object drags from being interpreted as scrolling.
function SemanticActions.UpdateDirectScroll(gesture, pointerFrame, targets, threshold)
    SemanticActions.Ensure(pointerFrame)
    if not SemanticActions.SupportsDirectScroll(pointerFrame) then return nil, nil end
    threshold = tonumber(threshold) or 8
    if pointerFrame.pressed then
        for _, target in ipairs(targets or {}) do
            local rect = target.rect
            if rect and pointerFrame.x >= rect.x and pointerFrame.x <= rect.x + rect.w
                and pointerFrame.y >= rect.y and pointerFrame.y <= rect.y + rect.h then
                local value = tonumber(target.value) or 0
                return {
                    target = target.id,
                    startX = pointerFrame.x,
                    startY = pointerFrame.y,
                    startValue = value,
                    value = value,
                    maximum = math.max(0, tonumber(target.maximum) or 0),
                    moved = false,
                }, { consume = true }
            end
        end
        return nil, nil
    end
    if not gesture then return nil, nil end

    local deltaX = pointerFrame.x - gesture.startX
    local deltaY = pointerFrame.y - gesture.startY
    if math.abs(deltaX) >= threshold or math.abs(deltaY) >= threshold then gesture.moved = true end
    if pointerFrame.released or not pointerFrame.down then
        return nil, { consume = true, tap = not gesture.moved, target = gesture.target }
    end
    if not gesture.moved then return gesture, { consume = true } end

    local value = clamp(gesture.startValue - deltaY, 0, gesture.maximum)
    local scroll = SemanticActions.AddScroll(pointerFrame, 0, value - gesture.value, {
        target = gesture.target,
        source = pointerFrame.source,
        raw = "direct.scroll",
    })
    gesture.value = value
    return gesture, {
        consume = true,
        target = gesture.target,
        value = value,
        action = scroll,
    }
end

return SemanticActions
