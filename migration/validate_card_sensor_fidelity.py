#!/usr/bin/env python3
"""Static regression contracts for card-face geometry and goal fallback."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "scripts" / "main.lua").read_text(encoding="utf-8")


def expect(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    errors: list[str] = []
    card = MAIN[MAIN.index("function DrawCardSurface"):MAIN.index("function DrawCards")]
    sensor = MAIN[MAIN.index("function GoalSensorContainsApple"):MAIN.index("function DoorOpenVector")]
    hit_test = MAIN[MAIN.index("function FindTopCardAt"):MAIN.index("function UpdateHoverState")]

    expect("local CARD_TEXT_SCALE = 144 / 124" in MAIN,
           "card render scale no longer matches Phaser's 124-to-144 transform", errors)
    expect("local CARD_RENDER_HEIGHT = 172 * CARD_TEXT_SCALE" in MAIN,
           "card paint height is not derived from the Phaser design face", errors)
    for source_rect in (
        "-60 * scale, -83 * scale, 124 * scale, 172 * scale",
        "-62 * scale, -87 * scale, 124 * scale, 172 * scale",
        "-57 * scale, -82 * scale, 114 * scale, 164 * scale",
        "-49 * scale, -32 * scale, 98 * scale, 76 * scale",
    ):
        expect(source_rect in card, f"missing source-scaled card rectangle: {source_rect}", errors)
    expect("CARD_RENDER_HEIGHT * .5" in hit_test,
           "card hit region still uses the oversized interaction height", errors)
    expect("local radius = apple_.radius + GOAL_CONTACT_SKIN" in sensor,
           "goal fallback lacks the Box2D/Matter contact skin", errors)
    expect("matterSpeed <= 4.8" in MAIN,
           "goal completion no longer preserves the source stability threshold", errors)

    if errors:
        print("CARD_SENSOR_FIDELITY_VALIDATE fail")
        for error in errors:
            print(f"- {error}")
        return 1
    print("CARD_SENSOR_FIDELITY_VALIDATE pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
