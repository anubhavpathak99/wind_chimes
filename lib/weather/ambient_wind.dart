import 'dart:math' as math;

import 'wind_timeline.dart';

/// The built-in breeze played until real wind is available: a gentle westerly that slowly rises
/// and falls over minutes. A pure function of the clock, so it is continuous across restarts and
/// simple to test. The simulation adds turbulence and gusts on top, as it does for real wind.
class AmbientWind {
  const AmbientWind();

  static const meanSpeed = 2.6;
  static const gustFactor = 1.5;

  WindReading at(DateTime time) {
    final t = time.millisecondsSinceEpoch / 1000;
    final speed = meanSpeed +
        0.6 * math.sin(2 * math.pi * t / 437) +
        0.3 * math.sin(2 * math.pi * t / 173 + 1.3);
    final direction = 255 + 25 * math.sin(2 * math.pi * t / 911);
    return WindReading(speed: speed, gust: speed * gustFactor, direction: direction);
  }
}
