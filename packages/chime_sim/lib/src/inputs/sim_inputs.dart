import 'dart:math' as math;

import '../wind/placement.dart';

/// Latest-value snapshot of everything outside the simulation that affects it.
///
/// Controllers write here whenever their data arrives; the simulation reads it once per fixed
/// step. Nothing here is a stream, so input rates and the physics rate stay decoupled.
final class SimInputs {
  /// Direction of gravity in the scene frame. The magnitude comes from the config, so tilting the
  /// phone rotates gravity without weakening it. Kept normalized by [setGravityDirection].
  double gravityDirX = 0;
  double gravityDirY = -1;
  double gravityDirZ = 0;

  /// The phone's linear acceleration in the scene frame, m/s². Applied to every body as the
  /// inertial pseudo-force −m·a.
  double deviceAccelX = 0;
  double deviceAccelY = 0;
  double deviceAccelZ = 0;

  /// Mean wind at 10 m height, as a weather service reports it, m/s.
  double windSpeed = 0;

  /// Gust speed at 10 m, m/s. At or below [windSpeed] means no gusts beyond turbulence.
  double windGust = 0;

  /// Direction the wind comes from, degrees clockwise from north.
  double windDirection = 270;

  Placement placement = Placement.garden;

  /// User multiplier on the wind the chime feels.
  double windSensitivity = 1;

  /// How quickly the chime's mean wind follows changes: a time constant in seconds. Weather
  /// updates use about 30 s so a new reading never jumps; manual control is snappier.
  double windResponseTime = 30;

  /// Particle held by the user's finger, or -1.
  int touchParticle = -1;
  double touchX = 0;
  double touchY = 0;
  double touchZ = 0;

  bool get isTouching => touchParticle >= 0;

  void setGravityDirection(double x, double y, double z) {
    final len = _length(x, y, z);
    if (!(len > 1e-9)) return;
    gravityDirX = x / len;
    gravityDirY = y / len;
    gravityDirZ = z / len;
  }

  void grab(int particle, double x, double y, double z) {
    touchParticle = particle;
    moveTouch(x, y, z);
  }

  void moveTouch(double x, double y, double z) {
    touchX = x;
    touchY = y;
    touchZ = z;
  }

  void release() => touchParticle = -1;
}

double _length(double x, double y, double z) => math.sqrt(x * x + y * y + z * z);
