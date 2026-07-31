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
    function ApplyAppleCardMaterial()
        if not apple_ or not apple_.shape then return end
        apple_.shape.restitution = MatterCalibration.CardRestitution(Rules.GetRestitutionMultiplier(rules_))
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
