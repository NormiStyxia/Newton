# Physics Trajectory Contract

`physics_trajectory_contract.py` compares exported Phaser Matter and Maker
Box2D tracks without importing either game runtime.

The common coordinate system is `lab-viewport-px`: the local 1500 x 596
laboratory viewport.  It deliberately excludes page offsets, DPR, and layout
scaling.  Time is simulation time, not wall-clock time.

## Contract schema

Each JSON file is either one record or an object with a `records` array.  A
record has these required fields:

```json
{
  "schema_version": 1,
  "engine": "phaser-matter",
  "case": "free_flight",
  "time_scale": 1.0,
  "coordinate_space": "lab-viewport-px",
  "material": {
    "apple_friction": 0.1,
    "apple_friction_air": 0.01,
    "apple_restitution": 0.0,
    "contact_friction": 0.1,
    "contact_restitution": 0.0,
    "matter_force_scale": 0.001,
    "matter_base_delta_ms": 16.6666666667,
    "apple_radius_px": 27.0
  },
  "samples": [
    {"t_ms": 0, "x": 310, "y": 238, "vx": 12, "vy": -8, "angle_deg": 0}
  ],
  "events": [
    {"t_ms": 16.667, "phase": "begin", "other": "world-floor"}
  ]
}
```

`engine` is `phaser-matter` or `maker-box2d`.  `time_scale` must be `1.0` or
`0.05`.  The case IDs are `free_flight`, `ground_slide`, `right_wall`, and
`spring_exit`.

## Effective material and spring timing

The material values in the level JSON are declarative inputs, not always the
values used by the Phaser solver.  In the current source, `setCircle` replaces
the apple body and restores Matter's effective dynamic baseline
`friction=.1`, `frictionAir=.01`, `restitution=0`; `Body.setStatic(true)` changes
static laboratory bodies to `friction=1`, `restitution=0`.  Therefore the
sliding contact coefficient is Matter's `min(.1, 1)=.1`.

UrhoX keeps the apple at `.1/.01/0` and gives static fixtures `.1/0`.  Box2D's
mixed friction `sqrt(.1 * .1)=.1` then matches Matter's kinetic pair.  Matter's
low-speed `frictionStatic * frictionNormalMultiplier` threshold is a separate
cached contact branch with no direct Box2D fixture equivalent; it is emitted
as diagnostic telemetry rather than baked into the fixture material.

For spring exits, the current Phaser runtime captures `body.velocity` in its
`beforeupdate` hook and consumes that pre-solve snapshot from `collisionStart`.
Maker comparisons must use the same snapshot, not the post-solver velocity or
an independently sampled later frame.

Phaser captures may use `lab-viewport-px` directly or `phaser-playfield`
(1400 x 700).  Maker manual captures may use `maker-world-m`.  The current
`PhysicsTelemetry` helper uses `maker-centered-px`: `x = world.x * 100`,
`y = -world.y * 100`, while `vx` and `vy` are already normalized Matter frame
velocities.  The tool maps that form by adding `(750, 298)` to position.  For
raw Maker metres/second it instead reverses the adapter:
`matterVelocity = worldVelocity / (0.6 * timeScale)`, including Y inversion.

## Commands

```powershell
python migration/physics_trajectory_contract.py --self-test
node migration/generate_phaser_matter_reference.cjs --output logs/physics/phaser-matter-reference.json
python migration/physics_trajectory_contract.py --template phaser-matter
python migration/physics_trajectory_contract.py --template maker-box2d
python migration/physics_trajectory_contract.py --maker-log logs/runtime.log
python migration/physics_trajectory_contract.py --compare phaser.json maker.json
```

`generate_phaser_matter_reference.cjs` imports Phaser 3.90's bundled Matter
implementation without booting or modifying the Phaser project. It emits the
four fixed fixtures at both `1x` and `.05x`. The apple uses the actual
`setCircle(27)` runtime body, then follows the scene's `setMass(1)` and
`setStatic(true/false)` sequence.

## Required Maker probe fields

The current Maker runtime only retains replay samples and has no contact-log
export.  A runtime probe must emit the required fields above at `PhysicsPostStep`
and `PhysicsBeginContact2D`, including the actual `TimeStep`, active
`time_scale`, contact phase, and the other node ID.  It must capture all four
cases at `1x` and `.05x`.

`--maker-log` consumes raw lines prefixed with `[PhysicsTelemetry]` and Maker
runtime JSONL records whose `msg` field contains that prefix. Every session
must start with `type=begin` and then emit exactly one explicit
`type=material` event before its first sample:

```json
{"type":"material","case":"free_flight","scale":1,
 "material":{"apple_friction":0.1,"apple_friction_air":0.01,
 "apple_restitution":0,"contact_friction":0.1,"contact_restitution":0,
 "matter_force_scale":0.001,"matter_base_delta_ms":16.6666666667,
 "apple_radius_px":27}}
```

Missing `begin`, `material`, or `end` events are hard failures.  The parser
does not fill material values from defaults, because that would hide a runtime
calibration regression.

The Maker probe starts from a focused game canvas in the `READY` state (not
paused and not replaying) with `Ctrl+Alt+T`. It runs on a dedicated collision
layer, disables ordinary level
collisions, and destroys its fixtures before resetting the normal experiment.
A missing sample, material field, or contact event is a comparison failure.

At `.05x`, the probe records every `PhysicsPostStep` so a low-speed contact is
not downsampled to 60Hz. Contact comparison uses begin/end lifecycle semantics:
repeated Matter begin notifications for a single resting pair do not count as
separate physical collisions.
