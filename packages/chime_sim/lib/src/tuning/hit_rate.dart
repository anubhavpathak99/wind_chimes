import '../config/chime_config.dart';
import '../core/chime_simulation.dart';
import '../events/collision_event.dart';
import '../wind/placement.dart';

/// Hits per second the default chime should produce by reported 10 m wind, in a garden with a
/// gust factor of 1.5, following the Beaufort descriptions: nearly silent in light air, regular
/// in a gentle breeze, lively in a moderate one, busy but not a cacophony in a strong one. Wind
/// strength also shows in how hard the tubes are struck, not only how often.
const hitRateTargets = <({double windSpeed, double min, double max})>[
  (windSpeed: 1, min: 0, max: 0.1),
  (windSpeed: 3, min: 0.5, max: 1.5),
  (windSpeed: 6, min: 1.5, max: 3.5),
  (windSpeed: 10, min: 2, max: 5),
];

final class HitRateReport {
  const HitRateReport({
    required this.windSpeed,
    required this.chimeWind,
    required this.seconds,
    required this.hits,
    required this.rodsHit,
    required this.medianImpulse,
    required this.p90Impulse,
    required this.maxImpulse,
    required this.leaning,
    required this.confined,
  });

  /// Reported 10 m wind, m/s.
  final double windSpeed;

  /// Mean wind at the chime, m/s.
  final double chimeWind;
  final double seconds;
  final int hits;

  /// How many different tubes were struck.
  final int rodsHit;
  final double medianImpulse;
  final double p90Impulse;
  final double maxImpulse;

  /// Fraction of the time the clapper was touching some tube.
  final double leaning;

  /// Fraction of substeps in which the clapper had to be kept from escaping the ring.
  final double confined;

  double get hitsPerSecond => hits / seconds;
}

/// Runs a fresh chime headless in steady reported wind and counts its impacts.
HitRateReport measureHitRate(
  ChimeConfig config, {
  required double windSpeed,
  double gustFactor = 1.5,
  double direction = 270,
  Placement placement = Placement.garden,
  double seconds = 180,
  double warmUp = 20,
  int seed = 1,
}) {
  final sim = ChimeSimulation(config, seed: seed);
  sim.inputs
    ..windSpeed = windSpeed
    ..windGust = windSpeed * gustFactor
    ..windDirection = direction
    ..placement = placement;
  sim.wind.snapToTarget(sim.inputs);

  final discard = _Collector();
  for (var i = 0; i < (warmUp / ChimeSimulation.stepDt).round(); i++) {
    sim.step();
    sim.events.drainTo(discard);
  }

  final hits = _Collector();
  final confinedBefore = sim.clapperConfinements;
  final steps = (seconds / ChimeSimulation.stepDt).round();
  var leaningSteps = 0;
  for (var i = 0; i < steps; i++) {
    sim.step();
    sim.events.drainTo(hits);
    for (var k = 0; k < sim.rods.length; k++) {
      if (sim.isTouchingRod(k)) {
        leaningSteps++;
        break;
      }
    }
  }

  final impulses = hits.impulses..sort();
  double quantile(double q) =>
      impulses.isEmpty ? 0 : impulses[((impulses.length - 1) * q).round()];
  return HitRateReport(
    windSpeed: windSpeed,
    chimeWind: sim.wind.meanSpeed,
    seconds: seconds,
    hits: impulses.length,
    rodsHit: hits.rods.length,
    medianImpulse: quantile(0.5),
    p90Impulse: quantile(0.9),
    maxImpulse: impulses.isEmpty ? 0 : impulses.last,
    leaning: leaningSteps / steps,
    confined: (sim.clapperConfinements - confinedBefore) / (steps * ChimeSimulation.substeps),
  );
}

class _Collector implements CollisionSink {
  final impulses = <double>[];
  final rods = <int>{};

  @override
  void onCollision(CollisionEvent event) {
    impulses.add(event.impulse);
    rods.add(event.rodId);
  }
}
