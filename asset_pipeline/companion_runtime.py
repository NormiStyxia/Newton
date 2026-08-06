from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from PIL import Image


PROCESSOR_VERSION = 4
DEFAULT_SPEC = Path(__file__).with_name("companion_runtime.json")


@dataclass(frozen=True)
class SourceFrame:
    name: str
    canvas: Image.Image
    texture_path: Path
    source_rect: tuple[int, int, int, int]
    source_offset: tuple[int, int]
    source_hash: str


def _natural_key(path: Path) -> tuple[Any, ...]:
    return tuple(int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", path.name))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _resource_path(project_root: Path, path: Path) -> str:
    relative = path.resolve().relative_to((project_root / "assets").resolve())
    return relative.as_posix()


def _rect_dict(rect: tuple[int, int, int, int]) -> dict[str, int]:
    left, top, right, bottom = rect
    return {"x": left, "y": top, "width": right - left, "height": bottom - top}


def _offset_rect(
    rect: tuple[int, int, int, int],
    offset: tuple[int, int],
) -> tuple[int, int, int, int]:
    left, top, right, bottom = rect
    offset_x, offset_y = offset
    return left + offset_x, top + offset_y, right + offset_x, bottom + offset_y


def _union(rectangles: Iterable[tuple[int, int, int, int]]) -> tuple[int, int, int, int]:
    items = list(rectangles)
    if not items:
        raise ValueError("animation clip has no visible frames")
    return (
        min(rect[0] for rect in items),
        min(rect[1] for rect in items),
        max(rect[2] for rect in items),
        max(rect[3] for rect in items),
    )


def _alpha_bounds(image: Image.Image, threshold: int = 0) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    if threshold > 0:
        alpha = alpha.point(lambda value: 255 if value > threshold else 0)
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("fully transparent animation frame is not supported")
    return bounds


def _normalized_anchor(spec: dict[str, Any], width: int, height: int) -> tuple[float, float]:
    unit = spec.get("unit", "normalized")
    x = float(spec["x"])
    y = float(spec["y"])
    if unit == "normalized":
        return x * width, y * height
    if unit == "pixels":
        return x, y
    raise ValueError(f"unsupported foot anchor unit: {unit}")


def _anchor_dict(anchor: tuple[float, float], frame_size: tuple[int, int]) -> dict[str, float]:
    frame_width, frame_height = frame_size
    anchor_x, anchor_y = anchor
    return {
        "x": anchor_x,
        "y": anchor_y,
        "normalizedX": anchor_x / frame_width,
        "normalizedY": anchor_y / frame_height,
    }


def _spatial_registration(
    clip_name: str,
    clip_spec: dict[str, Any],
    frames: list[SourceFrame],
    frame_size: tuple[int, int],
) -> tuple[tuple[int, int], list[tuple[int, int]], dict[str, Any] | None]:
    registration = clip_spec.get("registration")
    if not registration:
        return (0, 0), [(0, 0)] * len(frames), None

    method = registration.get("method")
    if method != "reference-relative-position":
        raise ValueError(f"{clip_name}: unsupported spatial registration method: {method}")
    threshold = int(registration.get("alphaThreshold", 32))
    reference_frame = int(registration.get("referenceFrame", 1))
    if reference_frame < 1 or reference_frame > len(frames):
        raise ValueError(f"{clip_name}: spatial registration referenceFrame is out of range")

    relative_positions = registration.get("referenceRelativePositions")
    if not isinstance(relative_positions, list) or len(relative_positions) != len(frames):
        raise ValueError(f"{clip_name}: referenceRelativePositions must match the frame count")
    positions = [(int(position["x"]), int(position["y"])) for position in relative_positions]
    if positions[reference_frame - 1] != (0, 0):
        raise ValueError(f"{clip_name}: reference frame relative position must be (0, 0)")

    feature_bounds = [_alpha_bounds(frame.canvas, threshold) for frame in frames]
    reference_x, reference_y = feature_bounds[reference_frame - 1][:2]
    corrections = [
        (
            reference_x + position[0] - bounds[0],
            reference_y + position[1] - bounds[1],
        )
        for position, bounds in zip(positions, feature_bounds)
    ]
    shared_spec = registration.get("sharedContentOffset", {})
    shared_offset = (int(shared_spec.get("x", 0)), int(shared_spec.get("y", 0)))
    offsets = [
        (shared_offset[0] + correction[0], shared_offset[1] + correction[1])
        for correction in corrections
    ]
    frame_width, frame_height = frame_size
    shifted_bounds = [
        _offset_rect(bounds, offset)
        for bounds, offset in zip(feature_bounds, offsets)
    ]
    if any(left < 0 or top < 0 or right > frame_width or bottom > frame_height
           for left, top, right, bottom in shifted_bounds):
        raise ValueError(f"{clip_name}: spatial registration exceeds the shared frame canvas")

    metadata = {
        "method": method,
        "alphaThreshold": threshold,
        "referenceFrame": reference_frame,
        "referenceFeature": {"x": reference_x, "y": reference_y},
        "sharedContentOffset": {"x": shared_offset[0], "y": shared_offset[1]},
        "referenceRelativePositions": [
            {"x": position[0], "y": position[1]} for position in positions
        ],
        "frameCorrections": [
            {"x": correction[0], "y": correction[1]} for correction in corrections
        ],
    }
    return shared_offset, corrections, metadata


def _sequence_frames(project_root: Path, source: dict[str, Any]) -> list[SourceFrame]:
    source_root = (project_root / source["root"]).resolve()
    paths = sorted(source_root.glob(source.get("pattern", "*.png")), key=_natural_key)
    if not paths:
        raise ValueError(f"no source frames found in {source_root}")
    frames: list[SourceFrame] = []
    for path in paths:
        image = Image.open(path).convert("RGBA")
        frames.append(SourceFrame(
            name=path.stem,
            canvas=image,
            texture_path=path,
            source_rect=(0, 0, image.width, image.height),
            source_offset=(0, 0),
            source_hash=_sha256(path),
        ))
    return frames


def _sheet_frames(project_root: Path, source: dict[str, Any]) -> list[SourceFrame]:
    texture_path = (project_root / source["texture"]).resolve()
    sheet = Image.open(texture_path).convert("RGBA")
    frame_specs = source.get("frames")
    if not isinstance(frame_specs, list) or not frame_specs:
        raise ValueError("spriteSheet source requires a non-empty frames array")
    texture_hash = _sha256(texture_path)
    frames: list[SourceFrame] = []
    for index, descriptor in enumerate(frame_specs, start=1):
        rect = descriptor["sourceRect"]
        source_rect = (
            int(rect["x"]), int(rect["y"]),
            int(rect["x"] + rect["width"]), int(rect["y"] + rect["height"]),
        )
        logical = descriptor.get("frameSize", {"width": rect["width"], "height": rect["height"]})
        offset = descriptor.get("sourceOffset", {"x": 0, "y": 0})
        canvas = Image.new("RGBA", (int(logical["width"]), int(logical["height"])), (0, 0, 0, 0))
        canvas.alpha_composite(sheet.crop(source_rect), (int(offset["x"]), int(offset["y"])))
        frames.append(SourceFrame(
            name=str(descriptor.get("name", f"frame_{index:02d}")),
            canvas=canvas,
            texture_path=texture_path,
            source_rect=source_rect,
            source_offset=(int(offset["x"]), int(offset["y"])),
            source_hash=texture_hash,
        ))
    return frames


def _load_frames(project_root: Path, source: dict[str, Any]) -> list[SourceFrame]:
    source_type = source.get("type")
    if source_type == "imageSequence":
        return _sequence_frames(project_root, source)
    if source_type == "spriteSheet":
        return _sheet_frames(project_root, source)
    raise ValueError(f"unsupported animation source type: {source_type}")


def _resize_rgba(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    # Premultiplied alpha prevents transparent RGB from bleeding into the
    # antialiased outline during the one-time Lanczos downsample.
    premultiplied = image.convert("RGBa")
    resized = premultiplied.resize(size, Image.Resampling.LANCZOS)
    return resized.convert("RGBA")


def _align_up(value: int, alignment: int) -> int:
    return int(math.ceil(value / alignment) * alignment)


def _frame_descriptor(
    texture: str,
    source_rect: tuple[int, int, int, int],
    source_offset: tuple[int, int],
    frame_size: tuple[int, int],
    anchor: tuple[float, float],
    visual_bounds: tuple[int, int, int, int],
    source_hash: str,
    semantic_anchors: dict[str, tuple[float, float]] | None = None,
) -> dict[str, Any]:
    frame_width, frame_height = frame_size
    anchor_x, anchor_y = anchor
    descriptor = {
        "texture": texture,
        "sourceRect": _rect_dict(source_rect),
        "sourceOffset": {"x": source_offset[0], "y": source_offset[1]},
        "frameWidth": frame_width,
        "frameHeight": frame_height,
        "footAnchor": _anchor_dict((anchor_x, anchor_y), frame_size),
        "visualBounds": _rect_dict(visual_bounds),
        "sourceHash": source_hash,
    }
    if semantic_anchors:
        descriptor["semanticAnchors"] = {
            name: _anchor_dict(value, frame_size)
            for name, value in semantic_anchors.items()
        }
    return descriptor


def _process_clip(
    project_root: Path,
    clip_name: str,
    clip_spec: dict[str, Any],
    runtime_spec: dict[str, Any],
    output_root: Path,
) -> tuple[dict[str, Any], dict[str, Any]]:
    frames = _load_frames(project_root, clip_spec["source"])
    source_size = frames[0].canvas.size
    if any(frame.canvas.size != source_size for frame in frames):
        raise ValueError(f"{clip_name}: all frames must share one logical canvas size")

    source_width, source_height = source_size
    foot_anchor = _normalized_anchor(clip_spec["footAnchor"], source_width, source_height)
    semantic_anchors = {
        name: _normalized_anchor(anchor, source_width, source_height)
        for name, anchor in clip_spec.get("semanticAnchors", {}).items()
    }
    alpha_bounds = [_alpha_bounds(frame.canvas) for frame in frames]
    visual_bounds = [_alpha_bounds(frame.canvas, 32) for frame in frames]
    shared_offset, frame_corrections, registration = _spatial_registration(
        clip_name, clip_spec, frames, source_size,
    )
    frame_offsets = [
        (shared_offset[0] + correction[0], shared_offset[1] + correction[1])
        for correction in frame_corrections
    ]
    registered_visual_bounds = [
        _offset_rect(bounds, offset)
        for bounds, offset in zip(visual_bounds, frame_offsets)
    ]
    registered_alpha_bounds = [
        _offset_rect(bounds, offset)
        for bounds, offset in zip(alpha_bounds, frame_offsets)
    ]
    union_bounds = _union(registered_alpha_bounds)
    visual_union = _union(registered_visual_bounds)

    runtime_height = int(runtime_spec["frameHeight"])
    scale = runtime_height / source_height
    scaled_width = max(1, int(round(source_width * scale)))
    padding = int(runtime_spec["horizontalPadding"])
    alignment = max(1, int(runtime_spec["widthAlignment"]))
    scaled_union_left = math.floor(union_bounds[0] * scale)
    scaled_union_right = math.ceil(union_bounds[2] * scale)
    raw_left = scaled_union_left - padding
    raw_right = scaled_union_right + padding
    output_width = _align_up(raw_right - raw_left, alignment)
    crop_left = math.floor((raw_left + raw_right - output_width) * 0.5)
    crop_right = crop_left + output_width
    runtime_shared_offset = (
        int(round(shared_offset[0] * scale)),
        int(round(shared_offset[1] * scale)),
    )
    runtime_frame_corrections = [
        (int(round(correction[0] * scale)), int(round(correction[1] * scale)))
        for correction in frame_corrections
    ]
    runtime_frame_offsets = [
        (
            runtime_shared_offset[0] + correction[0],
            runtime_shared_offset[1] + correction[1],
        )
        for correction in runtime_frame_corrections
    ]
    master_anchor = (
        foot_anchor[0] + shared_offset[0],
        foot_anchor[1] + shared_offset[1],
    )
    runtime_anchor = (
        foot_anchor[0] * scale + runtime_shared_offset[0] - crop_left,
        foot_anchor[1] * scale + runtime_shared_offset[1],
    )
    master_semantic_anchors = {
        name: (anchor[0] + shared_offset[0], anchor[1] + shared_offset[1])
        for name, anchor in semantic_anchors.items()
    }
    runtime_semantic_anchors = {
        name: (
            anchor[0] * scale + runtime_shared_offset[0] - crop_left,
            anchor[1] * scale + runtime_shared_offset[1],
        )
        for name, anchor in semantic_anchors.items()
    }
    master_descriptors: list[dict[str, Any]] = []
    runtime_descriptors: list[dict[str, Any]] = []
    clip_output = output_root / clip_name
    clip_output.mkdir(parents=True, exist_ok=True)

    for index, (frame, bounds, frame_offset) in enumerate(
        zip(frames, registered_visual_bounds, frame_offsets), start=1,
    ):
        master_texture = _resource_path(project_root, frame.texture_path)
        master_descriptors.append(_frame_descriptor(
            master_texture,
            frame.source_rect,
            (
                frame.source_offset[0] + frame_offset[0],
                frame.source_offset[1] + frame_offset[1],
            ),
            source_size,
            master_anchor,
            bounds,
            frame.source_hash,
            master_semantic_anchors,
        ))

        resized = _resize_rgba(frame.canvas, (scaled_width, runtime_height))
        runtime_frame = Image.new("RGBA", (output_width, runtime_height), (0, 0, 0, 0))
        runtime_offset = runtime_frame_offsets[index - 1]
        runtime_frame.alpha_composite(
            resized,
            (runtime_offset[0] - crop_left, runtime_offset[1]),
        )
        output_path = clip_output / f"frame_{index:02d}.png"
        runtime_frame.save(output_path, format="PNG", optimize=True, compress_level=9)
        runtime_bounds = _alpha_bounds(runtime_frame, 32)
        runtime_descriptors.append(_frame_descriptor(
            _resource_path(project_root, output_path),
            (0, 0, output_width, runtime_height),
            (0, 0),
            (output_width, runtime_height),
            runtime_anchor,
            runtime_bounds,
            _sha256(output_path),
            runtime_semantic_anchors,
        ))

    runtime_union = _union((
        frame["visualBounds"]["x"],
        frame["visualBounds"]["y"],
        frame["visualBounds"]["x"] + frame["visualBounds"]["width"],
        frame["visualBounds"]["y"] + frame["visualBounds"]["height"],
    ) for frame in runtime_descriptors)

    expected = {f"frame_{index:02d}.png" for index in range(1, len(frames) + 1)}
    for stale in clip_output.glob("frame_*.png"):
        if stale.name not in expected:
            stale.unlink()

    common = {
        "sourceType": clip_spec["source"]["type"],
        "fps": float(clip_spec["fps"]),
        "loop": bool(clip_spec["loop"]),
        "frameCount": len(frames),
    }
    master_clip = {
        **common,
        "frameWidth": source_width,
        "frameHeight": source_height,
        "visualBounds": _rect_dict(visual_union),
        "footAnchor": master_descriptors[0]["footAnchor"],
        "frames": master_descriptors,
    }
    if master_semantic_anchors:
        master_clip["semanticAnchors"] = master_descriptors[0]["semanticAnchors"]
    if registration:
        master_clip["spatialRegistration"] = registration
    runtime_clip = {
        **common,
        "frameWidth": output_width,
        "frameHeight": runtime_height,
        "visualBounds": _rect_dict(runtime_union),
        "footAnchor": runtime_descriptors[0]["footAnchor"],
        "sourceCrop": {
            "scaledCanvasWidth": scaled_width,
            "left": crop_left,
            "right": crop_right,
        },
        "scaleFromMaster": scale,
        "frames": runtime_descriptors,
    }
    if runtime_semantic_anchors:
        runtime_clip["semanticAnchors"] = runtime_descriptors[0]["semanticAnchors"]
    if registration:
        runtime_clip["spatialRegistration"] = {
            **registration,
            "referenceFeature": {
                "x": int(round(registration["referenceFeature"]["x"] * scale)) - crop_left,
                "y": int(round(registration["referenceFeature"]["y"] * scale)),
            },
            "sharedContentOffset": {
                "x": runtime_shared_offset[0], "y": runtime_shared_offset[1],
            },
            "referenceRelativePositions": [
                {
                    "x": int(round(position["x"] * scale)),
                    "y": int(round(position["y"] * scale)),
                }
                for position in registration["referenceRelativePositions"]
            ],
            "frameCorrections": [
                {"x": correction[0], "y": correction[1]}
                for correction in runtime_frame_corrections
            ],
        }
    return master_clip, runtime_clip


def build(spec_path: Path) -> dict[str, Any]:
    project_root = Path(__file__).resolve().parents[1]
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    if spec.get("schemaVersion") != 1:
        raise ValueError("unsupported processor spec schemaVersion")

    output_root = (project_root / spec["output"]["imageRoot"]).resolve()
    for clip in spec["clips"].values():
        source = clip["source"]
        source_path = project_root / (source.get("root") or source.get("texture"))
        resolved_source = source_path.resolve()
        if output_root == resolved_source or output_root in resolved_source.parents or resolved_source in output_root.parents:
            raise ValueError("runtime output must not overwrite or contain a Master source")

    master_clips: dict[str, Any] = {}
    runtime_clips: dict[str, Any] = {}
    for clip_name in sorted(spec["clips"]):
        master, runtime = _process_clip(
            project_root,
            clip_name,
            spec["clips"][clip_name],
            spec["runtime"],
            output_root,
        )
        master_clips[clip_name] = master
        runtime_clips[clip_name] = runtime

    variants = {
        spec["runtimeVariant"]: {"kind": "runtime", "clips": runtime_clips},
    }
    if spec["output"].get("includeMasterVariant", True):
        variants[spec["masterVariant"]] = {"kind": "master", "clips": master_clips}

    manifest = {
        "schemaVersion": 1,
        "processorVersion": PROCESSOR_VERSION,
        "assetId": spec["assetId"],
        "runtimePolicy": {
            "targetFrameHeight": int(spec["runtime"]["frameHeight"]),
            "horizontalPadding": int(spec["runtime"]["horizontalPadding"]),
            "widthAlignment": int(spec["runtime"]["widthAlignment"]),
            "resampling": spec["runtime"]["resampling"],
            "cropPolicy": "per-clip-alpha-union",
            "anchorSemantic": "foot-center",
            "registrationPolicy": "optional-reference-relative-xy",
            "visualAlphaThreshold": 32,
        },
        "variants": variants,
    }

    json_path = project_root / spec["output"]["jsonManifest"]
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def validate(manifest: dict[str, Any], project_root: Path) -> list[str]:
    errors: list[str] = []
    variants = manifest.get("variants", {})
    for variant_name, variant in variants.items():
        for clip_name, clip in variant.get("clips", {}).items():
            frames = clip.get("frames", [])
            if len(frames) != clip.get("frameCount"):
                errors.append(f"{variant_name}/{clip_name}: frame count mismatch")
            anchors = {
                (round(frame["footAnchor"]["normalizedX"], 8), round(frame["footAnchor"]["normalizedY"], 8))
                for frame in frames
            }
            if len(anchors) != 1:
                errors.append(f"{variant_name}/{clip_name}: frame anchors are not shared")
            for frame in frames:
                texture = project_root / "assets" / frame["texture"]
                if not texture.exists():
                    errors.append(f"{variant_name}/{clip_name}: missing {frame['texture']}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Build compact Companion runtime animation frames")
    parser.add_argument("command", choices=("build", "validate"), nargs="?", default="build")
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    args = parser.parse_args()
    project_root = Path(__file__).resolve().parents[1]
    spec = json.loads(args.spec.read_text(encoding="utf-8"))
    manifest_path = project_root / spec["output"]["jsonManifest"]
    manifest = build(args.spec) if args.command == "build" else json.loads(manifest_path.read_text(encoding="utf-8"))
    errors = validate(manifest, project_root)
    result = {
        "mode": "COMPANION_RUNTIME_ASSET_PROCESSOR",
        "command": args.command,
        "manifest": manifest_path.relative_to(project_root).as_posix(),
        "errors": errors,
        "status": "pass" if not errors else "fail",
    }
    print(json.dumps(result, ensure_ascii=False))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
