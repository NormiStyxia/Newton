package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message, 2) end
end

local function near(actual, expected, message)
    expect(math.abs(actual - expected) < 1e-9,
        string.format("%s: expected %.6f, got %.6f", message, expected, actual))
end

local previousGraphics = graphics
local viewport = { width = 1880, height = 840, dpr = 1 }
graphics = {
    GetWidth = function() return viewport.width end,
    GetHeight = function() return viewport.height end,
    GetDPR = function() return viewport.dpr end,
}

local DesignSpace = require("game.layout.DesignSpace")
local design = DesignSpace.New(100)

local normal = design:Frame(true)
expect(normal.mainStageActive and normal.logicalHeight == DesignSpace.BASE_HEIGHT,
    "normal viewport did not resolve to the fixed main stage")
near(normal.stageOffsetY, 0, "normal viewport stage offset")
local normalCardHandY = normal.cardHandY
near(normalCardHandY, 718.82857142857, "normal viewport authored card position")
expect(normal.playfieldY + normal.playfieldHeight <= normal.stageHeight
    and normal.newtonY + normal.newtonHeight <= normal.stageHeight
    and normal.cardHandY + 202 * 0.5 <= normal.stageHeight,
    "authored gameplay content overflows the fixed main stage")

viewport.height = 1120
local tall = design:Frame(true)
near(tall.viewportLogicalHeight, 1120, "tall viewport logical height")
near(tall.logicalHeight, 840, "tall viewport stage height")
near(tall.stageOffsetY, 140, "tall viewport vertical centering")
near(tall.cardHandY, normalCardHandY, "tall viewport changed the authored card position")
local topPadding = tall.stageOffsetY * tall.renderScale * tall.dpr
local bottomPadding = tall.physicalHeight
    - (tall.stageOffsetY + tall.stageHeight) * tall.renderScale * tall.dpr
near(topPadding, bottomPadding, "tall viewport letterbox symmetry")

viewport.width, viewport.height = 1280, 500
local short = design:Frame(true)
near(short.viewportLogicalHeight, 840, "short viewport contain height")
near(short.stageOffsetY, 0, "short viewport should not add vertical padding")
expect(short.renderScale < 1 and short.stageHeight == DesignSpace.BASE_HEIGHT,
    "short viewport did not keep the complete scaled stage")

viewport.width, viewport.height, viewport.dpr = 3760, 2240, 2
local highDpr = design:Frame(true)
near(highDpr.stageOffsetY, 140, "high-DPR stage offset")
local centerX, centerY = design:ScreenToLogical(1880, 1120)
near(centerX, 940, "high-DPR pointer x")
near(centerY, 420, "high-DPR pointer y")
local paddingX, paddingY = design:ScreenToLogical(1880, 100)
expect(paddingX == 940 and paddingY < 0
    and not design:IsLogicalPointInMainStage(paddingX, paddingY),
    "top background padding was treated as part of the interactive stage")

local previousNvg = {}
local nvgNames = {
    "nvgBeginFrame", "nvgBeginPath", "nvgRect", "nvgFillColor", "nvgRGBA", "nvgFill",
    "nvgSave", "nvgScale", "nvgTranslate", "nvgScissor", "nvgTextAlign", "nvgRestore", "nvgEndFrame",
}
for _, name in ipairs(nvgNames) do previousNvg[name] = _G[name] end
local previousAlignLeft, previousAlignTop = NVG_ALIGN_LEFT, NVG_ALIGN_TOP
local calls = {}
local function record(name, ...)
    calls[#calls + 1] = { name = name, args = { ... } }
end
nvgBeginFrame = function(...) record("begin", ...) end
nvgBeginPath = function(...) record("path", ...) end
nvgRect = function(...) record("rect", ...) end
nvgFillColor = function(...) record("fillColor", ...) end
nvgRGBA = function(...) return { ... } end
nvgFill = function(...) record("fill", ...) end
nvgSave = function(...) record("save", ...) end
nvgScale = function(...) record("scale", ...) end
nvgTranslate = function(...) record("translate", ...) end
nvgScissor = function(...) record("scissor", ...) end
nvgTextAlign = function(...) record("textAlign", ...) end
nvgRestore = function(...) record("restore", ...) end
nvgEndFrame = function(...) record("end", ...) end
NVG_ALIGN_LEFT, NVG_ALIGN_TOP = 1, 2

local Renderer = require("game.render.Canvas")
local renderer = setmetatable({ vg = {} }, { __index = Renderer })
renderer:Begin(highDpr)
renderer:Finish()
local byName = {}
for _, call in ipairs(calls) do byName[call.name] = call end
expect(calls[1].name == "begin" and byName.rect and byName.fill,
    "renderer did not restore the gameplay viewport background")
near(byName.rect.args[2], 0, "viewport background x")
near(byName.rect.args[3], 0, "viewport background y")
near(byName.rect.args[4], highDpr.systemLogicalWidth, "viewport background width")
near(byName.rect.args[5], highDpr.systemLogicalHeight, "viewport background height")
near(byName.translate.args[3], highDpr.stageOffsetY, "renderer stage translation")
near(byName.scissor.args[5], DesignSpace.BASE_HEIGHT, "renderer stage clip height")
expect(byName.restore and calls[#calls].name == "end",
    "renderer did not restore the stage transform before ending the frame")

for _, name in ipairs(nvgNames) do _G[name] = previousNvg[name] end
NVG_ALIGN_LEFT, NVG_ALIGN_TOP = previousAlignLeft, previousAlignTop

local mouse = { x = 1880, y = 100, down = true, pressed = true, released = false }
local inputStub = { mousePosition = mouse }
function inputStub:GetMouseButtonDown() return mouse.down end
function inputStub:GetMouseButtonPress() return mouse.pressed end
function inputStub:GetMouseButtonRelease() return mouse.released end
local pointerContext = {
    design_ = design,
    pointer_ = {
        activeTouchId = nil, touchX = 0, touchY = 0,
        touchPressed = false, touchReleased = false, stagePointerCaptured = nil,
    },
    input = inputStub,
    MOUSEB_LEFT = 1,
}
require("game.input.Pointer").Install(pointerContext)

local outsidePress = pointerContext.PointerState()
expect(not outsidePress.insideStage and not outsidePress.pressed and not outsidePress.down,
    "a pointer press beginning in the background padding reached the stage")

mouse.y, mouse.down, mouse.pressed, mouse.released = 1120, true, true, false
local insidePress = pointerContext.PointerState()
near(insidePress.y, 420, "captured pointer stage coordinate")
expect(insidePress.insideStage and insidePress.pressed and insidePress.down,
    "a pointer press inside the stage was not captured")

mouse.y, mouse.down, mouse.pressed, mouse.released = 100, true, false, false
local outsideDrag = pointerContext.PointerState()
expect(not outsideDrag.insideStage and outsideDrag.down,
    "a stage drag lost capture when crossing into the background padding")

mouse.down, mouse.released = false, true
local outsideRelease = pointerContext.PointerState()
expect(outsideRelease.released and pointerContext.pointer_.stagePointerCaptured == nil,
    "a captured drag could not release outside the stage")

local function touchEvent(id, x, y)
    local values = { TouchID = id, X = x, Y = y }
    return { GetInt = function(_, key) return values[key] end }
end
design:Frame(true)
pointerContext.HandleTouchBegin("TouchBegin", touchEvent(7, 1880, 100))
local outsideTouch = pointerContext.PointerState()
expect(outsideTouch.isTouch and not outsideTouch.insideStage
    and not outsideTouch.pressed and not outsideTouch.down,
    "a touch beginning in the background padding reached the stage")
pointerContext.HandleTouchEnd("TouchEnd", touchEvent(7, 1880, 100))
expect(not pointerContext.PointerState().released,
    "an uncaptured background touch emitted a stage release")

pointerContext.HandleTouchBegin("TouchBegin", touchEvent(8, 1880, 1120))
local insideTouch = pointerContext.PointerState()
expect(insideTouch.isTouch and insideTouch.insideStage and insideTouch.pressed and insideTouch.down,
    "a touch beginning inside the stage was not captured")
pointerContext.HandleTouchMove("TouchMove", touchEvent(8, 1880, 100))
local outsideTouchDrag = pointerContext.PointerState()
expect(not outsideTouchDrag.insideStage and outsideTouchDrag.down,
    "a captured touch drag was lost in the background padding")
pointerContext.HandleTouchEnd("TouchEnd", touchEvent(8, 1880, 100))
expect(pointerContext.PointerState().released and pointerContext.pointer_.stagePointerCaptured == nil,
    "a captured touch could not release outside the stage")

local viewportFrame = design:Frame(false)
mouse.down, mouse.pressed, mouse.released = true, true, false
local viewportPress = pointerContext.PointerState()
expect(not viewportFrame.mainStageActive and viewportPress.insideStage and viewportPress.pressed,
    "non-game viewport input was incorrectly clipped to the main stage")

graphics = previousGraphics
print(string.format('{"mode":"MAIN_STAGE_LAYOUT_CONTRACT","checks":%d,"status":"pass"}', checks))
