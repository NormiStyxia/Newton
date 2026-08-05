---@class CoordinateMapper
local CoordinateMapper = {}
CoordinateMapper.__index = CoordinateMapper

---@class CoordinateMapperConfig
---@field levelWidth number
---@field levelHeight number
---@field viewportWidth number
---@field viewportHeight number
---@field pixelsPerMeter number

---@param config CoordinateMapperConfig
---@return CoordinateMapper
function CoordinateMapper.New(config)
    local self = setmetatable({}, CoordinateMapper)
    self:Init(config)
    return self
end

---@param config CoordinateMapperConfig
function CoordinateMapper:Init(config)
    assert(config.levelWidth > 0 and config.levelHeight > 0, "关卡尺寸必须大于 0")
    assert(config.viewportWidth > 0 and config.viewportHeight > 0, "玩法视口尺寸必须大于 0")
    assert(config.pixelsPerMeter > 0, "pixelsPerMeter 必须大于 0")
    self.levelWidth = config.levelWidth
    self.levelHeight = config.levelHeight
    self.viewportWidth = config.viewportWidth
    self.viewportHeight = config.viewportHeight
    self.pixelsPerMeter = config.pixelsPerMeter
    self.objectScale = config.viewportHeight / config.levelHeight
end

---@param levelX number
---@param levelY number
---@return number viewportX
---@return number viewportY
function CoordinateMapper:LevelToViewport(levelX, levelY)
    return levelX / self.levelWidth * self.viewportWidth,
        levelY / self.levelHeight * self.viewportHeight
end

---@param viewportX number
---@param viewportY number
---@return number worldX
---@return number worldY
function CoordinateMapper:ViewportToWorld(viewportX, viewportY)
    return (viewportX - self.viewportWidth * 0.5) / self.pixelsPerMeter,
        (self.viewportHeight * 0.5 - viewportY) / self.pixelsPerMeter
end

---@param levelX number
---@param levelY number
---@return number worldX
---@return number worldY
function CoordinateMapper:LevelToWorld(levelX, levelY)
    local viewportX, viewportY = self:LevelToViewport(levelX, levelY)
    return self:ViewportToWorld(viewportX, viewportY)
end

---@param worldX number
---@param worldY number
---@return number levelX
---@return number levelY
function CoordinateMapper:WorldToLevel(worldX, worldY)
    local viewportX = worldX * self.pixelsPerMeter + self.viewportWidth * 0.5
    local viewportY = self.viewportHeight * 0.5 - worldY * self.pixelsPerMeter
    return viewportX / self.viewportWidth * self.levelWidth,
        viewportY / self.viewportHeight * self.levelHeight
end

---@param levelWidth number
---@param levelHeight number
---@return number worldWidth
---@return number worldHeight
function CoordinateMapper:LevelSizeToWorld(levelWidth, levelHeight)
    return levelWidth * self.objectScale / self.pixelsPerMeter,
        levelHeight * self.objectScale / self.pixelsPerMeter
end

---@param levelRotation number
---@return number worldRotation
function CoordinateMapper.LevelRotationToWorld(levelRotation)
    return -levelRotation
end

---@param screenX number
---@param screenY number
---@param screenViewport table
---@return number|nil levelX
---@return number|nil levelY
function CoordinateMapper:ScreenToLevel(screenX, screenY, screenViewport)
    if screenX < screenViewport.x
        or screenX > screenViewport.x + screenViewport.width
        or screenY < screenViewport.y
        or screenY > screenViewport.y + screenViewport.height then
        return nil, nil
    end
    local viewportX = (screenX - screenViewport.x) / screenViewport.width * self.viewportWidth
    local viewportY = (screenY - screenViewport.y) / screenViewport.height * self.viewportHeight
    return viewportX / self.viewportWidth * self.levelWidth,
        viewportY / self.viewportHeight * self.levelHeight
end

---@param levelDeltaX number
---@param levelDeltaY number
---@return number levelDeltaXClamped
---@return number levelDeltaYClamped
---@return number viewportDeltaX
---@return number viewportDeltaY
function CoordinateMapper:ClampLauncherDrag(levelDeltaX, levelDeltaY)
    local viewportDeltaX = levelDeltaX / self.levelWidth * self.viewportWidth
    local viewportDeltaY = levelDeltaY / self.levelHeight * self.viewportHeight
    local length = math.sqrt(viewportDeltaX * viewportDeltaX + viewportDeltaY * viewportDeltaY)
    if length > 98 then
        local scale = 98 / length
        viewportDeltaX = viewportDeltaX * scale
        viewportDeltaY = viewportDeltaY * scale
    end
    viewportDeltaX = math.max(viewportDeltaX, -76)
    viewportDeltaY = math.min(viewportDeltaY, 78)
    return viewportDeltaX / self.viewportWidth * self.levelWidth,
        viewportDeltaY / self.viewportHeight * self.levelHeight,
        viewportDeltaX,
        viewportDeltaY
end

---@param viewportVelocityX number Matter.js pixels per 60 Hz step
---@param viewportVelocityY number Matter.js pixels per 60 Hz step
---@return number worldVelocityX meters per second
---@return number worldVelocityY meters per second
function CoordinateMapper:MatterVelocityToWorld(viewportVelocityX, viewportVelocityY)
    local stepsPerSecond = 60
    return viewportVelocityX * stepsPerSecond / self.pixelsPerMeter,
        -viewportVelocityY * stepsPerSecond / self.pixelsPerMeter
end

---@param viewportVelocityX number Matter.js pixels per 60 Hz step
---@return number radiansPerSecond
function CoordinateMapper.MatterAngularVelocityToWorld(viewportVelocityX)
    return -viewportVelocityX * 0.006 * 60
end

return CoordinateMapper
