local History = {}
History.__index = History

---@param options table
---@return table
function History.New(options)
    assert(type(options) == "table" and options.clone, "clone is required")
    return setmetatable({
        clone = options.clone,
        limit = math.max(2, tonumber(options.limit) or 80),
        entries = {},
        cursor = 0,
    }, History)
end

local function makeSnapshot(self, document, viewState, label)
    return {
        document = self.clone(document),
        viewState = self.clone(viewState or {}),
        label = label or "编辑",
    }
end

function History:Reset(document, viewState, label)
    self.entries = { makeSnapshot(self, document, viewState, label or "打开关卡") }
    self.cursor = 1
end

function History:Push(document, viewState, label)
    while #self.entries > self.cursor do table.remove(self.entries) end
    self.entries[#self.entries + 1] = makeSnapshot(self, document, viewState, label)
    if #self.entries > self.limit then table.remove(self.entries, 1) end
    self.cursor = #self.entries
end

function History:CanUndo() return self.cursor > 1 end
function History:CanRedo() return self.cursor > 0 and self.cursor < #self.entries end

local function result(self)
    local snapshot = self.entries[self.cursor]
    if not snapshot then return nil end
    return self.clone(snapshot.document), self.clone(snapshot.viewState), snapshot.label
end

function History:Undo()
    if not self:CanUndo() then return nil end
    self.cursor = self.cursor - 1
    return result(self)
end

function History:Redo()
    if not self:CanRedo() then return nil end
    self.cursor = self.cursor + 1
    return result(self)
end

function History:Current() return result(self) end

return History
