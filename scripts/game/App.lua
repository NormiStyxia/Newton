local Config = require("game.Config")
local State = require("game.State")
local LevelData = require("game.level.LevelData")
local LevelDocument = require("game.level.LevelDocument")
local LevelPresentation = require("game.level.Presentation")
local CoordinateMapper = require("game.layout.CoordinateMapper")
local DesignSpace = require("game.layout.DesignSpace")
local WorkspaceLayout = require("game.layout.WorkspaceLayout")
local MatterCalibration = require("game.physics.Calibration")
local PhysicsProfiles = require("game.physics.Profiles")
local PhysicsProbe = require("game.physics.Probe")
local Rules = require("game.gameplay.Rules")
local RuntimeFactory = require("game.level.RuntimeFactory")
local Renderer2D = require("game.render.Canvas")
local SynthAudio = require("game.audio.Audio")
local GlobalBGM = require("game.audio.GlobalBGM")
local TrajectoryPrediction = require("game.physics.Trajectory")
local ReplayTimeline = require("game.replay.Timeline")
local ReplayFeed = require("game.replay.Feed")
local ReplayMode = require("game.replay.Mode")
local PhaseWallEffects = require("game.render.PhaseWallEffects")
local ExperimentProgress = require("game.progress.ExperimentProgress")
local CatalogTransition = require("ui.ExperimentCatalogTransition")

local INSTALLERS = {
    "game.gameplay.Status", "game.replay.Controller", "game.gameplay.RuleController",
    "game.level.LevelSession", "game.physics.System", "game.gameplay.Mechanisms",
    "game.gameplay.Goal", "game.gameplay.Experiment", "game.input.Pointer",
    "game.cards.Controller", "game.input.InteractionRouter", "game.render.WorldView",
    "game.render.ReplayView", "game.render.OverlayView", "game.render.CardView",
    "game.assist_demo.Controller", "game.green_assistant.Controller", "game.dialogue.DialogueController", "ui.result_report",
    "ui.result_report_layout", "game.workshop.Controller", "ui.ExperimentCatalog", "ui.TitleScreen", "game.AppRuntime",
}

local App = {}
App.__index = App

function App.New()
    local dependencies = {
        State = State,
        LevelData = LevelData, LevelDocument = LevelDocument, LevelPresentation = LevelPresentation,
        CoordinateMapper = CoordinateMapper, DesignSpace = DesignSpace,
        WorkspaceLayout = WorkspaceLayout,
        MatterCalibration = MatterCalibration, PhysicsProfiles = PhysicsProfiles, PhysicsProbe = PhysicsProbe,
        Rules = Rules, RuntimeFactory = RuntimeFactory, Renderer2D = Renderer2D, SynthAudio = SynthAudio,
        GlobalBGM = GlobalBGM,
        TrajectoryPrediction = TrajectoryPrediction, ReplayTimeline = ReplayTimeline, ReplayFeed = ReplayFeed,
        ReplayMode = ReplayMode, PhaseWallEffects = PhaseWallEffects, ExperimentProgress = ExperimentProgress,
        CatalogTransition = CatalogTransition,
    }
    local context = State.New(dependencies, Config.LegacyConstants())
    for _, moduleName in ipairs(INSTALLERS) do require(moduleName).Install(context) end
    return setmetatable({ context = context }, App)
end

function App:Start() self.context.Start() end
function App:Stop() self.context.Stop() end
function App:Update(eventType, eventData) self.context.HandleUpdate(eventType, eventData) end
function App:OnPhysicsPreStep(eventType, eventData) self.context.HandlePhysicsPreStep(eventType, eventData) end
function App:OnPhysicsPostStep(eventType, eventData) self.context.HandlePhysicsPostStep(eventType, eventData) end
function App:OnScreenMode() self.context.HandleScreenMode() end
function App:OnFirstAudioGesture(eventType, eventData) self.context.HandleFirstAudioGesture(eventType, eventData) end
function App:OnTouchBegin(eventType, eventData) self.context.HandleTouchBegin(eventType, eventData) end
function App:OnTouchMove(eventType, eventData) self.context.HandleTouchMove(eventType, eventData) end
function App:OnTouchEnd(eventType, eventData) self.context.HandleTouchEnd(eventType, eventData) end
function App:OnTextInput(eventType, eventData) self.context.HandleWorkshopTextInput(eventType, eventData) end
function App:OnContactBegin(eventType, eventData) self.context.HandleCollisionBegin(eventType, eventData) end
function App:OnContactUpdate(eventType, eventData) self.context.HandleCollisionUpdate(eventType, eventData) end
function App:OnContactEnd(eventType, eventData) self.context.HandleCollisionEnd(eventType, eventData) end
function App:Render() self.context.HandleRender() end

return App
