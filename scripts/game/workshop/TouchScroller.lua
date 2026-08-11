local TouchScroller = {}
local SemanticActions = require("game.input.SemanticActions")

function TouchScroller.Update(gesture, pointer, targets, threshold)
    return SemanticActions.UpdateDirectScroll(gesture, pointer, targets, threshold)
end

function TouchScroller.Targets(state)
    if state.modal then
        if (state.modal.kind == "export" or state.modal.kind == "import") and state.controls.modalBody then
            return { { id = "modal", rect = state.controls.modalBody,
                value = state.modal.scroll, maximum = state.modal.scrollMax } }
        end
        return {}
    end
    local targets = {}
    if state.layout.fileViewport then targets[#targets + 1] = { id = "files", rect = state.layout.fileViewport,
        value = state.view.fileScroll, maximum = state.view.fileScrollMax } end
    if state.layout.inspectorViewport then targets[#targets + 1] = { id = "inspector",
        rect = state.layout.inspectorViewport, value = state.view.inspectorScroll,
        maximum = state.view.inspectorScrollMax } end
    return targets
end

function TouchScroller.Apply(state, result)
    if not result or result.value == nil then return end
    if result.target == "modal" and state.modal then state.modal.scroll = result.value
    elseif result.target == "files" then state.view.fileScroll = result.value
    elseif result.target == "inspector" then state.view.inspectorScroll = result.value end
end

return TouchScroller
