local TouchScroller = {}

local function pointIn(rect, x, y)
    return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function TouchScroller.Update(gesture, pointer, targets, threshold)
    if not pointer or pointer.isTouch ~= true then return nil, nil end
    threshold = tonumber(threshold) or 8
    if pointer.pressed then
        for _, target in ipairs(targets or {}) do
            if pointIn(target.rect, pointer.x, pointer.y) then
                return {
                    target = target.id,
                    startX = pointer.x,
                    startY = pointer.y,
                    startValue = tonumber(target.value) or 0,
                    maximum = math.max(0, tonumber(target.maximum) or 0),
                    moved = false,
                }, { consume = true }
            end
        end
        return nil, nil
    end
    if not gesture then return nil, nil end
    local deltaX, deltaY = pointer.x - gesture.startX, pointer.y - gesture.startY
    if math.abs(deltaX) >= threshold or math.abs(deltaY) >= threshold then gesture.moved = true end
    if pointer.released or not pointer.down then
        return nil, { consume = true, tap = not gesture.moved, target = gesture.target }
    end
    if gesture.moved then
        return gesture, {
            consume = true,
            target = gesture.target,
            value = clamp(gesture.startValue - deltaY, 0, gesture.maximum),
        }
    end
    return gesture, { consume = true }
end

function TouchScroller.Targets(state)
    if state.modal then
        if (state.modal.kind == "export" or state.modal.kind == "import") and state.controls.modalBody then
            return { { id = "modal", rect = state.controls.modalBody,
                value = state.modal.scroll, maximum = state.modal.scrollMax } }
        end
        return {}
    end
    local targets = {}
    if state.layout.fileViewport then targets[#targets + 1] = { id = "files", rect = state.layout.fileViewport,
        value = state.view.fileScroll, maximum = state.view.fileScrollMax } end
    if state.layout.inspectorViewport then targets[#targets + 1] = { id = "inspector",
        rect = state.layout.inspectorViewport, value = state.view.inspectorScroll,
        maximum = state.view.inspectorScrollMax } end
    return targets
end

function TouchScroller.Apply(state, result)
    if not result or result.value == nil then return end
    if result.target == "modal" and state.modal then state.modal.scroll = result.value
    elseif result.target == "files" then state.view.fileScroll = result.value
    elseif result.target == "inspector" then state.view.inspectorScroll = result.value end
end

return TouchScroller
