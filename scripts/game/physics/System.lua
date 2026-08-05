-- physics/System: private runtime functions installed into the App context.
local M = {}

---@param context GameContext
function M.Install(context)
    local MatterCalibration = context.MatterCalibration
    local Rules = context.Rules
    local RuntimeFactory = context.RuntimeFactory
    local CONFIG = context.CONFIG
    local _ENV = context
    function CurrentPhysicsTimeScale()
        if level_ and level_.physicsProbe and level_.physicsProbe:IsActive() then
            return level_.physicsProbe:GetTimeScale()
        end
        return bulletTimeActive_ and CONFIG.bulletTimeScale or 1
    end

    -- Physics events can be dispatched after UI input has resolved a card and
    -- changed bullet time. A post-step must retain the scale that drove its
    -- matching pre-step, exactly like Matter's afterupdate event.delta.
    function CurrentPhysicsStepScale()
        return physicsStepTimeScale_ or CurrentPhysicsTimeScale()
    end

    -- Matter's body.speed is the velocity produced by its current integration
    -- delta. Box2D already has the corresponding slow-motion velocity after
    -- SetBulletTimeActive rescales it, so convert with the fixed 60 Hz reference
    -- only. Dividing by timeScale again makes the source 4.8 sensor threshold
    -- twenty times too strict during bullet time.
    function CurrentMatterVelocityToWorld(timeScale)
        return CONFIG.matterVelocityToWorld * (timeScale or CurrentPhysicsTimeScale())
    end
    function CurrentMatterSpeedFromWorld(velocity)
        return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y) / CONFIG.matterVelocityToWorld
    end
    ---@param timeStep number
    function ApplyAppleRollingResistance(timeStep)
        if not apple_ or not appleSupportNormal_ or apple_.body.bodyType ~= BT_DYNAMIC then return end

        local normal = appleSupportNormal_
        local normalLength = math.sqrt(normal.x * normal.x + normal.y * normal.y)
        if normalLength <= .000001 then return end
        local tangentX, tangentY = -normal.y / normalLength, normal.x / normalLength
        local velocity = apple_.body.linearVelocity
        local tangentSpeed = velocity.x * tangentX + velocity.y * tangentY
        local angularSpeed = apple_.body.angularVelocity
        local timeScale = CurrentPhysicsStepScale()
        local retention = math.max(0, math.min(1,
            1 - MatterCalibration.APPLE_ROLLING_DRAG
                * timeScale
                * math.max(0, timeStep)
                * MatterCalibration.MATTER_FRAMES_PER_SECOND
        ))
        local nextTangentSpeed = tangentSpeed * retention
        local nextAngularSpeed = angularSpeed * retention
        local stopTangentSpeed = MatterCalibration.APPLE_STOP_TANGENT_SPEED * timeScale
        local stopAngularSpeed = MatterCalibration.APPLE_STOP_ANGULAR_SPEED * timeScale
        if math.abs(nextTangentSpeed) < stopTangentSpeed
            and math.abs(nextAngularSpeed) < stopAngularSpeed then
            nextTangentSpeed = 0
            nextAngularSpeed = 0
        end

        local tangentDelta = nextTangentSpeed - tangentSpeed
        apple_.body.linearVelocity = Vector2(
            velocity.x + tangentX * tangentDelta,
            velocity.y + tangentY * tangentDelta
        )
        apple_.body.angularVelocity = nextAngularSpeed
    end
    function ApplyAppleCardMaterial()
        if not apple_ or not apple_.shape then return end
        apple_.shape.restitution = MatterCalibration.CardRestitution(Rules.GetRestitutionMultiplier(rules_))
    end
    ---@param node Node|nil
    ---@return table|nil
    function FindPhysicalContactBox(node)
        if not node then return nil end
        local object = runtime_ and runtime_.byId[node.name] or nil
        if object and object.worldWidth and object.worldHeight and object.shape and not object.shape.trigger then
            return object
        end
        for _, boundary in ipairs(laboratoryBoundaries_ and laboratoryBoundaries_.ordered or {}) do
            if boundary.node == node then return boundary end
        end
        return nil
    end
    ---@param object table
    ---@param incoming Vector2
    ---@return Vector2
    function MatterContactNormal(object, incoming)
        local center = object.node.position2D
        local position = apple_.node.position2D
        local rotation = math.rad(object.node.rotation2D)
        local cosine, sine = math.cos(rotation), math.sin(rotation)
        local dx, dy = position.x - center.x, position.y - center.y
        local localX = cosine * dx + sine * dy
        local localY = -sine * dx + cosine * dy
        -- Level objects expose worldWidth/worldHeight; laboratory boundaries
        -- expose bodyWidth/bodyHeight. Both are Box2D world metres.
        local width = object.worldWidth or object.bodyWidth
        local height = object.worldHeight or object.bodyHeight
        if not width or not height then return Vector2(0, 0) end
        local halfWidth, halfHeight = width * .5, height * .5
        local closestX = math.max(-halfWidth, math.min(localX, halfWidth))
        local closestY = math.max(-halfHeight, math.min(localY, halfHeight))
        local normalX, normalY = localX - closestX, localY - closestY
        local length = math.sqrt(normalX * normalX + normalY * normalY)
        if length > .000001 then
            normalX, normalY = normalX / length, normalY / length
        else
            -- Deep overlap has no unique closest-point vector. Select the
            -- nearest face and orient it against the incoming local velocity.
            local localVelocityX = cosine * incoming.x + sine * incoming.y
            local localVelocityY = -sine * incoming.x + cosine * incoming.y
            if halfWidth - math.abs(localX) <= halfHeight - math.abs(localY) then
                normalX = localX < 0 and -1 or localX > 0 and 1 or (localVelocityX > 0 and -1 or 1)
                normalY = 0
            else
                normalX = 0
                normalY = localY < 0 and -1 or localY > 0 and 1 or (localVelocityY > 0 and -1 or 1)
            end
        end
        return Vector2(cosine * normalX - sine * normalY, sine * normalX + cosine * normalY)
    end
    ---@param other Node|nil
    function QueueMatterRestitutionAlignment(other)
        if not apple_ or not applePreSolveVelocity_ or not apple_.shape or apple_.shape.restitution <= 0 then return end
        local object = FindPhysicalContactBox(other)
        if not object then return end
        pendingMatterRestitutions_ = pendingMatterRestitutions_ or {}
        pendingMatterRestitutions_[#pendingMatterRestitutions_ + 1] = {
            incoming = Vector2(applePreSolveVelocity_.x, applePreSolveVelocity_.y),
            normal = MatterContactNormal(object, applePreSolveVelocity_),
            restitution = apple_.shape.restitution,
            timeScale = CurrentPhysicsStepScale(),
        }
    end
    function ApplyPendingMatterRestitution()
        if not apple_ or not pendingMatterRestitutions_ then return end
        local solved = apple_.body.linearVelocity
        for _, pending in ipairs(pendingMatterRestitutions_) do
            local corrected = MatterCalibration.AlignRestitutionThreshold(
                pending.incoming,
                solved,
                pending.normal,
                pending.restitution,
                pending.timeScale,
                CONFIG.matterVelocityToWorld
            )
            if corrected then solved = corrected end
        end
        pendingMatterRestitutions_ = nil
        if solved.x ~= apple_.body.linearVelocity.x or solved.y ~= apple_.body.linearVelocity.y then
            apple_.body.linearVelocity = solved
            apple_.body.awake = true
        end
    end
    function RestoreAppleContactMaterial()
        if not apple_ or not apple_.shape then return end
        if math.abs(apple_.shape.friction - MatterCalibration.APPLE_FRICTION) > .0001 then
            apple_.shape.friction = MatterCalibration.APPLE_FRICTION
            if apple_.body and apple_.body.bodyType == BT_DYNAMIC then apple_.body.awake = true end
        end
    end
    function SetGravity()
        if not physicsWorld_ or not level_ or not physicsProfile_ then return end
        local base = level_.rules.initialGravity
        local gravity = Rules.GetGravity(rules_, base)
        local probeActive = level_.physicsProbe and level_.physicsProbe:IsActive()
        if probeActive then
            gravity = { x = 0, y = 1, strength = 1 }
        end
        local timeScale = CurrentPhysicsTimeScale()
        physicsWorld_:SetGravity(Vector2(
            gravity.x * gravity.strength * physicsProfile_.gravityAcceleration * timeScale * timeScale,
            -gravity.y * gravity.strength * physicsProfile_.gravityAcceleration * timeScale * timeScale
        ))
        -- PhysicsProbe owns the apple collision mask while it is sampling. Do not
        -- restore the normal level mask here or real fixtures leak into telemetry.
        if apple_ and apple_.shape and not probeActive then
            apple_.shape.maskBits = rules_.phaseActive and (RuntimeFactory.MASK_ALL & ~RuntimeFactory.CATEGORY_PHASEABLE) or RuntimeFactory.MASK_ALL
        end
        if ReevaluateButtons then ReevaluateButtons() end
    end

    ---@param active boolean
    function SetBulletTimeActive(active)
        if bulletTimeActive_ == active then return end
        local previousScale = CurrentPhysicsTimeScale()
        bulletTimeActive_ = active
        local nextScale = CurrentPhysicsTimeScale()
        if apple_ and apple_.body and apple_.body.bodyType == BT_DYNAMIC then
            local velocity = apple_.body.linearVelocity
            local scaleRatio = nextScale / previousScale
            apple_.body.linearVelocity = Vector2(velocity.x * scaleRatio, velocity.y * scaleRatio)
            apple_.body.angularVelocity = apple_.body.angularVelocity * scaleRatio
            apple_.body.linearDamping = MatterCalibration.Box2DLinearDamping(apple_.baseFrictionAir, nextScale)
            apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping(apple_.baseFrictionAir, nextScale)
            apple_.body.awake = true
        end
        SetGravity()
    end
    function SyncPhysicsUpdateEnabled()
        if not physicsWorld_ then return end
        if replayActive_ or isPaused_ then
            SetBulletTimeActive(false)
            physicsWorld_:SetUpdateEnabled(false)
            return
        end
        -- The Phaser scene does not slow simulation while a card is only being
        -- rearranged in the hand. Bullet time begins once it is primed, deployed,
        -- or resolving its burn animation.
        local bulletTime = activeCardDeploying_ or primedCardId_ ~= nil or #cardBurns_ > 0
        SetBulletTimeActive(bulletTime)
        physicsWorld_:SetUpdateEnabled(true)
    end
    function CapAppleSpeed()
        if not launched_ or not apple_ or apple_.body.bodyType ~= BT_DYNAMIC then return end
        local velocity = apple_.body.linearVelocity
        local speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        local maxSpeed = CONFIG.maxAppleSpeed * CurrentPhysicsTimeScale()
        if speed <= maxSpeed then return end
        local scale = maxSpeed / speed
        apple_.body.linearVelocity = Vector2(velocity.x * scale, velocity.y * scale)
        apple_.body.awake = true
    end
end

return M
