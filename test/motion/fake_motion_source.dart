import 'dart:async';

import 'package:wind_chimes/motion/motion_source.dart';

/// Motion readings the test pushes by hand.
class FakeMotionSource implements MotionSource {
  StreamController<MotionReading>? accel;
  StreamController<MotionReading>? linear;

  @override
  Stream<MotionReading> accelerometer() => (accel = StreamController()).stream;

  @override
  Stream<MotionReading> linearAcceleration() => (linear = StreamController()).stream;
}
