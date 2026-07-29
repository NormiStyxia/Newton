from __future__ import annotations

import json
import hashlib
import math
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


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


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
    master = manifest["variants"]["master_1080"]
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

    expected_clips = {
        "idle": {"fps": 10.0, "loop": True, "duration": 1.6, "grounded": True},
        "blink": {"fps": 10.0, "loop": False, "duration": 1.6, "grounded": True},
        "move": {"fps": 16.0, "loop": True, "duration": 1.0, "grounded": False},
        "drag": {"fps": 16.0, "loop": True, "duration": 1.0, "grounded": False},
        "tap_react_a": {"fps": 16.0, "loop": False, "duration": 1.0, "grounded": True},
        "tap_react_b": {"fps": 16.0, "loop": False, "duration": 1.0, "grounded": True},
    }
    for clip_name, expected_clip in expected_clips.items():
        master_clip = master["clips"][clip_name]
        runtime_clip = runtime["clips"][clip_name]
        expect(master_clip["frameCount"] == runtime_clip["frameCount"] == 16,
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
        expect(master_clip["fps"] == runtime_clip["fps"] == expected_fps,
               f"{clip_name}: animation fps changed")
        expect(master_clip["loop"] == runtime_clip["loop"] == expected_clip["loop"],
               f"{clip_name}: loop mode changed")
        expected_duration = expected_clip["duration"]
        expect(abs(master_clip["frameCount"] / master_clip["fps"] - expected_duration) < 1e-9,
               f"{clip_name}: animation cycle duration changed")
        master_screen_height = master_clip["visualBounds"]["height"] / master_clip["frameHeight"] * SPRITE_HEIGHT
        runtime_screen_height = runtime_clip["visualBounds"]["height"] / runtime_clip["frameHeight"] * SPRITE_HEIGHT
        # Reference-relative motion can enlarge the clip union by one Lanczos
        # threshold pixel at each extreme without changing spriteHeight.
        expect(abs(master_screen_height - runtime_screen_height) <= 0.75,
               f"{clip_name}: visual display height changed")
        for master_frame, runtime_frame in zip(master_clip["frames"], runtime_clip["frames"]):
            expect(sha256(texture_path(master_frame)) == master_frame["sourceHash"],
                   f"{clip_name}: Master source hash changed after manifest generation")
            master_bounds = master_frame["visualBounds"]
            runtime_bounds = runtime_frame["visualBounds"]
            scale = runtime_clip["scaleFromMaster"]
            # Lanczos can add up to roughly three alpha>0 fringe pixels while
            # preserving the visible alpha>32 silhouette.
            expect(abs(runtime_bounds["height"] - master_bounds["height"] * scale) <= 3.1,
                   f"{clip_name}: frame alpha height drifted during resize")
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

    master_move = master["clips"]["move"]
    runtime_move = runtime["clips"]["move"]
    master_registration = master_move.get("spatialRegistration", {})
    runtime_registration = runtime_move.get("spatialRegistration", {})
    expect(master_registration.get("method") == "reference-relative-position"
           and master_registration.get("referenceFrame") == 1,
           "move: Master reference-relative registration is missing")
    expect(master_registration.get("sharedContentOffset") == {"x": 0, "y": -24},
           "move: Master registration headroom changed")
    expect(runtime_registration.get("sharedContentOffset", {}).get("y", 0) < 0,
           "move: runtime frames were not moved upward")
    expected_positions = [
        (position["x"], position["y"])
        for position in master_registration.get("referenceRelativePositions", [])
    ]
    master_left = master_move["frames"][0]["visualBounds"]["x"]
    master_top = master_move["frames"][0]["visualBounds"]["y"]
    actual_positions = [
        (frame["visualBounds"]["x"] - master_left, frame["visualBounds"]["y"] - master_top)
        for frame in master_move["frames"]
    ]
    expect(actual_positions == expected_positions,
           "move: Master frames do not preserve the reference relative X/Y")
    runtime_positions = runtime_registration.get("referenceRelativePositions", [])
    runtime_left = runtime_move["frames"][0]["visualBounds"]["x"]
    runtime_top = runtime_move["frames"][0]["visualBounds"]["y"]
    for index, (frame, expected_position) in enumerate(
        zip(runtime_move["frames"], runtime_positions), start=1,
    ):
        expect(abs((frame["visualBounds"]["x"] - runtime_left) - expected_position["x"]) <= 1
               and abs((frame["visualBounds"]["y"] - runtime_top) - expected_position["y"]) <= 1,
               f"move: runtime frame {index} lost the reference relative X/Y")
    expect(master_move["footAnchor"]["normalizedY"] < 1
           and runtime_move["footAnchor"]["normalizedY"] < 1,
           "move: shared foot anchor did not compensate the upward content shift")

    master_drag = master["clips"]["drag"]
    runtime_drag = runtime["clips"]["drag"]
    master_grab = master_drag.get("semanticAnchors", {}).get("dragGrab", {})
    runtime_grab = runtime_drag.get("semanticAnchors", {}).get("dragGrab", {})
    expect(abs(master_grab.get("x", 0) - 611) < 1e-9
           and abs(master_grab.get("y", 0) - 184) < 1e-9,
           "drag: Master dragGrab no longer matches the approved cape-tip hotspot")
    master_foot = master_drag["footAnchor"]
    runtime_foot = runtime_drag["footAnchor"]
    master_screen_offset = (
        (master_grab["x"] - master_foot["x"]) / master_drag["frameHeight"] * SPRITE_HEIGHT,
        (master_grab["y"] - master_foot["y"]) / master_drag["frameHeight"] * SPRITE_HEIGHT,
    )
    runtime_screen_offset = (
        (runtime_grab["x"] - runtime_foot["x"]) / runtime_drag["frameHeight"] * SPRITE_HEIGHT,
        (runtime_grab["y"] - runtime_foot["y"]) / runtime_drag["frameHeight"] * SPRITE_HEIGHT,
    )
    expect(abs(master_screen_offset[0] - runtime_screen_offset[0]) <= 0.01
           and abs(master_screen_offset[1] - runtime_screen_offset[1]) <= 0.01,
           "drag: runtime crop/resize changed the cape-tip grab offset")
    for frame in runtime_drag["frames"]:
        expect(frame.get("semanticAnchors", {}).get("dragGrab") == runtime_grab,
               "drag: per-frame dragGrab anchor drifted")

    view_source = VIEW_PATH.read_text(encoding="utf-8")
    config_source = CONFIG_PATH.read_text(encoding="utf-8")
    expect("NVG_IMAGE_NEAREST" not in view_source, "Companion enabled nearest-neighbor filtering")
    expect("NVG_IMAGE_GENERATE_MIPMAPS" in view_source and "self.imageFlags" in view_source,
           "Companion mipmap flag is not local to its View")
    expect("mirrorOrigin = pivotX * 2 - rect.x" in view_source,
           "Companion horizontal flip is not pivoted around the logical foot/root anchor")
    for preset in ("A_MASTER_LINEAR", "B_RUNTIME_LINEAR", "C_RUNTIME_MIPMAP", "D_MASTER_MIPMAP"):
        expect(preset in config_source, f"missing quality preset {preset}")

    master_memory = rgba_memory(master)
    runtime_memory = rgba_memory(runtime)
    variants = {
        "A_MASTER_LINEAR": {"assetVariant": "master_1080", "mipmap": False},
        "B_RUNTIME_LINEAR": {"assetVariant": "runtime_512", "mipmap": False},
        "C_RUNTIME_MIPMAP": {"assetVariant": "runtime_512", "mipmap": True},
        "D_MASTER_MIPMAP": {"assetVariant": "master_1080", "mipmap": True},
    }
    result = {
        "mode": "COMPANION_RUNTIME_FAST_VALIDATE",
        "checks": checks,
        "errors": errors,
        "variants": variants,
        "clips": {
            name: {
                "master": clip_metrics(master["clips"][name]),
                "runtime": clip_metrics(runtime["clips"][name]),
            }
            for name in expected_clips
        },
        "memory": {
            "masterDecodedRGBABytes": master_memory,
            "runtimeDecodedRGBABytes": runtime_memory,
            "decodedReductionPercent": round((1 - runtime_memory / master_memory) * 100, 2),
            "masterDiskBytes": disk_bytes(master),
            "runtimeDiskBytes": disk_bytes(runtime),
        },
        "status": "pass" if not errors else "fail",
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
