local ResponsiveCatalogRoot = {}

ResponsiveCatalogRoot.MIN_ASPECT = 1.0
ResponsiveCatalogRoot.REGULAR_BREAKPOINT = 1.25
ResponsiveCatalogRoot.WIDE_BREAKPOINT = 1.55
ResponsiveCatalogRoot.MAX_ASPECT = 20 / 9
ResponsiveCatalogRoot.MIN_TOUCH_SIZE = 48

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function round(value)
    return math.floor(value + 0.5)
end

local function rect(x, y, w, h)
    return { x = round(x), y = round(y), w = math.max(0, round(w)), h = math.max(0, round(h)) }
end

local function resolveSafeInsets(frame, minimum)
    local source = frame.safeAreaInsets
    if not source and _G.GetSafeAreaInsets then
        local ok, safeRect = pcall(GetSafeAreaInsets, false)
        if ok and safeRect then
            source = {
                left = safeRect.min.x,
                top = safeRect.min.y,
                right = safeRect.max.x,
                bottom = safeRect.max.y,
            }
        end
    end
    source = source or {}
    local dpr = math.max(1, tonumber(frame.dpr) or 1)
    return {
        left = math.max(minimum, (tonumber(source.left) or 0) / dpr),
        top = math.max(minimum, (tonumber(source.top) or 0) / dpr),
        right = math.max(minimum, (tonumber(source.right) or 0) / dpr),
        bottom = math.max(minimum, (tonumber(source.bottom) or 0) / dpr),
    }
end

local function horizontalButtons(container, buttonHeight, gap, maximumGroupWidth)
    local side = clamp(container.w * 0.035, 14, 22)
    local groupWidth = math.min(container.w - side * 2, maximumGroupWidth)
    local buttonWidth = math.max(ResponsiveCatalogRoot.MIN_TOUCH_SIZE, (groupWidth - gap) * 0.5)
    groupWidth = buttonWidth * 2 + gap
    local x = container.x + container.w - side - groupWidth
    local y = container.y + container.h - side - buttonHeight
    return rect(x, y, buttonWidth, buttonHeight), rect(x + buttonWidth + gap, y, buttonWidth, buttonHeight)
end

local function panelContent(layout)
    local left = layout.left
    local right = layout.right
    local listTop = left.y + 56
    layout.listViewport = rect(left.x + 14, listTop, left.w - 28, math.max(24, left.y + left.h - listTop - 14))
    layout.listItemHeight = clamp(layout.listViewport.h / 9, 48, 62)

    local briefTop = right.y + 66
    local briefBottom = layout.startButton.y - 14
    layout.briefViewport = rect(right.x + 22, briefTop, right.w - 50, math.max(24, briefBottom - briefTop))
end

---@param frame table
---@param state table|nil
---@return table
function ResponsiveCatalogRoot.Resolve(frame, state)
    local viewportWidth = math.max(1, tonumber(frame.systemLogicalWidth) or tonumber(frame.logicalWidth) or 1)
    local viewportHeight = math.max(1, tonumber(frame.systemLogicalHeight) or tonumber(frame.logicalHeight) or 1)
    local aspect = viewportWidth / viewportHeight
    local baseSafe = clamp(math.min(viewportWidth, viewportHeight) * 0.016, 8, 18)
    local safeInsets = resolveSafeInsets(frame, baseSafe)
    local availableWidth = math.max(1, viewportWidth - safeInsets.left - safeInsets.right)
    local availableHeight = math.max(1, viewportHeight - safeInsets.top - safeInsets.bottom)
    local preliminaryWidth = math.min(availableWidth, availableHeight * ResponsiveCatalogRoot.MAX_ASPECT)
    local innerSafe = clamp(math.min(preliminaryWidth, availableHeight) * 0.012, 4, 10)
    local outerHeight = math.max(1, availableHeight - innerSafe * 2)
    local outerWidth = math.min(math.max(1, availableWidth - innerSafe * 2),
        outerHeight * ResponsiveCatalogRoot.MAX_ASPECT)
    local outerX = safeInsets.left + (availableWidth - outerWidth) * 0.5
    local outer = rect(outerX, safeInsets.top + innerSafe, outerWidth, outerHeight)

    local mode = aspect >= ResponsiveCatalogRoot.WIDE_BREAKPOINT and "wide"
        or aspect >= ResponsiveCatalogRoot.REGULAR_BREAKPOINT and "regular" or "square"
    local activeTab = state and state.activeTab or "list"
    if activeTab ~= "list" and activeTab ~= "preview" and activeTab ~= "brief" then activeTab = "list" end
    local artScale = clamp(outer.h / 590, 0.72, 1.28)
    local plaqueMaximum = outer.w * (mode == "square" and 0.56 or mode == "regular" and 0.44 or 0.38)
    local plaqueScale = math.min(artScale, plaqueMaximum / 370)
    local plaque = rect(outer.x + 11 * plaqueScale, outer.y + 8 * plaqueScale,
        359 * plaqueScale, 110 * plaqueScale)
    local headerHeight = math.max(118 * plaqueScale + 4, clamp(outer.h * 0.19, 92, 156))
    local padding = clamp(math.min(outer.w, outer.h) * 0.032, 16, 28)
    local content = rect(outer.x + padding, outer.y + headerHeight + 6,
        outer.w - padding * 2, outer.h - headerHeight - padding - 6)
    local gap = clamp(math.min(content.w, content.h) * 0.025, 12, 20)
    local buttonHeight = clamp(outer.h * 0.078, ResponsiveCatalogRoot.MIN_TOUCH_SIZE, 68)
    local buttonGap = clamp(content.w * 0.012, 10, 16)
    local layout = {
        mode = mode,
        aspect = aspect,
        viewport = rect(0, 0, viewportWidth, viewportHeight),
        outer = outer,
        content = content,
        headerHeight = headerHeight,
        gap = gap,
        safeInsets = safeInsets,
        renderScale = math.max(0.001, tonumber(frame.renderScale) or 1),
        wideWarning = aspect > ResponsiveCatalogRoot.MAX_ASPECT + 0.001,
        outerBorder = { left = 36, right = 36, top = 112, bottom = 64 },
        panelBorder = 60,
        activeTab = activeTab,
        visible = { list = mode ~= "square" or activeTab == "list",
            preview = mode ~= "square" or activeTab == "preview",
            brief = mode ~= "square" or activeTab == "brief" },
    }

    if mode == "wide" then
        local usableWidth = content.w - gap * 2
        local leftWidth = usableWidth * 0.22
        local centerWidth = usableWidth * 0.48
        layout.left = rect(content.x, content.y, leftWidth, content.h)
        layout.center = rect(layout.left.x + layout.left.w + gap, content.y, centerWidth, content.h)
        layout.right = rect(layout.center.x + layout.center.w + gap, content.y,
            content.x + content.w - (layout.center.x + layout.center.w + gap), content.h)
        layout.startButton, layout.workshopButton = horizontalButtons(layout.right, buttonHeight, buttonGap, 520)
    elseif mode == "regular" then
        local minimumReportHeight = math.min(300, content.h * 0.48)
        local topHeight = clamp(content.h * 0.52, 210, content.h - gap - minimumReportHeight)
        local usableWidth = content.w - gap
        local leftWidth = usableWidth * 0.30
        layout.left = rect(content.x, content.y, leftWidth, topHeight)
        layout.center = rect(layout.left.x + layout.left.w + gap, content.y,
            content.x + content.w - (layout.left.x + layout.left.w + gap), topHeight)
        layout.right = rect(content.x, content.y + topHeight + gap, content.w,
            content.y + content.h - (content.y + topHeight + gap))
        layout.startButton, layout.workshopButton = horizontalButtons(layout.right, buttonHeight, buttonGap, 520)
    else
        local tabHeight = math.max(ResponsiveCatalogRoot.MIN_TOUCH_SIZE, clamp(outer.h * 0.068, 48, 56))
        local tabGap = clamp(content.w * 0.012, 8, 12)
        local tabWidth = (content.w - tabGap * 2) / 3
        layout.tabs = {
            list = rect(content.x, content.y, tabWidth, tabHeight),
            preview = rect(content.x + tabWidth + tabGap, content.y, tabWidth, tabHeight),
            brief = rect(content.x + (tabWidth + tabGap) * 2, content.y, tabWidth, tabHeight),
        }
        local actionContainer = rect(content.x, content.y, content.w, content.h)
        layout.startButton, layout.workshopButton = horizontalButtons(actionContainer, buttonHeight, buttonGap, 520)
        local panelY = content.y + tabHeight + gap
        local panelBottom = layout.startButton.y - gap
        local activePanel = rect(content.x, panelY, content.w, math.max(40, panelBottom - panelY))
        layout.left, layout.center, layout.right = activePanel, activePanel, activePanel
    end

    panelContent(layout)

    local headerInstrument = rect(outer.x + 350 * plaqueScale, outer.y + 18 * plaqueScale,
        150 * plaqueScale, 90 * plaqueScale)
    local topRightScale = clamp(artScale * 0.9, 0.68, 1.12)
    local topRight = rect(outer.x + outer.w - 95 * topRightScale,
        outer.y + 16 * topRightScale, 78 * topRightScale, 108 * topRightScale)
    local bottomScale = clamp(outer.h / 720, 0.52, 1.0)
    bottomScale = math.min(bottomScale, outer.w * 0.32 / 335)
    bottomScale = math.max(0.42, bottomScale)
    local bottomLeft = rect(outer.x + 4 * bottomScale, outer.y + outer.h - 170 * bottomScale,
        331 * bottomScale, 157 * bottomScale)
    local bottomRight = rect(outer.x + outer.w - 240 * bottomScale, outer.y + outer.h - 155 * bottomScale,
        226 * bottomScale, 141 * bottomScale)
    local archiveWidth = clamp(outer.w * 0.32, 216, 264)
    local archiveY = mode == "square" and plaque.y + plaque.h + 1 or outer.y + 18
    local archiveHeight = mode == "square" and math.max(14, content.y - archiveY - 2) or 46
    layout.decor = {
        headerPlaque = plaque,
        headerInstrument = headerInstrument,
        topRight = topRight,
        bottomLeft = bottomLeft,
        bottomRight = bottomRight,
        archive = rect(outer.x + outer.w - archiveWidth - 18, archiveY, archiveWidth, archiveHeight),
    }
    return layout
end

function ResponsiveCatalogRoot.Begin(painter, layout)
    nvgSave(painter.vg)
    nvgScale(painter.vg, 1 / layout.renderScale, 1 / layout.renderScale)
end

function ResponsiveCatalogRoot.Finish(painter)
    nvgRestore(painter.vg)
end

---@param layout table
---@param pointerFrame table
---@return table
function ResponsiveCatalogRoot.MapPointer(layout, pointerFrame)
    return {
        x = (tonumber(pointerFrame.x) or 0) * layout.renderScale,
        y = (tonumber(pointerFrame.y) or 0) * layout.renderScale,
        down = pointerFrame.down == true,
        pressed = pointerFrame.pressed == true,
        released = pointerFrame.released == true,
        isTouch = pointerFrame.isTouch == true,
    }
end

return ResponsiveCatalogRoot
