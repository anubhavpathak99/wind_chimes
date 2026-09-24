import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/motion/one_euro_filter.dart';

void main() {
  const dt = 0.02;

  test('starts from its first sample', () {
    expect(OneEuroFilter().filter(3.5, 0), 3.5);
  });

  test('smooths jitter on a steady signal', () {
    final filter = OneEuroFilter(minCutoff: 0.8);
    final random = math.Random(1);
    final raw = <double>[], out = <double>[];
    for (var i = 0; i < 500; i++) {
      final x = 1 + (random.nextDouble() - 0.5) * 0.1;
      raw.add(x);
      out.add(filter.filter(x, dt));
    }
    double spread(List<double> v) {
      final tail = v.sublist(100);
      final mean = tail.reduce((a, b) => a + b) / tail.length;
      return math.sqrt(tail.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / tail.length);
    }

    expect(spread(out), lessThan(spread(raw) * 0.3));
  });

  test('follows a real change quickly', () {
    final filter = OneEuroFilter(minCutoff: 0.8, beta: 1);
    filter.filter(0, dt);
    var t = 0.0, value = 0.0;
    while (value < 0.9) {
      value = filter.filter(1, dt);
      t += dt;
    }
    expect(t, lessThan(0.35));
  });
}
