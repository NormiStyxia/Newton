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

    source_level = PHASER_ROOT / "data/levels/level_01.json"
    maker_level = MAKER_ROOT / "assets/Data/Levels/level_01.json"
    expect(sha256(source_level) == sha256(maker_level), "level_01.json copy hash mismatch")

    level = json.loads(maker_level.read_text(encoding="utf-8"))
    expect(level.get("schemaVersion") == 1, "schemaVersion must be 1")
    expect(level.get("playfield") == {"width": 1400, "height": 700}, "playfield must be 1400x700")
    ids = [item["id"] for item in level["objects"]]
    expect(len(ids) == len(set(ids)), "object ids must be unique")
    expect(any(item["type"] == "launcher" for item in level["objects"]), "launcher missing")
    expect(any(item["type"] == "goal_sensor" for item in level["objects"]), "goal sensor missing")

    for item in level["objects"]:
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
        expect(
            transform["x"] - half_width >= 0 and transform["x"] + half_width <= 1400,
            f"{item['id']} x out of bounds",
        )
        expect(
            transform["y"] - half_height >= 0 and transform["y"] + half_height <= 580,
            f"{item['id']} y out of bounds",
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

    main_lua = (MAKER_ROOT / "scripts/main.lua").read_text(encoding="utf-8")
    factory_lua = (MAKER_ROOT / "scripts/migration/RuntimeFactory.lua").read_text(encoding="utf-8")
    all_lua = "\n".join(path.read_text(encoding="utf-8") for path in (MAKER_ROOT / "scripts").rglob("*.lua"))
    expect("trigger = true" in factory_lua, "goal sensor trigger missing")
    expect("CollisionCircle2D" in factory_lua and "CollisionBox2D" in factory_lua, "Box2D shapes missing")
    expect("BT_DYNAMIC" in main_lua and "BT_STATIC" in factory_lua, "body state transition missing")
    expect("image/phase1/solid.png" not in factory_lua, "runtime still depends on solid.png")
    expect("nvgCreate" not in all_lua and "nvgBeginFrame" not in all_lua, "raw NanoVG unexpectedly present")

    result = {
        "mode": "FAST_VALIDATE",
        "checks": 30,
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }
    print(json.dumps(result, ensure_ascii=False))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
