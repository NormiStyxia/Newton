-- input/Pointer: private runtime functions installed into the App context.
local M = {}

function M.Install(context)
    local _ENV = context
    function DesignPointer(screenX, screenY)
        if screenX == nil or screenY == nil then
            local mouse = input.mousePosition
            screenX, screenY = mouse.x, mouse.y
        end
        local x, y = design_:ScreenToLogical(screenX, screenY)
        return x, y
    end

    -- Touch events carry physical screen coordinates, the same coordinate space as
    -- input.mousePosition. A single active touch keeps a gesture from triggering
    -- more than one game action on mobile devices.
    ---@return table PointerFrame { x, y, down, pressed, released }
    function PointerState()
        if pointer_.activeTouchId ~= nil or pointer_.touchPressed or pointer_.touchReleased then
            local x, y = DesignPointer(pointer_.touchX, pointer_.touchY)
            local frame = {
                x = x,
                y = y,
                down = pointer_.activeTouchId ~= nil,
                pressed = pointer_.touchPressed,
                released = pointer_.touchReleased,
            }
            pointer_.touchPressed = false
            pointer_.touchReleased = false
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
        if pointer_.activeTouchId ~= nil then return end
        pointer_.activeTouchId = eventData:GetInt("TouchID")
        pointer_.touchX = eventData:GetInt("X")
        pointer_.touchY = eventData:GetInt("Y")
        pointer_.touchPressed = true
    end

    ---@param _eventType string
    ---@param eventData TouchMoveEventData
    function HandleTouchMove(_eventType, eventData)
        if eventData:GetInt("TouchID") ~= pointer_.activeTouchId then return end
        pointer_.touchX = eventData:GetInt("X")
        pointer_.touchY = eventData:GetInt("Y")
    end

    ---@param _eventType string
    ---@param eventData TouchEndEventData
    function HandleTouchEnd(_eventType, eventData)
        if eventData:GetInt("TouchID") ~= pointer_.activeTouchId then return end
        pointer_.touchX = eventData:GetInt("X")
        pointer_.touchY = eventData:GetInt("Y")
        pointer_.activeTouchId = nil
        pointer_.touchReleased = true
    end

    ---@param _eventType string
    ---@param eventData PhysicsBeginContact2DEventData
end

return M
