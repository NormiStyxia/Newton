from __future__ import annotations

import json
import math
import re
from pathlib import Path

from runtime_source_index import all_runtime_source, legacy_main_source


ROOT = Path(__file__).resolve().parents[1]
LEVEL_ROOT = ROOT / "assets" / "Data" / "Levels"
GAME = ROOT / "scripts" / "game"

BASE_WIDTH = 1880
BASE_HEIGHT = 840
LAB_X = 290
LAB_Y = 112
LAB_WIDTH = 1500
LAB_HEIGHT = 596
LEVEL_WIDTH = 1400
LEVEL_HEIGHT = 700
PIXELS_PER_METER = 100
GROUND_Y = 580


def design_frame(physical_width: float, physical_height: float, dpr: float) -> dict[str, float]:
    system_width = physical_width / dpr
    system_height = physical_height / dpr
    scale = max(min(system_width / BASE_WIDTH, system_height / BASE_HEIGHT), 0.001)
    logical_width = system_width / scale
    logical_height = system_height / scale
    workspace_width = 250 + 16 + LAB_WIDTH
    workspace_x = max(24, (logical_width - workspace_width) * 0.5)
    return {
        "dpr": dpr,
        "render_scale": scale,
        "logical_width": logical_width,
        "logical_height": logical_height,
        "playfield_x": workspace_x + 250 + 16,
    }


def level_to_world(x: float, y: float) -> tuple[float, float]:
    viewport_x = x / LEVEL_WIDTH * LAB_WIDTH
    viewport_y = y / LEVEL_HEIGHT * LAB_HEIGHT
    return (viewport_x - LAB_WIDTH * 0.5) / PIXELS_PER_METER, (LAB_HEIGHT * 0.5 - viewport_y) / PIXELS_PER_METER


def world_to_logical(frame: dict[str, float], x: float, y: float) -> tuple[float, float]:
    return frame["playfield_x"] + LAB_WIDTH * 0.5 + x * PIXELS_PER_METER, LAB_Y + LAB_HEIGHT * 0.5 - y * PIXELS_PER_METER


def main() -> int:
    errors: list[str] = []
    checks = 0

    def expect(condition: bool, message: str) -> None:
        nonlocal checks
        checks += 1
        if not condition:
            errors.append(message)

    runtime = all_runtime_source()
    legacy = legacy_main_source()
    design_source = (GAME / "layout" / "DesignSpace.lua").read_text(encoding="utf-8")
    canvas_source = (GAME / "render" / "Canvas.lua").read_text(encoding="utf-8")
    state_source = (GAME / "State.lua").read_text(encoding="utf-8")
    input_source = (GAME / "input" / "InteractionRouter.lua").read_text(encoding="utf-8")
    level_session = (GAME / "level" / "LevelSession.lua").read_text(encoding="utf-8")

    expected_levels = [f"level_{index:02d}.json" for index in range(1, 10)]
    actual_levels = sorted(path.name for path in LEVEL_ROOT.glob("level_0[1-9].json"))
    expect(actual_levels == expected_levels, "the nine production levels are incomplete")
    supported_types = {"wall", "launcher", "goal_sensor", "spring", "button", "door"}
    known_cards = {"side-gravity", "feather-gravity", "hooke-bounce", "up-impulse", "quantum-phase", "mirror-motion"}

    for index, name in enumerate(expected_levels, 1):
        level = json.loads((LEVEL_ROOT / name).read_text(encoding="utf-8"))
        expect(level.get("schemaVersion") == 1, f"{name}: schema version")
        expect(level.get("levelId") == f"level_{index:02d}", f"{name}: level id")
        expect(level.get("playfield") == {"width": LEVEL_WIDTH, "height": LEVEL_HEIGHT}, f"{name}: playfield")
        objects = level.get("objects", [])
        ids = [item.get("id") for item in objects]
        expect(len(ids) == len(set(ids)), f"{name}: duplicate object id")
        expect(sum(item.get("type") == "launcher" for item in objects) == 1, f"{name}: launcher count")
        expect(sum(item.get("type") == "goal_sensor" for item in objects) == 1, f"{name}: goal count")
        expect(all(item.get("type") in supported_types for item in objects), f"{name}: unsupported object")
        for item in objects:
            transform = item.get("transform", {})
            values = [transform.get(key) for key in ("x", "y", "width", "height", "rotation")]
            expect(all(isinstance(value, (int, float)) and math.isfinite(value) for value in values),
                   f"{name}/{item.get('id')}: invalid transform")
            if all(isinstance(value, (int, float)) for value in values):
                radians = math.radians(transform["rotation"])
                half_x = abs(math.cos(radians)) * transform["width"] * 0.5 + abs(math.sin(radians)) * transform["height"] * 0.5
                half_y = abs(math.sin(radians)) * transform["width"] * 0.5 + abs(math.cos(radians)) * transform["height"] * 0.5
                expect(transform["width"] > 0 and transform["height"] > 0
                       and transform["x"] - half_x >= -1e-9 and transform["x"] + half_x <= LEVEL_WIDTH + 1e-9
                       and transform["y"] - half_y >= -1e-9 and transform["y"] + half_y <= GROUND_Y + 1e-9,
                       f"{name}/{item.get('id')}: object exceeds playfield")
        deck = level.get("cardDeck", {}).get("cards", [])
        expect(all(card.get("cardId") in known_cards for card in deck), f"{name}: unknown card")
        expect(len({card.get("cardId") for card in deck}) == len(deck)
               and all(isinstance(card.get("order"), int) and card["order"] >= 0 for card in deck),
               f"{name}: invalid card deck identity/order")
        produced_channels = {item.get("properties", {}).get("channelId") for item in objects if item.get("type") == "button"}
        needed_channels = {item.get("properties", {}).get("channelId") for item in objects if item.get("type") == "door"}
        expect(needed_channels <= produced_channels, f"{name}: door channel has no button producer")

    display_cases = (
        (1880, 840, 1), (3760, 1680, 2), (5640, 2520, 3),
        (2560, 1080, 1), (1080, 1920, 2), (1440, 2560, 3),
    )
    for physical_width, physical_height, dpr in display_cases:
        frame = design_frame(physical_width, physical_height, dpr)
        expect(frame["logical_width"] >= BASE_WIDTH - 1e-9 and frame["logical_height"] >= BASE_HEIGHT - 1e-9,
               f"layout clips design space at {physical_width}x{physical_height}@{dpr}")
        for level_x, level_y in ((0, 0), (700, 350), (1400, 700), (146.3513031481672, 467)):
            world_x, world_y = level_to_world(level_x, level_y)
            logical_x, logical_y = world_to_logical(frame, world_x, world_y)
            expected_x = frame["playfield_x"] + level_x / LEVEL_WIDTH * LAB_WIDTH
            expected_y = LAB_Y + level_y / LEVEL_HEIGHT * LAB_HEIGHT
            expect(abs(logical_x - expected_x) < 1e-9 and abs(logical_y - expected_y) < 1e-9,
                   f"mapper/design mismatch at {physical_width}x{physical_height}@{dpr}")
            screen_x = logical_x * frame["render_scale"] * dpr
            screen_y = logical_y * frame["render_scale"] * dpr
            restored_x = screen_x / dpr / frame["render_scale"]
            restored_y = screen_y / dpr / frame["render_scale"]
            expect(abs(restored_x - logical_x) < 1e-9 and abs(restored_y - logical_y) < 1e-9,
                   f"pointer/render inverse mismatch at {physical_width}x{physical_height}@{dpr}")

    expect("graphics:GetDPR()" in design_source and "ScreenToLogical" in design_source,
           "DPR-aware design input mapping is missing")
    expect("nvgBeginFrame(self.vg, frame.systemLogicalWidth, frame.systemLogicalHeight, frame.dpr)" in canvas_source
           and "nvgScale(self.vg, frame.renderScale, frame.renderScale)" in canvas_source,
           "NanoVG Mode A frame contract differs")
    expect("local pointerFrame = PointerState()" in input_source
           and all(name in runtime for name in ("HandleTouchBegin", "HandleTouchMove", "HandleTouchEnd")),
           "mouse/touch PointerFrame routing is incomplete")

    priority_markers = (
        "if HandleGreenAssistantPointer",
        "if replayActive_ then",
        "if IsResultOverlayVisible() then",
        "for index = 1, CONFIG.levelCount do",
        "Rules.Punch(rules_)",
        "IsNearApple(x, y)",
        "TryCardPress(x, y)",
    )
    pointer_handler = input_source[input_source.index("function HandlePointer"):]
    positions = [pointer_handler.index(marker) for marker in priority_markers]
    expect(positions == sorted(positions), "pointer interaction priority changed")
    expect("not isPaused_ and not launched_ and IsNearApple" in input_source
           and "TryCardPress(x, y)" in input_source,
           "tactical pause no longer leaves cards interactive")
    expect("bulletTimeScale = 0.05" in runtime and "MOUSEB_RIGHT" in legacy and "AnimateCardToHome" in legacy,
           "bullet time or right-click cancel contract is missing")

    expect("failureCountsByLevel_[level_.levelId]" in legacy
           and "failureCount_ = failureCountsByLevel_[level_.levelId] or 0" in level_session,
           "failure counts are not isolated by level")
    expect("ResetSessionState(true)" in level_session and "ResetSessionState(false)" in level_session,
           "build/reset do not share one initialization path")
    expect(all(token in legacy for token in (
        'SetReplayMode("playing")', 'SetReplayMode(wasPaused and "playing" or "paused")', 'SetReplayMode("finished")',
        "replaySavedApple_", "SyncPhysicsUpdateEnabled()", "RestoreAppleContactMaterial()",
    )), "replay lifecycle/Apple restoration contract is incomplete")
    expect("ReplayMode.PLAYER_REPLAY" in legacy and "ReplayMode.ASSIST_TAKEOVER" in legacy
           and "replayBusinessMode_" in state_source,
           "replay business lifecycle does not distinguish player replay from assist takeover")
    expect(all(token in legacy for token in (
        "UpdateSpringExits", "EvaluateButton", "SetDoorTarget", "UpdatePhaseTraversal",
        "GoalSensorContainsApple", "goalContactMs_", "absorbElapsedMs_", "RegisterFailure",
    )), "mechanism, goal, success, or failure contract is incomplete")
    expect("BeginGameSnapshot" in state_source and "GameSnapshot is read-only" in state_source
           and all(f'{domain}.mode' in state_source for domain in ("experiment", "cards"))
           and "domains.replay.mode" in state_source,
           "read-only render snapshot or independent domain modes are missing")

    result = {"mode": "RUNTIME_ACCEPTANCE_MATRIX", "checks": checks, "errors": errors,
              "status": "pass" if not errors else "fail"}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
