import 'package:chime_sim/chime_sim.dart';
import 'package:test/test.dart';

final class _Counter implements CollisionSink {
  int hits = 0;

  @override
  void onCollision(CollisionEvent event) => hits++;
}

void main() {
  final config = ChimeConfig.pentatonicAluminium();

  test('hit rate follows the Beaufort targets', () {
    for (final target in hitRateTargets) {
      final report = measureHitRate(config, windSpeed: target.windSpeed);
      expect(report.hitsPerSecond, inInclusiveRange(target.min, target.max),
          reason: '${target.windSpeed} m/s');
    }
  });

  test('stronger wind strikes harder', () {
    final gentle = measureHitRate(config, windSpeed: 3, seconds: 120);
    final strong = measureHitRate(config, windSpeed: 10, seconds: 120);
    expect(strong.medianImpulse, greaterThan(gentle.medianImpulse));
    expect(strong.p90Impulse, greaterThan(gentle.p90Impulse));
  });

  test('a gale plays every tube and keeps the clapper in the ring', () {
    final gale = measureHitRate(config, windSpeed: 20, seconds: 120);
    expect(gale.rodsHit, config.rods.length);
    expect(gale.confined, lessThan(0.05));
  });

  test('a steady west wind blows the sail east', () {
    final sim = ChimeSimulation(config);
    sim.inputs
      ..windSpeed = 6
      ..windDirection = 270;
    sim.wind.snapToTarget(sim.inputs);
    for (var i = 0; i < 20 * 120; i++) {
      sim.step();
    }
    var sumX = 0.0, sumZ = 0.0;
    const n = 10 * 120;
    final sail = 3 * ChimeSimulation.sailIndex;
    for (var i = 0; i < n; i++) {
      sim.step();
      sumX += sim.particles.position[sail];
      sumZ += sim.particles.position[sail + 2];
    }
    expect(sumX / n, greaterThan(0.05));
    expect((sumZ / n).abs(), lessThan(sumX / n / 3));
  });

  test('a weather update from 3 to 10 m/s is not heard as a jump', () {
    /// Hits in the 40 s before the update (per 5 s) and in the 5 s after it, over three seeds.
    ({double before, int after}) run(double responseTime) {
      var before = 0, after = 0;
      for (final seed in [1, 2, 3]) {
        final sim = ChimeSimulation(config, seed: seed);
        sim.inputs
          ..windSpeed = 3
          ..windGust = 4.5
          ..windResponseTime = responseTime;
        sim.wind.snapToTarget(sim.inputs);
        final counter = _Counter();
        for (var i = 0; i < 45 * 120; i++) {
          if (i == 40 * 120) {
            before += counter.hits;
            counter.hits = 0;
            sim.inputs
              ..windSpeed = 10
              ..windGust = 15;
          }
          sim.step();
          sim.events.drainTo(counter);
        }
        after += counter.hits;
      }
      return (before: before / 8, after: after);
    }

    final eased = run(30), instant = run(0);
    expect(eased.after, lessThan(1.4 * eased.before));
    // The same update applied at once is a burst: the check above can tell.
    expect(instant.after, greaterThan(1.6 * instant.before));
  });
}
