from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "assets/image/green_assistant/runtime/manifest.json"
VIEW_PATH = ROOT / "scripts/green_assistant/GreenAssistView.lua"
CONFIG_PATH = ROOT / "scripts/green_assistant/GreenAssistConfig.lua"
SPRITE_HEIGHT = 210.0


def alpha_bounds(path: Path) -> tuple[int, int, int, int]:
    with Image.open(path) as image:
        alpha = image.convert("RGBA").getchannel("A")
        bounds = alpha.point(lambda value: 255 if value > 32 else 0).getbbox()
    if bounds is None:
        raise AssertionError(f"fully transparent frame: {path}")
    return bounds


def texture_path(frame: dict) -> Path:
    return ROOT / "assets" / frame["texture"]


def rgba_memory(variant: dict) -> int:
    textures: dict[Path, tuple[int, int]] = {}
    for clip in variant["clips"].values():
        for frame in clip["frames"]:
            path = texture_path(frame)
            textures[path] = (frame["sourceRect"]["width"], frame["sourceRect"]["height"])
    return sum(width * height * 4 for width, height in textures.values())


def disk_bytes(variant: dict) -> int:
    return sum(path.stat().st_size for path in {texture_path(frame)
        for clip in variant["clips"].values() for frame in clip["frames"]})


def clip_metrics(clip: dict) -> dict:
    bounds = clip["visualBounds"]
    return {
        "frameSize": [clip["frameWidth"], clip["frameHeight"]],
        "effectivePixels": [bounds["width"], bounds["height"]],
        "screenDesignSize": [
            round(bounds["width"] / clip["frameHeight"] * SPRITE_HEIGHT, 3),
            round(bounds["height"] / clip["frameHeight"] * SPRITE_HEIGHT, 3),
        ],
        "footAnchor": [
            round(clip["footAnchor"]["normalizedX"], 6),
            round(clip["footAnchor"]["normalizedY"], 6),
        ],
    }


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    runtime = manifest["variants"]["runtime_512"]
    errors: list[str] = []
    checks = 0

    def expect(condition: bool, message: str) -> None:
        nonlocal checks
        checks += 1
        if not condition:
            errors.append(message)

    expect(manifest["runtimePolicy"]["cropPolicy"] == "per-clip-alpha-union",
           "runtime crop policy is not clip union")
    expect(manifest["runtimePolicy"]["resampling"] == "lanczos-premultiplied-alpha",
           "runtime resampling policy changed")
    expect(manifest["runtimePolicy"]["registrationPolicy"] == "optional-reference-relative-xy",
           "runtime registration policy changed")
    expect(set(manifest["variants"]) == {"runtime_512"},
           "manifest must ship only the runtime_512 asset variant")

    expected_clips = {
        "idle": {"frames": 16, "fps": 10.0, "loop": True, "duration": 1.6, "grounded": True},
        "blink": {"frames": 16, "fps": 10.0, "loop": False, "duration": 1.6, "grounded": True},
        "move": {"frames": 16, "fps": 16.0, "loop": True, "duration": 1.0, "grounded": False},
        "drag": {"frames": 16, "fps": 16.0, "loop": True, "duration": 1.0, "grounded": False},
        "tap_react_a": {"frames": 16, "fps": 16.0, "loop": False, "duration": 1.0, "grounded": True},
        "tap_react_b": {"frames": 16, "fps": 16.0, "loop": False, "duration": 1.0, "grounded": True},
        "takeover_raise": {"frames": 15, "fps": 16.0, "loop": False, "duration": 15 / 16, "grounded": True},
        "takeover_loop": {"frames": 16, "fps": 16.0, "loop": True, "duration": 1.0, "grounded": True},
        "takeover_finish": {"frames": 16, "fps": 16.0, "loop": False, "duration": 1.0, "grounded": True},
    }
    for clip_name, expected_clip in expected_clips.items():
        runtime_clip = runtime["clips"][clip_name]
        expect(runtime_clip["frameCount"] == expected_clip["frames"],
               f"{clip_name}: frame count changed")
        expect(runtime_clip["frameHeight"] == 512 and runtime_clip["frameWidth"] < 512,
               f"{clip_name}: runtime frame is not compact portrait data")
        runtime_sizes = {(frame["frameWidth"], frame["frameHeight"]) for frame in runtime_clip["frames"]}
        expect(len(runtime_sizes) == 1, f"{clip_name}: per-frame crop changed runtime canvas")
        runtime_anchors = {(round(frame["footAnchor"]["normalizedX"], 8),
                            round(frame["footAnchor"]["normalizedY"], 8))
                           for frame in runtime_clip["frames"]}
        expect(len(runtime_anchors) == 1, f"{clip_name}: foot anchor changed between frames")
        expected_fps = expected_clip["fps"]
        expect(runtime_clip["fps"] == expected_fps,
               f"{clip_name}: animation fps changed")
        expect(runtime_clip["loop"] == expected_clip["loop"],
               f"{clip_name}: loop mode changed")
        expected_duration = expected_clip["duration"]
        expect(abs(runtime_clip["frameCount"] / runtime_clip["fps"] - expected_duration) < 1e-9,
               f"{clip_name}: animation cycle duration changed")
        expect(0 < runtime_clip["visualBounds"]["height"] <= runtime_clip["frameHeight"],
               f"{clip_name}: clip visual bounds are invalid")
        for runtime_frame in runtime_clip["frames"]:
            path = texture_path(runtime_frame)
            expect(path.is_file(), f"{clip_name}: runtime texture is missing: {path}")
            expect(runtime_frame["sourceRect"] == {
                "x": 0, "y": 0,
                "width": runtime_frame["frameWidth"],
                "height": runtime_frame["frameHeight"],
            }, f"{clip_name}: runtime sourceRect no longer covers its texture")
            runtime_bounds = runtime_frame["visualBounds"]
            if expected_clip["grounded"]:
                expect(abs((runtime_bounds["y"] + runtime_bounds["height"])
                           - runtime_frame["footAnchor"]["y"]) <= 1,
                       f"{clip_name}: frame foot no longer reaches the shared anchor")
            actual = alpha_bounds(texture_path(runtime_frame))
            expected = runtime_frame["visualBounds"]
            offset = runtime_frame["sourceOffset"]
            expect(actual == (expected["x"] - offset["x"], expected["y"] - offset["y"],
                              expected["x"] + expected["width"] - offset["x"],
                              expected["y"] + expected["height"] - offset["y"]),
                   f"{clip_name}: runtime manifest alpha bounds are stale")

    runtime_move = runtime["clips"]["move"]
    runtime_registration = runtime_move.get("spatialRegistration", {})
    expect(runtime_registration.get("method") == "reference-relative-position"
           and runtime_registration.get("referenceFrame") == 1,
           "move: runtime reference-relative registration is missing")
    expect(runtime_registration.get("sharedContentOffset", {}).get("y", 0) < 0,
           "move: runtime frames were not moved upward")
    runtime_positions = runtime_registration.get("referenceRelativePositions", [])
    expect(len(runtime_positions) == runtime_move["frameCount"],
           "move: runtime registration frame count changed")
    runtime_left = runtime_move["frames"][0]["visualBounds"]["x"]
    runtime_top = runtime_move["frames"][0]["visualBounds"]["y"]
    for index, (frame, expected_position) in enumerate(
        zip(runtime_move["frames"], runtime_positions), start=1,
    ):
        expect(abs((frame["visualBounds"]["x"] - runtime_left) - expected_position["x"]) <= 1
               and abs((frame["visualBounds"]["y"] - runtime_top) - expected_position["y"]) <= 1,
               f"move: runtime frame {index} lost the reference relative X/Y")
    expect(runtime_move["footAnchor"]["normalizedY"] < 1,
           "move: shared foot anchor did not compensate the upward content shift")

    runtime_drag = runtime["clips"]["drag"]
    runtime_grab = runtime_drag.get("semanticAnchors", {}).get("dragGrab", {})
    runtime_foot = runtime_drag["footAnchor"]
    expect(abs(runtime_grab.get("normalizedX", 0) - 0.6712757201646091) < 1e-9
           and abs(runtime_grab.get("normalizedY", 0) - 0.17037037037037037) < 1e-9,
           "drag: runtime dragGrab no longer matches the approved cape-tip hotspot")
    expect(runtime_grab["y"] < runtime_foot["y"],
           "drag: runtime dragGrab must remain above the foot anchor")
    for frame in runtime_drag["frames"]:
        expect(frame.get("semanticAnchors", {}).get("dragGrab") == runtime_grab,
               "drag: per-frame dragGrab anchor drifted")

    runtime_raise = runtime["clips"]["takeover_raise"]
    runtime_loop = runtime["clips"]["takeover_loop"]
    runtime_finish = runtime["clips"]["takeover_finish"]
    loop_master_anchor_x = (
        runtime_loop["footAnchor"]["x"] + runtime_loop["sourceCrop"]["left"]
    ) / runtime_loop["scaleFromMaster"]
    expect(abs(loop_master_anchor_x - 565) < 1e-6,
           "takeover_loop: clip-level horizontal registration changed")

    def root_bounds(frame: dict) -> tuple[float, float, float, float]:
        bounds = frame["visualBounds"]
        anchor = frame["footAnchor"]
        return (
            bounds["x"] - anchor["x"],
            bounds["y"] - anchor["y"],
            bounds["x"] + bounds["width"] - anchor["x"],
            bounds["y"] + bounds["height"] - anchor["y"],
        )

    raise_end = root_bounds(runtime_raise["frames"][-1])
    loop_start = root_bounds(runtime_loop["frames"][0])
    loop_end = root_bounds(runtime_loop["frames"][-1])
    finish_start = root_bounds(runtime_finish["frames"][0])
    expect(abs(raise_end[0] - loop_start[0]) <= 2 and abs(raise_end[1] - loop_start[1]) <= 1,
           "takeover transition: raise-to-loop root alignment drifted")
    expect(abs(loop_end[0] - finish_start[0]) <= 2 and abs(loop_end[1] - finish_start[1]) <= 1,
           "takeover transition: loop-to-finish root alignment drifted")

    view_source = VIEW_PATH.read_text(encoding="utf-8")
    config_source = CONFIG_PATH.read_text(encoding="utf-8")
    expect("NVG_IMAGE_NEAREST" not in view_source, "Companion enabled nearest-neighbor filtering")
    expect("NVG_IMAGE_GENERATE_MIPMAPS" in view_source and "self.imageFlags" in view_source,
           "Companion mipmap flag is not local to its View")
    expect("mirrorOrigin = pivotX * 2 - rect.x" in view_source,
           "Companion horizontal flip is not pivoted around the logical foot/root anchor")
    for preset in ("B_RUNTIME_LINEAR", "C_RUNTIME_MIPMAP"):
        expect(preset in config_source, f"missing quality preset {preset}")
    expect("master_1080" not in config_source,
           "GreenAssistant config still references the removed master asset set")
    expect('TAKEOVER = { "takeover_raise", "takeover_loop" }' in config_source,
           "GreenAssistant takeover raise/loop animation sequence is missing")
    expect('SUCCESS = { "takeover_finish" }' in config_source,
           "GreenAssistant takeover finish animation sequence is missing")

    runtime_memory = rgba_memory(runtime)
    variants = {
        "B_RUNTIME_LINEAR": {"assetVariant": "runtime_512", "mipmap": False},
        "C_RUNTIME_MIPMAP": {"assetVariant": "runtime_512", "mipmap": True},
    }
    result = {
        "mode": "COMPANION_RUNTIME_FAST_VALIDATE",
        "checks": checks,
        "errors": errors,
        "variants": variants,
        "clips": {
            name: {"runtime": clip_metrics(runtime["clips"][name])}
            for name in expected_clips
        },
        "memory": {
            "runtimeDecodedRGBABytes": runtime_memory,
            "runtimeDiskBytes": disk_bytes(runtime),
        },
        "status": "pass" if not errors else "fail",
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
