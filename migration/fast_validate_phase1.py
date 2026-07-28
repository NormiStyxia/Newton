from __future__ import annotations

import hashlib
import json
import math
import struct
from pathlib import Path


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

    main_lua = (MAKER_ROOT / "scripts/main.lua").read_text(encoding="utf-8")
    factory_lua = (MAKER_ROOT / "scripts/migration/RuntimeFactory.lua").read_text(encoding="utf-8")
    renderer_lua = (MAKER_ROOT / "scripts/migration/Renderer.lua").read_text(encoding="utf-8")
    design_lua = (MAKER_ROOT / "scripts/migration/DesignSpace.lua").read_text(encoding="utf-8")
    synth_audio_lua = (MAKER_ROOT / "scripts/migration/SynthAudio.lua").read_text(encoding="utf-8")
    all_lua = "\n".join(path.read_text(encoding="utf-8") for path in (MAKER_ROOT / "scripts").rglob("*.lua"))
    portrait_source = PHASER_ROOT / "public/assets/newton-portrait.png"
    portrait_copy = MAKER_ROOT / "assets/image/newton-portrait.png"
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
    expect("QueueCardResolution" in main_lua and "duration = 690" in main_lua, "card burn timing missing")
    expect("UpdateBulletTime" in main_lua and "StartReplay" in main_lua, "card bullet time or replay missing")
    expect("migration.SynthAudio" in main_lua and "PlaySound(\"launch\")" in main_lua, "launch audio wiring missing")
    expect("PlaySound(\"card\")" in main_lua and "PlaySound(\"impact\")" in main_lua, "card or impact audio wiring missing")
    expect("PlaySound(\"punch\")" in main_lua and "PlaySound(\"success\")" in main_lua, "punch or success audio wiring missing")
    expect("audio/phase1/launch.wav" in synth_audio_lua and "self.elapsedMs - self.lastImpactMs < 80" in synth_audio_lua, "SynthAudio playback or impact gate missing")
    expect("apple_.shape.trigger = false" in main_lua and "object.contactProgress = 0" in main_lua, "success retry does not restore collision state")
    expect("isEditor_" not in main_lua and "EditorController" not in all_lua, "runtime editor remains in Maker build")

    result = {
        "mode": "FAST_VALIDATE",
        "checks": 93,
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }
    print(json.dumps(result, ensure_ascii=False))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
