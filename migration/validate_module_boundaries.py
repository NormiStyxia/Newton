from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
GAME = SCRIPTS / "game"


def module_name(path: Path) -> str:
    return ".".join(path.relative_to(SCRIPTS).with_suffix("").parts)


def main() -> int:
    errors: list[str] = []
    checks = 0

    def expect(condition: bool, message: str) -> None:
        nonlocal checks
        checks += 1
        if not condition:
            errors.append(message)

    main_path = SCRIPTS / "main.lua"
    main_source = main_path.read_text(encoding="utf-8")
    production = sorted(GAME.rglob("*.lua"))
    sources = {module_name(path): path.read_text(encoding="utf-8") for path in production}
    all_source = main_source + "\n" + "\n".join(sources.values())

    expect(len(main_source.splitlines()) <= 120, "scripts/main.lua exceeds 120 lines")
    allowed_globals = {
        "Start", "Stop", "HandleUpdate", "HandlePhysicsPreStep", "HandlePhysicsPostStep",
        "HandleScreenMode", "HandleTouchBegin", "HandleTouchMove", "HandleTouchEnd",
        "HandleCollisionBegin", "HandleCollisionUpdate", "HandleCollisionEnd", "HandleRender",
    }
    main_globals = set(re.findall(r"^function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", main_source, re.M))
    expect(main_globals == allowed_globals, "main.lua engine callback whitelist differs")

    for path in production:
        source = path.read_text(encoding="utf-8")
        lines = source.splitlines()
        expect(len(lines) <= 800, f"production module exceeds 800 lines: {path.relative_to(ROOT)}")
        expect(path.with_suffix(path.suffix + ".meta").exists(), f"missing Lua meta: {path.relative_to(ROOT)}")
        bare_globals = re.findall(r"^function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", source, re.M)
        expect(not bare_globals, f"script-environment globals outside main.lua: {path.relative_to(ROOT)}")

    expect('require("migration.' not in all_source and "require('migration." not in all_source,
           "production code still requires migration namespace")
    expect(not list((SCRIPTS / "migration").glob("*.lua")) if (SCRIPTS / "migration").exists() else True,
           "legacy scripts/migration Lua modules remain")
    expect("CreateViewportBackground" not in all_source, "no-op viewport background compatibility shell remains")

    requires: dict[str, set[str]] = {}
    require_pattern = re.compile(r"require\s*\(?\s*['\"](game\.[A-Za-z0-9_.]+)['\"]\s*\)?")
    for name, source in sources.items():
        declared = set(require_pattern.findall(source))
        missing = sorted(declared - sources.keys())
        expect(not missing, f"unresolved game require in {name}: {missing}")
        requires[name] = declared
    main_dependencies = set(require_pattern.findall(main_source))
    expect(not (main_dependencies - sources.keys()), "main.lua has unresolved game requires")

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(name: str, trail: tuple[str, ...]) -> None:
        if name in visited:
            return
        if name in visiting:
            errors.append("cyclic require: " + " -> ".join((*trail, name)))
            return
        visiting.add(name)
        for dependency in sorted(requires.get(name, ())):
            visit(dependency, (*trail, name))
        visiting.remove(name)
        visited.add(name)

    for name in sorted(sources):
        visit(name, ())
    checks += 1

    subscriptions = (
        "Update", "ScreenMode", "TouchBegin", "TouchMove", "TouchEnd", "PhysicsPreStep",
        "PhysicsPostStep", "PhysicsBeginContact2D", "PhysicsUpdateContact2D", "PhysicsEndContact2D",
    )
    for event_name in subscriptions:
        expect(all_source.count(f'SubscribeToEvent("{event_name}"') == 1,
               f"event subscription must be unique: {event_name}")
    expect(all_source.count('SubscribeToEvent(painter_.vg, "NanoVGRender"') == 1,
           "NanoVGRender subscription must be unique")
    expect(all_source.count("nvgBeginFrame(") == 1, "NanoVG Begin must have one production call site")
    expect(all_source.count("nvgEndFrame(") == 1, "NanoVG End must have one production call site")

    uuids: list[str] = []
    for path in production:
        meta = path.with_suffix(path.suffix + ".meta").read_text(encoding="utf-8")
        match = re.search(r'"uuid"\s*:\s*"([^"]+)"', meta)
        expect(match is not None, f"invalid Lua meta: {path.relative_to(ROOT)}")
        if match: uuids.append(match.group(1))
    expect(len(uuids) == len(set(uuids)), "Lua module UUIDs are not unique")

    app_source = sources["game.App"]
    public_methods = {
        "Start", "Stop", "Update", "OnPhysicsPreStep", "OnPhysicsPostStep", "OnScreenMode",
        "OnTouchBegin", "OnTouchMove", "OnTouchEnd", "OnContactBegin", "OnContactUpdate",
        "OnContactEnd", "Render",
    }
    actual_methods = set(re.findall(r"^function\s+App:([A-Za-z_][A-Za-z0-9_]*)\s*\(", app_source, re.M))
    expect(actual_methods == public_methods, "game.App engine adapter interface differs")
    expect("DesignSpace.New(constants.CONFIG.pixelsPerMeter)" in sources["game.State"],
           "DesignSpace does not share Config pixelsPerMeter")
    expect("function State.BeginGameSnapshot" in sources["game.State"]
           and "GameSnapshot is read-only" in sources["game.State"]
           and "State.BeginGameSnapshot(context)" in sources["game.AppRuntime"],
           "rendering is not guarded by a read-only GameSnapshot")
    expect('experiment.mode = "failed"' in sources["game.State"]
           and 'cards.mode = "burning"' in sources["game.State"]
           and 'domains.replay.mode = domains.replay.replayMode_' in sources["game.State"],
           "domain mode enums are missing")
    expect("LevelToLogical" not in all_source and "LogicalToLevel" not in all_source,
           "level/logical conversion bypasses CoordinateMapper")
    expect("mapper:LevelToWorld" in sources["game.render.WorldPrimitives"]
           and "design:WorldToLogical" in sources["game.render.WorldPrimitives"],
           "world rendering does not use the shared Mapper/DesignSpace pipeline")

    result = {"mode": "MODULE_BOUNDARY_VALIDATE", "checks": checks, "errors": errors,
              "status": "pass" if not errors else "fail"}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
