import 'dart:math' as math;

// Headless tuning harness: hit rate and impulse statistics across wind speeds.
//
//   dart run tool/harness.dart [--seconds 180] [--placement garden] [--gusts 1.5] [--seed 1]
import 'package:chime_sim/chime_sim.dart';

void main(List<String> args) {
  String option(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final seconds = double.parse(option('seconds', '180'));
  final placement = Placement.values.byName(option('placement', 'garden'));
  final gusts = double.parse(option('gusts', '1.5'));
  final seed = int.parse(option('seed', '1'));
  final config = ChimeConfig.pentatonicAluminium();
  final targets = {for (final t in hitRateTargets) t.windSpeed: t};

  print('placement ${placement.name}, gust factor $gusts, ${seconds.round()} s per speed, seed $seed\n');
  print('10m m/s  chime m/s  hits/s  tubes  J50 mN·s  J90 mN·s  Jmax mN·s  leaning  caged  clinks  twist  target');
  for (final speed in [0.0, 0.5, 1, 2, 3, 4, 6, 8, 10, 14, 20]) {
    final r = measureHitRate(config,
        windSpeed: speed.toDouble(), gustFactor: gusts, placement: placement, seconds: seconds, seed: seed);
    final target = targets[speed];
    final verdict = target == null
        ? ''
        : r.hitsPerSecond < target.min
            ? 'LOW  (${target.min}–${target.max})'
            : r.hitsPerSecond > target.max
                ? 'HIGH (${target.min}–${target.max})'
                : 'ok   (${target.min}–${target.max})';
    print('${speed.toStringAsFixed(1).padLeft(7)}  '
        '${r.chimeWind.toStringAsFixed(2).padLeft(9)}  '
        '${r.hitsPerSecond.toStringAsFixed(2).padLeft(6)}  '
        '${r.rodsHit.toString().padLeft(5)}  '
        '${(r.medianImpulse * 1000).toStringAsFixed(1).padLeft(8)}  '
        '${(r.p90Impulse * 1000).toStringAsFixed(1).padLeft(8)}  '
        '${(r.maxImpulse * 1000).toStringAsFixed(1).padLeft(9)}  '
        '${(r.leaning * 100).toStringAsFixed(0).padLeft(6)}%  '
        '${(r.confined * 100).toStringAsFixed(1).padLeft(4)}%  '
        '${(r.clinks / r.seconds).toStringAsFixed(2).padLeft(6)}  '
        '${(r.twist * 180 / math.pi).toStringAsFixed(0).padLeft(4)}°  '
        '$verdict');
  }
}
