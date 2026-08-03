#!/usr/bin/env node
/* Generate the source-physics side of the Maker trajectory contract.
 *
 * This deliberately imports the Matter implementation bundled by Phaser 3.90
 * in the original project. It does not boot Phaser or modify that project.
 */

const fs = require("fs");
const path = require("path");

const sourceProject = process.env.NEWTON_PHASER_ROOT
  || path.resolve(__dirname, "..", "..", "牛顿", "牛顿");
const matterRoot = path.join(sourceProject, "node_modules", "phaser", "src", "physics", "matter-js", "lib");

if (!fs.existsSync(matterRoot)) {
  throw new Error(`Cannot find Phaser Matter source at ${matterRoot}`);
}

const Engine = require(path.join(matterRoot, "core", "Engine.js"));
const Events = require(path.join(matterRoot, "core", "Events.js"));
const Body = require(path.join(matterRoot, "body", "Body.js"));
const Bodies = require(path.join(matterRoot, "factory", "Bodies.js"));
const Composite = require(path.join(matterRoot, "body", "Composite.js"));
const Resolver = require(path.join(matterRoot, "collision", "Resolver.js"));

// Phaser.Physics.Matter.MatterPhysics overwrites Matter's library Resolver
// defaults while the scene boots. Apply those runtime values explicitly here
// because this generator intentionally does not boot a browser Phaser game.
Resolver._restingThresh = 4;
Resolver._restingThreshTangent = 6;
Resolver._positionDampen = 0.9;
Resolver._positionWarming = 0.8;
Resolver._frictionNormalMultiplier = 5;

const BASE_DELTA_MS = 1000 / 60;
const LAB = { width: 1500, height: 596 };
const PLAYFIELD = { width: 1400, height: 700, groundY: 580 };
const APPLE_RADIUS = 27;
const MATERIAL = {
  apple_friction: 0.1,
  apple_friction_air: 0.01,
  apple_restitution: 0,
  contact_friction: 0.1,
  contact_restitution: 0,
  matter_force_scale: 0.001,
  matter_base_delta_ms: BASE_DELTA_MS,
  apple_radius_px: APPLE_RADIUS,
};
const HOOKE_RESTITUTION = 0.88;
const BASE_RESTITUTION = 0.36;

const floorY = PLAYFIELD.groundY / PLAYFIELD.height * LAB.height;
const fixtures = {
  floor: { id: "world-floor", x: LAB.width / 2, y: floorY + 14, width: LAB.width - 34, height: 28 },
  right: { id: "world-right", x: LAB.width - 14, y: LAB.height / 2, width: 24, height: LAB.height - 44 },
  // This exactly follows an 110 x 34 level spring after CoordinateConverter's
  // object-height scale (596 / 700), but keeps it isolated from level content.
  spring: { id: "spring", x: 510, y: 430, width: 110 * LAB.height / PLAYFIELD.height, height: 34 * LAB.height / PLAYFIELD.height },
};

const CASES = {
  free_flight: { duration: 1000, fixture: null, initial: { x: 310, y: 238, vx: 12, vy: -8 } },
  // groundY is the top surface of the floor rectangle, not its centre.
  ground_slide: { duration: 1000, fixture: "floor", initial: { x: 510, y: floorY - APPLE_RADIUS, vx: 12, vy: 0 } },
  right_wall: { duration: 500, fixture: "right", initial: { x: 1410, y: LAB.height / 2, vx: 18, vy: 0 } },
  hooke_wall: { duration: 500, fixture: "right", restitution: HOOKE_RESTITUTION, initial: { x: 1410, y: LAB.height / 2, vx: 18, vy: 0 } },
  hooke_resting: { duration: 500, fixture: "right", restitution: HOOKE_RESTITUTION, initial: { x: 1435, y: LAB.height / 2, vx: 3.5, vy: 0 } },
  spring_exit: { duration: 500, fixture: "spring", initial: { x: 510, y: 288, vx: 0, vy: 20 } },
  spring_exit_hooke: {
    duration: 500,
    fixture: "spring",
    restitution: HOOKE_RESTITUTION,
    springMultiplier: HOOKE_RESTITUTION / BASE_RESTITUTION,
    initial: { x: 510, y: 288, vx: 0, vy: 20 },
  },
};

function capture(body, time) {
  return {
    t_ms: Number(time.toFixed(6)),
    x: Number(body.position.x.toFixed(6)),
    y: Number(body.position.y.toFixed(6)),
    vx: Number(body.velocity.x.toFixed(6)),
    vy: Number(body.velocity.y.toFixed(6)),
    angle_deg: Number((body.angle * 180 / Math.PI).toFixed(6)),
  };
}

function makeStaticFixture(spec) {
  return Bodies.rectangle(spec.x, spec.y, spec.width, spec.height, {
    isStatic: true,
    label: spec.id,
    friction: spec.id === "spring" ? 0.1 : 0.78,
    restitution: spec.id === "spring" ? 0.5 : 0.22,
  });
}

function runCase(caseId, timeScale) {
  const spec = CASES[caseId];
  const engine = Engine.create({
    positionIterations: 10,
    velocityIterations: 8,
    constraintIterations: 4,
    enableSleeping: false,
  });
  engine.gravity.x = 0;
  engine.gravity.y = 0;
  engine.gravity.scale = 0;
  engine.timing.timeScale = timeScale;

  const apple = Bodies.circle(spec.initial.x, spec.initial.y, APPLE_RADIUS, { label: "apple" });
  Body.setMass(apple, 1);
  Body.setStatic(apple, true);
  Body.setStatic(apple, false);
  // PlayScene updates the dynamic apple after Hooke resolves. Static fixtures
  // remain at restitution 0, so Matter's max-pair rule observes exactly .88.
  apple.restitution = spec.restitution || 0;
  Body.setVelocity(apple, { x: spec.initial.vx, y: spec.initial.vy });
  Composite.add(engine.world, apple);

  const fixture = spec.fixture ? makeStaticFixture(fixtures[spec.fixture]) : null;
  if (fixture) Composite.add(engine.world, fixture);

  const events = [];
  let pendingSpringExit = null;
  let applePreSolveVelocity = { x: apple.velocity.x, y: apple.velocity.y };
  Events.on(engine, "beforeUpdate", () => {
    // PlayScene.preparePhysicsStep captures this before applying custom
    // gravity and before Matter integrates or solves the upcoming contacts.
    applePreSolveVelocity = { x: apple.velocity.x, y: apple.velocity.y };
    Body.applyForce(apple, apple.position, { x: 0, y: MATERIAL.matter_force_scale * apple.mass });
  });
  Events.on(engine, "collisionStart", event => {
    for (const pair of event.pairs) {
      const other = pair.bodyA === apple ? pair.bodyB : pair.bodyB === apple ? pair.bodyA : null;
      if (!other || !other.label) continue;
      events.push({ t_ms: Number(engine.timing.timestamp.toFixed(6)), phase: "begin", other: other.label });
      if (other.label === "spring") {
        pendingSpringExit = {
          x: applePreSolveVelocity.x,
          y: applePreSolveVelocity.y - 10 * (spec.springMultiplier || 1),
        };
      }
    }
  });

  const samples = [capture(apple, 0)];
  while (engine.timing.timestamp + 0.000001 < spec.duration) {
    Engine.update(engine, BASE_DELTA_MS);
    if (pendingSpringExit) {
      Body.setVelocity(apple, pendingSpringExit);
      pendingSpringExit = null;
    }
    samples.push(capture(apple, engine.timing.timestamp));
  }

  return {
    schema_version: 1,
    engine: "phaser-matter",
    case: caseId,
    time_scale: timeScale,
    coordinate_space: "lab-viewport-px",
    material: {
      ...MATERIAL,
      apple_restitution: spec.restitution || 0,
      contact_restitution: spec.restitution || 0,
    },
    samples,
    events,
  };
}

const records = [];
for (const caseId of Object.keys(CASES)) {
  for (const timeScale of [1, 0.05]) records.push(runCase(caseId, timeScale));
}

const payload = JSON.stringify({ schema_version: 1, records }, null, 2);
const outputIndex = process.argv.indexOf("--output");
if (outputIndex >= 0) {
  const outputPath = process.argv[outputIndex + 1];
  if (!outputPath) throw new Error("--output requires a file path");
  fs.writeFileSync(outputPath, `${payload}\n`, "utf8");
} else {
  process.stdout.write(`${payload}\n`);
}
