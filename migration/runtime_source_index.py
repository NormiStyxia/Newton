from __future__ import annotations

import re
import textwrap
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "scripts" / "game"

# Preserve the former main.lua declaration order for legacy source-contract
# checks while allowing each function to live in its owning domain module.
LEGACY_ORDER = (
    "SetStatus", "SetReplayMode", "ReplayLog", "PlaySound", "RuleFeedbackText", "StartRuleFeedback",
    "UpdateRuleFeedback", "LoadLevel", "InitializeCards", "CurrentPhysicsTimeScale",
    "CurrentMatterVelocityToWorld", "CurrentMatterSpeedFromWorld", "ApplyAppleCardMaterial",
    "RestoreAppleContactMaterial", "SetGravity", "SetBulletTimeActive", "UpdateAngerFromRules",
    "SyncPhysicsUpdateEnabled", "CreateScene", "SetupViewport", "ResetSessionState", "BuildLevel", "ResetExperiment",
    "DesignPointer", "PointerState", "PointerInPlayfield", "PointerToWorld", "AppleScreenPosition",
    "IsNearApple", "UpdateAppleDrag", "LaunchApple", "CancelAppleDrag", "ToggleTacticalPause",
    "IsAppleGoalPair", "IsAppleNode", "GoalSensorContainsApple", "DoorOpenVector", "DoorBlockedByApple",
    "SetDoorTarget", "ApplyDoorSignal", "EmitChannelSignal", "EvaluateButton", "ReevaluateButtons",
    "InitializeMechanisms", "UpdateDoors", "UpdateSpringExits", "UpdateSpringVisuals", "CapAppleSpeed",
    "IsInsidePhaseableWall", "UpdatePhaseTraversal", "ApplyDecision", "ApplyCardResolution", "BurnProgress",
    "BurnNoise", "EmitBurnParticles", "QueueCardResolution", "CardEntries", "CardPose", "CardHomePose",
    "CardDisplayedPose", "CardVisualPose", "CurrentCardVisualPose", "PrimedCardPose", "UpdateCardHomeMotions",
    "AnimateCardToHome", "MoveCardToHandSlot", "UpdateCardHoverStates", "SetHoveredCard",
    "CardHoverProgress", "FindTopCardAt", "UpdateHoverState", "TryCardPress", "ClearCardInteraction",
    "UpdateCardParameter", "ResolveActiveCard", "IsResultOverlayVisible", "HandleReplayPointer", "HandlePointer",
    "ResetGoal", "BeginGoalContact", "CaptureHandVisualPoses", "AnimateHandAfterBurn", "UpdateCardAnimations", "ActivateGoalContact",
    "DeactivateGoalContact", "RefreshGoalContact", "RecordReplay", "CaptureReplayFinalSample", "RecordReplayEvent", "ReplayDuration",
    "CanReplay", "ReplayStateAt", "StartReplay", "StopReplay", "UpdateReplay", "RegisterFailure",
    "UpdateExperiment", "DrawPrediction", "DrawAim", "DrawAimPrediction", "DrawCardPrediction", "DrawLaunchHint",
    "DrawTrail", "DrawVelocityArrow", "DrawRulePulse", "DrawRuleFlash", "DrawReplay", "DrawHUD",
    "CardUseLabel", "CardBadgeText", "DrawCardBadge", "DrawCardSurface", "DrawCards", "DrawSelectorArrow",
    "DrawCardParameterSelector", "DrawCardBurns", "DrawCardBurnParticles", "DrawPlayfieldOverlay", "DrawPauseShade",
    "DrawPauseStatus", "DrawResultOverlay", "RefreshWorkspaceLayout", "Start", "Stop", "HandleUpdate", "HandlePhysicsPreStep",
    "HandlePhysicsPostStep", "HandleScreenMode", "HandleTouchBegin", "HandleTouchMove", "HandleTouchEnd",
    "HandleCollisionBegin", "HandleCollisionUpdate", "HandleCollisionEnd", "HandleRender",
)


def _installer_blocks() -> dict[str, str]:
    blocks: dict[str, str] = {}
    pattern = re.compile(r"^    (?:function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(|([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\()")
    for path in GAME.rglob("*.lua"):
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        starts: list[tuple[int, str]] = []
        for index, line in enumerate(lines):
            match = pattern.match(line)
            if match:
                starts.append((index, match.group(1) or match.group(2)))
        for position, (start, name) in enumerate(starts):
            end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
            block = textwrap.dedent("".join(lines[start:end])).rstrip()
            # The final function in an installer is followed by the Install
            # function terminator and module return. They are irrelevant to
            # text contracts and would make the synthetic chunk misleading.
            block = re.sub(r"\nend\n\nreturn M\s*$", "", block)
            blocks[name] = block + "\n"
    return blocks


def legacy_main_source() -> str:
    blocks = _installer_blocks()
    missing = [name for name in LEGACY_ORDER if name not in blocks]
    if missing:
        raise RuntimeError(f"missing runtime functions: {missing}")
    prefix = (GAME / "Config.lua").read_text(encoding="utf-8")
    prefix += "\n" + (GAME / "App.lua").read_text(encoding="utf-8")
    return prefix + "\n" + "\n".join(blocks[name] for name in LEGACY_ORDER)


def all_runtime_source() -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in sorted(GAME.rglob("*.lua")))
