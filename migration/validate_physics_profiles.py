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
    level_data = (ROOT / "scripts/migration/LevelData.lua").read_text(encoding="utf-8")

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
