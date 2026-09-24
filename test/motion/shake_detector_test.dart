import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/motion/shake_detector.dart';

const g = 9.81;
const dt = 0.02;

/// Feeds [seconds] of linear acceleration from [at] and reports whether a shake was ever seen.
bool feed(ShakeDetector d, double seconds, (double, double, double) Function(double t) at) {
  var seen = false;
  for (var t = 0.0; t < seconds; t += dt) {
    final (x, y, z) = at(t);
    d.add(x, y, z, dt);
    seen |= d.shaking;
  }
  return seen;
}

void main() {
  test('side-to-side shaking is a shake', () {
    final d = ShakeDetector();
    expect(feed(d, 1.5, (t) => (1.2 * g * math.sin(2 * math.pi * 4 * t), 0, 0)), isTrue);
    expect(d.intensity, greaterThan(0.3));
  });

  test('shaking toward and away from you counts too', () {
    final d = ShakeDetector();
    expect(feed(d, 1.5, (t) => (0, 0, 1.2 * g * math.sin(2 * math.pi * 3 * t))), isTrue);
  });

  test('a single bump is not a shake', () {
    final d = ShakeDetector();
    expect(feed(d, 2, (t) => (t < 0.1 ? 1.5 * g : 0, 0, 0)), isFalse);
  });

  test('walking is not a shake', () {
    final d = ShakeDetector();
    final random = math.Random(2);
    expect(
      feed(d, 10, (t) {
        final step = 0.35 * g * math.sin(2 * math.pi * 2 * t);
        return ((random.nextDouble() - 0.5) * 0.2 * g, step, (random.nextDouble() - 0.5) * 0.2 * g);
      }),
      isFalse,
    );
  });

  test('ends soon after the shaking stops', () {
    final d = ShakeDetector();
    feed(d, 1.5, (t) => (1.2 * g * math.sin(2 * math.pi * 4 * t), 0, 0));
    expect(d.shaking, isTrue);
    feed(d, 1.5, (_) => (0, 0, 0));
    expect(d.shaking, isFalse);
  });
}
