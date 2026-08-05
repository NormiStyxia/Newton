local Presentation = {}

local function cloneTier(tier)
    return {
        score = tier.score,
        maxInterventions = tier.maxInterventions,
        title = tier.title,
        description = tier.description,
    }
end

---@param level table
---@param meta table|nil
---@param scoreProfiles table
---@param defaultScoreProfile string
---@return table
function Presentation.Apply(level, meta, scoreProfiles, defaultScoreProfile)
    meta = meta or {}
    local inlineScoring = level.scoring
    level.objective = meta.objective or level.objective or ""
    level.shortObjective = meta.shortObjective or level.objective
    level.observation = meta.observation or level.observation or ""
    level.description = meta.description or level.description or ""

    if type(inlineScoring) == "table" and type(inlineScoring.tiers) == "table" then
        level.scoring = { profileId = inlineScoring.profileId, metric = inlineScoring.metric, tiers = {} }
        for _, tier in ipairs(inlineScoring.tiers) do
            level.scoring.tiers[#level.scoring.tiers + 1] = cloneTier(tier)
        end
        return level
    end

    local profileId = meta.scoreProfile or level.scoreProfile or defaultScoreProfile
    local profile = scoreProfiles and scoreProfiles[profileId] or nil
    level.scoring = { profileId = profileId, metric = profile and profile.metric or nil, tiers = {} }
    if profile and type(profile.tiers) == "table" then
        for _, tier in ipairs(profile.tiers) do
            level.scoring.tiers[#level.scoring.tiers + 1] = cloneTier(tier)
        end
    end
    return level
end

---@param scoring table|nil
---@param interventionCount integer
---@return integer|nil
function Presentation.ExpectedScore(scoring, interventionCount)
    if not scoring or scoring.metric ~= "ruleDeployCount" or type(scoring.tiers) ~= "table" then return nil end
    local count = math.max(0, math.floor(tonumber(interventionCount) or 0))
    for _, tier in ipairs(scoring.tiers) do
        if tier.maxInterventions == nil or count <= tier.maxInterventions then return tier.score end
    end
    return nil
end

return Presentation
