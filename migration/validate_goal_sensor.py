from __future__ import annotations

import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def circle_overlaps_oriented_box(
    circle_x: float,
    circle_y: float,
    radius: float,
    box_x: float,
    box_y: float,
    box_width: float,
    box_height: float,
    rotation_degrees: float,
) -> bool:
    inverse = math.radians(-rotation_degrees)
    dx, dy = circle_x - box_x, circle_y - box_y
    local_x = dx * math.cos(inverse) - dy * math.sin(inverse)
    local_y = dx * math.sin(inverse) + dy * math.cos(inverse)
    half_width, half_height = box_width * 0.5, box_height * 0.5
    closest_x = max(-half_width, min(local_x, half_width))
    closest_y = max(-half_height, min(local_y, half_height))
    return (local_x - closest_x) ** 2 + (local_y - closest_y) ** 2 <= radius**2


def main() -> int:
    main_lua = (ROOT / "scripts/main.lua").read_text(encoding="utf-8")
    errors: list[str] = []

    def expect(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    # Fixture-equivalent coverage: inside, tangency, outside, and rotation.
    expect(circle_overlaps_oriented_box(0, 0, 0.27, 0, 0, 1.53, 1.37, 0), "center overlap was rejected")
    expect(circle_overlaps_oriented_box(1.035, 0, 0.27, 0, 0, 1.53, 1.37, 0), "edge tangency was rejected")
    expect(not circle_overlaps_oriented_box(1.036, 0, 0.27, 0, 0, 1.53, 1.37, 0), "outside circle was accepted")
    expect(circle_overlaps_oriented_box(0.7, 0.7, 0.27, 0, 0, 1.53, 1.37, 45), "rotated fixture overlap was rejected")

    expect("function GoalSensorContainsApple()" in main_lua, "goal fixture overlap fallback is missing")
    expect("local rotation = math.rad(runtimeGoal.node.rotation2D)" in main_lua,
           "goal overlap does not account for fixture rotation")
    expect("return offsetX * offsetX + offsetY * offsetY <= apple_.radius * apple_.radius" in main_lua,
           "goal overlap does not use the apple fixture radius")
    expect("UpdateSpringExits()\n    RefreshGoalContact()\n    UpdateExperiment" in main_lua,
           "goal overlap is not refreshed before the physics-time stay counter")
    expect("if not GoalSensorContainsApple() then ResetGoal() end" in main_lua,
           "trigger EndContact still unconditionally clears the goal timer")

    if errors:
        print("GOAL_SENSOR_VALIDATE fail")
        for error in errors:
            print(f"- {error}")
        return 1
    print("GOAL_SENSOR_VALIDATE pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
