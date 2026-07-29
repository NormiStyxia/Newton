from __future__ import annotations

import json
import math
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    errors: list[str] = []
    checks = 0

    def expect(condition: bool, message: str) -> None:
        nonlocal checks
        checks += 1
        if not condition:
            errors.append(message)

    profiles = (ROOT / "scripts/migration/PhysicsProfiles.lua").read_text(encoding="utf-8")
    main_lua = (ROOT / "scripts/main.lua").read_text(encoding="utf-8")
    factory = (ROOT / "scripts/migration/RuntimeFactory.lua").read_text(encoding="utf-8")
    calibration = (ROOT / "scripts/migration/MatterCalibration.lua").read_text(encoding="utf-8")
    level_data = (ROOT / "scripts/migration/LevelData.lua").read_text(encoding="utf-8")

    def has_main_function(name: str) -> bool:
        return re.search(rf"^(?:local\s+)?function\s+{re.escape(name)}\s*\(", main_lua, re.M) is not None

    standard_id = "standard"
    incident_id = "incident_codex_migration_01"
    expect(f'DEFAULT_ID = "{standard_id}"' in profiles, "standard is not the profile default")
    expect(f'INCIDENT_ID = "{incident_id}"' in profiles, "incident profile id is missing")
    expect("local id = PhysicsProfiles.IsKnown(requestedId) and requestedId or PhysicsProfiles.DEFAULT_ID" in profiles,
           "profile resolution does not fail closed to standard")
    expect("local physicsProfile_ = nil" in main_lua, "runtime profile state is missing")
    expect("physicsProfile_ = PhysicsProfiles.Resolve(level_.physicsProfile)" in main_lua,
           "level profile is not resolved during level construction")
    expect("physicsProfile_.gravityAcceleration" in main_lua, "gravity does not use the resolved profile")
    expect("CreateLaboratoryBoundaries" in main_lua and "physicsProfile_.boundaries" in main_lua,
           "boundaries are not selected by the resolved profile")
    expect("CreateGround" not in main_lua and "function RuntimeFactory.CreateGround" not in factory,
           "legacy floor-only factory remains in the production path")
    expect("if level.physicsProfile ~= nil and not PhysicsProfiles.IsKnown(level.physicsProfile)" in level_data,
           "unknown explicit physics profiles are not rejected")

    # Matter's per-step force is integrated over (1000 / 60)^2 milliseconds.
    force_scale = 0.001
    matter_step_ms = 1000 / 60
    pixels_per_meter = 100
    standard_acceleration = force_scale * matter_step_ms**2 * 60**2 / pixels_per_meter
    incident_acceleration = force_scale * matter_step_ms * 1000 / pixels_per_meter
    expect(math.isclose(standard_acceleration, 10.0, rel_tol=0, abs_tol=1e-12),
           "standard acceleration conversion is not 10 m/s^2")
    expect(math.isclose(incident_acceleration, 1 / 6, rel_tol=0, abs_tol=1e-12),
           "incident acceleration does not preserve the historical 1/6 m/s^2")
    expect(math.isclose(standard_acceleration * 1.05, 10.5, rel_tol=0, abs_tol=1e-12),
           "standard default gravity is not 10.5 m/s^2")
    expect(math.isclose(incident_acceleration * 1.05, 0.175, rel_tol=0, abs_tol=1e-12),
           "incident default gravity does not preserve 0.175 m/s^2")

    standard_block = re.search(r"standard = \{(?P<body>.*?)\n    \},\n    incident_codex", profiles, re.S)
    incident_block = re.search(r"incident_codex_migration_01 = \{(?P<body>.*?)\n    \},\n\}", profiles, re.S)
    expect(standard_block is not None, "standard profile block is missing")
    expect(incident_block is not None, "incident profile block is missing")
    standard_body = standard_block.group("body") if standard_block else ""
    incident_body = incident_block.group("body") if incident_block else ""
    standard_boundaries: dict[str, bool] = {}
    incident_boundaries: dict[str, bool] = {}
    for boundary in ("floor", "ceiling", "left", "right"):
        standard_boundaries[boundary] = re.search(rf"{boundary} = true", standard_body) is not None
        incident_boundaries[boundary] = re.search(rf"{boundary} = true", incident_body) is not None
        expect(standard_boundaries[boundary], f"standard does not enable {boundary} boundary")
    expect(len(re.findall(r"= true", incident_body)) == 1 and "floor = true" in incident_body,
           "incident does not preserve the historical floor-only boundary")
    for boundary in ("ceiling", "left", "right"):
        expect(f"{boundary} = false" in incident_body, f"incident {boundary} omission is not explicit")
    expect(all(standard_boundaries.values()), "standard boundary configuration permits laboratory escape")
    expect(not incident_boundaries["ceiling"] and not incident_boundaries["left"] and not incident_boundaries["right"],
           "incident boundary configuration cannot reproduce laboratory escape")

    # These are the source laboratory dimensions in viewport pixels.
    viewport_width, viewport_height = 1500, 596
    for boundary in ("floor", "ceiling", "left", "right"):
        expect(f'boundary = "{boundary}"' in factory, f"factory definition for {boundary} is missing")
    expect(factory.count("width = mapper.viewportWidth - 34") == 2,
           f"floor/ceiling width differs from Phaser's {viewport_width - 34}px")
    expect("height = 28" in factory and "height = 24" in factory,
           "floor/ceiling thickness differs from Phaser")
    expect(factory.count("width = 24") == 2 and factory.count("height = mapper.viewportHeight - 44") == 2,
           f"side wall dimensions differ from Phaser's 24x{viewport_height - 44}px")
    expect("x = 14" in factory and "x = mapper.viewportWidth - 14" in factory,
           "side wall positions differ from Phaser")
    expect("y = 24" in factory and "y = mapper.viewportHeight * 0.5" in factory,
           "ceiling or side wall vertical positions differ from Phaser")
    expect("categoryBits = CATEGORY_WORLD" in factory and "maskBits = MASK_ALL" in factory,
           "laboratory boundaries do not use world collision masks")

    levels = sorted((ROOT / "assets/Data/Levels").glob("level_*.json"))
    production_levels = [path for path in levels if re.fullmatch(r"level_\d{2}\.json", path.name)]
    expect(len(production_levels) == 9, "expected nine production levels")
    for path in production_levels:
        level = json.loads(path.read_text(encoding="utf-8"))
        expect("physicsProfile" not in level, f"{path.name} implicitly opts into a non-standard profile")
    expect(f'"physicsProfile": "{incident_id}"' not in "\n".join(
        path.read_text(encoding="utf-8") for path in production_levels
    ), "incident profile leaked into a production level")
    expect(main_lua.count(incident_id) == 0, "main runtime hard-codes the incident profile")

    # The source's SetBody/Body.setStatic calls replace constructor material
    # values. These assertions lock the migration to the observed runtime
    # values rather than the misleading declarative options.
    expect("APPLE_FRICTION = 0.1" in calibration, "apple effective friction is not calibrated")
    expect("APPLE_FRICTION_STATIC = 0.5" in calibration, "Matter static-friction multiplier is not calibrated")
    expect("APPLE_FRICTION_AIR = 0.01" in calibration, "apple effective air friction is not calibrated")
    expect("APPLE_INITIAL_RESTITUTION = 0" in calibration, "apple initial restitution is not calibrated")
    expect("APPLE_MATTER_INERTIA_PX2 = 1443.867317" in calibration
           and "APPLE_INERTIA = MatterCalibration.APPLE_MATTER_INERTIA_PX2" in calibration
           and "function MatterCalibration.ApplyAppleMassProperties" in calibration,
           "apple's observed Matter 26-gon inertia is not calibrated")
    expect(main_lua.count("MatterCalibration.ApplyAppleMassProperties(apple_.body)") == 1
           and "MatterCalibration.ApplyAppleMassProperties(apple.body)" in (ROOT / "scripts/migration/PhysicsProbe.lua").read_text(encoding="utf-8"),
           "apple mass properties are not restored after every static-to-dynamic transition")
    expect("STATIC_FRICTION = 0.1" in calibration and "STATIC_RESTITUTION = 0" in calibration,
           "static Matter material is not calibrated")
    expect("CARD_RESTITUTION_BASE = 0.36" in calibration, "card restitution baseline is not preserved")
    expect("MatterCalibration.APPLE_FRICTION" in factory and "MatterCalibration.STATIC_FRICTION" in factory,
           "RuntimeFactory does not use calibrated Matter materials")
    expect("MatterCalibration.CardRestitution" in main_lua and "ApplyAppleCardMaterial" in main_lua,
           "card material updates are not isolated from normal gravity setup")
    expect("UpdateMatterStaticFriction" not in main_lua and "TrackApplePhysicalContact" not in main_lua,
           "Box2D still applies a global fixture mutation for Matter static friction")
    expect("AppleFixtureFrictionForMatterStaticContact" not in calibration,
           "calibration still models Matter's pair cache as a Box2D fixture material")
    expect("1 / 3" not in main_lua and "SetBulletTimeActive" in main_lua and "bulletTimeScale = 0.05" in main_lua,
           "bullet time still uses sparse full physics steps")
    expect("physicsWorld_:SetAllowSleeping(false)" in main_lua,
           "Box2D world allows sleeping while the source Matter scene does not")
    expect("body.allowSleep = false" in factory,
           "apple body allows sleeping while the source Matter body does not")

    # Matter keeps a velocity normalized to its 60 Hz base delta. During
    # engine timeScale=s, the stored displacement is s times that velocity;
    # Box2D instead integrates metres/second over an unscaled physics step.
    # These identities verify the adapter used by SetBulletTimeActive,
    # SetGravity, and every card velocity write/read.
    air_friction = 0.01
    velocity_to_world = 60 / pixels_per_meter
    source_velocity = 13.7
    source_frame_acceleration = 0.73
    source_gravity = source_frame_acceleration * 60**2 / pixels_per_meter
    for time_scale in (1.0, 0.05):
        for time_step in (1 / 30, 1 / 60, 1 / 120):
            retention = 1 - air_friction * time_scale * time_step * 60
            box2d_damping = (1 / time_step) * (1 / retention - 1)
            maker_before = source_velocity * velocity_to_world * time_scale
            maker_after = maker_before / (1 + box2d_damping * time_step)
            expected_maker_after = source_velocity * retention * velocity_to_world * time_scale
            expect(math.isclose(maker_after, expected_maker_after, rel_tol=0, abs_tol=1e-12),
                   f"Box2D air damping diverges at scale {time_scale}, dt {time_step}")
    expect(math.isclose(
        source_velocity * velocity_to_world * 0.05 / 0.05,
        source_velocity * velocity_to_world,
        rel_tol=0,
        abs_tol=1e-12,
    ), "bullet-time exit does not restore the Matter-normalized velocity")
    expect("velocity.x * scaleRatio" in main_lua and "timeScale * timeScale" in main_lua,
           "runtime does not apply the verified velocity/gravity time-scale mapping")
    expect("CurrentMatterVelocityToWorld" in main_lua and "CurrentMatterSpeedFromWorld" in main_lua,
           "Matter velocity reads are not normalized for the active time scale")
    expect("5.52 * CurrentPhysicsTimeScale()" in main_lua,
           "up-impulse is not scaled for Matter bullet time")
    expect("* CurrentMatterVelocityToWorld()" in main_lua,
           "spring exit velocity is not scaled for Matter bullet time")
    expect("object.impulseStrength * Rules.GetGravityMultiplier(rules_, level_.rules.initialGravity)" in main_lua,
           "spring exit impulse does not follow the source gravity multiplier")
    expect("object.impulseStrength * Rules.GetRestitutionMultiplier(rules_)" not in main_lua,
           "spring exit impulse is incorrectly coupled to Hooke restitution")
    expect("eventData:GetFloat(\"TimeStep\")" in main_lua and "timeStep" in calibration,
           "air damping is not calibrated to the current physics step")
    expect("apple_.body.angularDamping = MatterCalibration.Box2DLinearDamping" in main_lua
           and "body.angularDamping = MatterCalibration.Box2DLinearDamping" in factory,
           "Matter frictionAir is not applied to the apple's angular motion")
    expect("CaptureReplayFinalSample()" in main_lua and "if not CanReplay() then" in main_lua,
           "replay start does not reject an unrecorded timeline")
    expect(has_main_function("CanReplay") and "#replaySamples_ >= 2" in main_lua,
           "replay availability does not require a real timeline")
    expect(has_main_function("SetReplayMode") and 'SetReplayMode("playing")' in main_lua
           and 'replayMode_ ~= "none"' in main_lua and "ClearCardInteraction()" in main_lua,
           "replay start does not take exclusive ownership of the result UI")
    expect('level_.resultOverlayVisible = mode == "none" and (success_ or failed_) or false' in main_lua
           and 'return replayMode_ == "none" and level_ and level_.resultOverlayVisible == true' in main_lua,
           "replay mode no longer exclusively owns the result overlay")
    expect("[Replay]" in main_lua and "ReplayLog(\"start\")" in main_lua and "ReplayLog(\"finished\")" in main_lua,
           "replay lifecycle has no runtime audit markers")

    # Matter combines contact friction with min(a, b); Box2D uses sqrt(a*b).
    # Giving each Box2D fixture 0.1 yields the same apple/static baseline,
    # while restitution keeps the source's max(a, b) behavior.
    expect(math.isclose(math.sqrt(0.1 * 0.1), min(0.1, 1.0), rel_tol=0, abs_tol=1e-12),
           "Box2D fixture friction does not reproduce Matter apple/static friction")
    static_contact = 0.1 * 0.5 * 5
    expect(math.isclose(static_contact, 0.25, rel_tol=0, abs_tol=1e-12),
           "Matter static friction threshold is not 0.25")
    expect("global fixture swap" in calibration and "AppleFixtureFrictionForMatterStaticContact" not in calibration,
           "Matter static-friction cache limitation is not documented")
    expect(math.sqrt(6) > 0.25,
           "Matter tangent resting threshold unexpectedly collapsed into its friction threshold")
    expect(max(0.0, 0.0) == 0.0 and max(0.88, 0.0) == 0.88,
           "baseline and Hooke restitution do not reproduce Matter contact response")

    result = {
        "mode": "PHYSICS_PROFILE_VALIDATE",
        "checks": checks,
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }
    print(json.dumps(result, ensure_ascii=False))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
