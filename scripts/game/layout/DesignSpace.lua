---@class DesignSpace
local DesignSpace = {}
DesignSpace.__index = DesignSpace

DesignSpace.BASE_WIDTH = 1880
DesignSpace.BASE_HEIGHT = 840
DesignSpace.LAB = { x = 323, y = 112, width = 1500, height = 596 }
DesignSpace.NEWTON = { x = 57, y = 112, width = 250, height = 596 }
DesignSpace.GROUND_LOCAL_Y = 580
DesignSpace.PLAYFIELD_HEIGHT = 700

local function round(value)
    return math.floor(value + 0.5)
end

local function resolveCardHandY(logicalHeight)
    local playfieldBottom = DesignSpace.LAB.y + DesignSpace.LAB.height
    local groundY = DesignSpace.LAB.y
        + (DesignSpace.GROUND_LOCAL_Y / DesignSpace.PLAYFIELD_HEIGHT) * DesignSpace.LAB.height
    local available = logicalHeight - playfieldBottom
    local compact = DesignSpace.BASE_HEIGHT - playfieldBottom
    local minimum = groundY + 12 + 202 * 0.5
    local preferred = minimum + 35
    local maximum = minimum + 61
    if available <= 292 then
        local range = 292 - compact
        local t = range > 0 and (available - compact) / range or 1
        t = math.max(0, math.min(1, t))
        return minimum + (preferred - minimum) * t
    end
    local t = (available - 292) / 125
    t = math.max(0, math.min(1, t))
    return preferred + (maximum - preferred) * t
end

function DesignSpace.New(pixelsPerMeter)
    local self = setmetatable({}, DesignSpace)
    self:Init(pixelsPerMeter)
    return self
end

function DesignSpace:Init(pixelsPerMeter)
    self.pixelsPerMeter = assert(pixelsPerMeter, "pixelsPerMeter is required")
    self.physicalWidth = 1
    self.physicalHeight = 1
    self.dpr = 1
    self.systemLogicalWidth = DesignSpace.BASE_WIDTH
    self.systemLogicalHeight = DesignSpace.BASE_HEIGHT
    self.renderScale = 1
    self.logicalWidth = DesignSpace.BASE_WIDTH
    self.logicalHeight = DesignSpace.BASE_HEIGHT
    self.mainStageActive = false
    self.stageOffsetY = 0
    self.stageWidth = DesignSpace.BASE_WIDTH
    self.stageHeight = DesignSpace.BASE_HEIGHT
    self.workspaceX = DesignSpace.NEWTON.x
    self.playfieldX = DesignSpace.LAB.x
    self.cardHandY = resolveCardHandY(DesignSpace.BASE_HEIGHT)
end

function DesignSpace:UpdateFromGraphics()
    local physicalWidth = math.max(1, graphics:GetWidth())
    local physicalHeight = math.max(1, graphics:GetHeight())
    local dpr = graphics.GetDPR and graphics:GetDPR() or 1
    dpr = math.max(1, dpr or 1)
    local systemWidth = physicalWidth / dpr
    local systemHeight = physicalHeight / dpr

    -- Mode A: preserve the original 1880 x 840 proportions, while allowing
    -- the source layout to expand on whichever axis the viewport exposes.
    local scale = math.min(systemWidth / DesignSpace.BASE_WIDTH, systemHeight / DesignSpace.BASE_HEIGHT)
    scale = math.max(scale, 0.001)
    self.systemLogicalWidth = systemWidth
    self.systemLogicalHeight = systemHeight
    self.renderScale = scale
    self.logicalWidth = systemWidth / scale
    self.logicalHeight = systemHeight / scale
    self.physicalWidth = physicalWidth
    self.physicalHeight = physicalHeight
    self.dpr = dpr

    -- Preserve the authored 1880-wide alignment when wider viewports expose extra space.
    self.workspaceX = DesignSpace.NEWTON.x
    self.playfieldX = self.workspaceX + DesignSpace.NEWTON.width + 16
    self.cardHandY = resolveCardHandY(self.logicalHeight)
    return self
end

---@param mainStageActive boolean|nil
function DesignSpace:Frame(mainStageActive)
    self:UpdateFromGraphics()
    -- The viewport keeps the full window dimensions. Gameplay uses a fixed
    -- local stage height and one shared translation for rendering and input.
    self.mainStageActive = mainStageActive == true
    self.stageWidth = self.logicalWidth
    self.stageHeight = self.mainStageActive and DesignSpace.BASE_HEIGHT or self.logicalHeight
    self.stageOffsetY = self.mainStageActive
        and math.max(0, (self.logicalHeight - self.stageHeight) * 0.5) or 0
    local contentHeight = self.stageHeight
    return {
        physicalWidth = self.physicalWidth,
        physicalHeight = self.physicalHeight,
        dpr = self.dpr,
        systemLogicalWidth = self.systemLogicalWidth,
        systemLogicalHeight = self.systemLogicalHeight,
        renderScale = self.renderScale,
        logicalWidth = self.logicalWidth,
        logicalHeight = contentHeight,
        viewportLogicalWidth = self.logicalWidth,
        viewportLogicalHeight = self.logicalHeight,
        mainStageActive = self.mainStageActive,
        stageX = 0,
        stageY = 0,
        stageWidth = self.stageWidth,
        stageHeight = self.stageHeight,
        stageOffsetX = 0,
        stageOffsetY = self.stageOffsetY,
        workspaceX = self.workspaceX,
        playfieldX = self.playfieldX,
        playfieldY = DesignSpace.LAB.y,
        playfieldWidth = DesignSpace.LAB.width,
        playfieldHeight = DesignSpace.LAB.height,
        newtonX = self.workspaceX,
        newtonY = DesignSpace.NEWTON.y,
        newtonWidth = DesignSpace.NEWTON.width,
        newtonHeight = DesignSpace.NEWTON.height,
        groundY = DesignSpace.LAB.y + (DesignSpace.GROUND_LOCAL_Y / DesignSpace.PLAYFIELD_HEIGHT) * DesignSpace.LAB.height,
        cardHandY = self.mainStageActive and resolveCardHandY(contentHeight) or self.cardHandY,
    }
end

function DesignSpace:ScreenToLogical(screenX, screenY)
    return screenX / self.dpr / self.renderScale,
        screenY / self.dpr / self.renderScale - self.stageOffsetY
end

function DesignSpace:IsLogicalPointInMainStage(x, y)
    if not self.mainStageActive then return true end
    return x >= 0 and x <= self.stageWidth and y >= 0 and y <= self.stageHeight
end

function DesignSpace:LogicalToWorld(x, y)
    local px = x - self.playfieldX
    local py = y - DesignSpace.LAB.y
    return (px - DesignSpace.LAB.width * 0.5) / self.pixelsPerMeter,
        (DesignSpace.LAB.height * 0.5 - py) / self.pixelsPerMeter
end

function DesignSpace:WorldToLogical(x, y)
    return self.playfieldX + DesignSpace.LAB.width * 0.5 + x * self.pixelsPerMeter,
        DesignSpace.LAB.y + DesignSpace.LAB.height * 0.5 - y * self.pixelsPerMeter
end

function DesignSpace:WorldSizeToLogical(width, height)
    return width * self.pixelsPerMeter, height * self.pixelsPerMeter
end

return DesignSpace
