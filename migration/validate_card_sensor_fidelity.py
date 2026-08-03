#!/usr/bin/env python3
"""Static regression contracts for card-face geometry and goal fallback."""

from pathlib import Path

from runtime_source_index import legacy_main_source


ROOT = Path(__file__).resolve().parents[1]
MAIN = legacy_main_source()


def expect(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    errors: list[str] = []
    card = MAIN[MAIN.index("function DrawCardSurface"):MAIN.index("function DrawCards")]
    sensor = MAIN[MAIN.index("function GoalSensorContainsApple"):MAIN.index("function DoorOpenVector")]
    hit_test = MAIN[MAIN.index("function FindTopCardAt"):MAIN.index("function UpdateHoverState")]

    expect("local CARD_DESIGN_WIDTH = 124" in MAIN and "local CARD_DESIGN_HEIGHT = 174" in MAIN,
           "card design geometry no longer matches Phaser's 124x174 face", errors)
    expect("local CARD_TEXT_SCALE = 144 / CARD_DESIGN_WIDTH" in MAIN,
           "card render scale no longer matches Phaser's 124-to-144 transform", errors)
    expect("local CARD_RENDER_HEIGHT = CARD_DESIGN_HEIGHT * CARD_TEXT_SCALE" in MAIN,
           "card paint height is not derived from the Phaser design face", errors)
    for source_rect in (
        "-60 * scale, -83 * scale, CARD_DESIGN_WIDTH * scale, CARD_DESIGN_HEIGHT * scale",
        "-62 * scale, -87 * scale, CARD_DESIGN_WIDTH * scale, CARD_DESIGN_HEIGHT * scale",
        "-57 * scale, -82 * scale, 114 * scale, 164 * scale",
        "-49 * scale, -32 * scale, 98 * scale, 76 * scale",
    ):
        expect(source_rect in card, f"missing source-scaled card rectangle: {source_rect}", errors)
    expect("CARD_RENDER_HEIGHT * .5" in hit_test,
           "card hit region still uses the oversized interaction height", errors)
    expect("local sensorRadius = math.max(24 / pixelsPerMeter," in sensor
           and "local overlapRadius = sensorRadius + apple_.radius" in sensor,
           "goal fallback no longer uses circular Sensor/apple volume overlap", errors)
    expect("matterSpeed <= 4.8" not in MAIN,
           "goal completion still has the removed stability threshold", errors)
    speed_conversion = MAIN[MAIN.index("function CurrentMatterSpeedFromWorld"):MAIN.index("function ApplyAppleCardMaterial")]
    expect("/ CONFIG.matterVelocityToWorld" in speed_conversion
           and "CurrentMatterVelocityToWorld" not in speed_conversion,
           "goal speed comparison rescales slow-motion velocity twice", errors)

    if errors:
        print("CARD_SENSOR_FIDELITY_VALIDATE fail")
        for error in errors:
            print(f"- {error}")
        return 1
    print("CARD_SENSOR_FIDELITY_VALIDATE pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
