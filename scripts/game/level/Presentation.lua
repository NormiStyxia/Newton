local Presentation = {}

local DEFAULT_MAX_SCORE = 100
local RESULT_COPY_BY_SCORE = {
    [100] = {
        ratingLabel = "精准实验",
        summaryText = "以最少必要干预完成本次观测",
    },
    [80] = {
        ratingLabel = "有效实验",
        summaryText = "在少量规则干预下完成本次观测",
    },
    [60] = {
        ratingLabel = "观测成立",
        summaryText = "通过多次规则修正后完成本次观测",
    },
}

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
---@return table|nil
function Presentation.ResolveScoreTier(scoring, interventionCount)
    if not scoring or scoring.metric ~= "ruleDeployCount" or type(scoring.tiers) ~= "table" then return nil end
    local count = math.max(0, math.floor(tonumber(interventionCount) or 0))
    for _, tier in ipairs(scoring.tiers) do
        if tier.maxInterventions == nil or count <= tier.maxInterventions then return tier end
    end
    return nil
end

---@param scoring table|nil
---@param interventionCount integer
---@return integer|nil
function Presentation.ExpectedScore(scoring, interventionCount)
    local tier = Presentation.ResolveScoreTier(scoring, interventionCount)
    return tier and tier.score or nil
end

---@param scoring table|nil
---@param interventionCount integer
---@return table
function Presentation.BuildResultSummary(scoring, interventionCount)
    local count = math.max(0, math.floor(tonumber(interventionCount) or 0))
    local tier = Presentation.ResolveScoreTier(scoring, count)
    local score = math.floor(tonumber(tier and tier.score) or 60)
    local fallback = RESULT_COPY_BY_SCORE[score] or RESULT_COPY_BY_SCORE[60]
    return {
        score = score,
        maxScore = DEFAULT_MAX_SCORE,
        ratingLabel = tier and tier.title or fallback.ratingLabel,
        interventionCount = count,
        summaryText = fallback.summaryText,
    }
end

return Presentation
