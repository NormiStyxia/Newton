from __future__ import annotations

import math
from pathlib import Path

from runtime_source_index import legacy_main_source


ROOT = Path(__file__).resolve().parents[1]
GOAL_CONTACT_MISS_LIMIT = 2


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


def advance_goal_contact(
    state: dict[str, float | int | bool],
    *,
    event_seen: bool,
    end_seen: bool = False,
    geometry_inside: bool,
    delta_ms: float = 1000 / 60,
) -> tuple[dict[str, float | int | bool], bool]:
    """Model the adapter debounce independently of the game runtime."""
    next_state = dict(state)
    confirmed = event_seen or (not end_seen and geometry_inside)
    next_state["confirmed"] = confirmed
    if confirmed:
        next_state["active"] = True
        next_state["misses"] = 0
        next_state["timer"] = max(1.0, float(next_state["timer"])) + delta_ms
    elif bool(next_state["active"]):
        next_state["misses"] = int(next_state["misses"]) + 1
        if int(next_state["misses"]) >= GOAL_CONTACT_MISS_LIMIT:
            next_state.update(active=False, confirmed=False, misses=0, timer=0.0)
    else:
        next_state.update(confirmed=False, misses=0, timer=0.0)
    completed = bool(next_state["active"] and next_state["confirmed"] and float(next_state["timer"]) >= 700)
    return next_state, completed


def main() -> int:
    main_lua = legacy_main_source()
    goal_lua = (ROOT / "scripts/game/gameplay/Goal.lua").read_text(encoding="utf-8")
    errors: list[str] = []

    def expect(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    # Fixture-equivalent coverage: inside, tangency, outside, and rotation.
    expect(circle_overlaps_oriented_box(0, 0, 0.27, 0, 0, 1.53, 1.37, 0), "center overlap was rejected")
    expect(circle_overlaps_oriented_box(1.035, 0, 0.27, 0, 0, 1.53, 1.37, 0), "edge tangency was rejected")
    expect(not circle_overlaps_oriented_box(1.036, 0, 0.27, 0, 0, 1.53, 1.37, 0), "outside circle was accepted")
    expect(circle_overlaps_oriented_box(0.7, 0.7, 0.27, 0, 0, 1.53, 1.37, 45), "rotated fixture overlap was rejected")

    # A single callback/transform handoff miss must preserve, but never advance
    # or complete, the stay timer. A genuine two-step exit must still reset it.
    state: dict[str, float | int | bool] = {"active": True, "confirmed": True, "misses": 0, "timer": 710.0}
    state, completed = advance_goal_contact(state, event_seen=False, geometry_inside=False)
    expect(bool(state["active"]) and not bool(state["confirmed"]), "single contact dropout did not enter grace")
    expect(math.isclose(float(state["timer"]), 710.0), "grace step advanced or reset the stay timer")
    expect(not completed, "an unconfirmed grace step completed the level")
    state, completed = advance_goal_contact(state, event_seen=False, geometry_inside=True)
    expect(bool(state["active"]) and bool(state["confirmed"]) and int(state["misses"]) == 0,
           "geometry fallback did not resume the same stay after one dropout")
    expect(completed, "a confirmed recovery did not resume source stay-time completion")
    churn_state: dict[str, float | int | bool] = {"active": True, "confirmed": True, "misses": 0, "timer": 500.0}
    churn_state, _ = advance_goal_contact(churn_state, event_seen=True, end_seen=True, geometry_inside=False)
    expect(bool(churn_state["confirmed"]), "begin/update did not win over same-pass EndContact churn")
    state = {"active": True, "confirmed": True, "misses": 0, "timer": 500.0}
    state, completed = advance_goal_contact(state, event_seen=False, end_seen=True, geometry_inside=True)
    expect(not bool(state["confirmed"]) and not completed,
           "EndContact allowed a stale synchronized transform to advance completion")
    state, completed = advance_goal_contact(state, event_seen=False, geometry_inside=False)
    expect(not bool(state["active"]) and float(state["timer"]) == 0 and not completed,
           "a genuine sensor exit did not reset after the one-step grace")

    expect("function GoalSensorContainsApple()" in main_lua, "goal fixture overlap fallback is missing")
    expect("local rotation = math.rad(runtimeGoal.node.rotation2D)" in main_lua,
           "goal overlap does not account for fixture rotation")
    expect("local radius = apple_.radius + GOAL_CONTACT_SKIN" in main_lua
           and "return offsetX * offsetX + offsetY * offsetY <= radius * radius" in main_lua,
           "goal overlap does not include the Box2D/Matter contact skin")
    expect("local GOAL_CONTACT_MISS_LIMIT = 2" in goal_lua
           and "or (not goalContactEndSeen_ and GoalSensorContainsApple())" in main_lua
           and "goalContactMissSteps_ >= GOAL_CONTACT_MISS_LIMIT" in main_lua,
           "goal contact handoff does not tolerate exactly one unconfirmed physics step")
    expect("function DeactivateGoalContact(nodeA, nodeB)" in main_lua
           and "if DeactivateGoalContact(nodeA, nodeB) then" in main_lua,
           "goal EndContact does not participate in the post-step debounce")
    expect("if goalContactConfirmed_ then goalContactMs_ = goalContactMs_ + dt * 1000 end" in main_lua
           and "if goalContactConfirmed_ and goalContactMs_ >= requiredStayTime and matterSpeed <= 4.8 then" in main_lua,
           "unconfirmed Sensor grace can advance or complete the stay timer")
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
