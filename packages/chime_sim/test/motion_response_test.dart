import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';
import 'package:test/test.dart';

class _Count implements CollisionSink {
  var hits = 0;

  @override
  void onCollision(CollisionEvent event) => hits++;
}

int run(ChimeSimulation sim, double seconds, [void Function(double t)? each]) {
  final count = _Count();
  var t = 0.0;
  for (var i = 0; i < (seconds / ChimeSimulation.stepDt).round(); i++) {
    each?.call(t);
    sim.step();
    sim.events.drainTo(count);
    t += ChimeSimulation.stepDt;
  }
  return count.hits;
}

void main() {
  final config = ChimeConfig.pentatonicAluminium();

  test('tilting the phone makes the chime hang plumb at the tilt angle', () {
    final sim = ChimeSimulation(config);
    const tilt = 20 * math.pi / 180;
    sim.inputs.setGravityDirection(math.sin(tilt), -math.cos(tilt), 0);
    run(sim, 40);
    var angle = 0.0;
    const n = 20 * 120;
    final p = sim.particles.position;
    final m = 3 * ChimeSimulation.mountIndex, c = 3 * ChimeSimulation.clapperIndex;
    run(sim, 20, (_) => angle += math.atan2(p[c] - p[m], p[m + 1] - p[c + 1]) / n);
    expect(angle * 180 / math.pi, closeTo(20, 2));
  });

  test('shaking the phone sets the chime ringing', () {
    final sim = ChimeSimulation(config);
    expect(run(sim, 2), 0);
    final hits = run(sim, 3, (t) {
      sim.inputs.deviceAccelX = (t * 5).floor().isEven ? 8 : -8;
    });
    expect(hits, greaterThanOrEqualTo(5));
  });

  test('walking with the phone only jiggles it', () {
    final sim = ChimeSimulation(config);
    final hits = run(sim, 10, (t) {
      sim.inputs.deviceAccelY = 3 * math.sin(2 * math.pi * 2 * t);
    });
    expect(hits, lessThanOrEqualTo(2));
    expect(sim.recoveryCount, 0);
  });
}
