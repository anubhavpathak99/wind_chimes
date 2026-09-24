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
