#!/usr/bin/env python3
"""Regression contracts for Phaser-equivalent card placement behavior."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "scripts" / "main.lua").read_text(encoding="utf-8")
RULES = (ROOT / "scripts" / "migration" / "Rules.lua").read_text(encoding="utf-8")


def expect(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    errors: list[str] = []
    hover = MAIN[MAIN.index("function UpdateHoverState"):MAIN.index("function TryCardPress")]
    press = MAIN[MAIN.index("function TryCardPress"):MAIN.index("function ClearCardInteraction")]
    card_hand = RULES[RULES.index("function Rules.CardHand"):]

    expect("or isPaused_" not in hover, "tactical pause still clears card hover", errors)
    expect("if #cardBurns_ > 0 then return false end" in press,
           "burn timeline does not lock further card presses", errors)
    expect("function CaptureHandVisualPoses(removedId)" in MAIN
           and "function AnimateHandAfterBurn(displayed)" in MAIN
           and "duration = .16" in MAIN
           and "CaptureHandVisualPoses(burn.id)" in MAIN
           and "AnimateHandAfterBurn(displayed)" in MAIN,
           "burn completion does not animate surviving cards into their new hand slots", errors)
    burn_completion = MAIN[MAIN.index("if burn.elapsed >= burn.totalDuration"):MAIN.index("burningCardIds_[burn.id] = nil")]
    expect(burn_completion.index("CaptureHandVisualPoses(burn.id)") < burn_completion.index("cardState.remainingUses"),
           "hand animation captures cards after the consumed card changes the source layout", errors)
    expect("local PRESET_X_SCALE = .92" in RULES,
           "source hand preset scale is missing", errors)
    expect("x = centerX + pose.x * PRESET_X_SCALE" in card_hand,
           "hand slots do not apply the source floating-point scale", errors)
    for value in ("x = -85", "x = -150", "x = -225", "x = -285", "x = -340"):
        expect(value in card_hand, f"source hand preset {value} is missing", errors)

    if errors:
        print("CARD_DEPLOYMENT_VALIDATE fail")
        for error in errors:
            print(f"- {error}")
        return 1
    print("CARD_DEPLOYMENT_VALIDATE pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
