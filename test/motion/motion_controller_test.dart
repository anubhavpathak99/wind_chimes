import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/motion/motion_controller.dart';

import 'fake_motion_source.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeMotionSource source;
  late SimInputs inputs;
  late MotionController controller;

  setUp(() {
    source = FakeMotionSource();
    inputs = SimInputs();
    controller = MotionController(source: source, inputs: inputs);
  });

  /// A phone rolled right-edge-down by 20°, pushed right at 3 m/s².
  Future<void> sendTiltedPush(double seconds) async {
    const roll = 20 * math.pi / 180;
    for (var t = 0.0; t < seconds; t += 0.02) {
      source.linear!.add((x: 3.0, y: 0.0, z: 0.0, seconds: t));
      source.accel!.add((x: 3 - 9.81 * math.sin(roll), y: 9.81 * math.cos(roll), z: 0.0, seconds: t));
    }
    await settle();
  }

  test('writes tilt and acceleration into the simulation inputs', () async {
    controller.start();
    await sendTiltedPush(1);
    controller.update(1 / 60);
    expect(math.atan2(inputs.gravityDirX, -inputs.gravityDirY) * 180 / math.pi, closeTo(20, 1));
    expect(inputs.deviceAccelX, closeTo(3 - 0.15, 0.05));
    controller.update(0.3);
    expect(controller.snapshot.value.status, MotionStatus.live);
  });

  test('a push fades out when the sensor goes quiet', () async {
    controller.start();
    await sendTiltedPush(0.5);
    for (var i = 0; i < 60; i++) {
      controller.update(1 / 60);
    }
    expect(inputs.deviceAccelX.abs(), lessThan(0.05));
  });

  test('no readings at all means no sensors; the chime hangs straight', () async {
    controller.start();
    for (var i = 0; i < 150; i++) {
      controller.update(1 / 60);
    }
    expect(controller.snapshot.value.status, MotionStatus.unavailable);
    expect(inputs.gravityDirY, -1);
    expect(inputs.deviceAccelX, 0);
  });

  test('no linear-acceleration sensor: tilt still works and motion is derived', () async {
    controller.start();
    source.linear!.addError(StateError('NO_SENSOR'));
    await settle();
    const roll = 20 * math.pi / 180;
    for (var t = 0.0; t < 1; t += 0.02) {
      source.accel!.add((x: -9.81 * math.sin(roll), y: 9.81 * math.cos(roll), z: 0.0, seconds: t));
    }
    await settle();
    controller.update(0.3);
    expect(controller.processor.deriveLinear, isTrue);
    expect(controller.snapshot.value.status, MotionStatus.live);
    expect(math.atan2(inputs.gravityDirX, -inputs.gravityDirY) * 180 / math.pi, closeTo(20, 1));
  });

  test('a linear sensor that never reports is treated as missing', () async {
    controller.start();
    for (var t = 0.0; t < 1.5; t += 0.02) {
      source.accel!.add((x: 0.0, y: 9.81, z: 0.0, seconds: t));
      await settle();
      controller.update(0.02);
    }
    expect(controller.processor.deriveLinear, isTrue);
  });

  test('an accelerometer error is survived', () async {
    controller.start();
    source.accel!.addError(StateError('no accelerometer'));
    await settle();
    expect(controller.isRunning, isFalse);
    controller.update(0.3);
    expect(controller.snapshot.value.status, MotionStatus.unavailable);
    expect(inputs.gravityDirY, -1);
  });

  test('stopping lets the chime hang straight again', () async {
    controller.start();
    await sendTiltedPush(1);
    controller.update(1 / 60);
    await controller.stop();
    expect(inputs.gravityDirX, closeTo(0, 1e-12));
    expect(inputs.gravityDirY, -1);
    expect(inputs.deviceAccelX, 0);
    expect(controller.snapshot.value.status, MotionStatus.off);
  });
}
