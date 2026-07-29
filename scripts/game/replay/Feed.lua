---@class ReplayFeed
local ReplayFeed = {}

local INSTANT_ACTIVE_MS = 1400
local PUNCH_ACCENT = { 201, 108, 89 }

local function InvalidateCard(items, cardId)
    for index = #items, 1, -1 do
        local item = items[index]
        if item.cardId == cardId and item.active then
            item.active = false
            item.status = "\u{5DF2}\u{5931}\u{6548}"
            return
        end
    end
end

---@param events table[]
---@param playhead number
---@param cards table
---@return table[]
function ReplayFeed.Items(events, playhead, cards)
    local items = {}
    for index, event in ipairs(events) do
        if event.t > playhead + .001 then break end
        if event.type == "CARD_PLAYED" and event.cardId then
            local definition = cards[event.cardId]
            if definition then
                local persistent = definition.kind == "field"
                local active = persistent or playhead - event.t <= INSTANT_ACTIVE_MS
                items[#items + 1] = {
                    key = tostring(index) .. ":" .. event.cardId,
                    cardId = event.cardId,
                    symbol = definition.symbol,
                    title = definition.name,
                    status = persistent and "\u{751F}\u{6548}\u{4E2D}"
                        or (active and "\u{6267}\u{884C}\u{4E2D}" or "\u{5386}\u{53F2}\u{8BB0}\u{5F55}"),
                    accent = definition.accent,
                    persistent = persistent,
                    active = active,
                }
            end
        elseif event.type == "RULE_REMOVED" and event.cardId then
            InvalidateCard(items, event.cardId)
        elseif event.type == "NEWTON_PUNCH" then
            for _, item in ipairs(items) do
                if item.persistent then
                    item.active = false
                    item.status = "\u{5DF2}\u{5F52}\u{96F6}"
                end
            end
            items[#items + 1] = {
                key = tostring(index) .. ":punch",
                symbol = "N",
                title = "\u{725B}\u{987F}\u{4FEE}\u{6B63}\u{62F3}",
                status = "\u{89C4}\u{5219}\u{5F52}\u{96F6}",
                accent = PUNCH_ACCENT,
                persistent = false,
                active = true,
            }
        end
    end
    return items
end

return ReplayFeed
