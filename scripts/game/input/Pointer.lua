-- input/Pointer: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local _ENV = context

    local function pointInPauseButton(screenX, screenY)
        if screen_ ~= "game" and screen_ ~= "workshop_preview" then return false end
        if not frame_ or not context.design_ then return false end
        local x, y = context.design_:ScreenToLogical(screenX, screenY)
        local titleX = frame_.workspaceX - 37
        return x >= titleX + 375 and x <= titleX + 421 and y >= 23 and y <= 69
    end

    local function handleSecondaryPauseTouch(touchId, screenX, screenY)
        local pointer = context.pointer_
        if pointer.activeTouchId == nil or pointer.pauseTouchId ~= nil then return false end
        if not pointInPauseButton(screenX, screenY) then return false end
        pointer.pauseTouchId = touchId
        if context.hudDropdown_ then context.hudDropdown_ = nil end
        if context.playUIClick then context.playUIClick() end
        if context.ToggleTacticalPause then context.ToggleTacticalPause() end
        return true
    end

    local function buildPointerFrame(x, y, rawDown, rawPressed, rawReleased, isTouch)
        local insideStage = context.design_:IsLogicalPointInMainStage(x, y)
        local captured = context.pointer_.stagePointerCaptured == true
        if rawPressed then
            captured = insideStage
            context.pointer_.stagePointerCaptured = captured or nil
        end
        local frame = {
            x = x,
            y = y,
            down = captured and rawDown or false,
            pressed = captured and rawPressed or false,
            released = captured and rawReleased or false,
            isTouch = isTouch,
            insideStage = insideStage,
        }
        if rawReleased then context.pointer_.stagePointerCaptured = nil end
        return frame
    end

    function DesignPointer(screenX, screenY)
        if screenX == nil or screenY == nil then
            local mouse = input.mousePosition
            screenX, screenY = mouse.x, mouse.y
        end
        local x, y = context.design_:ScreenToLogical(screenX, screenY)
        return x, y
    end

    -- Touch events carry physical screen coordinates, the same coordinate space as
    -- input.mousePosition. The primary touch owns the stage gesture; a secondary
    -- touch is accepted only for the top-level pause control.
    ---@return table PointerFrame { x, y, down, pressed, released, isTouch, insideStage }
    function PointerState()
        if context.pointer_.activeTouchId ~= nil or context.pointer_.touchPressed or context.pointer_.touchReleased then
            local x, y = DesignPointer(context.pointer_.touchX, context.pointer_.touchY)
            local frame = buildPointerFrame(x, y,
                context.pointer_.activeTouchId ~= nil,
                context.pointer_.touchPressed,
                context.pointer_.touchReleased,
                true)
            context.pointer_.touchPressed = false
            context.pointer_.touchReleased = false
            return frame
        end
        local x, y = DesignPointer()
        return buildPointerFrame(x, y,
            input:GetMouseButtonDown(MOUSEB_LEFT),
            input:GetMouseButtonPress(MOUSEB_LEFT),
            input:GetMouseButtonRelease(MOUSEB_LEFT),
            false)
    end
    function HandleTouchBegin(_eventType, eventData)
        context.HandleFirstAudioGesture()
        local touchId = eventData:GetInt("TouchID")
        local screenX, screenY = eventData:GetInt("X"), eventData:GetInt("Y")
        if handleSecondaryPauseTouch(touchId, screenX, screenY) then return end
        if context.pointer_.activeTouchId ~= nil then return end
        context.pointer_.activeTouchId = touchId
        context.pointer_.touchX = screenX
        context.pointer_.touchY = screenY
        context.pointer_.touchPressed = true
    end

    ---@param _eventType string
    ---@param eventData TouchMoveEventData
    function HandleTouchMove(_eventType, eventData)
        if eventData:GetInt("TouchID") == context.pointer_.pauseTouchId then return end
        if eventData:GetInt("TouchID") ~= context.pointer_.activeTouchId then return end
        context.pointer_.touchX = eventData:GetInt("X")
        context.pointer_.touchY = eventData:GetInt("Y")
    end

    ---@param _eventType string
    ---@param eventData TouchEndEventData
    function HandleTouchEnd(_eventType, eventData)
        if eventData:GetInt("TouchID") == context.pointer_.pauseTouchId then
            context.pointer_.pauseTouchId = nil
            return
        end
        if eventData:GetInt("TouchID") ~= context.pointer_.activeTouchId then return end
        context.pointer_.touchX = eventData:GetInt("X")
        context.pointer_.touchY = eventData:GetInt("Y")
        context.pointer_.activeTouchId = nil
        context.pointer_.touchReleased = true
    end
end

return M
