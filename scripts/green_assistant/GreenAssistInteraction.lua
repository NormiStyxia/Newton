local Interaction = {}
Interaction.__index = Interaction

local function RandomLine(lines)
    if type(lines) ~= "table" or #lines == 0 then return "……" end
    return lines[math.random(1, #lines)]
end

function Interaction.New(config)
    local self = setmetatable({}, Interaction)
    self.config = config or {}
    self.pokeCount = 0
    self.lastPokeTime = -math.huge
    return self
end

Interaction.new = Interaction.New

function Interaction:poke(now)
    now = now or 0
    if now - self.lastPokeTime <= (self.config.consecutiveWindow or 1.2) then
        self.pokeCount = self.pokeCount + 1
    else
        self.pokeCount = 1
    end
    self.lastPokeTime = now
    local lines = self.config.pokeLines or {}
    local line = RandomLine(lines)
    if self.pokeCount >= 5 and #lines > 0 then line = lines[#lines] end
    return line, self.pokeCount
end

function Interaction:reset()
    self.pokeCount = 0
    self.lastPokeTime = -math.huge
end

return Interaction
