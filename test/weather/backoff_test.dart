import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/weather/backoff.dart';

void main() {
  test('doubles from 30 s up to 15 min, with jitter', () {
    final backoff = Backoff(random: math.Random(1));
    final minutes = [for (var i = 0; i < 8; i++) backoff.next().inMilliseconds / 60000];
    const expected = [0.5, 1, 2, 4, 8, 15, 15, 15];
    for (var i = 0; i < expected.length; i++) {
      expect(minutes[i], inInclusiveRange(expected[i] * 0.8, expected[i] * 1.2), reason: 'try $i');
    }
    expect(minutes.toSet().length, minutes.length, reason: 'jittered');
  });

  test('starts over after a reset', () {
    final backoff = Backoff(jitter: 0)
      ..next()
      ..next()
      ..reset();
    expect(backoff.next(), const Duration(seconds: 30));
  });
}
