import 'dart:math' as math;
import 'dart:typed_data';

import '../inputs/sim_inputs.dart';
import 'ou_noise.dart';
import 'placement.dart';

/// Turns the slowly changing mean wind in [SimInputs] into the fluctuating wind the chime feels.
///
/// A weather service reports a 10-minute mean, and a steady force only leans a chime over; it
/// rings because the wind keeps changing. So the mean (scaled by placement, soft-capped, eased
/// toward new values) gets turbulence along and across the wind, discrete gusts sized by the
/// reported gust factor, and a slowly meandering direction. Turbulence has two scales: large eddies
/// (seconds) and small ones (fractions of a second) whose energy sits near the chime's own swing
/// frequency. Gusts travel through the chime at the mean speed, so upwind tubes feel them first.
///
/// Scene frame: x = east, z = toward the viewer, who faces north. The wind is horizontal.
final class WindField {
  WindField({required this.stepDt, int seed = 1})
      : _gaussian = Gaussian(math.Random(seed)),
        _random = math.Random(seed * 7919 + 1) {
    _alongSlow = OrnsteinUhlenbeck(largeEddySeconds, _gaussian);
    _alongFast = OrnsteinUhlenbeck(smallEddySeconds, _gaussian);
    _acrossSlow = OrnsteinUhlenbeck(largeEddySeconds, _gaussian);
    _acrossFast = OrnsteinUhlenbeck(smallEddySeconds, _gaussian);
    _meander = OrnsteinUhlenbeck(meanderSeconds, _gaussian);
  }

  /// Wind above this (m/s at the chime) is compressed so storms stay wild without breaking.
  static const double softCap = 8;
  /// Correlation times of the large and small eddies, s.
  static const double largeEddySeconds = 2.5;
  static const double smallEddySeconds = 0.4;

  /// Share of the turbulent variance carried by small eddies.
  static const double smallEddyShare = 0.35;

  /// Crosswind turbulence relative to along-wind turbulence (about 0.75 near the ground).
  static const double crosswindRatio = 0.75;

  /// Light winds are relatively gustier than strong ones (thermals and meandering dominate).
  /// Adds this much turbulence intensity at calm, fading with a scale of [lightWindScale] m/s.
  static const double lightWindGustiness = 0.25;
  static const double lightWindScale = 1.5;

  /// Slow wander of the mean direction: correlation time (s) and standard deviation (radians).
  static const double meanderSeconds = 6;
  static const double meander = 10 * math.pi / 180;

  /// Gusts arrive at (G − 1) × this rate per second, G being the gust factor: one every 15 s at
  /// G = 1.5.
  static const double gustRatePerFactor = 2 / 15;
  static const double minGustSeconds = 2;
  static const double maxGustSeconds = 5;

  /// Distance upwind of the chime's axis where a gust is "now". Keeps travel delays positive.
  static const double reach = 0.08;

  static final double _slowWeight = math.sqrt(1 - smallEddyShare);
  static final double _fastWeight = math.sqrt(smallEddyShare);
  static const int _maxGusts = 4;
  static const int _historyLength = 64;

  /// Mean wind at the chime for a reported 10 m wind: exposure, soft cap, then sensitivity.
  static double chimeSpeed(double speed10m, Placement placement, {double sensitivity = 1}) =>
      softCap * _tanh(placement.exposure * math.max(speed10m, 0.0) / softCap) * sensitivity;

  final double stepDt;
  final Gaussian _gaussian;
  final math.Random _random;
  late final OrnsteinUhlenbeck _alongSlow;
  late final OrnsteinUhlenbeck _alongFast;
  late final OrnsteinUhlenbeck _acrossSlow;
  late final OrnsteinUhlenbeck _acrossFast;
  late final OrnsteinUhlenbeck _meander;

  final Float64List _gustStart = Float64List(_maxGusts);
  final Float64List _gustDuration = Float64List(_maxGusts);
  final Float64List _gustAmplitude = Float64List(_maxGusts);
  final Float64List _history = Float64List(_historyLength * 2);
  int _historyHead = 0;
  int _historyCount = 0;

  double _time = 0;
  double _meanX = 0;
  double _meanZ = 0;
  double _baseAngle = 0;
  double _speed = 0;
  double _gust = 0;
  double _x = 0;
  double _z = 0;

  /// Eased mean wind speed at the chime, m/s.
  double get meanSpeed => math.sqrt(_meanX * _meanX + _meanZ * _meanZ);

  /// Instantaneous wind speed at the chime's upwind edge, m/s.
  double get speed => _speed;

  /// The part of [speed] due to gusts, m/s.
  double get gust => _gust;
  double get x => _x;
  double get z => _z;

  /// Jumps the mean straight to the current target, skipping the easing.
  void snapToTarget(SimInputs inputs) {
    final target = _target(inputs);
    _meanX = target.x;
    _meanZ = target.z;
  }

  void step(SimInputs inputs) {
    final dt = stepDt;
    _time += dt;

    final target = _target(inputs);
    final response = inputs.windResponseTime;
    final alpha = response > 0 ? 1 - math.exp(-dt / response) : 1.0;
    _meanX += (target.x - _meanX) * alpha;
    _meanZ += (target.z - _meanZ) * alpha;
    final mean = meanSpeed;
    if (mean > 1e-6) _baseAngle = math.atan2(_meanZ, _meanX);

    _maybeStartGust(mean, _gustFactor(inputs), dt);
    _gust = _gustAt(_time);
    final along = _slowWeight * _alongSlow.step(dt) + _fastWeight * _alongFast.step(dt);
    final across = _slowWeight * _acrossSlow.step(dt) + _fastWeight * _acrossFast.step(dt);
    final intensity =
        inputs.placement.turbulence + lightWindGustiness * math.exp(-mean / lightWindScale);
    final sigma = intensity * mean;

    final alongSpeed = math.max(0.0, mean + sigma * along + _gust);
    final acrossSpeed = crosswindRatio * sigma * across;
    final angle = _baseAngle + meander * _meander.step(dt);
    final c = math.cos(angle), s = math.sin(angle);
    _x = alongSpeed * c - acrossSpeed * s;
    _z = alongSpeed * s + acrossSpeed * c;
    _speed = math.sqrt(_x * _x + _z * _z);

    _history[2 * _historyHead] = _x;
    _history[2 * _historyHead + 1] = _z;
    _historyHead = (_historyHead + 1) % _historyLength;
    if (_historyCount < _historyLength) _historyCount++;
  }

  /// Wind velocity at horizontal scene position ([px], [pz]), delayed by the time a gust takes to
  /// travel there from [reach] upwind. Writes x and z into `out[at]` and `out[at + 1]`.
  void sampleAt(double px, double pz, Float64List out, int at) {
    if (_historyCount == 0) {
      out[at] = 0;
      out[at + 1] = 0;
      return;
    }
    final mean = meanSpeed;
    var lag = 0.0;
    if (mean > 0.05) {
      final along = (px * _meanX + pz * _meanZ) / mean;
      lag = math.max(0, (along + reach) / mean / stepDt);
    }
    lag = math.min(lag, (_historyCount - 1).toDouble());
    final k = lag.floor();
    final frac = lag - k;
    final a = _historyIndex(k);
    final b = _historyIndex(math.min(k + 1, _historyCount - 1));
    out[at] = _history[2 * a] + (_history[2 * b] - _history[2 * a]) * frac;
    out[at + 1] = _history[2 * a + 1] + (_history[2 * b + 1] - _history[2 * a + 1]) * frac;
  }

  int _historyIndex(int stepsAgo) =>
      (_historyHead - 1 - stepsAgo + 2 * _historyLength) % _historyLength;

  ({double x, double z}) _target(SimInputs inputs) {
    final speed = chimeSpeed(inputs.windSpeed, inputs.placement,
        sensitivity: inputs.windSensitivity);
    // Meteorological direction is where the wind comes from; it blows the opposite way.
    final from = inputs.windDirection * math.pi / 180;
    return (x: -speed * math.sin(from), z: speed * math.cos(from));
  }

  static double _gustFactor(SimInputs inputs) {
    if (inputs.windSpeed < 0.1 || inputs.windGust <= inputs.windSpeed) return 1;
    return math.min(inputs.windGust / inputs.windSpeed, 3);
  }

  void _maybeStartGust(double mean, double gustFactor, double dt) {
    if (gustFactor <= 1 || mean <= 0) return;
    if (_random.nextDouble() >= (gustFactor - 1) * gustRatePerFactor * dt) return;
    for (var i = 0; i < _maxGusts; i++) {
      if (_gustAmplitude[i] > 0) continue;
      _gustStart[i] = _time;
      _gustDuration[i] =
          minGustSeconds + (maxGustSeconds - minGustSeconds) * _random.nextDouble();
      _gustAmplitude[i] = mean * (gustFactor - 1) * (0.3 + 0.7 * _random.nextDouble());
      return;
    }
  }

  /// Sum of active gusts, each a smooth 1 − cos pulse.
  double _gustAt(double t) {
    var total = 0.0;
    for (var i = 0; i < _maxGusts; i++) {
      final amplitude = _gustAmplitude[i];
      if (amplitude == 0) continue;
      final u = (t - _gustStart[i]) / _gustDuration[i];
      if (u >= 1) {
        _gustAmplitude[i] = 0;
        continue;
      }
      total += amplitude * 0.5 * (1 - math.cos(2 * math.pi * u));
    }
    return total;
  }
}

double _tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}
