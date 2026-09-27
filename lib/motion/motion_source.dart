import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// One sensor reading, m/s², Android axis convention, [seconds] on the sensor's clock. The clock
/// is only good for spacing between readings; it isn't wall time on every platform.
typedef MotionReading = ({double x, double y, double z, double seconds});

/// Where phone motion comes from. `sensors_plus` today; a native fused-motion plugin can replace
/// it without touching anything downstream.
abstract interface class MotionSource {
  /// Accelerometer readings, gravity included.
  Stream<MotionReading> accelerometer();

  /// Linear acceleration, with gravity removed by the OS's sensor fusion.
  Stream<MotionReading> linearAcceleration();
}

class SensorsPlusMotionSource implements MotionSource {
  const SensorsPlusMotionSource();

  /// The plugin only exists on Android, iOS and the web. Elsewhere its calls throw from futures it
  /// never hands back, so they can't be caught: use [NoMotionSource] there instead.
  static bool get isSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// 50 Hz: responsive enough for shaking, without the battery cost of the fastest rate.
  static const period = SensorInterval.gameInterval;

  @override
  Stream<MotionReading> accelerometer() => accelerometerEventStream(samplingPeriod: period)
      .map((e) => (x: e.x, y: e.y, z: e.z, seconds: e.timestamp.microsecondsSinceEpoch / 1e6));

  @override
  Stream<MotionReading> linearAcceleration() =>
      userAccelerometerEventStream(samplingPeriod: period)
          .map((e) => (x: e.x, y: e.y, z: e.z, seconds: e.timestamp.microsecondsSinceEpoch / 1e6));
}

/// A device with no motion sensors (desktop): both streams fail at once, so motion goes straight
/// to unavailable instead of waiting for readings that will never come.
class NoMotionSource implements MotionSource {
  const NoMotionSource();

  @override
  Stream<MotionReading> accelerometer() => Stream.error(UnsupportedError('No motion sensors'));

  @override
  Stream<MotionReading> linearAcceleration() => Stream.error(UnsupportedError('No motion sensors'));
}
