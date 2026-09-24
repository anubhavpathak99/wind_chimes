import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/motion/motion_processor.dart';

const g = 9.81;
const dt = 0.02;
const degree = math.pi / 180;

/// Where gravity points in the device frame (x right, y up, z out of the screen) for a phone
/// leaned back from upright by [pitch] and rolled right-edge-down by [roll].
(double, double, double) downFor({required double pitch, required double roll}) => (
      math.cos(pitch) * math.sin(roll),
      -math.cos(pitch) * math.cos(roll),
      -math.sin(pitch),
    );

/// Feeds [seconds] of both streams at 50 Hz. The accelerometer reads the phone's linear
/// acceleration minus gravity, the way both platforms report it.
void hold(
  MotionProcessor p,
  double seconds, {
  (double, double, double) down = (0, -1, 0),
  (double, double, double) Function(double t)? linear,
  double noise = 0,
  bool pairLinear = true,
  void Function()? eachSample,
}) {
  final random = math.Random(3);
  double jitter() => (random.nextDouble() - 0.5) * 2 * noise;
  for (var t = 0.0; t < seconds; t += dt) {
    final (lx, ly, lz) = linear?.call(t) ?? (0.0, 0.0, 0.0);
    if (pairLinear) p.addLinearAcceleration(lx, ly, lz, t);
    p.addAccelerometer(
      lx - down.$1 * g + jitter(),
      ly - down.$2 * g + jitter(),
      lz - down.$3 * g + jitter(),
      t,
    );
    eachSample?.call();
  }
}

void main() {
  group('tilt', () {
    test('an upright phone lets the chime hang straight down', () {
      final p = MotionProcessor();
      hold(p, 1);
      expect(p.tilt, closeTo(0, 1e-9));
      expect(p.gravityY, closeTo(-1, 1e-9));
    });

    test('dipping the right edge leans gravity right by the same angle', () {
      final p = MotionProcessor();
      hold(p, 2, down: downFor(pitch: 0, roll: 20 * degree));
      expect(p.tilt / degree, closeTo(20, 0.5));
      expect(p.gravityX, greaterThan(0));
    });

    test('holding the phone leaned back, as people do, still reads the roll', () {
      final p = MotionProcessor();
      hold(p, 2, down: downFor(pitch: 50 * degree, roll: -15 * degree));
      expect(p.tilt / degree, closeTo(-15, 0.5));
    });

    test('is clamped at 40°', () {
      final p = MotionProcessor();
      hold(p, 2, down: downFor(pitch: 0, roll: 70 * degree));
      expect(p.tilt / degree, closeTo(40, 1e-6));
    });

    test('fades out as the phone lies flat or turns upside down', () {
      for (final (pitch, roll) in [(90.0, 0.0), (80.0, 30.0), (0.0, 180.0)]) {
        final p = MotionProcessor();
        hold(p, 2, down: downFor(pitch: pitch * degree, roll: roll * degree));
        expect(p.tilt.abs() / degree, lessThan(0.5), reason: 'pitch $pitch°, roll $roll°');
      }
    });

    test('sensor noise does not jiggle it', () {
      final p = MotionProcessor();
      var worst = 0.0;
      hold(p, 5, noise: 0.3, eachSample: () => worst = math.max(worst, p.tilt.abs()));
      expect(worst / degree, lessThan(1.5));
    });

    test('shaking the phone does not read as tilting it', () {
      final p = MotionProcessor();
      var worst = 0.0;
      hold(
        p,
        3,
        linear: (t) => (8 * math.sin(2 * math.pi * 4 * t), 0, 0),
        eachSample: () => worst = math.max(worst, p.tilt.abs()),
      );
      expect(worst / degree, lessThan(2));
    });

    test('can be switched off', () {
      final p = MotionProcessor(tiltEnabled: false);
      hold(p, 1, down: downFor(pitch: 0, roll: 20 * degree));
      expect(p.tilt, 0);
    });
  });

  group('acceleration', () {
    test('a phone at rest applies nothing', () {
      final p = MotionProcessor();
      hold(p, 2, linear: (_) => (0.05, -0.04, 0.03));
      expect(p.accelX, 0);
      expect(p.accelY, 0);
      expect(p.accelZ, 0);
    });

    test('passes a push through, scaled by sensitivity', () {
      final normal = MotionProcessor(), doubled = MotionProcessor(sensitivity: 2);
      for (final p in [normal, doubled]) {
        hold(p, 0.5, linear: (_) => (2, 0, 0));
      }
      expect(normal.accelX, closeTo(2 - MotionProcessor.deadZone, 0.01));
      expect(doubled.accelX, closeTo(2 * normal.accelX, 0.05));
    });

    test('a violent jolt is soft-clamped', () {
      final p = MotionProcessor(sensitivity: 2);
      hold(p, 0.5, linear: (_) => (0, 60, 0));
      expect(p.accelY, lessThanOrEqualTo(MotionProcessor.maxAcceleration));
      expect(p.accelY, greaterThan(0.9 * MotionProcessor.maxAcceleration));
    });

    test('fades out when readings stop', () {
      final p = MotionProcessor();
      hold(p, 0.5, linear: (_) => (3, 0, 0));
      for (var i = 0; i < 30; i++) {
        p.fadeMotion(dt);
      }
      expect(p.accelX.abs(), lessThan(0.01));
    });

    test('without a linear sensor, shaking is derived from the accelerometer', () {
      final p = MotionProcessor()..deriveLinear = true;
      var peak = 0.0;
      hold(
        p,
        2,
        pairLinear: false,
        linear: (t) => (4 * math.sin(2 * math.pi * 3 * t), 0, 0),
        eachSample: () => peak = math.max(peak, p.accelX.abs()),
      );
      expect(peak, greaterThan(2));
      expect(p.tilt.abs() / degree, lessThan(3));
    });

    test('without a linear sensor, a phone held still applies nothing', () {
      final p = MotionProcessor()..deriveLinear = true;
      hold(p, 3, pairLinear: false, down: downFor(pitch: 40 * degree, roll: 10 * degree), noise: 0.05);
      expect(p.accelX.abs() + p.accelY.abs() + p.accelZ.abs(), lessThan(0.01));
      expect(p.tilt / degree, closeTo(10, 0.5));
    });

    test('reset forgets everything', () {
      final p = MotionProcessor();
      hold(p, 1, down: downFor(pitch: 0, roll: 20 * degree), linear: (_) => (3, 0, 0));
      p.reset();
      expect(p.hasTilt, isFalse);
      expect(p.tilt, 0);
      expect(p.accelX, 0);
    });
  });
}
