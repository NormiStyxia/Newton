from __future__ import annotations

import hashlib
import json
import math
import re
import struct
from pathlib import Path

from runtime_source_index import all_runtime_source, legacy_main_source


MAKER_ROOT = Path(__file__).resolve().parents[1]
PHASER_ROOT = Path(r"D:\System Files\Download\牛顿\牛顿")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main() -> int:
    errors: list[str] = []

    def expect(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    source_levels = sorted((PHASER_ROOT / "data/levels").glob("*.json"))
    maker_levels = sorted((MAKER_ROOT / "assets/Data/Levels").glob("*.json"))
    expect(source_levels, "source levels are missing")
    expect(
        [path.name for path in maker_levels] == [path.name for path in source_levels],
        "Maker level copy set differs from Phaser source",
    )

    object_types: set[str] = set()
    for source_level in source_levels:
        maker_level = MAKER_ROOT / "assets/Data/Levels" / source_level.name
        expect(maker_level.exists(), f"missing level copy {source_level.name}")
        if not maker_level.exists():
            continue
        expect(sha256(source_level) == sha256(maker_level), f"{source_level.name} copy hash mismatch")

        level = json.loads(maker_level.read_text(encoding="utf-8"))
        expect(level.get("schemaVersion") == 1, f"{source_level.name} schemaVersion must be 1")
        expect(level.get("playfield") == {"width": 1400, "height": 700}, f"{source_level.name} playfield must be 1400x700")
        objects = level.get("objects", [])
        ids = [item.get("id") for item in objects]
        expect(len(ids) == len(set(ids)), f"{source_level.name} object ids must be unique")
        expect(any(item.get("type") == "launcher" for item in objects), f"{source_level.name} launcher missing")
        expect(any(item.get("type") == "goal_sensor" for item in objects), f"{source_level.name} goal sensor missing")

        is_playable_level = source_level.stem[6:].isdigit()
        for item in objects:
            object_types.add(item["type"])
            transform = item["transform"]
            angle = math.radians(transform["rotation"])
            half_width = (
                abs(math.cos(angle)) * transform["width"] / 2
                + abs(math.sin(angle)) * transform["height"] / 2
            )
            half_height = (
                abs(math.sin(angle)) * transform["width"] / 2
                + abs(math.cos(angle)) * transform["height"] / 2
            )
            if is_playable_level:
                expect(
                    transform["x"] - half_width >= 0 and transform["x"] + half_width <= 1400,
                    f"{source_level.name}:{item['id']} x out of bounds",
                )
                expect(
                    transform["y"] - half_height >= 0 and transform["y"] + half_height <= 580,
                    f"{source_level.name}:{item['id']} y out of bounds",
                )
    expect(
        {"wall", "launcher", "goal_sensor", "spring", "button", "door"}.issubset(object_types),
        "level suite does not exercise every supported object type",
    )

    viewport_width, viewport_height, pixels_per_meter = 1500, 596, 100
    samples = [(0, 0), (1400, 700), (146.3513031481672, 467), (726.6581392279712, 493.10993757704875)]
    for level_x, level_y in samples:
        viewport_x = level_x / 1400 * viewport_width
        viewport_y = level_y / 700 * viewport_height
        world_x = (viewport_x - viewport_width / 2) / pixels_per_meter
        world_y = (viewport_height / 2 - viewport_y) / pixels_per_meter
        roundtrip_x = (world_x * pixels_per_meter + viewport_width / 2) / viewport_width * 1400
        roundtrip_y = (viewport_height / 2 - world_y * pixels_per_meter) / viewport_height * 700
        expect(abs(roundtrip_x - level_x) < 1e-9, f"x roundtrip failed at {level_x}")
        expect(abs(roundtrip_y - level_y) < 1e-9, f"y roundtrip failed at {level_y}")

    ground_world_y = (viewport_height / 2 - (580 / 700 * viewport_height)) / pixels_per_meter
    expect(abs(ground_world_y - (-1.9582857142857142)) < 1e-9, "ground mapping changed")

    def source_viewport(width: float, height: float) -> tuple[int, int]:
        base_width, base_height = 1880, 840
        if width / height >= base_width / base_height:
            return round(base_height * width / height), base_height
        return base_width, round(base_width * height / width)

    def source_card_hand_y(viewport_height: float) -> float:
        playfield_bottom = 112 + 596
        ground_y = 112 + 580 / 700 * 596
        compact_bottom = 840 - playfield_bottom
        available = viewport_height - playfield_bottom
        minimum = ground_y + 12 + 202 / 2
        preferred = minimum + 35
        maximum = minimum + 61
        if available <= 292:
            ratio = 292 - compact_bottom
            progress = (available - compact_bottom) / ratio if ratio else 1
            return minimum + (preferred - minimum) * max(0, min(1, progress))
        progress = (available - 292) / (417 - 292)
        return preferred + (maximum - preferred) * max(0, min(1, progress))

    def maker_frame(physical_width: float, physical_height: float, dpr: float) -> tuple[float, float, float, float, float]:
        system_width, system_height = physical_width / dpr, physical_height / dpr
        scale = min(system_width / 1880, system_height / 840)
        logical_width, logical_height = system_width / scale, system_height / scale
        workspace_x = max(24, (logical_width - (250 + 16 + 1500)) * 0.5)
        return scale, logical_width, logical_height, workspace_x, source_card_hand_y(logical_height)

    responsive_samples = [
        (1880, 840, 1),
        (2560, 1080, 1),
        (1080, 1920, 1),
        (3760, 1680, 2),
    ]
    for physical_width, physical_height, dpr in responsive_samples:
        scale, logical_width, logical_height, workspace_x, card_hand_y = maker_frame(physical_width, physical_height, dpr)
        expected_width, expected_height = source_viewport(physical_width / dpr, physical_height / dpr)
        expect(abs(logical_width - expected_width) <= 0.5, f"responsive width mismatch at {physical_width}x{physical_height}@{dpr}")
        expect(abs(logical_height - expected_height) <= 0.5, f"responsive height mismatch at {physical_width}x{physical_height}@{dpr}")
        expect(abs(workspace_x - max(24, (logical_width - 1766) * 0.5)) < 1e-9, f"workspace layout mismatch at {physical_width}x{physical_height}@{dpr}")
        expect(abs(card_hand_y - source_card_hand_y(logical_height)) < 1e-9, f"card hand layout mismatch at {physical_width}x{physical_height}@{dpr}")
        screen_x, screen_y = 937.25 * dpr * scale, 421.5 * dpr * scale
        expect(abs(screen_x / dpr / scale - 937.25) < 1e-9 and abs(screen_y / dpr / scale - 421.5) < 1e-9, f"input inverse mismatch at {physical_width}x{physical_height}@{dpr}")

    manifest = json.loads((MAKER_ROOT / "migration/phase1_asset_manifest.json").read_text(encoding="utf-8"))
    for item in manifest["assets"]:
        derived = MAKER_ROOT / item["derived"]
        expect(derived.exists(), f"missing {item['derived']}")
        expect(sha256(derived) == item["derivedSha256"], f"derived hash mismatch {item['derived']}")
        if "sourceSha256" in item:
            source = Path(item["source"])
            expect(sha256(source) == item["sourceSha256"], f"original SVG changed {item['source']}")
        signature = derived.read_bytes()[:24]
        expect(signature[:8] == bytes.fromhex("89504E470D0A1A0A"), f"not PNG: {item['derived']}")
        width, height = struct.unpack(">II", signature[16:24])
        expect(f"{width}x{height}" == item["size"], f"PNG size mismatch {item['derived']}")
    for item in manifest.get("vectorSources", []):
        source = Path(item["source"])
        expect(source.exists(), f"missing vector source {item['source']}")
        if source.exists():
            expect(sha256(source) == item["sourceSha256"], f"vector source changed {item['source']}")

    audio_manifest_path = MAKER_ROOT / "migration/phase1_audio_manifest.json"
    expect(audio_manifest_path.exists(), "audio manifest missing")
    expected_audio_kinds = {"launch", "card", "impact", "punch", "success", "reset"}
    if audio_manifest_path.exists():
        audio_manifest = json.loads(audio_manifest_path.read_text(encoding="utf-8"))
        synth_source = PHASER_ROOT / "src/game/audio/SynthAudio.ts"
        expect(audio_manifest.get("sourceSha256") == sha256(synth_source), "SynthAudio source hash mismatch")
        audio_assets = {item["kind"]: item for item in audio_manifest.get("assets", [])}
        expect(set(audio_assets) == expected_audio_kinds, "audio asset set differs from original SynthAudio")
        for kind in expected_audio_kinds:
            item = audio_assets.get(kind)
            if not item:
                continue
            derived = MAKER_ROOT / item["derived"]
            expect(derived.exists(), f"missing audio asset {item['derived']}")
            if not derived.exists():
                continue
            expect(sha256(derived) == item["sha256"], f"audio hash mismatch {item['derived']}")
            signature = derived.read_bytes()[:12]
            expect(signature[:4] == b"RIFF" and signature[8:12] == b"WAVE", f"not WAV: {item['derived']}")
            expect(derived.with_suffix(derived.suffix + ".meta").exists(), f"audio meta missing {item['derived']}")

    main_lua = legacy_main_source()
    calibration_lua = (MAKER_ROOT / "scripts/game/physics/Calibration.lua").read_text(encoding="utf-8")
    profiles_lua = (MAKER_ROOT / "scripts/game/physics/Profiles.lua").read_text(encoding="utf-8")
    factory_lua = (MAKER_ROOT / "scripts/game/level/RuntimeFactory.lua").read_text(encoding="utf-8")
    renderer_lua = (MAKER_ROOT / "scripts/game/render/Canvas.lua").read_text(encoding="utf-8")
    renderer_lua += (MAKER_ROOT / "scripts/game/render/WorldPrimitives.lua").read_text(encoding="utf-8")
    design_lua = (MAKER_ROOT / "scripts/game/layout/DesignSpace.lua").read_text(encoding="utf-8")
    workspace_layout_lua = (MAKER_ROOT / "scripts/game/layout/WorkspaceLayout.lua").read_text(encoding="utf-8")
    card_hand_layout_lua = (MAKER_ROOT / "scripts/game/layout/CardHandLayout.lua").read_text(encoding="utf-8")
    companion_controller_lua = (MAKER_ROOT / "scripts/green_assistant/CompanionController.lua").read_text(encoding="utf-8")
    green_assistant_lua = (MAKER_ROOT / "scripts/green_assistant/GreenAssistant.lua").read_text(encoding="utf-8")
    green_assist_config_lua = (MAKER_ROOT / "scripts/green_assistant/GreenAssistConfig.lua").read_text(encoding="utf-8")
    green_assist_view_lua = (MAKER_ROOT / "scripts/green_assistant/GreenAssistView.lua").read_text(encoding="utf-8")
    app_runtime_lua = (MAKER_ROOT / "scripts/game/AppRuntime.lua").read_text(encoding="utf-8")
    synth_audio_lua = (MAKER_ROOT / "scripts/game/audio/Audio.lua").read_text(encoding="utf-8")
    trajectory_lua = (MAKER_ROOT / "scripts/game/physics/Trajectory.lua").read_text(encoding="utf-8")
    replay_timeline_lua = (MAKER_ROOT / "scripts/game/replay/Timeline.lua").read_text(encoding="utf-8")
    replay_feed_lua = (MAKER_ROOT / "scripts/game/replay/Feed.lua").read_text(encoding="utf-8")
    physics_probe_lua = (MAKER_ROOT / "scripts/game/physics/Probe.lua").read_text(encoding="utf-8")
    physics_telemetry_lua = (MAKER_ROOT / "scripts/game/physics/Telemetry.lua").read_text(encoding="utf-8")
    trajectory_contract_py = (MAKER_ROOT / "migration/physics_trajectory_contract.py").read_text(encoding="utf-8")
    rules_lua = (MAKER_ROOT / "scripts/game/gameplay/Rules.lua").read_text(encoding="utf-8")
    all_lua = all_runtime_source()
    portrait_source = PHASER_ROOT / "public/assets/newton-portrait.png"
    portrait_copy = MAKER_ROOT / "assets/image/newton-portrait.png"

    def has_main_function(name: str) -> bool:
        return re.search(rf"^\s*(?:local\s+)?function\s+{re.escape(name)}\s*\(", main_lua, re.M) is not None
    expect(portrait_copy.exists(), "Newton portrait copy missing")
    expect(portrait_source.exists() and sha256(portrait_source) == sha256(portrait_copy), "Newton portrait hash mismatch")

    expect("trigger = trigger == true" in factory_lua, "goal sensor trigger setup missing")
    expect("CollisionCircle2D" in factory_lua and "CollisionBox2D" in factory_lua, "Box2D shapes missing")
    expect("BT_DYNAMIC" in main_lua and "BT_STATIC" in factory_lua, "body state transition missing")
    expect("nvgCreateImage" in renderer_lua and "nvgBeginFrame" in renderer_lua, "NanoVG visual renderer missing")
    expect("image/phase1/apple.png" in renderer_lua and "image/phase1/launcher.png" in renderer_lua, "source-derived sprite loading missing")
    expect("image/newton-portrait.png" in renderer_lua, "Newton portrait loading missing")
    expect("BASE_WIDTH = 1880" in design_lua and "BASE_HEIGHT = 840" in design_lua, "design viewport changed")
    expect("graphics:GetDPR" in design_lua and "renderScale" in design_lua, "DPR-aware design scaling missing")
    expect("source-svg" not in all_lua, "runtime reads original SVG files")
    expect("NoTextureUnlit.xml" not in all_lua and "StaticModel" not in all_lua, "obsolete geometry renderer remains")
    expect("QueueCardResolution" in main_lua and "delay = 55" in main_lua and "duration = 690" in main_lua and "totalDuration = 745" in main_lua, "card burn timeline differs from Phaser")
    expect("nvgScale(painter_.vg, CARD_TEXT_SCALE, CARD_TEXT_SCALE)" in main_lua, "card vector artwork no longer follows the Phaser container scale")
    expect(has_main_function("GoalSensorContainsApple") and has_main_function("RefreshGoalContact"), "goal Sensor overlap fallback missing")
    expect("RefreshGoalContact()\n    UpdateExperiment" in main_lua, "goal Sensor overlap fallback is not evaluated on every physics step")
    expect("BurnProgress" in main_lua and "1 - math.cos(linear * math.pi * .5)" in main_lua and "DrawCardBurnParticles" in main_lua, "card burn easing or particles are missing")
    expect("MoveCardToHandSlot" in main_lua and "duration = .16" in main_lua and "UpdateCardHomeMotions" in main_lua, "live hand reordering tween differs from Phaser")
    expect("SetBulletTimeActive" in main_lua and "CurrentPhysicsTimeScale" in main_lua and "StartReplay" in main_lua, "continuous card bullet time or replay missing")
    expect("game.audio.Audio" in main_lua and "PlaySound(\"launch\")" in main_lua, "launch audio wiring missing")
    expect("PlaySound(\"card\")" in main_lua and "PlaySound(\"impact\")" in main_lua, "card or impact audio wiring missing")
    expect("PlaySound(\"punch\")" in main_lua and "PlaySound(\"success\")" in main_lua, "punch or success audio wiring missing")
    expect("audio/phase1/launch.wav" in synth_audio_lua and "self.elapsedMs - self.lastImpactMs < 80" in synth_audio_lua, "SynthAudio playback or impact gate missing")
    expect("apple_.shape.trigger = false" in main_lua and "object.contactProgress = 0" in main_lua, "success retry does not restore collision state")
    expect("isEditor_" not in main_lua and "EditorController" not in all_lua, "runtime editor remains in Maker build")
    expect(has_main_function("PointerState") and "local pointerFrame = PointerState()" in main_lua
           and "pointerFrame.down, pointerFrame.pressed, pointerFrame.released" in main_lua,
           "input state is not unified")
    expect('SubscribeToEvent("TouchBegin", "HandleTouchBegin")' in main_lua and 'SubscribeToEvent("TouchMove", "HandleTouchMove")' in main_lua and 'SubscribeToEvent("TouchEnd", "HandleTouchEnd")' in main_lua, "touch events are not wired")
    expect("function HandleTouchBegin" in main_lua and "function HandleTouchMove" in main_lua and "function HandleTouchEnd" in main_lua, "touch event handlers are missing")
    expect("activeTouchId" in main_lua and 'eventData:GetInt("TouchID")' in main_lua, "single-touch ownership is missing")
    expect("game.physics.Trajectory" in main_lua and "TrajectoryPrediction.PredictFreeFlight" in main_lua, "source-equivalent trajectory preview is not wired")
    expect("MATTER_BASE_DELTA_MS = 1000 / 60" in trajectory_lua and "input.forceScale * MATTER_BASE_DELTA_MS * MATTER_BASE_DELTA_MS" in trajectory_lua, "trajectory integration scale differs from Phaser")
    expect("velocityX = velocityX * frictionFactor + accelerationX" in trajectory_lua and "if frame % input.sampleEvery == 0" in trajectory_lua, "trajectory integration order differs from Phaser")
    expect(re.search(r"draggedApple_\s*=\s*true\s*\n\s*-- Phaser starts aiming on POINTER_DOWN", main_lua) is not None
           and "UpdateAppleDrag(x, y)" in main_lua,
           "apple aim does not initialize on the same pointer-down frame as Phaser")
    expect("function DrawAim()" in main_lua and "function DrawAimPrediction(preview)" in main_lua and "function DrawCardPrediction()" in main_lua
           and 'activeCardId_ == "side-gravity"' in main_lua and 'activeCardId_ == "mirror-motion"' in main_lua,
           "source-backed aim or parameter-card trajectory previews are missing")
    aim_prediction = main_lua.split("function DrawAimPrediction(preview)", 1)[1].split("function DrawCardPrediction()", 1)[0]
    expect("DrawPrediction(nil, 0.55" in aim_prediction,
           "aim trajectory no longer reuses the source free-flight prediction")
    aim_tether = main_lua.split("function DrawAim()", 1)[1].split("function DrawAimPrediction(preview)", 1)[0]
    expect("DrawAimPrediction(aimPreview_)" in aim_tether,
           "aim tether and trajectory preview are no longer generated from one aim state")
    expect("matterFramesPerSecond = 60" in main_lua and "matterVelocityToWorld" in main_lua, "Matter-to-Box2D velocity conversion missing")
    expect("CONFIG.maxAppleSpeed = 25 * CONFIG.matterVelocityToWorld" in main_lua and has_main_function("CapAppleSpeed"), "source apple speed cap missing")
    expect("PhysicsProfiles.Resolve" in main_lua and "physicsProfile_.gravityAcceleration" in main_lua, "gravity profile is not wired")
    expect("local probeActive = level_.physicsProbe and level_.physicsProbe:IsActive()" in main_lua
           and "if apple_ and apple_.shape and not probeActive then" in main_lua
           and "apple.shape.maskBits = PROBE_CATEGORY" in physics_probe_lua,
           "physics probe does not isolate apple contacts from level fixtures")
    expect("input:GetKeyDown(KEY_CTRL) and input:GetKeyDown(KEY_ALT) and input:GetKeyPress(KEY_T)" in main_lua,
           "physics probe no longer has an explicit development capture trigger")
    expect("self.sampleEveryStep = timeScale <= .05" in physics_telemetry_lua
           and "not self.sampleEveryStep and self.simulationTime + .0001 < self.nextSample" in physics_telemetry_lua,
           "slow-motion physics telemetry no longer records every Box2D post-step")
    expect("envelope.get(\"msg\")" in trajectory_contract_py
           and "def normalise_contact_events" in trajectory_contract_py,
           "Maker JSONL telemetry or contact lifecycle normalization is missing")
    expect("STANDARD_GRAVITY_ACCELERATION" in profiles_lua and "MATTER_BASE_DELTA_MS * MATTER_BASE_DELTA_MS" in profiles_lua, "standard gravity conversion missing")
    expect("INCIDENT_GRAVITY_ACCELERATION" in profiles_lua and "incident_codex_migration_01" in profiles_lua, "incident gravity profile missing")
    expect("CreateLaboratoryBoundaries" in factory_lua and "world-ceiling" in factory_lua and "world-left" in factory_lua and "world-right" in factory_lua, "laboratory boundaries are incomplete")
    expect("DEFAULT_GRAVITY_MAGNITUDE = 1.05" in rules_lua and "function Rules.GetGravityMultiplier" in rules_lua, "source gravity magnitude or button multiplier missing")
    expect("APPLE_FRICTION_AIR = 0.01" in calibration_lua and "Box2DLinearDamping" in calibration_lua, "effective Matter air friction is not calibrated")
    expect("APPLE_FRICTION_STATIC = 0.5" in calibration_lua and "MATTER_FRICTION_NORMAL_MULTIPLIER = 5" in calibration_lua and "MATTER_RESTING_TANGENT_SPEED" in calibration_lua, "Matter static-friction thresholds are not calibrated")
    expect("MatterCalibration.APPLE_FRICTION" in factory_lua and "MatterCalibration.STATIC_RESTITUTION" in factory_lua, "effective Matter fixture materials are not calibrated")
    expect("UpdateMatterStaticFriction" not in main_lua and "TrackApplePhysicalContact" not in main_lua and "AppleFixtureFrictionForMatterStaticContact" not in main_lua, "Box2D still mutates the apple fixture to fake Matter static friction")
    expect("apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping" in main_lua, "Matter frictionAir is not applied to angular motion")
    expect('SubscribeToEvent("PhysicsPreStep", "HandlePhysicsPreStep")' in main_lua and 'SubscribeToEvent("PhysicsPostStep", "HandlePhysicsPostStep")' in main_lua, "physics step event wiring missing")
    expect("applePreSolveVelocity_" in main_lua and "local v = applePreSolveVelocity_ or apple_.body.linearVelocity" in main_lua, "spring does not retain pre-solve velocity")
    expect("object.impulseStrength * Rules.GetGravityMultiplier(rules_, level_.rules.initialGravity)" in main_lua
           and "* CurrentMatterVelocityToWorld()" in main_lua,
           "spring impulse no longer follows the source gravity multiplier")
    expect("CapAppleSpeed()\n    apple_.body.linearDamping" in main_lua, "speed cap is not applied before the physics pass")
    expect("UpdateSpringExits()\n    RefreshGoalContact()\n    UpdateExperiment(eventData:GetFloat(\"TimeStep\") * CurrentPhysicsTimeScale())" in main_lua, "physics post-step timing differs from source bullet time")
    expect("uiElapsed_ * 1000 - object.triggeredAt" in main_lua and "uiElapsed_ * 1000 >= object.closeAt" in main_lua, "scene-time cooldown or door delay differs from source")
    expect("if #trail_ > 18" in main_lua and "flightMs_ - lastTrailAt_ > 55" in main_lua and "DrawVelocityArrow" in main_lua, "trail or velocity visualization differs from Phaser")
    expect("input:GetMouseButtonPress(MOUSEB_RIGHT)" in main_lua and "input:GetKeyPress(KEY_ESCAPE)" in main_lua and "ToggleTacticalPause" in main_lua, "source keyboard or cancel interaction is missing")
    expect("replayNextSampleMs_" in main_lua and "while replayNextSampleMs_ <= flightMs_ + .0001 do" in main_lua, "replay no longer interpolates at the source sample cadence")
    expect("replayPreviousSample_" in main_lua and "deltaAngle = ((current.angle - previous.angle + 540) % 360) - 180" in main_lua, "replay angle interpolation differs from Phaser")
    replay_update = main_lua.split("function UpdateReplay(dt)", 1)[1].split("function RegisterFailure()", 1)[0]
    expect("math.max(0, dt) * 1000 * replaySpeed_" in replay_update
           and "replaySpeed_ = .5" in main_lua and "replaySpeed_ = 1" in main_lua and "replaySpeed_ = 2" in main_lua,
           "replay speed no longer advances the original recorded timeline at 0.5x/1x/2x")
    expect("game.replay.Timeline" in main_lua and "ReplayTimeline.SamplesThrough(replaySamples_, replayTime_)" in main_lua,
           "replay rendering does not share the source timeline contract")
    expect("function ReplayTimeline.StateAt" in replay_timeline_lua and "while low + 1 < high" in replay_timeline_lua
           and "function ReplayTimeline.SamplesThrough" in replay_timeline_lua,
           "replay timeline interpolation or visible-sample contract is missing")
    expect("game.replay.Feed" in main_lua and "ReplayFeed.Items(replayEvents_, replayTime_, Rules.CARDS)" in main_lua,
           "replay rule feed does not use the source-equivalent state model")
    expect("INSTANT_ACTIVE_MS = 1400" in replay_feed_lua and 'event.type == "RULE_REMOVED"' in replay_feed_lua
           and 'event.type == "NEWTON_PUNCH"' in replay_feed_lua,
           "replay rule-feed persistence and removal states are missing")
    expect('RecordReplayEvent("RULE_REMOVED", "quantum-phase")' in main_lua and "local removedRules = {}" in main_lua,
           "replay does not record phase or Newton rule removals")
    expect("frictionAir = apple_.baseFrictionAir or MatterCalibration.APPLE_FRICTION_AIR" in main_lua,
           "trajectory preview does not read the apple's current air-friction material")
    render_loop = main_lua.split("function HandleRender()", 1)[1]
    expect(render_loop.index("DrawPlayfieldOverlay()") < render_loop.index("DrawPauseShade()")
           < render_loop.index("DrawCards(nil, 71.999, true)")
           < render_loop.index("DrawPauseStatus()") < render_loop.index("DrawCardParameterSelector()")
           < render_loop.index("DrawCards(72, nil, false)"),
           "pause shade, cards, pause status, selector, and active cards no longer follow Phaser depth bands")
    pause_overlay = main_lua.split("function DrawPauseShade()", 1)[1].split("function DrawPauseStatus()", 1)[0]
    expect("实验暂停 · 规则卡可操作" not in pause_overlay,
           "pause label is drawn with the depth-53 shade instead of at Phaser depth 67")
    expect(render_loop.index("DrawAim()") < render_loop.index("painter_:DrawApple"),
           "aim tether is not drawn above the shared trajectory preview and below the apple")
    expect(render_loop.index("DrawCards(72, nil, false)") < render_loop.index("if replayActive_ then DrawReplay() end"),
           "replay trajectory and controls no longer render above the gameplay HUD and cards")
    expect(has_main_function("IsResultOverlayVisible") and 'if replayMode_ ~= "none" then return end' in main_lua, "replay does not hide the completed-result overlay")
    expect("if replayActive_ then" in main_lua
           and "if replayBusinessMode_ == ReplayMode.PLAYER_REPLAY then HandleReplayPointer(x, y, press) end" in main_lua,
           "player replay controls do not retain pointer priority over result controls")
    expect("ReplayMode.PLAYER_REPLAY" in main_lua and "ReplayMode.ASSIST_TAKEOVER" in main_lua,
           "player replay and assist takeover do not have separate business modes")
    expect("SetReplayMode(\"playing\")" in main_lua and "level_.resultOverlayVisible = false" in main_lua and "SyncPhysicsUpdateEnabled()" in main_lua, "replay does not take exclusive ownership of outcome UI and physics")
    replay_start = main_lua.split("StartReplay = function()", 1)[1].split("StopReplay = function()", 1)[0]
    expect("replayOutcome_" not in main_lua and "success_ = false" not in replay_start and "failed_ = false" not in replay_start,
           "replay must retain the completed result while its mode suppresses the overlay")

    # Card interactions must use the same visual transform for painting and
    # hit testing. Parameter cards resolve at their settled anchor, not where
    # the pointer happened to be released.
    expect(has_main_function("CardVisualPose") and "local pose = CardVisualPose(card.cardId, poses[i])" in main_lua,
           "card draw and hit testing do not share one visual transform")
    expect("local deployment = needsParameter and cardParameterStart_" in main_lua
           and "QueueCardResolution(id, deployment.x, deployment.y, candidate" in main_lua,
           "parameter card burn still resolves at the release point")
    expect("AnimateCardToHome(previous, PrimedCardPose(previous), .12)" in main_lua
           and "AnimateCardToHome(id, from, .18)" in main_lua,
           "primed or cancelled cards do not restore with Phaser timing")
    expect("CARD_DESIGN_WIDTH = 124" in main_lua
           and "CARD_DESIGN_HEIGHT = 174" in main_lua
           and "CARD_TEXT_SCALE = 144 / CARD_DESIGN_WIDTH" in main_lua
           and "hasCandidate and .58" in main_lua
           and "local function clamp(value, minimum, maximum)" in main_lua,
           "card content scaling or parameter selector feedback differs from Phaser")
    expect("absorbing_" in main_lua and "absorbElapsedMs_ = math.min(520" in main_lua and "absorbElapsedMs_ >= 520" in main_lua, "success absorption timing differs from Phaser")
    expect("function Renderer:DrawApple(frame, apple, scale, alpha, design)" in renderer_lua
           and "1 - absorbProgress * .65" in main_lua, "success absorption visual differs from Phaser")
    expect("goalPulseElapsedMs_" in main_lua and "goalPulseElapsedMs_ / 460" in main_lua, "goal pulse timing differs from Phaser")
    expect("state.goalPulseProgress" in renderer_lua and "1 + progress * .22" in renderer_lua, "goal pulse expansion differs from Phaser")
    expect("glass = { 216, 214, 232, 255 }" in renderer_lua and "glassEdge = { 128, 118, 181, 255 }" in renderer_lua, "phase wall palette differs from LightLabTheme")
    expect("object.phaseable and COLORS.glass" in renderer_lua and "object.phaseable and COLORS.glassEdge" in renderer_lua, "phase wall does not use the source glass palette")
    expect("darkPrimary = { 47, 73, 56, 255 }" in renderer_lua, "darkPrimary palette differs from LightLabTheme")
    expect("COLORS.darkPrimary, 4" in renderer_lua and "f[7] and COLORS.darkPrimary" in renderer_lua, "playfield or formula strong color differs from LightLabTheme")
    expect("fieldCardBorder = { 142, 175, 114, 255 }" in renderer_lua, "field card border differs from LightLabTheme")
    expect("decisionCardSurface = { 249, 222, 121, 255 }" in renderer_lua and "decisionCardBorder = { 208, 181, 86, 255 }" in renderer_lua, "decision card palette differs from LightLabTheme")
    expect("decisionCardText = { 73, 63, 39, 255 }" in renderer_lua and "decisionCardBody = { 101, 90, 52, 255 }" in renderer_lua, "decision card typography palette differs from LightLabTheme")
    expect("Renderer2D.COLORS.fieldCardSurface" in main_lua and "Renderer2D.COLORS.decisionCardSurface" in main_lua, "rule cards do not use source-specific surfaces")
    expect("function Renderer:DrawCardSymbol" in renderer_lua and "painter_:DrawCardSymbol(id, 0, 7, titleColor)" in main_lua,
           "card symbols still depend on unavailable browser fallback glyphs")
    expect("function Renderer:DrawNavigationIcon" in renderer_lua and "painter_:DrawNavigationIcon" in main_lua,
           "navigation icons still depend on unavailable browser fallback glyphs")
    expect("function Renderer:DrawFist" in renderer_lua and "nvgBezierTo(self.vg, 102, 41, 115, 48, 110, 58)" in renderer_lua, "fist.svg vector path is not reproduced")
    expect("painter_:DrawFist(cx, cy - 5, 46" in main_lua, "Newton ability does not render the source fist.svg")
    expect("painter_:Text(cx, cy - 16" not in main_lua and "tabStartX = frame_.playfieldX + frame_.playfieldWidth - 290" in main_lua, "obsolete fist placeholder or level-tab input remains")
    expect("object.pulseElapsedMs = 0" in main_lua and "UpdateSpringVisuals(dt)" in main_lua, "spring trigger animation is missing")
    expect("nvgScale(self.vg, 1 - compression * .12, 1 - compression * .28)" in renderer_lua, "spring compression visual differs from Phaser")
    expect("function Rules.CanPunch(state)" in rules_lua and "if not Rules.CanPunch(state) then return false end" in rules_lua, "Newton ability eligibility differs from the Phaser runtime")
    expect(any(item.get("source", "").endswith("fist.svg") for item in manifest.get("vectorSources", [])), "fist.svg source hash is not recorded")
    expect("frame_.playfieldWidth - 98" in main_lua and "frame_.cardHandY - 17" in main_lua, "Newton ability hit target differs from the original 80px container")
    expect("depth = 54 + (1 - normalized) * 4" in rules_lua, "card hand depth differs from CardHandLayout")
    expect("CardHandLayout.Bounds" in workspace_layout_lua
           and "bounds.left - config.cardSafeGap" in workspace_layout_lua
           and "frame.companionZone = companionZone" in workspace_layout_lua,
           "layout does not derive CompanionZone from nominal cardHandBounds")
    expect("RotatedHalfExtents" in card_hand_layout_lua and "pose.angle" in card_hand_layout_lua,
           "cardHandBounds does not include rotated visual geometry")
    expect('IDLE = "IDLE"' in companion_controller_lua
           and 'WALK = "WALK"' in companion_controller_lua
           and 'DRAGGING = "DRAGGING"' in companion_controller_lua,
           "portable CompanionController states are incomplete")
    expect("pointerCandidate" in companion_controller_lua
           and "dragThreshold" in companion_controller_lua
           and "settleDuration" in companion_controller_lua
           and "pointerX + candidate.grabOffsetX" in companion_controller_lua
           and "function Controller:_captureGrabOffset" in companion_controller_lua,
           "immediate rigid drag or tap/settle flow is missing")
    expect("local function ConfigureDragGrab" in green_assistant_lua
           and "semanticAnchors.dragGrab" in green_assistant_lua
           and "ConfigureDragGrab(self.config)" in green_assistant_lua,
           "drag animation hotspot is not converted into a fixed screen-space grab offset")
    expect("CardHand" not in companion_controller_lua
           and "Matter" not in companion_controller_lua
           and "Tween" not in companion_controller_lua
           and "nvg" not in companion_controller_lua,
           "CompanionController is coupled to host layout, physics, tween, or renderer")
    expect('sourceFacing = "LEFT"' in green_assist_config_lua
           and 'self.flipX = (facingRight == true) ~= sourceFacesRight' in green_assist_view_lua,
           "Companion sprite facing is not derived from the left-facing source asset")
    runtime_update = app_runtime_lua.split("function HandleUpdate", 1)[1].split("function HandleScreenMode", 1)[0]
    expect(runtime_update.index("RefreshWorkspaceLayout()")
           < runtime_update.index("local pointerFrame = PointerState()")
           < runtime_update.index("HandleGreenAssistantPointer(pointerFrame.x, pointerFrame.y, pointerFrame)")
           < runtime_update.index("UpdateGreenAssistant(dt)"),
           "Companion input is not applied after layout and before animation/update")
    expect(has_main_function("UpdateCardHoverStates") and has_main_function("FindTopCardAt"), "card hover or depth-aware hit testing is missing")
    expect("failureCountsByLevel_" in main_lua and has_main_function("RegisterFailure"), "failure counts are not isolated per level")
    expect("activeCardPressPose_" in main_lua and "visual.x, visual.y = pressPose.x, pressPose.y" in main_lua,
           "a direct card press no longer preserves its actual rendered pose")
    expect("function CardBadgeText" in main_lua and "停稳后选方向" in main_lua and "松手确认" in main_lua and "燃烧" in main_lua,
           "card interaction states are not reflected by the status badge")
    expect("nvgTextBounds(painter_.vg, 0, 0, value)" in main_lua and "local right = 51 * CARD_TEXT_SCALE" in main_lua,
           "card badge sizing or description text geometry differs from Phaser scaling")
    expect("local clipPoints" in main_lua and "DrawCardSurface(burn.id, def, card, cardState, \"燃烧\", true, false)" in main_lua
           and "startScale" in main_lua,
           "card burn does not preserve the jagged mask and active face")
    expect("function StartRuleFeedback" in main_lua and "function DrawRulePulse" in main_lua and "function DrawRuleFlash" in main_lua,
           "card resolution feedback layers are missing")
    expect(render_loop.index("DrawPlayfieldOverlay()") < render_loop.index("DrawPauseShade()")
           < render_loop.index("DrawPauseStatus()")
           < render_loop.index("DrawRulePulse()"),
           "rule pulse must render above the pause and bullet-time overlay")
    expect(render_loop.index("DrawCards(nil, 71.999, true)") < render_loop.index("DrawPauseStatus()")
           < render_loop.index("DrawCardParameterSelector()") < render_loop.index("DrawCards(72, nil, false)"),
           "parameter selector must remain between normal and active card depth bands")
    expect("Renderer2D.COLORS.greenSoft, nil, nil, 46" in main_lua and "Renderer2D.COLORS.primaryActive, 3, 179" in main_lua,
           "bullet-time fill and border alphas are not independently calibrated")
    expect("observation_ = \"苹果已在爱因斯坦观察窗内稳定停留。\"" in main_lua and "function Renderer:DrawNewton(frame, level, anger, observation)" in renderer_lua, "runtime observation state differs from Phaser")
    expect('SubscribeToEvent("PhysicsUpdateContact2D", "HandleCollisionUpdate")' in main_lua
           and has_main_function("ActivateGoalContact") and has_main_function("HandleCollisionUpdate"),
           "goal Sensor does not subscribe to continuous Box2D contact updates")
    expect("ActivateGoalContact(nodeA, nodeB, true)" in main_lua and "ActivateGoalContact(nodeA, nodeB, false)" in main_lua
           and "goalContactMs_ = math.max(1, goalContactMs_)" in main_lua,
           "goal Sensor enter/update lifecycle does not preserve a single active stay timer")
    expect("if recordEntry and not goalEntryRecorded_ then" in main_lua and "goalEntryRecorded_ = false" in main_lua
           and "RecordReplayEvent(\"GOAL_ENTER\")" in main_lua
           and "if goalContactMs_ >= requiredStayTime and matterSpeed <= 4.8 then" in main_lua,
           "goal Sensor does not enforce one enter event and the source completion threshold")

    result = {
        "mode": "FAST_VALIDATE",
        "checks": 165,
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }
    print(json.dumps(result, ensure_ascii=False))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
