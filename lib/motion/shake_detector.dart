import 'dart:math' as math;
import 'dart:typed_data';

/// Recognizes deliberate shaking, as opposed to a single bump or walking, from the phone's linear
/// acceleration. The physics doesn't need it (shaking already moves the chime as an inertial
/// force); it's for app-level reactions such as haptics.
///
/// A shake needs [reversalsNeeded] back-and-forth swings stronger than [swingThreshold] along the
/// dominant horizontal axis within [reversalWindow] seconds, with overall energy above
/// [startLevel]. It ends once the energy stays below [stopLevel] for [stopHold] seconds. Walking
/// fails the test: its spikes are vertical and don't swing back and forth sideways.
class ShakeDetector {
  static const double g = 9.81;
  static const double energySeconds = 0.3;
  static const double swingThreshold = 0.5 * g;
  static const int reversalsNeeded = 3;
  static const double reversalWindow = 0.8;
  static const double startLevel = 0.4 * g;
  static const double stopLevel = 0.2 * g;
  static const double stopHold = 0.3;

  final Float64List _reversals = Float64List(8)..fillRange(0, 8, double.negativeInfinity);
  int _reversalHead = 0;
  double _time = 0;
  double _energy = 0;
  double _xLevel = 0;
  double _zLevel = 0;
  int _lastSwingSign = 0;
  bool _xDominant = true;
  double _quietFor = 0;

  bool shaking = false;

  /// Root-mean-square acceleration over the last ~[energySeconds], m/s².
  double get level => math.sqrt(_energy);

  /// How hard the phone is being shaken, 0 to 1.
  double get intensity => ((level - 0.3 * g) / (1.2 * g)).clamp(0.0, 1.0);

  /// Feeds one linear-acceleration sample (m/s², device frame), [dt] seconds after the last.
  void add(double x, double y, double z, double dt) {
    _time += dt;
    final smoothing = 1 - math.exp(-dt / energySeconds);
    _energy += (x * x + y * y + z * z - _energy) * smoothing;
    _xLevel += (x.abs() - _xLevel) * smoothing;
    _zLevel += (z.abs() - _zLevel) * smoothing;
    final dominantX = _xLevel >= _zLevel;
    if (dominantX != _xDominant) {
      _xDominant = dominantX;
      _lastSwingSign = 0;
    }

    final along = dominantX ? x : z;
    if (along.abs() > swingThreshold) {
      final sign = along.sign.toInt();
      if (_lastSwingSign != 0 && sign != _lastSwingSign) {
        _reversals[_reversalHead] = _time;
        _reversalHead = (_reversalHead + 1) % _reversals.length;
      }
      _lastSwingSign = sign;
    }

    if (!shaking) {
      var recent = 0;
      for (final t in _reversals) {
        if (t > _time - reversalWindow) recent++;
      }
      shaking = recent >= reversalsNeeded && level > startLevel;
      _quietFor = 0;
    } else {
      _quietFor = level < stopLevel ? _quietFor + dt : 0;
      if (_quietFor >= stopHold) shaking = false;
    }
  }

  void reset() {
    _reversals.fillRange(0, _reversals.length, double.negativeInfinity);
    _energy = _xLevel = _zLevel = _quietFor = 0;
    _lastSwingSign = 0;
    shaking = false;
  }
}
