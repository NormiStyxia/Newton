#!/usr/bin/env python3
"""Offline trajectory contract for Phaser Matter and Maker Box2D captures.

This tool intentionally does not import either game runtime.  It validates
recordings exported by a runtime-specific probe, normalizes them into the
laboratory viewport coordinate system, and compares them at simulation time.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
LAB_WIDTH = 1500.0
LAB_HEIGHT = 596.0
PLAYFIELD_WIDTH = 1400.0
PLAYFIELD_HEIGHT = 700.0
PIXELS_PER_METER = 100.0
MATTER_VELOCITY_TO_WORLD = 60.0 / PIXELS_PER_METER

COORDINATE_SPACES = {
    "lab-viewport-px",
    "phaser-playfield",
    "maker-centered-px",
    "maker-world-m",
}
ENGINES = {"phaser-matter", "maker-box2d"}


@dataclass(frozen=True)
class Tolerance:
    position_px: float
    velocity_px_per_step: float
    angle_deg: float
    contact_time_ms: float


CASE_SPECS: dict[str, dict[str, Any]] = {
    "free_flight": {
        "description": "No-contact integration and air damping.",
        "duration_ms": 1000.0,
        "expected_contacts": 0,
        "initial_lab_viewport": {"x": 310.0, "y": 238.0, "vx": 12.0, "vy": -8.0},
        "tolerance": Tolerance(1.5, 0.15, 4.0, 16.667),
    },
    "ground_slide": {
        "description": "Apple tangent to the probe floor top at y=580/700*596, with horizontal speed.",
        "duration_ms": 1000.0,
        "expected_contacts": 1,
        "initial_lab_viewport": {"x": 510.0, "y": 466.8285714285714, "vx": 12.0, "vy": 0.0},
        "tolerance": Tolerance(10.0, 0.55, 7.0, 20.0),
    },
    "right_wall": {
        "description": "Zero-restitution collision with the 24px probe wall centered at x=1486.",
        "duration_ms": 500.0,
        "expected_contacts": 1,
        "initial_lab_viewport": {"x": 1410.0, "y": 298.0, "vx": 18.0, "vy": 0.0},
        "tolerance": Tolerance(10.0, 0.70, 8.0, 20.0),
    },
    "spring_exit": {
        "description": "Pre-solve velocity plus one upward spring exit impulse.",
        "duration_ms": 500.0,
        "expected_contacts": 1,
        "initial_lab_viewport": {"x": 510.0, "y": 288.0, "vx": 0.0, "vy": 20.0},
        "tolerance": Tolerance(18.0, 1.80, 12.0, 35.0),
    },
}

REQUIRED_SUITE_KEYS = frozenset(
    (case, time_scale)
    for case in CASE_SPECS
    for time_scale in (0.05, 1.0)
)


BASELINE_MATERIAL = {
    "apple_friction": 0.1,
    "apple_friction_air": 0.01,
    "apple_restitution": 0.0,
    "contact_friction": 0.1,
    "contact_restitution": 0.0,
    "matter_force_scale": 0.001,
    "matter_base_delta_ms": 1000.0 / 60.0,
    # PlayScene.ts calls setCircle(APPLE_RADIUS), where APPLE_RADIUS is 27.
    # GoldenPath.test.ts uses 34 only in its independent toy model.
    "apple_radius_px": 27.0,
}


def sample(t_ms: float, x: float, y: float, vx: float, vy: float, angle_deg: float | None = None) -> dict[str, float | None]:
    return {
        "t_ms": t_ms,
        "x": x,
        "y": y,
        "vx": vx,
        "vy": vy,
        "angle_deg": angle_deg,
    }


# These values were sampled from Phaser 3.90's bundled CustomMain.js at 60 Hz.
# Coordinates are laboratory-local pixels, not browser or display pixels.
REFERENCE_RECORDS = [
    {
        "schema_version": SCHEMA_VERSION,
        "engine": "phaser-matter",
        "case": "free_flight",
        "time_scale": 1.0,
        "coordinate_space": "lab-viewport-px",
        "material": BASELINE_MATERIAL,
        "samples": [
            sample(0.0, 310.0, 238.0, 12.0, -8.0, 0.0),
            sample(16.667, 321.88, 230.357778, 11.88, -7.642222, 0.0),
            sample(250.0, 476.250675, 158.993359, 10.3207, -2.993199, 0.0),
            sample(500.0, 619.235956, 149.352056, 8.876404, 1.312942, 0.0),
            sample(1000.0, 847.977909, 300.695494, 6.56588, 8.201729, 0.0),
        ],
        "events": [],
    },
    {
        "schema_version": SCHEMA_VERSION,
        "engine": "phaser-matter",
        "case": "ground_slide",
        "time_scale": 1.0,
        "coordinate_space": "lab-viewport-px",
        "material": BASELINE_MATERIAL,
        "samples": [
            sample(0.0, 510.0, 466.828571, 12.0, 0.0, 0.0),
            sample(16.667, 521.88, 466.903029, 11.08, 0.0, 0.0),
            sample(250.0, 606.273052, 466.946068, 3.364391, 0.07459, 72.930014),
            sample(500.0, 652.254747, 466.967747, 2.78933, 0.189126, 170.577025),
            sample(1000.0, 720.213243, 466.940416, 1.817253, -0.097017, 315.406415),
        ],
        "events": [{"t_ms": 16.667, "phase": "begin", "other": "world-floor"}],
    },
    {
        "schema_version": SCHEMA_VERSION,
        "engine": "phaser-matter",
        "case": "right_wall",
        "time_scale": 1.0,
        "coordinate_space": "lab-viewport-px",
        "material": BASELINE_MATERIAL,
        "samples": [
            sample(0.0, 1410.0, 298.0, 18.0, 0.0, 0.0),
            sample(16.667, 1427.82, 298.277778, 17.82, 0.277778, 0.0),
            sample(250.0, 1446.852008, 314.949405, -0.038198, 2.334474, -15.633814),
            sample(500.0, 1446.322801, 379.118868, -0.032853, 5.895052, -38.332662),
        ],
        "events": [{"t_ms": 50.0, "phase": "begin", "other": "world-right"}],
    },
    {
        "schema_version": SCHEMA_VERSION,
        "engine": "phaser-matter",
        "case": "spring_exit",
        "time_scale": 1.0,
        "coordinate_space": "lab-viewport-px",
        "material": BASELINE_MATERIAL,
        "samples": [
            sample(0.0, 510.0, 288.0, 0.0, 20.0, 0.0),
            sample(16.667, 510.0, 308.077778, 0.0, 20.077778, 0.0),
            sample(250.0, 506.708026, 388.732131, -0.333667, -0.036093, -7.682984),
            sample(500.0, 502.50474, 388.641049, -0.26383, 0.01281, -16.627067),
        ],
        "events": [{"t_ms": 83.333, "phase": "begin", "other": "spring"}],
    },
]


class ContractError(ValueError):
    pass


def finite(value: Any, name: str) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(float(value)):
        raise ContractError(f"{name} must be a finite number")
    return float(value)


def mapping(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ContractError(f"{name} must be an object")
    return value


def validate_sample(raw: Any, label: str) -> dict[str, float | None]:
    item = mapping(raw, label)
    normalized: dict[str, float | None] = {
        "t_ms": finite(item.get("t_ms"), f"{label}.t_ms"),
        "x": finite(item.get("x"), f"{label}.x"),
        "y": finite(item.get("y"), f"{label}.y"),
        "vx": finite(item.get("vx"), f"{label}.vx"),
        "vy": finite(item.get("vy"), f"{label}.vy"),
        "angle_deg": None,
    }
    if item.get("angle_deg") is not None:
        normalized["angle_deg"] = finite(item["angle_deg"], f"{label}.angle_deg")
    return normalized


def validate_event(raw: Any, label: str) -> dict[str, Any]:
    item = mapping(raw, label)
    phase = item.get("phase")
    other = item.get("other")
    if phase not in {"begin", "end"}:
        raise ContractError(f"{label}.phase must be begin or end")
    if not isinstance(other, str) or not other:
        raise ContractError(f"{label}.other must be a non-empty string")
    return {"t_ms": finite(item.get("t_ms"), f"{label}.t_ms"), "phase": phase, "other": other}


def validate_material(raw: Any, label: str) -> dict[str, float]:
    item = mapping(raw, label)
    return {key: finite(item.get(key), f"{label}.{key}") for key in BASELINE_MATERIAL}


def validate_record(raw: Any, label: str) -> dict[str, Any]:
    item = mapping(raw, label)
    if item.get("schema_version") != SCHEMA_VERSION:
        raise ContractError(f"{label}.schema_version must be {SCHEMA_VERSION}")
    engine = item.get("engine")
    if engine not in ENGINES:
        raise ContractError(f"{label}.engine must be one of {sorted(ENGINES)}")
    case = item.get("case")
    if case not in CASE_SPECS:
        raise ContractError(f"{label}.case must be one of {sorted(CASE_SPECS)}")
    coordinate_space = item.get("coordinate_space")
    if coordinate_space not in COORDINATE_SPACES:
        raise ContractError(f"{label}.coordinate_space must be one of {sorted(COORDINATE_SPACES)}")
    time_scale = finite(item.get("time_scale"), f"{label}.time_scale")
    if time_scale not in {0.05, 1.0}:
        raise ContractError(f"{label}.time_scale must be 0.05 or 1.0")
    samples_raw = item.get("samples")
    events_raw = item.get("events")
    if not isinstance(samples_raw, list) or not samples_raw:
        raise ContractError(f"{label}.samples must be a non-empty array")
    if not isinstance(events_raw, list):
        raise ContractError(f"{label}.events must be an array")
    samples = [validate_sample(value, f"{label}.samples[{index}]") for index, value in enumerate(samples_raw)]
    events = [validate_event(value, f"{label}.events[{index}]") for index, value in enumerate(events_raw)]
    if any(later["t_ms"] <= earlier["t_ms"] for earlier, later in zip(samples, samples[1:])):
        raise ContractError(f"{label}.samples must be strictly ordered by t_ms")
    return {
        "schema_version": SCHEMA_VERSION,
        "engine": engine,
        "case": case,
        "time_scale": time_scale,
        "coordinate_space": coordinate_space,
        "material": validate_material(item.get("material"), f"{label}.material"),
        "samples": samples,
        "events": events,
    }


def parse_records(path: Path) -> list[dict[str, Any]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ContractError(f"cannot read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ContractError(f"cannot decode {path}: {error}") from error
    records_raw = payload.get("records") if isinstance(payload, dict) and "records" in payload else [payload]
    if not isinstance(records_raw, list):
        raise ContractError(f"{path}: records must be an array")
    return [validate_record(value, f"{path.name}.records[{index}]") for index, value in enumerate(records_raw)]


def telemetry_payloads(lines: Iterable[str], source: str) -> Iterable[dict[str, Any]]:
    prefix = "[PhysicsTelemetry]"
    for line_number, line in enumerate(lines, start=1):
        start = line.find(prefix)
        if start < 0:
            continue
        encoded = line[start + len(prefix):].strip()
        try:
            payload = json.loads(encoded)
        except json.JSONDecodeError as error:
            raise ContractError(f"{source}:{line_number}: invalid PhysicsTelemetry JSON: {error.msg}") from error
        yield mapping(payload, f"{source}:{line_number}")


def parse_maker_log_lines(lines: Iterable[str], source: str) -> list[dict[str, Any]]:
    completed: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for payload in telemetry_payloads(lines, source):
        event_type = payload.get("type")
        if event_type == "begin":
            if current is not None:
                raise ContractError(f"{source}: received begin before the previous telemetry session ended")
            case = payload.get("case")
            if case not in CASE_SPECS:
                raise ContractError(f"{source}: telemetry begin has an unknown case")
            scale = finite(payload.get("scale"), f"{source}.begin.scale")
            if scale not in {0.05, 1.0}:
                raise ContractError(f"{source}: telemetry begin scale must be 0.05 or 1.0")
            current = {
                "schema_version": SCHEMA_VERSION,
                "engine": "maker-box2d",
                "case": case,
                "time_scale": scale,
                "coordinate_space": "maker-centered-px",
                "material": None,
                "samples": [],
                "events": [],
            }
            continue
        if current is None:
            continue
        if payload.get("case") != current["case"]:
            raise ContractError(f"{source}: telemetry event case does not match its begin event")
        if event_type == "material":
            if current["material"] is not None:
                raise ContractError(f"{source}: telemetry session emitted material more than once")
            scale = finite(payload.get("scale"), f"{source}.material.scale")
            if not math.isclose(scale, current["time_scale"], abs_tol=1e-12):
                raise ContractError(f"{source}: material scale does not match begin scale")
            current["material"] = validate_material(payload.get("material"), f"{source}.material")
        elif event_type == "sample":
            if current["material"] is None:
                raise ContractError(f"{source}: sample arrived before an explicit material event")
            scale = finite(payload.get("scale"), f"{source}.sample.scale")
            if not math.isclose(scale, current["time_scale"], abs_tol=1e-12):
                raise ContractError(f"{source}: sample scale does not match begin scale")
            current["samples"].append(
                {
                    "t_ms": finite(payload.get("t"), f"{source}.sample.t"),
                    "x": finite(payload.get("x"), f"{source}.sample.x"),
                    "y": finite(payload.get("y"), f"{source}.sample.y"),
                    "vx": finite(payload.get("vx"), f"{source}.sample.vx"),
                    "vy": finite(payload.get("vy"), f"{source}.sample.vy"),
                    "angle_deg": finite(payload.get("angle"), f"{source}.sample.angle"),
                }
            )
        elif event_type in {"contact_begin", "contact_end"}:
            current["events"].append(
                {
                    "t_ms": finite(payload.get("t"), f"{source}.contact.t"),
                    "phase": "begin" if event_type == "contact_begin" else "end",
                    "other": payload.get("contact"),
                }
            )
        elif event_type == "end":
            if current["material"] is None:
                raise ContractError(f"{source}: telemetry session ended without an explicit material event")
            completed.append(validate_record(current, f"{source}.completed[{len(completed)}]"))
            current = None
    if current is not None:
        raise ContractError(f"{source}: telemetry session did not emit an end event")
    if not completed:
        raise ContractError(f"{source}: no complete PhysicsTelemetry sessions found")
    return completed


def parse_maker_log(path: Path) -> list[dict[str, Any]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise ContractError(f"cannot read {path}: {error}") from error
    return parse_maker_log_lines(lines, str(path))


def normalise_sample(record: dict[str, Any], raw: dict[str, float | None]) -> dict[str, float | None]:
    space = record["coordinate_space"]
    x, y, vx, vy = raw["x"], raw["y"], raw["vx"], raw["vy"]
    assert isinstance(x, float) and isinstance(y, float) and isinstance(vx, float) and isinstance(vy, float)
    if space == "lab-viewport-px":
        return dict(raw)
    if space == "phaser-playfield":
        return {
            "t_ms": raw["t_ms"],
            "x": x * LAB_WIDTH / PLAYFIELD_WIDTH,
            "y": y * LAB_HEIGHT / PLAYFIELD_HEIGHT,
            "vx": vx * LAB_WIDTH / PLAYFIELD_WIDTH,
            "vy": vy * LAB_HEIGHT / PLAYFIELD_HEIGHT,
            "angle_deg": raw["angle_deg"],
        }
    if space == "maker-centered-px":
        # PhysicsTelemetry reports position relative to the laboratory center
        # and already converts Box2D velocity back to Matter frame units.
        return {
            "t_ms": raw["t_ms"],
            "x": LAB_WIDTH * 0.5 + x,
            "y": LAB_HEIGHT * 0.5 - y,
            "vx": vx,
            "vy": vy,
            "angle_deg": raw["angle_deg"],
        }
    # Maker body velocity is metres/second. It contains Matter velocity times
    # MATTER_VELOCITY_TO_WORLD and the active Matter timeScale.
    velocity_scale = MATTER_VELOCITY_TO_WORLD * record["time_scale"]
    return {
        "t_ms": raw["t_ms"],
        "x": LAB_WIDTH * 0.5 + x * PIXELS_PER_METER,
        "y": LAB_HEIGHT * 0.5 - y * PIXELS_PER_METER,
        "vx": vx / velocity_scale,
        "vy": -vy / velocity_scale,
        "angle_deg": raw["angle_deg"],
    }


def normalise_record(record: dict[str, Any]) -> dict[str, Any]:
    return {**record, "coordinate_space": "lab-viewport-px", "samples": [normalise_sample(record, value) for value in record["samples"]]}


def interpolate(samples: list[dict[str, float | None]], time_ms: float) -> dict[str, float | None] | None:
    if time_ms < samples[0]["t_ms"] - 0.001 or time_ms > samples[-1]["t_ms"] + 0.001:
        return None
    for before, after in zip(samples, samples[1:]):
        if before["t_ms"] <= time_ms <= after["t_ms"]:
            span = after["t_ms"] - before["t_ms"]
            progress = 0.0 if span == 0 else (time_ms - before["t_ms"]) / span
            result: dict[str, float | None] = {"t_ms": time_ms}
            for key in ("x", "y", "vx", "vy"):
                result[key] = float(before[key]) + (float(after[key]) - float(before[key])) * progress
            before_angle, after_angle = before["angle_deg"], after["angle_deg"]
            if before_angle is None or after_angle is None:
                result["angle_deg"] = None
            else:
                delta = (float(after_angle) - float(before_angle) + 540.0) % 360.0 - 180.0
                result["angle_deg"] = float(before_angle) + delta * progress
            return result
    if math.isclose(float(samples[-1]["t_ms"]), time_ms, abs_tol=0.001):
        return dict(samples[-1])
    return None


def angular_distance(first: float, second: float) -> float:
    return abs((first - second + 180.0) % 360.0 - 180.0)


def event_key(event: dict[str, Any]) -> tuple[str, str]:
    return event["phase"], event["other"]


def match_contact_events(
    expected_events: Iterable[dict[str, Any]], actual_events: Iterable[dict[str, Any]]
) -> Iterable[tuple[dict[str, Any], dict[str, Any] | None, int]]:
    """Match each phase/other contact occurrence to its next Maker occurrence.

    Matter may emit repeated begin events for a resting contact at slow time
    scales.  A lookup by just phase/other would repeatedly select the first
    Maker event and hide drift in all later occurrences, so matching keeps a
    separate occurrence cursor for every contact key.
    """
    actual_by_key: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for event in actual_events:
        actual_by_key.setdefault(event_key(event), []).append(event)

    expected_occurrences: dict[tuple[str, str], int] = {}
    for expected in expected_events:
        key = event_key(expected)
        occurrence = expected_occurrences.get(key, 0) + 1
        expected_occurrences[key] = occurrence
        candidates = actual_by_key.get(key, [])
        actual = candidates[occurrence - 1] if occurrence <= len(candidates) else None
        yield expected, actual, occurrence


def compare_records(source_raw: dict[str, Any], maker_raw: dict[str, Any]) -> dict[str, Any]:
    errors: list[str] = []
    if source_raw["engine"] != "phaser-matter":
        errors.append("source record must use engine=phaser-matter")
    if maker_raw["engine"] != "maker-box2d":
        errors.append("maker record must use engine=maker-box2d")
    if source_raw["case"] != maker_raw["case"]:
        errors.append("case differs")
    if not math.isclose(source_raw["time_scale"], maker_raw["time_scale"], abs_tol=1e-12):
        errors.append("time_scale differs")
    if errors:
        return {"case": source_raw["case"], "time_scale": source_raw["time_scale"], "status": "fail", "errors": errors}

    case = source_raw["case"]
    tolerance: Tolerance = CASE_SPECS[case]["tolerance"]
    source = normalise_record(source_raw)
    maker = normalise_record(maker_raw)
    max_position_error = 0.0
    max_velocity_error = 0.0
    max_angle_error = 0.0
    compared_samples = 0
    for expected in source["samples"]:
        actual = interpolate(maker["samples"], float(expected["t_ms"]))
        if actual is None:
            errors.append(f"Maker samples do not cover t={expected['t_ms']:.3f}ms")
            continue
        position_error = math.hypot(float(expected["x"]) - float(actual["x"]), float(expected["y"]) - float(actual["y"]))
        velocity_error = math.hypot(float(expected["vx"]) - float(actual["vx"]), float(expected["vy"]) - float(actual["vy"]))
        max_position_error = max(max_position_error, position_error)
        max_velocity_error = max(max_velocity_error, velocity_error)
        if expected["angle_deg"] is not None and actual["angle_deg"] is not None:
            max_angle_error = max(max_angle_error, angular_distance(float(expected["angle_deg"]), float(actual["angle_deg"])))
        compared_samples += 1
    if max_position_error > tolerance.position_px:
        errors.append(f"max position error {max_position_error:.3f}px > {tolerance.position_px:.3f}px")
    if max_velocity_error > tolerance.velocity_px_per_step:
        errors.append(f"max velocity error {max_velocity_error:.3f} > {tolerance.velocity_px_per_step:.3f}")
    if max_angle_error > tolerance.angle_deg:
        errors.append(f"max angle error {max_angle_error:.3f}deg > {tolerance.angle_deg:.3f}deg")

    for expected_event, actual_event, occurrence in match_contact_events(source["events"], maker["events"]):
        if actual_event is None:
            errors.append(
                f"missing contact {expected_event['phase']}:{expected_event['other']} occurrence {occurrence}"
            )
        elif abs(float(expected_event["t_ms"]) - float(actual_event["t_ms"])) > tolerance.contact_time_ms:
            errors.append(
                f"contact {expected_event['phase']}:{expected_event['other']} occurrence {occurrence} at "
                f"{actual_event['t_ms']:.3f}ms differs from "
                f"{expected_event['t_ms']:.3f}ms by more than {tolerance.contact_time_ms:.3f}ms"
            )
    expected_contact_count = CASE_SPECS[case]["expected_contacts"]
    if expected_contact_count == 0 and maker["events"]:
        errors.append(f"Maker emitted {len(maker['events'])} unexpected contacts; expected 0")
    elif len(maker["events"]) < expected_contact_count:
        errors.append(f"Maker emitted {len(maker['events'])} contacts; expected at least {expected_contact_count}")

    for key, expected_value in BASELINE_MATERIAL.items():
        actual_value = maker["material"][key]
        if not math.isclose(actual_value, expected_value, rel_tol=0.0, abs_tol=1e-9):
            errors.append(f"material.{key}={actual_value} differs from expected {expected_value}")
    return {
        "case": case,
        "time_scale": source["time_scale"],
        "status": "pass" if not errors else "fail",
        "compared_samples": compared_samples,
        "max_position_error_px": max_position_error,
        "max_velocity_error": max_velocity_error,
        "max_angle_error_deg": max_angle_error,
        "errors": errors,
    }


def records_by_key(records: Iterable[dict[str, Any]]) -> dict[tuple[str, float], dict[str, Any]]:
    indexed: dict[tuple[str, float], dict[str, Any]] = {}
    for record in records:
        key = (record["case"], record["time_scale"])
        if key in indexed:
            raise ContractError(f"duplicate record for {key[0]} at {key[1]}x")
        indexed[key] = record
    return indexed


def compare_suites(source_records: list[dict[str, Any]], maker_records: list[dict[str, Any]]) -> dict[str, Any]:
    source_by_key = records_by_key(source_records)
    maker_by_key = records_by_key(maker_records)
    results: list[dict[str, Any]] = []
    missing_source = sorted(REQUIRED_SUITE_KEYS - set(source_by_key))
    missing_maker = sorted(REQUIRED_SUITE_KEYS - set(maker_by_key))
    for case, scale in sorted(REQUIRED_SUITE_KEYS):
        source = source_by_key.get((case, scale))
        maker = maker_by_key.get((case, scale))
        if source is None or maker is None:
            missing_sides = []
            if source is None:
                missing_sides.append("Phaser")
            if maker is None:
                missing_sides.append("Maker")
            results.append(
                {
                    "case": case,
                    "time_scale": scale,
                    "status": "fail",
                    "errors": [f"required record missing from {' and '.join(missing_sides)} suite"],
                }
            )
            continue
        results.append(compare_records(source, maker))
    errors = [error for result in results for error in result.get("errors", [])]
    return {
        "mode": "PHYSICS_TRAJECTORY_COMPARE",
        "schema_version": SCHEMA_VERSION,
        "status": "pass" if not errors else "fail",
        "required_records": len(REQUIRED_SUITE_KEYS),
        "source_record_count": len(source_by_key),
        "maker_record_count": len(maker_by_key),
        "missing_source_keys": [f"{case}@{scale}x" for case, scale in missing_source],
        "missing_maker_keys": [f"{case}@{scale}x" for case, scale in missing_maker],
        "results": results,
    }


def reference_suite() -> dict[str, Any]:
    return {"schema_version": SCHEMA_VERSION, "records": REFERENCE_RECORDS}


def template_suite(engine: str) -> dict[str, Any]:
    coordinate_space = "lab-viewport-px" if engine == "phaser-matter" else "maker-centered-px"
    records = []
    for case in CASE_SPECS:
        for time_scale in (1.0, 0.05):
            records.append(
                {
                    "schema_version": SCHEMA_VERSION,
                    "engine": engine,
                    "case": case,
                    "time_scale": time_scale,
                    "coordinate_space": coordinate_space,
                    "material": BASELINE_MATERIAL,
                    "samples": [],
                    "events": [],
                }
            )
    return {"schema_version": SCHEMA_VERSION, "records": records}


def self_test() -> dict[str, Any]:
    checks = 0
    errors: list[str] = []

    def expect(condition: bool, message: str) -> None:
        nonlocal checks
        checks += 1
        if not condition:
            errors.append(message)

    records = [validate_record(item, f"reference[{index}]") for index, item in enumerate(REFERENCE_RECORDS)]
    expect(len(records) == len(CASE_SPECS), "reference does not cover every case")
    expect({record["case"] for record in records} == set(CASE_SPECS), "reference case IDs differ")
    ground_reference = next(record for record in records if record["case"] == "ground_slide")
    expected_ground_y = 580.0 / PLAYFIELD_HEIGHT * LAB_HEIGHT - BASELINE_MATERIAL["apple_radius_px"]
    expect(
        math.isclose(CASE_SPECS["ground_slide"]["initial_lab_viewport"]["y"], expected_ground_y, abs_tol=1e-12),
        "ground-slide specification no longer matches the probe floor geometry",
    )
    expect(
        math.isclose(float(ground_reference["samples"][0]["y"]), expected_ground_y, abs_tol=1e-6),
        "built-in ground-slide reference no longer matches the Phaser capture geometry",
    )
    maker_free = validate_record(
        {
            "schema_version": SCHEMA_VERSION,
            "engine": "maker-box2d",
            "case": "free_flight",
            "time_scale": 1.0,
            "coordinate_space": "maker-world-m",
            "material": BASELINE_MATERIAL,
            "samples": [sample(0.0, -4.4, 0.6, 7.2, 4.8, 0.0), sample(1000.0, 0.0, 0.0, 1.0, 1.0, 0.0)],
            "events": [],
        },
        "maker_free",
    )
    normalised = normalise_sample(maker_free, maker_free["samples"][0])
    expect(math.isclose(float(normalised["x"]), 310.0, abs_tol=1e-12), "Maker x normalization changed")
    expect(math.isclose(float(normalised["y"]), 238.0, abs_tol=1e-12), "Maker y normalization changed")
    expect(math.isclose(float(normalised["vx"]), 12.0, abs_tol=1e-12), "Maker vx normalization changed")
    expect(math.isclose(float(normalised["vy"]), -8.0, abs_tol=1e-12), "Maker vy normalization changed")
    maker_centered = validate_record(
        {
            "schema_version": SCHEMA_VERSION,
            "engine": "maker-box2d",
            "case": "free_flight",
            "time_scale": 1.0,
            "coordinate_space": "maker-centered-px",
            "material": BASELINE_MATERIAL,
            "samples": [sample(0.0, -440.0, 60.0, 12.0, -8.0, 0.0), sample(1000.0, 0.0, 0.0, 1.0, 1.0, 0.0)],
            "events": [],
        },
        "maker_centered",
    )
    centered = normalise_sample(maker_centered, maker_centered["samples"][0])
    expect(math.isclose(float(centered["x"]), 310.0, abs_tol=1e-12), "centered Maker x normalization changed")
    expect(math.isclose(float(centered["y"]), 238.0, abs_tol=1e-12), "centered Maker y normalization changed")
    log_records = parse_maker_log_lines(
        [
            '[PhysicsTelemetry] {"type":"begin","case":"free_flight","scale":1}',
            '[PhysicsTelemetry] {"type":"material","case":"free_flight","scale":1,"material":{"apple_friction":0.1,"apple_friction_air":0.01,"apple_restitution":0,"contact_friction":0.1,"contact_restitution":0,"matter_force_scale":0.001,"matter_base_delta_ms":16.666666666666668,"apple_radius_px":27}}',
            '[PhysicsTelemetry] {"type":"sample","case":"free_flight","t":0,"dt":0,"scale":1,"x":-440,"y":60,"vx":12,"vy":-8,"angle":0,"contact":""}',
            '[PhysicsTelemetry] {"type":"sample","case":"free_flight","t":1000,"dt":16.667,"scale":1,"x":0,"y":0,"vx":1,"vy":1,"angle":0,"contact":""}',
            '[PhysicsTelemetry] {"type":"end","case":"free_flight","t":1000}',
        ],
        "self-test-log",
    )
    expect(len(log_records) == 1 and log_records[0]["coordinate_space"] == "maker-centered-px", "log parser changed")
    try:
        parse_maker_log_lines(
            [
                '[PhysicsTelemetry] {"type":"begin","case":"free_flight","scale":1}',
                '[PhysicsTelemetry] {"type":"sample","case":"free_flight","t":0,"dt":0,"scale":1,"x":0,"y":0,"vx":0,"vy":0,"angle":0,"contact":""}',
            ],
            "missing-material-log",
        )
    except ContractError:
        missing_material_rejected = True
    else:
        missing_material_rejected = False
    expect(missing_material_rejected, "log parser accepts a sample without material")
    source_free = next(record for record in records if record["case"] == "free_flight")
    identical = compare_records(source_free, {**source_free, "engine": "maker-box2d"})
    expect(identical["status"] == "pass", "reference cannot compare to canonical coordinates")

    duplicate_contact_source = {
        **ground_reference,
        "events": [
            {"t_ms": 10.0, "phase": "begin", "other": "world-floor"},
            {"t_ms": 20.0, "phase": "begin", "other": "world-floor"},
        ],
    }
    duplicate_contact_maker = {
        **duplicate_contact_source,
        "engine": "maker-box2d",
        "events": [
            {"t_ms": 10.0, "phase": "begin", "other": "world-floor"},
            {"t_ms": 60.0, "phase": "begin", "other": "world-floor"},
        ],
    }
    duplicate_contact_result = compare_records(duplicate_contact_source, duplicate_contact_maker)
    expect(
        duplicate_contact_result["status"] == "fail"
        and any("occurrence 2 at 60.000ms" in error for error in duplicate_contact_result["errors"]),
        "repeated contacts reuse the first Maker event instead of matching in occurrence order",
    )

    unexpected_contact_result = compare_records(
        source_free,
        {
            **source_free,
            "engine": "maker-box2d",
            "events": [{"t_ms": 10.0, "phase": "begin", "other": "world-floor"}],
        },
    )
    expect(
        unexpected_contact_result["status"] == "fail"
        and "expected 0" in "\n".join(unexpected_contact_result["errors"]),
        "no-contact cases accept unexpected Maker contacts",
    )

    full_source_records: list[dict[str, Any]] = []
    full_maker_records: list[dict[str, Any]] = []
    for record in records:
        for time_scale in (0.05, 1.0):
            source_record = {**record, "time_scale": time_scale}
            full_source_records.append(source_record)
            full_maker_records.append({**source_record, "engine": "maker-box2d"})
    full_suite_result = compare_suites(full_source_records, full_maker_records)
    expect(
        full_suite_result["status"] == "pass"
        and full_suite_result["required_records"] == 8
        and len(full_suite_result["results"]) == 8,
        "complete eight-record suites do not compare successfully",
    )
    common_subset_result = compare_suites(full_source_records[:1], full_maker_records[:1])
    expect(
        common_subset_result["status"] == "fail"
        and len(common_subset_result["results"]) == 8
        and len(common_subset_result["missing_source_keys"]) == 7
        and len(common_subset_result["missing_maker_keys"]) == 7,
        "a common one-record subset can pass without all four cases at both time scales",
    )
    return {
        "mode": "PHYSICS_TRAJECTORY_CONTRACT_SELF_TEST",
        "schema_version": SCHEMA_VERSION,
        "checks": checks,
        "status": "pass" if not errors else "fail",
        "errors": errors,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="verify the schema, canonical Matter baselines, and coordinate transforms")
    parser.add_argument("--reference", action="store_true", help="print the reviewed 1x Phaser Matter reference suite")
    parser.add_argument("--template", choices=sorted(ENGINES), help="print an empty eight-run capture suite for the selected engine")
    parser.add_argument("--maker-log", metavar="LOG", help="parse complete [PhysicsTelemetry] sessions into a Maker capture suite")
    parser.add_argument("--compare", nargs=2, metavar=("PHASER_JSON", "MAKER_JSON"), help="compare exported source and Maker suites")
    args = parser.parse_args(argv)
    selected = sum(bool(value) for value in (args.self_test, args.reference, args.template, args.maker_log, args.compare))
    if selected != 1:
        parser.error("select exactly one of --self-test, --reference, --template, --maker-log, or --compare")
    try:
        if args.self_test:
            result = self_test()
        elif args.reference:
            result = reference_suite()
        elif args.template:
            result = template_suite(args.template)
        elif args.maker_log:
            result = {"schema_version": SCHEMA_VERSION, "records": parse_maker_log(Path(args.maker_log))}
        else:
            source_records = parse_records(Path(args.compare[0]))
            maker_records = parse_records(Path(args.compare[1]))
            result = compare_suites(source_records, maker_records)
    except ContractError as error:
        result = {"mode": "PHYSICS_TRAJECTORY_CONTRACT", "status": "fail", "errors": [str(error)]}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("status", "pass") == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
