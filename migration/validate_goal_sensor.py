from __future__ import annotations

import math
from pathlib import Path

from runtime_source_index import legacy_main_source


ROOT = Path(__file__).resolve().parents[1]
GOAL_REQUIRED_STAY_MS = 1000


def circle_overlaps_sensor(
    circle_x: float,
    circle_y: float,
    radius: float,
    sensor_x: float,
    sensor_y: float,
    sensor_radius: float,
) -> bool:
    dx, dy = circle_x - sensor_x, circle_y - sensor_y
    overlap_radius = radius + sensor_radius
    return dx * dx + dy * dy <= overlap_radius * overlap_radius


def advance_goal_contact(
    state: dict[str, float | int | bool],
    geometry_inside: bool,
    delta_ms: float = 1000 / 60,
) -> tuple[dict[str, float | int | bool], bool]:
    """Model exact circular overlap timing independently of the game runtime."""
    next_state = dict(state)
    confirmed = geometry_inside
    next_state["confirmed"] = confirmed
    if confirmed:
        next_state["active"] = True
        next_state["misses"] = 0
        next_state["timer"] = float(next_state["timer"]) + delta_ms
    else:
        next_state.update(active=False, confirmed=False, misses=0, timer=0.0)
    completed = bool(next_state["active"] and next_state["confirmed"] and float(next_state["timer"]) >= GOAL_REQUIRED_STAY_MS)
    return next_state, completed


def main() -> int:
    main_lua = legacy_main_source()
    goal_lua = (ROOT / "scripts/game/gameplay/Goal.lua").read_text(encoding="utf-8")
    errors: list[str] = []

    def expect(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    # Circle-volume coverage: center, tangency, and separation.
    expect(circle_overlaps_sensor(0, 0, 0.27, 0, 0, 0.5), "center overlap was rejected")
    expect(circle_overlaps_sensor(0.77, 0, 0.27, 0, 0, 0.5), "edge tangency was rejected")
    expect(not circle_overlaps_sensor(0.771, 0, 0.27, 0, 0, 0.5), "outside circle was accepted")
    expect(not circle_overlaps_sensor(0.7, 0.7, 0.27, 0, 0, 0.5), "corner outside circular Sensor was accepted")

    state: dict[str, float | int | bool] = {"active": False, "confirmed": False, "misses": 0, "timer": 0.0}
    state, completed = advance_goal_contact(state, geometry_inside=True, delta_ms=999)
    expect(bool(state["active"]) and math.isclose(float(state["timer"]), 999), "overlap did not start the timer")
    expect(not completed, "999ms overlap completed the level")
    state, completed = advance_goal_contact(state, geometry_inside=True, delta_ms=1)
    expect(completed, "1000ms overlap did not complete the level")
    state, completed = advance_goal_contact(state, geometry_inside=False)
    expect(not bool(state["active"]) and float(state["timer"]) == 0 and not completed,
           "complete separation did not reset the timer")
    state, completed = advance_goal_contact(state, geometry_inside=True, delta_ms=1)
    expect(float(state["timer"]) == 1 and not completed,
           "re-entry did not restart timing from zero")

    expect("function GoalSensorContainsApple()" in main_lua, "goal fixture overlap fallback is missing")
    expect("local sensorRadius = math.max(24 / pixelsPerMeter," in main_lua
           and "local overlapRadius = sensorRadius + apple_.radius" in main_lua
           and "return dx * dx + dy * dy <= overlapRadius * overlapRadius" in main_lua,
           "goal overlap does not use the circular Sensor boundary and apple volume")
    expect("local contactConfirmed = GoalSensorContainsApple()" in main_lua
           and "else\n            ResetGoal()" in main_lua,
           "complete Sensor separation does not reset the stay timer immediately")
    expect("function DeactivateGoalContact(nodeA, nodeB)" in main_lua
           and "if DeactivateGoalContact(nodeA, nodeB) then" in main_lua,
           "goal EndContact does not participate in the post-step debounce")
    expect("if goalContactConfirmed_ then goalContactMs_ = goalContactMs_ + dt * 1000 end" in main_lua
           and "if goalContactConfirmed_ and goalContactMs_ >= requiredStayTime then" in main_lua
           and "matterSpeed <= 4.8" not in main_lua,
           "Sensor completion still has a speed requirement")
    expect("UpdateSpringExits()\n    RefreshGoalContact()\n    UpdateExperiment" in main_lua,
           "goal overlap is not refreshed before the physics-time stay counter")
    end_contact = main_lua[main_lua.index("function HandleCollisionEnd"):main_lua.index("function HandleRender")]
    expect("ResetGoal()" not in end_contact,
           "trigger EndContact resets the goal timer before PhysicsPostStep can read final contact state")

    if errors:
        print("GOAL_SENSOR_VALIDATE fail")
        for error in errors:
            print(f"- {error}")
        return 1
    print("GOAL_SENSOR_VALIDATE pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
