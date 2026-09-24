import 'package:chime_sim/chime_sim.dart';
import 'package:test/test.dart';

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
}
