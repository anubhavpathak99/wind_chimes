import 'dart:async';
import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/foundation.dart';

import 'motion_processor.dart';
import 'motion_source.dart';

enum MotionStatus { off, waiting, live, unavailable }

@immutable
class MotionSnapshot {
  const MotionSnapshot({
    required this.status,
    required this.tiltDegrees,
    required this.acceleration,
    required this.shaking,
    required this.shakeIntensity,
  });

  static const off = MotionSnapshot(
    status: MotionStatus.off,
    tiltDegrees: 0,
    acceleration: 0,
    shaking: false,
    shakeIntensity: 0,
  );

  final MotionStatus status;
  final double tiltDegrees;

  /// Magnitude of the phone acceleration being applied, m/s².
  final double acceleration;
  final bool shaking;
  final double shakeIntensity;
}

/// Feeds phone motion into the simulation: sensor readings go through [MotionProcessor] as they
/// arrive, and once per frame the latest tilt and acceleration are written to [SimInputs].
///
/// Sensors run only between [start] and [stop], so the app can switch them off in the background.
/// Without an accelerometer (desktop, most desktop browsers) motion is [MotionStatus.unavailable]
/// and the chime simply hangs straight. Without the OS's linear-acceleration sensor (phones with
/// no gyroscope) the processor derives it from the accelerometer instead.
class MotionController {
  MotionController({required this.source, required this.inputs, MotionProcessor? processor})
      : processor = processor ?? MotionProcessor();

  /// Waiting longer than this for a first reading means there are no sensors.
  static const noSensorsAfter = 2.0;

  /// Accelerometer readings but no linear ones for this long: derive them instead.
  static const noLinearAfter = 1.0;
  static const _publishInterval = 0.25;

  final MotionSource source;
  final SimInputs inputs;
  final MotionProcessor processor;
  final ValueNotifier<MotionSnapshot> snapshot = ValueNotifier(MotionSnapshot.off);

  StreamSubscription<MotionReading>? _accelerometer;
  StreamSubscription<MotionReading>? _linear;
  MotionStatus _status = MotionStatus.off;
  double _sinceReading = 0;
  double _sinceLinear = 0;
  double _publishClock = 0;

  bool get isRunning => _accelerometer != null;

  void start() {
    if (isRunning || _status == MotionStatus.unavailable) return;
    processor
      ..reset()
      ..deriveLinear = false;
    _status = MotionStatus.waiting;
    _sinceReading = _sinceLinear = 0;
    _accelerometer = source.accelerometer().listen((r) {
      processor.addAccelerometer(r.x, r.y, r.z, r.seconds);
      _received();
    }, onError: (Object _) => _accelerometerFailed());
    _linear = source.linearAcceleration().listen((r) {
      processor.addLinearAcceleration(r.x, r.y, r.z, r.seconds);
      _sinceLinear = 0;
      _received();
    }, onError: (Object _) => _deriveLinear());
    _publish();
  }

  /// Stops the sensors and lets the chime hang straight again.
  Future<void> stop() async {
    final subscriptions = [_accelerometer, _linear];
    _accelerometer = _linear = null;
    for (final s in subscriptions) {
      await s?.cancel();
    }
    processor.reset();
    _apply();
    if (_status != MotionStatus.unavailable) _status = MotionStatus.off;
    _publish();
  }

  /// Once per frame, after the readings that arrived since the last frame.
  void update(double dt) {
    if (!isRunning) return;
    _sinceReading += dt;
    _sinceLinear += dt;
    if (!processor.deriveLinear) {
      if (_status == MotionStatus.live && _sinceLinear > noLinearAfter) _deriveLinear();
      if (_sinceLinear > MotionProcessor.staleAfter) processor.fadeMotion(dt);
    } else if (_sinceReading > MotionProcessor.staleAfter) {
      processor.fadeMotion(dt);
    }
    if (_status == MotionStatus.waiting && _sinceReading > noSensorsAfter) {
      _status = MotionStatus.unavailable;
    }
    _apply();
    _publishClock += dt;
    if (_publishClock >= _publishInterval) {
      _publishClock = 0;
      _publish();
    }
  }

  void dispose() {
    _accelerometer?.cancel();
    _linear?.cancel();
    snapshot.dispose();
  }

  void _received() {
    _sinceReading = 0;
    _status = MotionStatus.live;
  }

  void _accelerometerFailed() {
    _status = MotionStatus.unavailable;
    stop();
  }

  void _deriveLinear() {
    _linear?.cancel();
    _linear = null;
    processor.deriveLinear = true;
  }

  void _apply() {
    // Until the first reading, keep whatever gravity the simulation already has.
    if (processor.hasTilt || !isRunning) {
      inputs.setGravityDirection(processor.gravityX, processor.gravityY, 0);
    }
    inputs
      ..deviceAccelX = processor.accelX
      ..deviceAccelY = processor.accelY
      ..deviceAccelZ = processor.accelZ;
  }

  void _publish() {
    final p = processor;
    snapshot.value = MotionSnapshot(
      status: _status,
      tiltDegrees: p.tilt * 180 / math.pi,
      acceleration: math.sqrt(p.accelX * p.accelX + p.accelY * p.accelY + p.accelZ * p.accelZ),
      shaking: p.shake.shaking,
      shakeIntensity: p.shake.intensity,
    );
  }
}
