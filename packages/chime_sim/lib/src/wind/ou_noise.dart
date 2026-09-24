import 'dart:math' as math;

/// Standard normal samples via Box–Muller, without allocating.
final class Gaussian {
  Gaussian(this._random);

  final math.Random _random;
  double? _spare;

  double next() {
    final spare = _spare;
    if (spare != null) {
      _spare = null;
      return spare;
    }
    double u;
    do {
      u = _random.nextDouble();
    } while (u <= 1e-300);
    final r = math.sqrt(-2 * math.log(u));
    final theta = 2 * math.pi * _random.nextDouble();
    _spare = r * math.sin(theta);
    return r * math.cos(theta);
  }
}

/// Ornstein–Uhlenbeck process with zero mean and unit variance: smooth, mean-reverting noise
/// whose memory is [correlationTime]. Uses the exact update, so it behaves the same at any step
/// size: `n ← n·e^(−dt/T) + √(1 − e^(−2dt/T))·N(0,1)`.
final class OrnsteinUhlenbeck {
  OrnsteinUhlenbeck(this.correlationTime, this._gaussian);

  final double correlationTime;
  final Gaussian _gaussian;
  double value = 0;

  double step(double dt) {
    final decay = math.exp(-dt / correlationTime);
    value = value * decay + math.sqrt(1 - decay * decay) * _gaussian.next();
    return value;
  }
}
