local FailureAssist = {}
FailureAssist.__index = FailureAssist

function FailureAssist.New(config)
    local self = setmetatable({}, FailureAssist)
    self.threshold = math.max(1, math.floor(config and config.failureThreshold or 3))
    self.failureCount = 0
    self.hasOfferedThisLevel = false
    self.hasSucceededThisLevel = false
    return self
end

FailureAssist.new = FailureAssist.New

function FailureAssist:onAttemptFailed(payload)
    self.failureCount = self.failureCount + 1
    return {
        kind = self.failureCount >= self.threshold and not self.hasOfferedThisLevel and "offer" or "observe",
        failureCount = self.failureCount,
        threshold = self.threshold,
        payload = payload,
    }
end

function FailureAssist:markOffered()
    self.hasOfferedThisLevel = true
end

function FailureAssist:canReoffer()
    return self.failureCount >= self.threshold and self.hasOfferedThisLevel
end

function FailureAssist:canOfferOnPoke()
    return self.hasSucceededThisLevel or self:canReoffer()
end

function FailureAssist:onAttemptSucceeded()
    self.failureCount = 0
    self.hasSucceededThisLevel = true
end

function FailureAssist:onLevelChanged()
    self.failureCount = 0
    self.hasOfferedThisLevel = false
    self.hasSucceededThisLevel = false
end

function FailureAssist:getFailureCount()
    return self.failureCount
end

return FailureAssist
