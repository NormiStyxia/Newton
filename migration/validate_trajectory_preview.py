#!/usr/bin/env python3
"""Regression checks for the Maker trajectory preview render path."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    canvas = (ROOT / "scripts/game/render/Canvas.lua").read_text(encoding="utf-8")
    world_view = (ROOT / "scripts/game/render/WorldView.lua").read_text(encoding="utf-8")
    interaction = (ROOT / "scripts/game/input/InteractionRouter.lua").read_text(encoding="utf-8")
    experiment = (ROOT / "scripts/game/gameplay/Experiment.lua").read_text(encoding="utf-8")
    cards = (ROOT / "scripts/game/cards/Controller.lua").read_text(encoding="utf-8")
    calibration = (ROOT / "scripts/game/physics/Calibration.lua").read_text(encoding="utf-8")

    errors: list[str] = []

    def expect(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    expect("primary = { 95, 143, 104, 255 }" in canvas,
           "trajectory color is missing from the renderer palette")
    expect("Renderer2D.COLORS.primary" in world_view
           and "TrajectoryPrediction.PredictFreeFlight" in world_view,
           "world preview does not render the shared trajectory solver")
    expect("if not draggedApple_ or not aimPreview_ then return end" in world_view
           and "DrawAimPrediction(aimPreview_)" in world_view,
           "apple aiming does not draw its prediction from the live aim state")
    expect('if activeCardId_ == "side-gravity"' in world_view
           and 'if activeCardId_ == "mirror-motion"' in world_view
           and "DrawPrediction" in world_view,
           "rule previews do not cover both parameterized cards")
    expect("draggedApple_ = true" in interaction
           and "UpdateAppleDrag(x, y)" in interaction,
           "apple pointer-down does not initialize the preview state")
    expect("cardCandidate_ = dx >= 0 and \"RIGHT\" or \"LEFT\"" in cards
           and "cardCandidate_ = math.abs(dx) >= math.abs(dy) and \"HORIZONTAL\" or \"VERTICAL\"" in cards,
           "rule parameter gestures do not produce preview candidates")
    expect("aimPreview_ = { x = lx + dx" in experiment,
           "apple aim state is not retained for rendering and launch")
    expect("APPLE_FLIGHT_FRICTION_AIR = 0.01" in calibration
           and "APPLE_GAMEPLAY_GRAVITY_SCALE = 0.962001" in calibration
           and "APPLE_TRAJECTORY_GRAVITY_SCALE = 1" in calibration
           and "frictionAir = apple_.flightFrictionAir or MatterCalibration.APPLE_FLIGHT_FRICTION_AIR" in world_view
           and "gravityX = gravityX * MatterCalibration.APPLE_TRAJECTORY_GRAVITY_SCALE" in world_view,
           "preview does not use the same flight damping and gravity as gameplay")

    if errors:
        print("TRAJECTORY_PREVIEW_VALIDATE fail")
        for error in errors:
            print(f"- {error}")
        return 1
    print("TRAJECTORY_PREVIEW_VALIDATE pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
