local Interaction = {}
Interaction.__index = Interaction

local function RandomItem(items, random)
    if type(items) ~= "table" or #items == 0 then return nil end
    local index = math.min(#items, math.floor(random() * #items) + 1)
    return items[index]
end

local function RandomLine(lines, random)
    if type(lines) ~= "table" or #lines == 0 then return "……" end
    return RandomItem(lines, random)
end

function Interaction.New(config, options)
    local self = setmetatable({}, Interaction)
    self.config = config or {}
    self.random = options and options.random or math.random
    self.pokeCount = 0
    self.lastPokeTime = -math.huge
    return self
end

Interaction.new = Interaction.New

function Interaction:poke(now)
    now = now or 0
    if now - self.lastPokeTime < (self.config.retriggerCooldown or 0.3) then
        return nil, self.pokeCount, nil, "cooldown"
    end
    if now - self.lastPokeTime <= (self.config.consecutiveWindow or 1.2) then
        self.pokeCount = self.pokeCount + 1
    else
        self.pokeCount = 1
    end
    self.lastPokeTime = now
    local lines = self.config.pokeLines or {}
    local line = RandomLine(lines, self.random)
    if self.pokeCount >= 5 and #lines > 0 then line = lines[#lines] end
    local animation = RandomItem(self.config.tapAnimations, self.random)
    return line, self.pokeCount, animation
end

function Interaction:canPoke(now)
    return (now or 0) - self.lastPokeTime >= (self.config.retriggerCooldown or 0.3)
end

function Interaction:reset()
    self.pokeCount = 0
    self.lastPokeTime = -math.huge
end

return Interaction
