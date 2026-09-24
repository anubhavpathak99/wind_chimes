import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:chime_sim/chime_sim.dart';
import 'package:flame/components.dart';

import 'sky.dart';

/// Specks of dust and seed drifting behind the chime on the same wind that moves it, so a gust is
/// seen arriving just as the chime answers it. Nearer specks are bigger, brighter and faster
/// (parallax); in calm air they fade away. All state is in preallocated arrays.
class WindMotes extends Component {
  WindMotes(this.wind, this.sky, {int count = 40, int seed = 11})
      : _x = Float64List(count),
        _y = Float64List(count),
        _depth = Float64List(count),
        _phase = Float64List(count),
        _random = math.Random(seed);

  /// Screen widths travelled per second per m/s of wind, for the farthest and nearest specks.
  static const _farSpeed = 0.035;
  static const _nearSpeed = 0.16;

  final WindField wind;
  final SkyModel sky;
  final Float64List _x;
  final Float64List _y;
  final Float64List _depth;
  final Float64List _phase;
  final math.Random _random;
  final Paint _paint = Paint();
  Vector2 _size = Vector2.zero();
  double _time = 0;
  double _visibility = 0;
  bool _seeded = false;

  /// How visible the specks are, 0–1, following the wind.
  double get visibility => _visibility;

  /// Mean horizontal position, as a fraction of the width (for tests; allocation-free).
  double get meanX {
    var sum = 0.0;
    for (final x in _x) {
      sum += x;
    }
    return sum / _x.length;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _size = size.clone();
    if (!_seeded) {
      _seeded = true;
      for (var i = 0; i < _x.length; i++) {
        _respawn(i, anywhere: true);
      }
    }
  }

  void _respawn(int i, {bool anywhere = false, double side = 0}) {
    _depth[i] = 0.15 + 0.85 * math.pow(_random.nextDouble(), 1.5);
    _phase[i] = _random.nextDouble() * 2 * math.pi;
    _y[i] = 0.05 + 0.9 * _random.nextDouble();
    _x[i] = anywhere ? _random.nextDouble() : (side < 0 ? -0.03 : 1.03);
  }

  @override
  void update(double dt) {
    _time += dt;
    final speed = wind.speed;
    // Specks show once there is some wind, and fade away in calm air.
    final target = ((speed - 0.4) / 2.5).clamp(0.0, 1.0);
    _visibility += (target - _visibility) * (1 - math.exp(-dt / 1.5));
    final windX = wind.x;
    final aspect = _size.y > 0 ? _size.x / _size.y : 0.5;
    for (var i = 0; i < _x.length; i++) {
      final d = _depth[i];
      final pace = _farSpeed + (_nearSpeed - _farSpeed) * d;
      final swirl = math.sin(_time * (0.6 + 0.5 * d) + _phase[i]);
      _x[i] += dt * (windX * pace + 0.01 * swirl);
      _y[i] += dt * aspect * (0.012 * math.cos(_time * 0.8 + _phase[i]) + 0.004 * speed * swirl * d);
      if (_x[i] < -0.05 || _x[i] > 1.05 || _y[i] < -0.05 || _y[i] > 1.05) {
        // Re-enter from the side the wind comes from.
        _respawn(i, side: windX >= 0 ? -1 : 1);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (_visibility < 0.01) return;
    final light = sky.palette.light;
    final w = _size.x, h = _size.y;
    for (var i = 0; i < _x.length; i++) {
      final d = _depth[i];
      final twinkle = 0.8 + 0.2 * math.sin(_time * 1.3 + _phase[i]);
      final alpha = _visibility * (0.12 + 0.38 * d) * twinkle * (0.6 + 0.4 * light);
      _paint.color = Color.fromRGBO(236, 228, 210, alpha);
      canvas.drawCircle(Offset(_x[i] * w, _y[i] * h), 0.8 + 2.2 * d, _paint);
    }
  }
}
