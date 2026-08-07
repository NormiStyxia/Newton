local App = require("game.App")

local app = App.New()

function Start() app:Start() end
function Stop() app:Stop() end
function HandleUpdate(eventType, eventData) app:Update(eventType, eventData) end
function HandlePhysicsPreStep(eventType, eventData) app:OnPhysicsPreStep(eventType, eventData) end
function HandlePhysicsPostStep(eventType, eventData) app:OnPhysicsPostStep(eventType, eventData) end
function HandleScreenMode() app:OnScreenMode() end
function HandleFirstAudioGesture(eventType, eventData) app:OnFirstAudioGesture(eventType, eventData) end
function HandleTouchBegin(eventType, eventData) app:OnTouchBegin(eventType, eventData) end
function HandleTouchMove(eventType, eventData) app:OnTouchMove(eventType, eventData) end
function HandleTouchEnd(eventType, eventData) app:OnTouchEnd(eventType, eventData) end
function HandleTextInput(eventType, eventData) app:OnTextInput(eventType, eventData) end
function HandleCollisionBegin(eventType, eventData) app:OnContactBegin(eventType, eventData) end
function HandleCollisionUpdate(eventType, eventData) app:OnContactUpdate(eventType, eventData) end
function HandleCollisionEnd(eventType, eventData) app:OnContactEnd(eventType, eventData) end
function HandleRender() app:Render() end
