---@class DesignSpace
local DesignSpace = {}
DesignSpace.__index = DesignSpace

DesignSpace.BASE_WIDTH = 1880
DesignSpace.BASE_HEIGHT = 840
DesignSpace.LAB = { x = 290, y = 112, width = 1500, height = 596 }
DesignSpace.NEWTON = { x = 24, y = 112, width = 250, height = 596 }
DesignSpace.GROUND_LOCAL_Y = 580
DesignSpace.PLAYFIELD_HEIGHT = 700

local function round(value)
    return math.floor(value + 0.5)
end

function DesignSpace.New()
    local self = setmetatable({}, DesignSpace)
    self:Init()
    return self
end

function DesignSpace:Init()
    self.physicalWidth = 1
    self.physicalHeight = 1
    self.dpr = 1
    self.systemLogicalWidth = DesignSpace.BASE_WIDTH
    self.systemLogicalHeight = DesignSpace.BASE_HEIGHT
    self.renderScale = 1
    self.logicalWidth = DesignSpace.BASE_WIDTH
    self.logicalHeight = DesignSpace.BASE_HEIGHT
    self.workspaceX = 24
    self.playfieldX = DesignSpace.LAB.x
    self.cardHandY = 800
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

    local workspaceWidth = DesignSpace.NEWTON.width + 16 + DesignSpace.LAB.width
    self.workspaceX = math.max(24, (self.logicalWidth - workspaceWidth) * 0.5)
    self.playfieldX = self.workspaceX + DesignSpace.NEWTON.width + 16
    local playfieldBottom = DesignSpace.LAB.y + DesignSpace.LAB.height
    local groundY = DesignSpace.LAB.y + (DesignSpace.GROUND_LOCAL_Y / DesignSpace.PLAYFIELD_HEIGHT) * DesignSpace.LAB.height
    local available = self.logicalHeight - playfieldBottom
    local compact = DesignSpace.BASE_HEIGHT - playfieldBottom
    local minimum = groundY + 12 + 202 * 0.5
    local preferred = minimum + 35
    local maximum = minimum + 61
    if available <= 292 then
        local range = 292 - compact
        local t = range > 0 and (available - compact) / range or 1
        t = math.max(0, math.min(1, t))
        self.cardHandY = minimum + (preferred - minimum) * t
    else
        local t = (available - 292) / 125
        t = math.max(0, math.min(1, t))
        self.cardHandY = preferred + (maximum - preferred) * t
    end
    return self
end

function DesignSpace:Frame()
    self:UpdateFromGraphics()
    return {
        physicalWidth = self.physicalWidth,
        physicalHeight = self.physicalHeight,
        dpr = self.dpr,
        systemLogicalWidth = self.systemLogicalWidth,
        systemLogicalHeight = self.systemLogicalHeight,
        renderScale = self.renderScale,
        logicalWidth = self.logicalWidth,
        logicalHeight = self.logicalHeight,
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
        cardHandY = self.cardHandY,
    }
end

function DesignSpace:ScreenToLogical(screenX, screenY)
    return screenX / self.dpr / self.renderScale, screenY / self.dpr / self.renderScale
end

function DesignSpace:LogicalToWorld(x, y)
    local px = x - self.playfieldX
    local py = y - DesignSpace.LAB.y
    return (px - DesignSpace.LAB.width * 0.5) / 100,
        (DesignSpace.LAB.height * 0.5 - py) / 100
end

function DesignSpace:WorldToLogical(x, y)
    return self.playfieldX + DesignSpace.LAB.width * 0.5 + x * 100,
        DesignSpace.LAB.y + DesignSpace.LAB.height * 0.5 - y * 100
end

function DesignSpace:LevelToLogical(levelX, levelY)
    return self.playfieldX + levelX / 1400 * DesignSpace.LAB.width,
        DesignSpace.LAB.y + levelY / 700 * DesignSpace.LAB.height
end

function DesignSpace:LogicalToLevel(x, y)
    return (x - self.playfieldX) / DesignSpace.LAB.width * 1400,
        (y - DesignSpace.LAB.y) / DesignSpace.LAB.height * 700
end

return DesignSpace
