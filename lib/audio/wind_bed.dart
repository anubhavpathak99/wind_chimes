import 'dart:math' as math;

/// Level and playback speed of the wind ambience for the wind at the chime ([speed], m/s): silent
/// in calm air, louder and a little higher as it blows harder. It follows the instantaneous wind,
/// so a gust is heard arriving just before the chime answers it.
({double volume, double speed}) windBedLevel(double speed, {double maxVolume = 0.35}) {
  final s = ((speed - 0.3) / 6).clamp(0.0, 1.0);
  return (volume: maxVolume * math.pow(s, 1.3).toDouble(), speed: 0.8 + 0.5 * s);
}
