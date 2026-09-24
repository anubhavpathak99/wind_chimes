import 'dart:math' as math;

import 'one_euro_filter.dart';
import 'shake_detector.dart';

/// Turns raw phone motion into the two things the simulation takes: which way gravity points on
/// screen, and how the phone itself is accelerating.
///
/// Axes are the device's, which in portrait are the scene's: x right, y up, z out of the screen.
/// Readings follow the Android convention on both platforms: at rest the accelerometer reads the
/// opposite of gravity (+9.81 on whichever axis points up).
///
/// **Tilt.** Gravity is the accelerometer reading minus the linear acceleration (so shaking doesn't
/// read as tilting), smoothed with a 1€ filter. Only its roll in the screen plane is used, clamped
/// to ±[maxTilt] and faded out as the phone lies flat or turns upside down, where the in-screen
/// part of gravity means nothing. Only the direction comes from the sensor; gravity's strength is
/// the simulation's.
///
/// **Shaking.** Linear acceleration past a small dead zone, lightly smoothed, scaled by
/// [sensitivity] and soft-clamped to [maxAcceleration] above a knee. The simulation applies it to
/// every body as the inertial force −m·a, which is exactly what a chime hanging inside the phone
/// would feel.
class MotionProcessor {
  MotionProcessor({this.sensitivity = 1, this.tiltEnabled = true});

  static const double g = 9.81;
  static const double maxTilt = 40 * math.pi / 180;

  /// Linear acceleration below this (m/s²) is sensor noise: a phone on a table reads ~0.03.
  static const double deadZone = 0.15;
  static const double smoothingSeconds = 0.025;
  static const double maxAcceleration = 1.5 * g;

  /// With no linear-acceleration reading for this long, the phone's motion fades out.
  static const double staleAfter = 0.2;
  static const double fadeSeconds = 0.1;

  /// A linear reading this close in time to an accelerometer reading is subtracted from it.
  static const double pairingWindow = 0.1;

  /// Time constant of the slow gravity estimate used when [deriveLinear] is on, s.
  static const double gravitySeconds = 0.6;

  double sensitivity;
  bool tiltEnabled;

  /// For phones whose OS offers no fused linear-acceleration sensor (no gyroscope): derive the
  /// phone's motion from the accelerometer minus a slow estimate of gravity, and tilt from that
  /// estimate. Coarser (tilt follows in about half a second, and a quick tilt briefly reads as a
  /// push), but tilting and shaking both still work.
  bool deriveLinear = false;
  final ShakeDetector shake = ShakeDetector();

  final OneEuroFilter _gx = OneEuroFilter(minCutoff: 0.8, beta: 1);
  final OneEuroFilter _gy = OneEuroFilter(minCutoff: 0.8, beta: 1);
  double? _lastAccelTime;
  double? _lastLinearTime;
  double _rawX = 0, _rawY = 0;
  double _smoothX = 0, _smoothY = 0, _smoothZ = 0;
  double? _slowX;
  double _slowY = 0, _slowZ = 0;

  /// Whether an accelerometer reading has arrived since the last [reset].
  bool get hasTilt => _lastAccelTime != null;

  /// Roll of gravity in the screen plane, radians: positive leans right, as when the phone's
  /// right edge dips.
  double tilt = 0;

  double get gravityX => math.sin(tilt);
  double get gravityY => -math.cos(tilt);

  /// The phone's acceleration to apply, m/s², after sensitivity and the clamp.
  double accelX = 0;
  double accelY = 0;
  double accelZ = 0;

  /// An accelerometer reading (gravity included), m/s², at [seconds] on the sensor clock.
  void addAccelerometer(double x, double y, double z, double seconds) {
    final dt = _interval(_lastAccelTime, seconds);
    _lastAccelTime = seconds;
    double gravityReadingX, gravityReadingY;
    if (deriveLinear) {
      // Without fusion, only a slow estimate keeps shaking from reading as tilt.
      _deriveLinear(x, y, z, dt);
      gravityReadingX = _slowX!;
      gravityReadingY = _slowY;
    } else {
      final linear = _lastLinearTime;
      final paired = linear != null && (seconds - linear).abs() <= pairingWindow;
      gravityReadingX = x - (paired ? _rawX : 0);
      gravityReadingY = y - (paired ? _rawY : 0);
    }
    // The reading is the opposite of gravity; work in g.
    final gx = _gx.filter(-gravityReadingX / g, dt);
    final gy = _gy.filter(-gravityReadingY / g, dt);
    if (!tiltEnabled) {
      tilt = 0;
      return;
    }
    final inPlane = math.sqrt(gx * gx + gy * gy);
    if (inPlane < 1e-6) {
      tilt = 0;
      return;
    }
    final roll = math.atan2(gx, -gy);
    final weight = _smoothstep(0.25, 0.5, inPlane) * _smoothstep(0, 0.3, -gy / inPlane);
    tilt = roll.clamp(-maxTilt, maxTilt) * weight;
  }

  /// A linear-acceleration reading (gravity removed), m/s², at [seconds] on the sensor clock.
  void addLinearAcceleration(double x, double y, double z, double seconds) {
    final dt = _interval(_lastLinearTime, seconds);
    _lastLinearTime = seconds;
    _rawX = x;
    _rawY = y;
    _addLinear(x, y, z, dt);
  }

  /// Updates the slow gravity estimate, trusting readings less the further their magnitude is from
  /// 1 g (the phone is being moved), and feeds the difference in as linear acceleration.
  void _deriveLinear(double x, double y, double z, double dt) {
    final slowX = _slowX;
    if (slowX == null) {
      _slowX = x;
      _slowY = y;
      _slowZ = z;
      return;
    }
    final deviation = (math.sqrt(x * x + y * y + z * z) - g) / (0.15 * g);
    final alpha = (1 - math.exp(-dt / gravitySeconds)) * math.exp(-deviation * deviation);
    _slowX = slowX + (x - slowX) * alpha;
    _slowY += (y - _slowY) * alpha;
    _slowZ += (z - _slowZ) * alpha;
    _addLinear(x - _slowX!, y - _slowY, z - _slowZ, dt);
  }

  void _addLinear(double x, double y, double z, double dt) {
    shake.add(x, y, z, dt);

    // Soft dead zone: continuous at its edge, so a slow push doesn't start with a step.
    final magnitude = math.sqrt(x * x + y * y + z * z);
    final keep = magnitude > deadZone ? (magnitude - deadZone) / magnitude : 0.0;
    final alpha = 1 - math.exp(-dt / smoothingSeconds);
    _smoothX += (x * keep - _smoothX) * alpha;
    _smoothY += (y * keep - _smoothY) * alpha;
    _smoothZ += (z * keep - _smoothZ) * alpha;
    _publishAcceleration();
  }

  /// Lets the phone's motion fade out, for when linear readings have stopped arriving: a stale
  /// value must not keep pushing the chime.
  void fadeMotion(double dt) {
    final keep = math.exp(-dt / fadeSeconds);
    _smoothX *= keep;
    _smoothY *= keep;
    _smoothZ *= keep;
    _publishAcceleration();
  }

  void reset() {
    _gx.reset();
    _gy.reset();
    shake.reset();
    _lastAccelTime = _lastLinearTime = null;
    _rawX = _rawY = 0;
    _smoothX = _smoothY = _smoothZ = 0;
    _slowX = null;
    tilt = 0;
    _publishAcceleration();
  }

  void _publishAcceleration() {
    var x = _smoothX * sensitivity, y = _smoothY * sensitivity, z = _smoothZ * sensitivity;
    // Soft knee: ordinary pushes pass unchanged; only violent jolts are compressed.
    final magnitude = math.sqrt(x * x + y * y + z * z);
    const knee = 0.6 * maxAcceleration;
    if (magnitude > knee) {
      final scale =
          (knee + (maxAcceleration - knee) * _tanh((magnitude - knee) / (maxAcceleration - knee))) /
              magnitude;
      x *= scale;
      y *= scale;
      z *= scale;
    }
    accelX = x;
    accelY = y;
    accelZ = z;
  }

  /// Seconds since the previous reading of the same sensor; a gap (or the first reading) counts
  /// as one nominal sample.
  static double _interval(double? last, double now) {
    if (last == null) return 0;
    final dt = now - last;
    return dt > 0 && dt < 0.5 ? dt : 0.02;
  }
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _tanh(double x) {
  if (x > 20) return 1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}
