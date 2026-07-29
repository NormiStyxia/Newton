local CardHandLayout = {}

local function RotatedHalfExtents(width, height, angleDegrees, scale)
    local radians = math.rad(angleDegrees or 0)
    local cosine, sine = math.abs(math.cos(radians)), math.abs(math.sin(radians))
    local halfWidth = width * (scale or 1) * 0.5
    local halfHeight = height * (scale or 1) * 0.5
    return cosine * halfWidth + sine * halfHeight,
        sine * halfWidth + cosine * halfHeight
end

function CardHandLayout.Bounds(poses, cardWidth, cardHeight)
    if type(poses) ~= "table" or #poses == 0 then return nil end
    assert(type(cardWidth) == "number" and cardWidth > 0, "cardWidth is required")
    assert(type(cardHeight) == "number" and cardHeight > 0, "cardHeight is required")
    local left, right, top, bottom
    for _, pose in ipairs(poses) do
        local halfWidth, halfHeight = RotatedHalfExtents(cardWidth, cardHeight, pose.angle, pose.scale)
        local poseLeft, poseRight = pose.x - halfWidth, pose.x + halfWidth
        local poseTop, poseBottom = pose.y - halfHeight, pose.y + halfHeight
        left = left and math.min(left, poseLeft) or poseLeft
        right = right and math.max(right, poseRight) or poseRight
        top = top and math.min(top, poseTop) or poseTop
        bottom = bottom and math.max(bottom, poseBottom) or poseBottom
    end
    return { left = left, right = right, top = top, bottom = bottom, width = right - left, height = bottom - top }
end

return CardHandLayout
