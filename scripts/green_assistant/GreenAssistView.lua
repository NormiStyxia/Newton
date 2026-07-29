---@class GreenAssistView
local View = {}
View.__index = View

local COLORS = {
    panel = { 255, 253, 248, 255 },
    border = { 95, 143, 104, 255 },
    text = { 47, 73, 56, 255 },
    secondary = { 100, 114, 104, 255 },
    primary = { 95, 143, 104, 255 },
    primaryHover = { 117, 180, 110, 255 },
    soft = { 232, 241, 222, 255 },
    white = { 255, 253, 248, 255 },
    debug = { 32, 55, 44, 255 },
}

local function PointInRect(x, y, rect)
    return rect and x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height
end

function View.New(options)
    local self = setmetatable({}, View)
    self.renderer = assert(options and options.renderer, "GreenAssistView renderer is required")
    self.config = assert(options.config, "GreenAssistView config is required")
    self.images = {}
    self.imageSizes = {}
    self.position = { x = 0, y = 0 }
    self.logicalWidth = 1
    self.logicalHeight = 1
    self.visible = true
    self.enabled = true
    self.flipX = false
    self.characterRect = nil
    self.bubbleRect = nil
    self.choiceRects = {}
    self.message = nil
    self.choices = nil
    return self
end

View.new = View.New

function View:destroy()
    local vg = self.renderer and self.renderer.vg
    if vg then
        for _, handle in pairs(self.images) do
            if handle and handle >= 0 then nvgDeleteImage(vg, handle) end
        end
    end
    self.images = {}
    self.imageSizes = {}
end

function View:setFrame(frame)
    if not frame then return end
    self.logicalWidth = math.max(1, frame.logicalWidth or self.logicalWidth)
    self.logicalHeight = math.max(1, frame.logicalHeight or self.logicalHeight)
end

function View:getHomePosition()
    local ui = self.config.ui
    return self.logicalWidth * ui.anchorX + ui.offsetX,
        self.logicalHeight * ui.anchorY + ui.offsetY
end

function View:getRoamBounds()
    local area = self.config.roamArea
    if area.relativeToAnchor == false then
        return area.xMin, area.xMax, area.yMin, area.yMax
    end
    local anchorX = self.logicalWidth * self.config.ui.anchorX
    local anchorY = self.logicalHeight * self.config.ui.anchorY
    return anchorX + area.xMin, anchorX + area.xMax, anchorY + area.yMin, anchorY + area.yMax
end

function View:setPosition(x, y)
    self.position.x, self.position.y = x, y
end

function View:getPosition()
    return self.position.x, self.position.y
end

function View:setFacingRight(facingRight)
    self.flipX = facingRight == false
end

function View:setVisible(visible)
    self.visible = visible == true
end

function View:setEnabled(enabled)
    self.enabled = enabled == true
end

function View:showMessage(text)
    self.message = tostring(text or "")
    self.choices = nil
    self.choiceRects = {}
end

function View:showChoice(text, choices)
    self.message = tostring(text or "")
    self.choices = choices or {}
    self.choiceRects = {}
end

function View:hideMessage()
    self.message = nil
    self.choices = nil
    self.bubbleRect = nil
    self.choiceRects = {}
end

function View:_image(path)
    if self.images[path] ~= nil then return self.images[path], self.imageSizes[path] end
    local handle = nvgCreateImage(self.renderer.vg, path, 0)
    self.images[path] = handle
    if handle and handle >= 0 then
        local width, height = nvgImageSize(self.renderer.vg, handle)
        self.imageSizes[path] = { width = width, height = height }
    else
        self.imageSizes[path] = { width = 1, height = 1 }
        print("[GreenAssistant] frame load failed: " .. tostring(path))
    end
    return handle, self.imageSizes[path]
end

function View:preloadAnimation(config)
    for _, frame in ipairs(config and config.frames or {}) do
        local path = type(frame) == "table" and frame.path or frame
        if type(path) == "string" then self:_image(path) end
    end
end

function View:preloadAnimations(animations)
    for _, config in pairs(animations or {}) do self:preloadAnimation(config) end
end

function View:_spriteRect(frameData)
    local ui = self.config.ui
    local height = ui.spriteHeight * ui.scale * (frameData.scale or 1)
    local _, source = self:_image(frameData.path)
    local width = height * source.width / math.max(1, source.height)
    local x = self.position.x + (frameData.offsetX or 0) - width * (frameData.anchorX or 0.5)
    local y = self.position.y + (frameData.offsetY or 0) - height * (frameData.anchorY or 1)
    return { x = x, y = y, width = width, height = height }
end

function View:_updateHitbox()
    local ui = self.config.ui
    local width = ui.hitboxWidth * ui.scale
    local height = ui.hitboxHeight * ui.scale
    self.characterRect = {
        x = self.position.x - width * 0.5,
        y = self.position.y - height,
        width = width,
        height = height,
    }
end

function View:_updateBubbleLayout()
    self.choiceRects = {}
    if not self.message then self.bubbleRect = nil; return end
    local width = self.choices and 270 or 176
    local height = self.choices and 112 or 58
    local preferredX = self.position.x + 62
    local preferredY = self.position.y - self.config.ui.spriteHeight * self.config.ui.scale - height + 38
    local x = math.max(12, math.min(self.logicalWidth - width - 12, preferredX))
    local y = math.max(12, math.min(self.logicalHeight - height - 12, preferredY))
    self.bubbleRect = { x = x, y = y, width = width, height = height }
    if self.choices then
        local gap = 10
        local buttonWidth = (width - 28 - gap) / math.max(1, #self.choices)
        for index = 1, #self.choices do
            self.choiceRects[index] = {
                x = x + 14 + (index - 1) * (buttonWidth + gap),
                y = y + height - 42,
                width = buttonWidth,
                height = 30,
            }
        end
    end
end

function View:hitTestCharacter(x, y)
    self:_updateHitbox()
    return self.visible and self.enabled and PointInRect(x, y, self.characterRect)
end

function View:hitTestBubble(x, y)
    self:_updateBubbleLayout()
    return PointInRect(x, y, self.bubbleRect)
end

function View:hitTestChoice(x, y)
    self:_updateBubbleLayout()
    for index, rect in ipairs(self.choiceRects) do
        if PointInRect(x, y, rect) then return index, self.choices[index] end
    end
    return nil, nil
end

function View:render(frameData, debugInfo)
    if not self.visible or not frameData or not frameData.path then return end
    self:_updateHitbox()
    self:_updateBubbleLayout()
    local handle = self:_image(frameData.path)
    local rect = self:_spriteRect(frameData)
    if handle and handle >= 0 then
        local vg = self.renderer.vg
        nvgSave(vg)
        if self.flipX then
            nvgTranslate(vg, rect.x + rect.width, rect.y)
            nvgScale(vg, -1, 1)
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, rect.width, rect.height)
            nvgFillPaint(vg, nvgImagePattern(vg, 0, 0, rect.width, rect.height, 0, handle, 1))
        else
            nvgBeginPath(vg)
            nvgRect(vg, rect.x, rect.y, rect.width, rect.height)
            nvgFillPaint(vg, nvgImagePattern(vg, rect.x, rect.y, rect.width, rect.height, 0, handle, 1))
        end
        nvgFill(vg)
        nvgRestore(vg)
    end

    if self.bubbleRect then
        local bubble = self.bubbleRect
        self.renderer:RoundedRect(bubble.x, bubble.y, bubble.width, bubble.height, 8, COLORS.panel, COLORS.border, 2, 248)
        self.renderer:Text(bubble.x + 14, bubble.y + 13, self.message, 15, COLORS.text)
        if self.choices then
            for index, choice in ipairs(self.choices) do
                local button = self.choiceRects[index]
                local primary = choice.id == "accept"
                self.renderer:RoundedRect(button.x, button.y, button.width, button.height, 5,
                    primary and COLORS.primary or COLORS.soft, COLORS.border, 1, 255)
                self.renderer:Text(button.x + button.width * 0.5, button.y + 7, choice.label or tostring(choice), 13,
                    primary and COLORS.white or COLORS.text, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, "maker-display")
            end
        end
    end

    if debugInfo then
        local x = math.max(12, math.min(self.logicalWidth - 300, self.position.x + 70))
        local y = math.max(12, self.position.y - 228)
        self.renderer:RoundedRect(x, y, 288, 176, 5, COLORS.debug, COLORS.border, 1, 232)
        for index, line in ipairs(debugInfo) do
            self.renderer:Text(x + 12, y + 10 + (index - 1) * 19, line, 12,
                index == 1 and COLORS.white or COLORS.soft)
        end
    end
end

return View
