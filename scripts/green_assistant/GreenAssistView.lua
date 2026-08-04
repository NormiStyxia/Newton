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

local function FrameTexture(frame)
    return frame and (frame.texture or frame.path) or nil
end

function View.New(options)
    local self = setmetatable({}, View)
    self.renderer = assert(options and options.renderer, "GreenAssistView renderer is required")
    self.config = assert(options.config, "GreenAssistView config is required")
    self.images = {}
    self.imageSizes = {}
    self.imageFlags = self:_resolveImageFlags()
    self.position = { x = 0, y = 0 }
    self.logicalWidth = 1
    self.logicalHeight = 1
    self.companionZone = nil
    self.visible = true
    self.enabled = true
    -- The current sprite source faces left.  Keep this asset convention in
    -- the View/config boundary so the portable controller can continue to
    -- express logical LEFT/RIGHT without knowing how the frames were drawn.
    self.flipX = self.config.ui.sourceFacing == "LEFT"
    self.characterRect = nil
    self.bubbleRect = nil
    self.choiceRects = {}
    self.message = nil
    self.choices = nil
    self.relocationEffect = nil
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
    self.companionZone = frame.companionZone
end

function View:getHomePosition()
    local ui = self.config.ui
    return self.logicalWidth * ui.anchorX + ui.offsetX,
        self.logicalHeight * ui.anchorY + ui.offsetY
end

function View:getRoamBounds()
    local zone = self:getCompanionZone()
    return zone.left, zone.right, zone.top, zone.bottom
end

function View:getCompanionZone()
    if self.companionZone then return self.companionZone end
    local area = self.config.roamArea
    local anchorX = area.relativeToAnchor == false and 0 or self.logicalWidth * self.config.ui.anchorX
    local anchorY = area.relativeToAnchor == false and 0 or self.logicalHeight * self.config.ui.anchorY
    local baselineY = self.logicalHeight * self.config.ui.anchorY + self.config.ui.offsetY
    return {
        left = anchorX + area.xMin,
        right = anchorX + area.xMax,
        top = math.min(anchorY + area.yMin, baselineY),
        bottom = math.max(anchorY + area.yMax, baselineY),
        baselineY = baselineY,
        fallbackX = self.logicalWidth * self.config.ui.anchorX + self.config.ui.offsetX,
        walkingAllowed = true,
    }
end

function View:setPosition(x, y)
    self.position.x, self.position.y = x, y
end

function View:getPosition()
    return self.position.x, self.position.y
end

function View:setFacingRight(facingRight)
    local sourceFacesRight = self.config.ui.sourceFacing ~= "LEFT"
    self.flipX = (facingRight == true) ~= sourceFacesRight
end

function View:setFacing(facing)
    self:setFacingRight(facing ~= "LEFT")
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

function View:_resolveImageFlags()
    local enabled = self.config.render and self.config.render.generateMipmaps == true
    if not enabled then return 0 end
    if type(NVG_IMAGE_GENERATE_MIPMAPS) == "number" then
        return NVG_IMAGE_GENERATE_MIPMAPS
    end
    print("[GreenAssistant] NVG_IMAGE_GENERATE_MIPMAPS is unavailable; using linear filtering")
    return 0
end

function View:_image(path)
    local key = tostring(self.imageFlags) .. ":" .. path
    if self.images[key] ~= nil then return self.images[key], self.imageSizes[key] end
    local handle = nvgCreateImage(self.renderer.vg, path, self.imageFlags)
    self.images[key] = handle
    if handle and handle >= 0 then
        local width, height = nvgImageSize(self.renderer.vg, handle)
        self.imageSizes[key] = { width = width, height = height }
    else
        self.imageSizes[key] = { width = 1, height = 1 }
        print("[GreenAssistant] frame load failed: " .. tostring(path))
    end
    return handle, self.imageSizes[key]
end

function View:preloadAnimation(config)
    for _, frame in ipairs(config and config.frames or {}) do
        local path = type(frame) == "table" and FrameTexture(frame) or frame
        if type(path) == "string" then self:_image(path) end
    end
end

function View:preloadAnimations(animations)
    for _, config in pairs(animations or {}) do self:preloadAnimation(config) end
end

function View:_spriteRect(frameData, positionX, positionY)
    local ui = self.config.ui
    local height = ui.spriteHeight * ui.scale * (frameData.scale or 1)
    local _, source = self:_image(FrameTexture(frameData))
    local frameWidth = frameData.frameWidth or source.width
    local frameHeight = frameData.frameHeight or source.height
    local width = height * frameWidth / math.max(1, frameHeight)
    positionX = positionX or self.position.x
    positionY = positionY or self.position.y
    local x = positionX + (frameData.offsetX or 0) - width * (frameData.anchorX or 0.5)
    local y = positionY + (frameData.offsetY or 0) - height * (frameData.anchorY or 1)
    return { x = x, y = y, width = width, height = height }
end

function View:_drawFrame(vg, handle, imageSize, frameData, frameRect)
    local sourceRect = frameData.sourceRect or {
        x = 0, y = 0, width = imageSize.width, height = imageSize.height,
    }
    local sourceOffset = frameData.sourceOffset or { x = 0, y = 0 }
    local frameWidth = frameData.frameWidth or sourceRect.width
    local frameHeight = frameData.frameHeight or sourceRect.height
    local scaleX = frameRect.width / math.max(1, frameWidth)
    local scaleY = frameRect.height / math.max(1, frameHeight)
    local drawX = frameRect.x + (sourceOffset.x or 0) * scaleX
    local drawY = frameRect.y + (sourceOffset.y or 0) * scaleY
    local drawWidth = sourceRect.width * scaleX
    local drawHeight = sourceRect.height * scaleY
    local patternX = drawX - sourceRect.x * scaleX
    local patternY = drawY - sourceRect.y * scaleY
    local patternWidth = imageSize.width * scaleX
    local patternHeight = imageSize.height * scaleY
    nvgBeginPath(vg)
    nvgRect(vg, drawX, drawY, drawWidth, drawHeight)
    nvgFillPaint(vg, nvgImagePattern(vg, patternX, patternY,
        patternWidth, patternHeight, 0, handle, 1))
    nvgFill(vg)
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

function View:startRelocationEffect(effect)
    assert(type(effect) == "table", "relocation effect is required")
    self.relocationEffect = {
        age = 0,
        from = { x = effect.from.x, y = effect.from.y },
        to = { x = effect.to.x, y = effect.to.y },
        exitDuration = math.max(0.01, effect.exitDuration or 0.18),
        holdDuration = math.max(0, effect.holdDuration or 0.06),
        enterDuration = math.max(0.01, effect.enterDuration or 0.22),
        slatCount = math.max(2, math.floor(effect.slatCount or 8)),
    }
end

function View:updateRelocationEffect(dt)
    local effect = self.relocationEffect
    if not effect then return true end
    effect.age = effect.age + math.max(0, dt or 0)
    local duration = effect.exitDuration + effect.holdDuration + effect.enterDuration
    if effect.age < duration then return false end
    self.relocationEffect = nil
    return true
end

function View:cancelRelocationEffect()
    self.relocationEffect = nil
end

local function EaseOut(value)
    value = math.max(0, math.min(1, value))
    return 1 - (1 - value) ^ 3
end

function View:_drawSprite(frameData, positionX, positionY)
    local texture = FrameTexture(frameData)
    if not frameData or not texture then return end
    local handle, imageSize = self:_image(texture)
    if not handle or handle < 0 then return end
    local vg = self.renderer.vg
    local rect = self:_spriteRect(frameData, positionX, positionY)
    nvgSave(vg)
    if self.flipX then
        local pivotX = (positionX or self.position.x) + (frameData.offsetX or 0)
        local mirrorOrigin = pivotX * 2 - rect.x
        nvgTranslate(vg, mirrorOrigin, rect.y)
        nvgScale(vg, -1, 1)
        self:_drawFrame(vg, handle, imageSize, frameData,
            { x = 0, y = 0, width = rect.width, height = rect.height })
    else
        self:_drawFrame(vg, handle, imageSize, frameData, rect)
    end
    nvgRestore(vg)
end

function View:_drawBlindSprite(frameData, position, progress, slatCount)
    if not frameData or progress <= 0 then return end
    local rect = self:_spriteRect(frameData, position.x, position.y)
    local vg = self.renderer.vg
    local clampedProgress = math.max(0, math.min(1, progress))
    local slatHeight = rect.height / slatCount
    -- A PPT-style horizontal blind is made from horizontal slats which
    -- collapse around their own center.  The old implementation clipped the
    -- width from alternating sides, producing a vertical/checkerboard wipe
    -- that was very easy to miss on the game background.
    local slatGap = math.min(2, slatHeight * 0.08)
    local visibleHeight = math.max(0, slatHeight * clampedProgress - slatGap)
    if visibleHeight <= 0 then return end
    for index = 0, slatCount - 1 do
        local slatTop = rect.y + index * slatHeight
        local centerY = slatTop + slatHeight * 0.5
        local clipY = centerY - visibleHeight * 0.5
        nvgSave(vg)
        nvgScissor(vg, rect.x, clipY, rect.width, visibleHeight)
        self:_drawSprite(frameData, position.x, position.y)
        nvgRestore(vg)

        -- Keep a restrained separator visible while the transition is in
        -- progress. It makes the horizontal slat motion readable without
        -- introducing a second overlay or changing the character asset.
        if clampedProgress > 0 and clampedProgress < 1 and index < slatCount - 1 then
            local lineY = slatTop + slatHeight
            nvgSave(vg)
            nvgStrokeColor(vg, nvgRGBA(76, 104, 84, 72))
            nvgStrokeWidth(vg, 1)
            nvgBeginPath(vg)
            nvgMoveTo(vg, rect.x, lineY)
            nvgLineTo(vg, rect.x + rect.width, lineY)
            nvgStroke(vg)
            nvgRestore(vg)
        end
    end
end

function View:_resolveRelocationVisualPosition(frameData, position, fallback)
    if not position then return fallback end
    local rect = self:_spriteRect(frameData, position.x, position.y)
    local visible = rect.x + rect.width > 0
        and rect.x < self.logicalWidth
        and rect.y + rect.height > 0
        and rect.y < self.logicalHeight
    return visible and position or fallback
end

function View:_renderRelocationEffect(frameData)
    local effect = self.relocationEffect
    if not effect or not frameData then return end
    local age = effect.age
    -- If the user released fully outside the viewport, the raw `from` root is
    -- not drawable. Use the legal destination as the visual transition point
    -- so the relocation is still observable instead of silently disappearing.
    local visualFrom = self:_resolveRelocationVisualPosition(frameData, effect.from, effect.to)
    if age < effect.exitDuration then
        local progress = EaseOut(age / effect.exitDuration)
        self:_drawBlindSprite(frameData, visualFrom, 1 - progress, effect.slatCount)
    elseif age >= effect.exitDuration + effect.holdDuration then
        local enterAge = age - effect.exitDuration - effect.holdDuration
        local progress = EaseOut(enterAge / effect.enterDuration)
        self:_drawBlindSprite(frameData, effect.to, progress, effect.slatCount)
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
    local texture = FrameTexture(frameData)
    if not self.visible or not frameData or not texture then return end
    if self.relocationEffect then
        self:_renderRelocationEffect(frameData)
        return
    end
    self:_updateHitbox()
    self:_updateBubbleLayout()
    self:_drawSprite(frameData, self.position.x, self.position.y)

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
