import 'dart:math' as math;

/// Retry delays that double from [first] up to [max], each jittered by ±[jitter] so many phones
/// that lost the network together don't all retry together.
class Backoff {
  Backoff({
    math.Random? random,
    this.first = const Duration(seconds: 30),
    this.max = const Duration(minutes: 15),
    this.jitter = 0.2,
  }) : _random = random ?? math.Random();

  final Duration first;
  final Duration max;
  final double jitter;
  final math.Random _random;
  int _failures = 0;

  int get failures => _failures;

  /// The delay before the next attempt, after one more failure.
  Duration next() {
    final base = math.min(
      first.inMilliseconds * math.pow(2, _failures),
      max.inMilliseconds.toDouble(),
    );
    _failures++;
    final spread = 1 + jitter * (2 * _random.nextDouble() - 1);
    return Duration(milliseconds: (base * spread).round());
  }

  void reset() => _failures = 0;
}
