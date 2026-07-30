#!/usr/bin/env python3
"""Regression contract for the Maker replay clock and physics-step timestamps."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def advance(playhead: float, duration: float, frame_delta_ms: float, speed: float) -> float:
    bounded_duration = max(0.0, duration)
    start = max(0.0, min(bounded_duration, playhead))
    return min(bounded_duration, start + max(0.0, frame_delta_ms) * max(0.0, speed))


def expect(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    errors: list[str] = []
    timeline = (ROOT / "scripts/game/replay/Timeline.lua").read_text(encoding="utf-8")
    controller = (ROOT / "scripts/game/replay/Controller.lua").read_text(encoding="utf-8")
    runtime = (ROOT / "scripts/game/AppRuntime.lua").read_text(encoding="utf-8")
    state = (ROOT / "scripts/game/State.lua").read_text(encoding="utf-8")

    # A replay at a fixed speed must depend only on accumulated wall time, not
    # how the renderer partitions that time into frames.
    duration = 3000.0
    whole = advance(0.0, duration, 1000.0, 1.0)
    partitioned = 0.0
    for delta in (17.0, 5.0, 31.0, 16.0, 43.0, 888.0):
        partitioned = advance(partitioned, duration, delta, 1.0)
    expect(whole == partitioned == 1000.0, "1x replay clock depends on frame partitioning", errors)
    expect(advance(100.0, duration, 400.0, 0.5) == 300.0, "0.5x replay increment is incorrect", errors)
    expect(advance(100.0, duration, 400.0, 2.0) == 900.0, "2x replay increment is incorrect", errors)
    expect(advance(2950.0, duration, 100.0, 1.0) == duration, "replay end is not clamped", errors)
    expect(advance(400.0, duration, -100.0, 2.0) == 400.0, "negative frame delta moves replay backwards", errors)

    expect("function ReplayTimeline.Advance" in timeline, "timeline has no single playback-clock primitive", errors)
    expect("ReplayTimeline.Advance(replayTime_, ReplayDuration(), math.max(0, dt) * 1000, replaySpeed_)" in controller,
           "controller does not use the shared playback clock", errors)
    expect("physicsStepTimeScale_" in state, "physics-step scale is not owned state", errors)
    expect("local physicsTimeScale = CurrentPhysicsTimeScale()" in runtime
           and "physicsStepTimeScale_ = physicsTimeScale" in runtime,
           "physics pre-step does not capture its time scale", errors)
    expect("local physicsTimeScale = CurrentPhysicsStepScale()" in runtime
           and "UpdateExperiment(eventData:GetFloat(\"TimeStep\") * physicsTimeScale)" in runtime,
           "replay recording does not use the time scale from its physical step", errors)
    expect("CurrentMatterVelocityToWorld(CurrentPhysicsStepScale())" in runtime,
           "spring exit does not use the time scale from its physical step", errors)

    if errors:
        print("REPLAY_TIMEBASE_VALIDATE fail")
        for error in errors:
            print(f"- {error}")
        return 1
    print("REPLAY_TIMEBASE_VALIDATE pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
