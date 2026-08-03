package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path

local function expect(condition, message)
    if not condition then error(message, 2) end
end

local CompanionController = require("green_assistant.CompanionController")
local WorkspaceLayout = require("game.layout.WorkspaceLayout")
local Rules = require("game.gameplay.Rules")

local randomValues = { 0.5, 0.5, 0.8, 0.25, 0.7, 0.4 }
local randomIndex = 0
local function deterministicRandom()
    randomIndex = randomIndex % #randomValues + 1
    return randomValues[randomIndex]
end

local events = {}
local controller = CompanionController.new({
    random = deterministicRandom,
    config = {
        moveSpeed = 100,
        idleMinDuration = 0.2,
        idleMaxDuration = 0.2,
        minWalkDistance = 20,
        maxWalkDistance = 120,
        characterHalfWidth = 20,
        edgePadding = 5,
        dragThreshold = 8,
        dragHoldDuration = 0.3,
        settleDuration = 0.15,
    },
    onEvent = function(name) events[#events + 1] = name end,
})

local wideZone = { left = 0, right = 500, top = 200, bottom = 280, baselineY = 270, fallbackX = 40 }
expect(controller:setZone(wideZone), "initial CompanionZone was rejected")
expect(controller:getState() == CompanionController.State.IDLE, "Companion must start IDLE")
controller:update(0.21, true)
expect(controller:getState() == CompanionController.State.WALK, "IDLE did not transition to WALK")
expect(controller.facing == CompanionController.Facing.RIGHT, "right walk did not lock RIGHT facing")
expect(controller:getRequestedAnimation() == "walk", "WALK semantic animation missing")

for _ = 1, 100 do controller:update(0.05, true) end
expect(controller:getState() == CompanionController.State.IDLE, "WALK did not finish at its target")
local reachedX = controller.x
expect(controller:moveTo(controller.validMinX), "explicit left walk was rejected")
expect(controller.facing == CompanionController.Facing.LEFT, "left walk did not lock LEFT facing")
controller:update(0.05, true)
expect(controller.facing == CompanionController.Facing.LEFT, "facing changed during one WALK segment")

controller.x = math.max(controller.validMinX + 30, reachedX)
controller:moveTo(controller.validMaxX)
local shrinkZone = { left = 0, right = 260, top = 200, bottom = 280, baselineY = 270, fallbackX = 40 }
controller:setZone(shrinkZone)
expect(controller.x >= controller.validMinX and controller.x <= controller.validMaxX, "zone shrink did not clamp current X")
expect(not controller.targetX or controller.targetX >= controller.validMinX and controller.targetX <= controller.validMaxX,
    "zone shrink left an invalid WALK target")

controller:interrupt("drag-test")
expect(controller:moveTo(controller.validMaxX), "walk could not be started before drag interruption")
local grabbedX, grabbedY = controller.x, controller.y
local pointer = { x = grabbedX + 6, y = grabbedY - 12, down = true, pressed = true, released = false }
local consumed, result = controller:handlePointer(pointer, true)
expect(consumed and result.kind == "press-pending", "pointer down did not create a pending press")
expect(controller:getState() == CompanionController.State.IDLE, "pointer down entered DRAGGING before the hold threshold")
expect(controller.targetX == nil and controller.velocityX == 0 and controller.velocityY == 0,
    "pending press did not interrupt movement target and velocity")
expect(controller.x == grabbedX and controller.y == grabbedY, "pointer down changed the captured UI origin")
expect(controller:getRequestedAnimation() == "idle_base", "pending press incorrectly requested the drag animation")
controller:update(0.29, true)
expect(controller:getState() == CompanionController.State.IDLE, "short press crossed the hold threshold early")
local dragFacing = controller.facing
pointer = { x = pointer.x + 30, y = pointer.y - 25, down = true, pressed = false, released = false }
consumed, result = controller:handlePointer(pointer, false)
expect(consumed and result.kind == "press-pending", "pre-hold pointer movement was not captured")
expect(controller.x == grabbedX and controller.y == grabbedY,
    "pre-hold pointer movement displaced the character")
controller:update(0.02, true)
expect(controller:getState() == CompanionController.State.DRAGGING, "long press did not enter DRAGGING")
expect(controller:getRequestedAnimation() == "drag", "long press did not request the drag animation")
expect(controller.x == grabbedX + 30 and controller.y == grabbedY - 25,
    "long-press slide did not preserve the pointer-to-origin grab offset")
local rigidX, rigidY = controller.x, controller.y
controller:update(0.5, true)
expect(controller.x == rigidX and controller.y == rigidY,
    "autonomy or movement overwrote the active drag position")
local dragZone = { left = 0, right = 250, top = 200, bottom = 280, baselineY = 270, fallbackX = 40 }
controller:setZone(dragZone)
expect(controller.x == rigidX and controller.y == rigidY,
    "layout rewrote the active drag transform before the current pointer sample")
pointer = { x = 999, y = 0, down = true, pressed = false, released = false }
controller:handlePointer(pointer, false)
expect(controller.x == 993 and controller.y == 12, "drag did not preserve the raw out-of-zone pointer position")
expect(controller:getSnapshot().relocating == false, "drag entered relocation before pointer release")
expect(controller.facing == dragFacing, "drag changed the locked facing")
pointer = { x = 999, y = 0, down = false, pressed = false, released = true }
controller:handlePointer(pointer, false)
expect(controller:getState() == CompanionController.State.RELOCATING, "out-of-zone release did not enter RELOCATING")
local returnX, returnY = controller.lastReachableX, controller.lastReachableY
controller:update(1, true)
expect(controller:getState() == CompanionController.State.RELOCATING,
    "autonomy changed position during relocation")
expect(controller:finishRelocation(returnX, returnY), "relocation did not accept the last reachable position")
expect(controller:getState() == CompanionController.State.IDLE
    and controller.x == returnX and controller.y == returnY,
    "relocation did not restore the last reachable position")

local tapOriginX, tapOriginY = controller.x, controller.y
local tapEventStart = #events + 1
pointer = { x = tapOriginX, y = tapOriginY, down = true, pressed = true, released = false }
consumed, result = controller:handlePointer(pointer, true)
expect(consumed and result.kind == "press-pending", "tap did not remain pending until release")
controller:update(0.1, true)
expect(controller:getState() == CompanionController.State.IDLE,
    "tap candidate triggered DRAGGING before release")
pointer = { x = tapOriginX + 2, y = tapOriginY - 2, down = false, pressed = false, released = true }
consumed, result = controller:handlePointer(pointer, true)
expect(consumed and result.kind == "tap", "tap was not preserved separately from drag")
expect(controller:getState() == CompanionController.State.IDLE, "tap release did not restore IDLE")
expect(controller.x == tapOriginX and controller.y == dragZone.baselineY,
    "sub-threshold tap left a drag displacement behind")
for index = tapEventStart, #events do
    expect(events[index] ~= "dragStarted", "tap emitted dragStarted")
end

pointer = { x = tapOriginX, y = tapOriginY, down = true, pressed = true, released = false }
controller:handlePointer(pointer, true)
pointer = { x = tapOriginX + 20, y = tapOriginY, down = true, pressed = false, released = false }
consumed, result = controller:handlePointer(pointer, false)
expect(consumed and result.kind == "press-pending", "early slide was not retained as a pending press")
pointer.down, pointer.released = false, true
consumed, result = controller:handlePointer(pointer, false)
expect(consumed and result.kind == "press-cancelled", "early slide release was misclassified as tap or drag")
expect(controller:getState() == CompanionController.State.IDLE,
    "cancelled pre-hold slide changed the companion state")

local function hotspotController(facing)
    local instance = CompanionController.new({
        facing = facing,
        config = {
            characterHalfWidth = 20,
            edgePadding = 5,
            dragThreshold = 8,
            dragGrabOffsetX = 14,
            dragGrabOffsetY = -174,
            dragGrabSourceFacing = CompanionController.Facing.LEFT,
        },
    })
    instance:setZone({ left = 0, right = 500, top = 0, bottom = 500, baselineY = 400, fallbackX = 100 })
    instance:handlePointer({ x = 200, y = 100, down = true, pressed = true, released = false }, true)
    expect(instance.x == 100 and instance.y == 400,
        "semantic pointer down displaced the companion before the hold threshold")
    instance:update(instance.config.dragHoldDuration, true)
    return instance
end

local leftGrab = hotspotController(CompanionController.Facing.LEFT)
expect(leftGrab.x == 186 and leftGrab.y == 274,
    "LEFT drag did not place the lifted-cloth tip under the pointer immediately")
expect(leftGrab:getSnapshot().dragGrabOffsetX == -14 and leftGrab:getSnapshot().dragGrabOffsetY == 174,
    "LEFT drag did not preserve the rigid root-to-pointer offset")
expect(leftGrab:getSnapshot().usesSemanticGrab, "LEFT drag did not use the semantic hotspot")
leftGrab:handlePointer({ x = -50, y = -50, down = true, pressed = false, released = false }, false)
expect(leftGrab.x == -64 and leftGrab.y == 124 and leftGrab.x + 14 == -50 and leftGrab.y - 174 == -50,
    "drag hotspot did not preserve the raw top-left out-of-zone position")
leftGrab:handlePointer({ x = 999, y = 999, down = true, pressed = false, released = false }, false)
expect(leftGrab.x == 985 and leftGrab.y == 1173 and leftGrab.x + 14 == 999 and leftGrab.y - 174 == 999,
    "drag hotspot did not preserve the raw bottom-right out-of-zone position")
leftGrab:handlePointer({ x = 999, y = 999, down = false, pressed = false, released = true }, false)
expect(leftGrab:getState() == CompanionController.State.RELOCATING,
    "semantic out-of-zone release did not enter RELOCATING")
expect(leftGrab:finishRelocation(leftGrab.lastReachableX, leftGrab.lastReachableY)
    and leftGrab.x == 186 and leftGrab.y == 274,
    "semantic relocation did not restore the last reachable root")
local rightGrab = hotspotController(CompanionController.Facing.RIGHT)
expect(rightGrab.x == 214 and rightGrab.y == 274,
    "RIGHT drag did not mirror the lifted-cloth tip around the foot anchor")
expect(rightGrab:getSnapshot().dragGrabOffsetX == 14,
    "RIGHT drag hotspot X was not mirrored with facing")

local frame = {
    logicalWidth = 1880,
    logicalHeight = 840,
    workspaceX = 24,
    playfieldX = 323,
    playfieldWidth = 1500,
    groundY = 584,
    cardHandY = 719,
}
local previousLeft, previousRight
for _, count in ipairs({ 1, 3, 6, 10 }) do
    local poses = Rules.CardHand(count, frame.playfieldX + frame.playfieldWidth * 0.5, frame.cardHandY, frame.playfieldWidth)
    local zone, bounds = WorkspaceLayout.Apply(frame, poses, 144, 202.064516129)
    expect(bounds and zone.right == math.min(frame.logicalWidth - 18, bounds.left - 32),
        "CompanionZone right is not derived from cardHandBounds.left")
    expect(zone.left == frame.workspaceX and zone.top == frame.groundY and zone.bottom == frame.logicalHeight - 2,
        "CompanionZone drag rectangle is not bounded by workspace, ground, and bottom edges")
    if previousLeft then
        expect(bounds.left < previousLeft, "more cards did not expand cardHandBounds leftward")
        expect(zone.right < previousRight, "more cards did not shrink CompanionZone")
    end
    previousLeft, previousRight = bounds.left, zone.right
end

local emptyZone, emptyBounds = WorkspaceLayout.Apply(frame, {}, 144, 202.064516129)
expect(emptyBounds == nil and emptyZone.right > previousRight, "empty hand fallback did not widen CompanionZone")
expect(frame.cardHandBounds == nil and frame.companionZone == emptyZone, "layout outputs were not attached to frame")

local narrowZone = { left = 0, right = 40, top = 0, bottom = 20, baselineY = 20, walkingAllowed = false, fallbackX = 25 }
controller:setZone(shrinkZone)
controller:moveTo(controller.validMaxX)
controller:setZone(narrowZone)
controller:update(10, true)
expect(controller:getState() == CompanionController.State.IDLE and not controller.walkingAllowed,
    "narrow-zone fallback did not suspend autonomous WALK")

expect(#events > 0, "semantic controller events were not emitted")

randomIndex = 0
local rhythm = CompanionController.new({ random = deterministicRandom })
rhythm:setZone({ left = 0, right = 950, top = 700, bottom = 824, baselineY = 822, fallbackX = 76 })
local idleSeconds, walkSeconds = 0, 0
for _ = 1, 12000 do
    if rhythm:getState() == CompanionController.State.IDLE then
        idleSeconds = idleSeconds + 0.05
    elseif rhythm:getState() == CompanionController.State.WALK then
        walkSeconds = walkSeconds + 0.05
    end
    rhythm:update(0.05, true)
end
local idleRatio = idleSeconds / math.max(0.001, idleSeconds + walkSeconds)
expect(idleRatio >= 0.45 and idleRatio <= 0.55,
    string.format("long-run Idle/Walk rhythm drifted outside the natural range: %.3f", idleRatio))
print("COMPANION_CONTROLLER_SPEC_OK")
