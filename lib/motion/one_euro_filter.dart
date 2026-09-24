import 'dart:math' as math;

/// The 1€ filter (Casiez, Roussel & Vogel, 2012): a low-pass whose cutoff rises with how fast the
/// signal moves. It smooths hard while the input is steady, which removes sensor jitter, and opens
/// up when the input changes, which keeps lag low.
class OneEuroFilter {
  OneEuroFilter({this.minCutoff = 1.0, this.beta = 1.0, this.derivativeCutoff = 1.0});

  /// Cutoff while the signal is steady, Hz.
  final double minCutoff;

  /// How much the cutoff rises per unit/s of change.
  final double beta;
  final double derivativeCutoff;

  double? _value;
  double _derivative = 0;

  double? get value => _value;

  double filter(double input, double dt) {
    final previous = _value;
    if (previous == null || !(dt > 0)) {
      _value = input;
      _derivative = 0;
      return input;
    }
    _derivative += _alpha(dt, derivativeCutoff) * ((input - previous) / dt - _derivative);
    final cutoff = minCutoff + beta * _derivative.abs();
    return _value = previous + _alpha(dt, cutoff) * (input - previous);
  }

  void reset() {
    _value = null;
    _derivative = 0;
  }

  static double _alpha(double dt, double cutoff) => 1 / (1 + 1 / (2 * math.pi * cutoff * dt));
}
