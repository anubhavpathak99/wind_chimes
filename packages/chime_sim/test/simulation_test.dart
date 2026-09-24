import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chime_sim/chime_sim.dart';
import 'package:test/test.dart';

typedef Hit = ({int rod, double impulse, double speed, double strikePos, double time});

class _Hits implements CollisionSink {
  final list = <Hit>[];

  @override
  void onCollision(CollisionEvent e) => list.add((
        rod: e.rodId,
        impulse: e.impulse,
        speed: e.normalSpeed,
        strikePos: e.strikePos,
        time: e.simTime,
      ));
}

const clapper = ChimeSimulation.clapperIndex;

ChimeSimulation newSim() => ChimeSimulation(ChimeConfig.pentatonicAluminium());

void run(ChimeSimulation sim, double seconds, [void Function()? eachStep]) {
  final steps = (seconds / ChimeSimulation.stepDt).round();
  for (var i = 0; i < steps; i++) {
    eachStep?.call();
    sim.step();
  }
}

List<Hit> drain(ChimeSimulation sim) {
  final hits = _Hits();
  sim.events.drainTo(hits);
  return hits.list;
}

({double x, double y, double z}) positionOf(ChimeSimulation sim, int i) {
  final p = sim.particles.position;
  return (x: p[3 * i], y: p[3 * i + 1], z: p[3 * i + 2]);
}

/// Horizontal unit vector from the chime's axis toward tube [rod].
({double x, double z}) towardRod(ChimeSimulation sim, int rod) {
  final angle = sim.rods[rod].ringAngle;
  return (x: math.sin(angle), z: math.cos(angle));
}

/// Drags the clapper toward [rod] by [distance] over [duration], then lets go.
void fling(ChimeSimulation sim, int rod, {double distance = 0.12, double duration = 0.15}) {
  final start = positionOf(sim, clapper);
  final dir = towardRod(sim, rod);
  final steps = (duration / ChimeSimulation.stepDt).round();
  sim.inputs.grab(clapper, start.x, start.y, start.z);
  for (var i = 1; i <= steps; i++) {
    final s = distance * i / steps;
    sim.inputs.moveTouch(start.x + dir.x * s, start.y, start.z + dir.z * s);
    sim.step();
  }
  sim.inputs.release();
}

double settledRestEnergy() {
  final sim = newSim();
  run(sim, 10);
  return sim.mechanicalEnergy();
}

void main() {
  test('rest pose stays at rest', () {
    final sim = newSim();
    final rest = sim.restPositions;
    run(sim, 10);

    var maxDrift = 0.0;
    for (var i = 0; i < rest.length; i++) {
      maxDrift = math.max(maxDrift, (sim.particles.position[i] - rest[i]).abs());
    }
    expect(maxDrift, lessThan(0.002));
    expect(drain(sim), isEmpty);
    expect(sim.maxConstraintError(), lessThan(0.005));
  });

  test('flinging the clapper at a tube strikes that tube', () {
    final sim = newSim();
    for (var rod = 0; rod < sim.rods.length; rod++) {
      sim.reset();
      drain(sim);
      fling(sim, rod);
      run(sim, 1);
      final hits = drain(sim);
      expect(hits, isNotEmpty, reason: 'rod $rod');
      final first = hits.first;
      expect(first.rod, rod);
      expect(first.speed, greaterThan(0.1));
      expect(first.impulse, inInclusiveRange(1e-4, 0.2));
      expect(first.strikePos, inInclusiveRange(0.3, 0.8));
    }
  });

  test('a clapper held against a tube goes quiet once settled', () {
    final sim = newSim();
    const rod = 2;
    final start = positionOf(sim, clapper);
    final dir = towardRod(sim, rod);
    sim.inputs.grab(clapper, start.x + dir.x * 0.06, start.y, start.z + dir.z * 0.06);

    run(sim, 2);
    expect(drain(sim), isNotEmpty, reason: 'the initial strike');
    // The push twists the whole chime a little on its rope, which can bring a neighbour round
    // for a slow tap or two before everything settles.
    run(sim, 20);
    drain(sim);
    run(sim, 10);
    expect(drain(sim), isEmpty);
    expect(sim.isTouchingRod(rod), isTrue);
    expect(sim.mountYawVelocity.abs(), lessThan(0.1), reason: 'still turning, but gently');
  });

  test('pressing means real contact: held against a tube, not hovering after a hit', () {
    final sim = newSim();
    const rod = 1;
    final start = positionOf(sim, clapper);
    final dir = towardRod(sim, rod);
    sim.inputs.grab(clapper, start.x + dir.x * 0.06, start.y, start.z + dir.z * 0.06);
    run(sim, 2);
    var pressed = 0;
    run(sim, 1, () => pressed += sim.isPressingRod(rod) ? 1 : 0);
    expect(pressed, greaterThan(115));

    sim.inputs.release();
    run(sim, 3);
    var pressedWhileFree = 0;
    run(sim, 5, () => pressedWhileFree += sim.isPressingRod(rod) ? 1 : 0);
    expect(pressedWhileFree, lessThan(5 * 120 * 0.2));
  });

  test('energy only decays after a fling', () {
    final restEnergy = settledRestEnergy();
    final sim = newSim();
    fling(sim, 0, distance: 0.15);
    run(sim, 0.5);

    var previous = sim.mechanicalEnergy() - restEnergy;
    final initial = previous;
    expect(initial, greaterThan(1e-3));
    for (var second = 0; second < 30; second++) {
      run(sim, 1);
      final excess = sim.mechanicalEnergy() - restEnergy;
      expect(excess, lessThanOrEqualTo(previous * 1.01 + 1e-6), reason: 'at ${second + 1} s');
      previous = excess;
    }
    expect(previous, lessThan(initial * 0.05));
  });

  test('ten minutes of abuse stay finite, bounded and connected', () {
    final sim = newSim();
    final random = math.Random(7);
    final grabbable = [
      ChimeSimulation.mountIndex,
      clapper,
      ChimeSimulation.sailIndex,
      for (final rod in sim.rods) ...[rod.upper, rod.lower],
    ];

    var t = 0.0;
    var nextAction = 0.0;
    var releaseAt = -1.0;
    var shakeUntil = -1.0;
    var target = (x: 0.0, y: 0.0, z: 0.0);
    var velocity = (x: 0.0, y: 0.0, z: 0.0);
    var maxSpeed = 0.0;
    var maxError = 0.0;
    final hits = _Hits();

    double spread(double r) => (random.nextDouble() * 2 - 1) * r;

    run(sim, 600, () {
      t += ChimeSimulation.stepDt;
      if (t >= nextAction) {
        final particle = grabbable[random.nextInt(grabbable.length)];
        final p = positionOf(sim, particle);
        target = (x: p.x, y: p.y, z: p.z);
        velocity = (x: spread(2), y: spread(1), z: spread(2));
        sim.inputs.grab(particle, target.x, target.y, target.z);
        releaseAt = t + 0.2 + random.nextDouble() * 0.3;
        nextAction = t + 0.8 + random.nextDouble() * 1.5;
        if (random.nextDouble() < 0.2) shakeUntil = t + 1;
        if (random.nextDouble() < 0.3) {
          final roll = spread(40) * math.pi / 180;
          sim.inputs.setGravityDirection(math.sin(roll), -math.cos(roll), 0);
        }
      }
      if (sim.inputs.isTouching) {
        target = (
          x: target.x + velocity.x * ChimeSimulation.stepDt,
          y: target.y + velocity.y * ChimeSimulation.stepDt,
          z: target.z + velocity.z * ChimeSimulation.stepDt,
        );
        sim.inputs.moveTouch(target.x, target.y, target.z);
        if (t >= releaseAt) sim.inputs.release();
      }
      final shaking = t < shakeUntil;
      final sign = (t * 12).floor().isEven ? 1.0 : -1.0;
      sim.inputs
        ..deviceAccelX = shaking ? 15 * sign : 0
        ..deviceAccelZ = shaking ? 8 * sign : 0;

      final v = sim.particles.velocity;
      for (var i = 0; i < v.length; i += 3) {
        maxSpeed = math.max(maxSpeed, math.sqrt(v[i] * v[i] + v[i + 1] * v[i + 1] + v[i + 2] * v[i + 2]));
      }
      maxError = math.max(maxError, sim.maxConstraintError());
      sim.events.drainTo(hits);
    });

    expect(sim.recoveryCount, 0);
    expect(maxSpeed, lessThanOrEqualTo(sim.config.maxSpeed + 1e-9));
    expect(maxError, lessThan(0.05));
    expect(hits.list.length, greaterThan(100));
    for (final hit in hits.list) {
      expect(hit.impulse.isFinite && hit.impulse > 0, isTrue);
    }
  });

  group('advance', () {
    test('clamps long frames', () {
      final sim = newSim();
      expect(sim.advance(5), ChimeSimulation.maxStepsPerFrame);
      expect(sim.interpolationAlpha, inInclusiveRange(0, 1));
    });

    test('ignores zero and non-finite frame times', () {
      final sim = newSim();
      expect(sim.advance(0), 0);
      expect(sim.advance(double.nan), 0);
      expect(sim.advance(-1), 0);
    });

    test('runs 120 steps per simulated second at 60 fps', () {
      final sim = newSim();
      var steps = 0;
      for (var i = 0; i < 60; i++) {
        steps += sim.advance(1 / 60);
      }
      expect(steps, inInclusiveRange(119, 120));
    });
  });

  test('warming up leaves the chime moving in the wind, silently', () {
    final sim = ChimeSimulation(ChimeConfig.pentatonicAluminium());
    sim.inputs
      ..windSpeed = 5
      ..windGust = 7.5
      ..windResponseTime = 0;
    sim.warmUp(10);
    expect(sim.time, closeTo(10, 1e-9));
    expect(sim.events.length, 0);
    final clapper = 3 * ChimeSimulation.clapperIndex;
    final moved = (sim.particles.position[clapper] - sim.restPositions[clapper]).abs() +
        (sim.particles.position[clapper + 2] - sim.restPositions[clapper + 2]).abs();
    expect(moved, greaterThan(0.002));
    expect(sim.wind.meanSpeed, greaterThan(2));
  });

  group('mount twist', () {
    test('a sideways push on a tube twists the mount, and the rope turns it back', () {
      final sim = newSim();
      const rod = 0;
      final r = sim.rods[rod];
      final p = sim.particles.position;
      final tangent = (x: math.cos(r.ringAngle), z: -math.sin(r.ringAngle));
      final start = (x: p[3 * r.lower], y: p[3 * r.lower + 1], z: p[3 * r.lower + 2]);
      sim.inputs.grab(r.lower, start.x + tangent.x * 0.03, start.y, start.z + tangent.z * 0.03);
      run(sim, 3);
      final twisted = sim.mountYaw.angle;
      expect(twisted.abs(), greaterThan(0.1), reason: 'the chime turns with the push');

      sim.inputs.release();
      var peak = 0.0;
      run(sim, 60, () => peak = math.max(peak, sim.mountYaw.angle.abs()));
      expect(peak, lessThan(twisted.abs() * 1.5 + 0.05), reason: 'no runaway spin');
      expect(sim.mountYaw.angle.abs(), lessThan(0.1), reason: 'back near where it started');
    });

    test('in steady wind the chime turns to and fro, a few degrees', () {
      final sim = newSim();
      sim.inputs
        ..windSpeed = 6
        ..windGust = 9
        ..windResponseTime = 0;
      var sum2 = 0.0, steps = 0;
      run(sim, 60, () {
        sum2 += sim.mountYaw.angle * sim.mountYaw.angle;
        steps++;
      });
      final rmsDegrees = math.sqrt(sum2 / steps) * 180 / math.pi;
      expect(rmsDegrees, inInclusiveRange(1, 30));
    });
  });

  group('tube against tube', () {
    /// Drags tube [a]'s lower end into tube [b] and holds it there.
    void pushInto(ChimeSimulation sim, int a, int b, {double overshoot = 0.02}) {
      final p = sim.particles.position;
      final from = sim.rods[a].lower, to = sim.rods[b].lower;
      final dx = p[3 * to] - p[3 * from], dz = p[3 * to + 2] - p[3 * from + 2];
      final d = math.sqrt(dx * dx + dz * dz);
      sim.inputs.grab(from, p[3 * from] + dx * (1 + overshoot / d), p[3 * from + 1],
          p[3 * from + 2] + dz * (1 + overshoot / d));
    }

    test('knocking two tubes together clinks, reported once for each tube', () {
      final sim = newSim();
      pushInto(sim, 0, 1);
      final events = <({int rod, int other})>[];
      final sink = _Clinks(events);
      run(sim, 1, () => sim.events.drainTo(sink));
      sim.events.drainTo(sink);
      expect(events, isNotEmpty);
      expect(events.first.other, isNot(-1));
      expect(events.where((e) => e.rod == 0 && e.other == 1), isNotEmpty);
      expect(events.where((e) => e.rod == 1 && e.other == 0), isNotEmpty);
    });

    test('tubes pushed together never pass through each other, and lean together quietly', () {
      final sim = newSim();
      pushInto(sim, 2, 3, overshoot: 0.05);
      final a = sim.rods[2], b = sim.rods[3];
      final ends = Float64List(3);
      var closest = double.infinity;
      final events = <({int rod, int other})>[];
      final sink = _Clinks(events);
      run(sim, 20, () {
        sim.events.drainTo(sink);
        a.bottom.eval(sim.particles.position, ends);
        final ax = ends[0], az = ends[2];
        b.bottom.eval(sim.particles.position, ends);
        final gap = math.sqrt((ax - ends[0]) * (ax - ends[0]) + (az - ends[2]) * (az - ends[2]));
        closest = math.min(closest, gap);
      });
      expect(closest, greaterThan(a.spec.radius + b.spec.radius - 0.004));
      events.clear();
      run(sim, 5, () => sim.events.drainTo(sink));
      expect(events.where((e) => e.other >= 0), isEmpty, reason: 'resting contact is silent');
    });
  });
}

class _Clinks implements CollisionSink {
  _Clinks(this.events);

  final List<({int rod, int other})> events;

  @override
  void onCollision(CollisionEvent event) => events.add((rod: event.rodId, other: event.otherRodId));
}
