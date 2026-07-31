-- input/Pointer: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local _ENV = context
    function DesignPointer(screenX, screenY)
        if screenX == nil or screenY == nil then
            local mouse = input.mousePosition
            screenX, screenY = mouse.x, mouse.y
        end
        local x, y = context.design_:ScreenToLogical(screenX, screenY)
        return x, y
    end

    -- Touch events carry physical screen coordinates, the same coordinate space as
    -- input.mousePosition. A single active touch keeps a gesture from triggering
    -- more than one game action on mobile devices.
    ---@return table PointerFrame { x, y, down, pressed, released }
    function PointerState()
        if context.pointer_.activeTouchId ~= nil or context.pointer_.touchPressed or context.pointer_.touchReleased then
            local x, y = DesignPointer(context.pointer_.touchX, context.pointer_.touchY)
            local frame = {
                x = x,
                y = y,
                down = context.pointer_.activeTouchId ~= nil,
                pressed = context.pointer_.touchPressed,
                released = context.pointer_.touchReleased,
            }
            context.pointer_.touchPressed = false
            context.pointer_.touchReleased = false
            return frame
        end
        local x, y = DesignPointer()
        return {
            x = x,
            y = y,
            down = input:GetMouseButtonDown(MOUSEB_LEFT),
            pressed = input:GetMouseButtonPress(MOUSEB_LEFT),
            released = input:GetMouseButtonRelease(MOUSEB_LEFT),
        }
    end
    function HandleTouchBegin(_eventType, eventData)
        if context.pointer_.activeTouchId ~= nil then return end
        context.pointer_.activeTouchId = eventData:GetInt("TouchID")
        context.pointer_.touchX = eventData:GetInt("X")
        context.pointer_.touchY = eventData:GetInt("Y")
        context.pointer_.touchPressed = true
    end

    ---@param _eventType string
    ---@param eventData TouchMoveEventData
    function HandleTouchMove(_eventType, eventData)
        if eventData:GetInt("TouchID") ~= context.pointer_.activeTouchId then return end
        context.pointer_.touchX = eventData:GetInt("X")
        context.pointer_.touchY = eventData:GetInt("Y")
    end

    ---@param _eventType string
    ---@param eventData TouchEndEventData
    function HandleTouchEnd(_eventType, eventData)
        if eventData:GetInt("TouchID") ~= context.pointer_.activeTouchId then return end
        context.pointer_.touchX = eventData:GetInt("X")
        context.pointer_.touchY = eventData:GetInt("Y")
        context.pointer_.activeTouchId = nil
        context.pointer_.touchReleased = true
    end
end

return M
