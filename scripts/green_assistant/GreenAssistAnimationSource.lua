---@class GreenAssistAnimationSource
local AnimationSource = {}

local function CopyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            result[key] = CopyTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function ValidateRect(rect, label)
    return type(rect) == "table"
        and type(rect.x) == "number"
        and type(rect.y) == "number"
        and type(rect.width) == "number" and rect.width > 0
        and type(rect.height) == "number" and rect.height > 0,
        label .. " must be a positive rectangle"
end

local function ValidateFrame(frame, label)
    if type(frame) ~= "table" then return false, label .. " must be a table" end
    if type(frame.texture) ~= "string" or frame.texture == "" then
        return false, label .. ".texture is required"
    end
    local rectValid, rectError = ValidateRect(frame.sourceRect, label .. ".sourceRect")
    if not rectValid then return false, rectError end
    if type(frame.frameWidth) ~= "number" or frame.frameWidth <= 0
        or type(frame.frameHeight) ~= "number" or frame.frameHeight <= 0 then
        return false, label .. " frame size is invalid"
    end
    local anchor = frame.footAnchor
    if type(anchor) ~= "table"
        or type(anchor.normalizedX) ~= "number"
        or type(anchor.normalizedY) ~= "number" then
        return false, label .. ".footAnchor is invalid"
    end
    if frame.semanticAnchors ~= nil and type(frame.semanticAnchors) ~= "table" then
        return false, label .. ".semanticAnchors must be a table"
    end
    for name, semanticAnchor in pairs(frame.semanticAnchors or {}) do
        if type(semanticAnchor) ~= "table"
            or type(semanticAnchor.x) ~= "number"
            or type(semanticAnchor.y) ~= "number"
            or type(semanticAnchor.normalizedX) ~= "number"
            or type(semanticAnchor.normalizedY) ~= "number" then
            return false, string.format("%s.semanticAnchors.%s is invalid", label, tostring(name))
        end
    end
    return true
end

function AnimationSource.Validate(manifest, variantName)
    if type(manifest) ~= "table" or manifest.schemaVersion ~= 1 then
        return false, "unsupported Companion animation manifest"
    end
    local variants = manifest.variants
    local variant = type(variants) == "table" and variants[variantName] or nil
    if type(variant) ~= "table" or type(variant.clips) ~= "table" then
        return false, "Companion animation variant not found: " .. tostring(variantName)
    end
    for clipName, clip in pairs(variant.clips) do
        if type(clip.frames) ~= "table" or #clip.frames == 0 then
            return false, "Companion animation clip has no frames: " .. tostring(clipName)
        end
        for index, frame in ipairs(clip.frames) do
            local valid, errorMessage = ValidateFrame(frame,
                string.format("%s.frames[%d]", tostring(clipName), index))
            if not valid then return false, errorMessage end
        end
    end
    return true
end

local function RuntimeFrame(frame)
    local anchor = frame.footAnchor
    return {
        -- path remains the compatibility field used by the current Animator.
        -- texture/sourceRect are the portable FrameDescriptor fields.
        path = frame.texture,
        texture = frame.texture,
        sourceRect = CopyTable(frame.sourceRect),
        sourceOffset = CopyTable(frame.sourceOffset or { x = 0, y = 0 }),
        frameWidth = frame.frameWidth,
        frameHeight = frame.frameHeight,
        visualBounds = CopyTable(frame.visualBounds),
        footAnchor = CopyTable(anchor),
        semanticAnchors = CopyTable(frame.semanticAnchors),
        anchorX = anchor.normalizedX,
        anchorY = anchor.normalizedY,
    }
end

function AnimationSource.Apply(config, manifest, variantName)
    local valid, errorMessage = AnimationSource.Validate(manifest, variantName)
    if not valid then return false, errorMessage end
    local variant = manifest.variants[variantName]
    for animationName, animation in pairs(config.animations or {}) do
        local clipName = animation.assetClip
        local clip = clipName and variant.clips[clipName] or nil
        if clip then
            local frames = {}
            for index, frame in ipairs(clip.frames) do frames[index] = RuntimeFrame(frame) end
            animation.frames = frames
            -- Timing remains owned by the AnimationClip configuration.  The
            -- manifest repeats fps/loop for non-Lua consumers and validation.
            if clip.fps ~= animation.fps or clip.loop ~= animation.loop then
                return false, string.format("animation timing mismatch for %s/%s", animationName, clipName)
            end
        end
    end
    config.assets.activeVariant = variantName
    return true
end

return AnimationSource
