import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:chime_sim/chime_sim.dart';
import 'package:flame/components.dart';

import 'chime_projection.dart';

/// Draws the chime from the simulation's interpolated state.
///
/// One component draws every body, so depth ordering is an insertion sort over a handful of
/// indices instead of re-prioritizing components each frame. Shaders are built on resize and
/// drawn in local coordinates, so they are reused every frame.
class ChimeRenderer extends Component {
  ChimeRenderer(this.simulation, this.projection)
      : _positions = Float64List(simulation.particles.count * 3),
        _rodScreen = Float64List(simulation.rods.length * _stride),
        _flash = Float64List(simulation.rods.length),
        _order = Int32List(simulation.rods.length + 1),
        _depth = Float64List(simulation.rods.length + 1),
        _rodPaints = List.generate(simulation.rods.length, (_) => Paint());

  // Per tube: top x, top y, bottom x, bottom y, scale, world z of its middle, anchor x, anchor y.
  static const _stride = 8;
  static const _flashSeconds = 0.25;

  static const _metal = [
    Color(0xFF3E454E),
    Color(0xFF9AA4AE),
    Color(0xFFF4F7FA),
    Color(0xFFB7C0C9),
    Color(0xFF6B7580),
    Color(0xFF3A414A),
  ];
  static const _metalStops = [0.0, 0.18, 0.32, 0.5, 0.8, 1.0];

  final ChimeSimulation simulation;
  final ChimeProjection projection;

  final Float64List _positions;
  final Float64List _rodScreen;
  final Float64List _flash;
  final Int32List _order;
  final Float64List _depth;
  final Float64List _point = Float64List(3);
  final List<Paint> _rodPaints;
  final Paint _clapperPaint = Paint();
  final Paint _sailPaint = Paint();
  final Paint _stringPaint = Paint()
    ..color = const Color(0xCCD8D2C4)
    ..strokeWidth = 1.1
    ..style = PaintingStyle.stroke;
  final Paint _ropePaint = Paint()
    ..color = const Color(0xFFB8A487)
    ..strokeWidth = 2.2
    ..style = PaintingStyle.stroke;
  final Paint _mountSidePaint = Paint()..color = const Color(0xFF5E4029);
  final Paint _mountBottomPaint = Paint()..color = const Color(0xFF7C5636);
  final Paint _holePaint = Paint()..color = const Color(0xFF1E2228);
  final Paint _shadePaint = Paint();
  final Paint _flashPaint = Paint();

  int get _clapperItem => simulation.rods.length;

  /// Brightens [rod] briefly; harder hits flash brighter.
  void strike(int rod, double impulse) {
    final level = (impulse / 0.02).clamp(0.3, 1.0);
    if (level > _flash[rod]) _flash[rod] = level;
  }

  @override
  void update(double dt) {
    final decay = math.exp(-dt / _flashSeconds);
    for (var k = 0; k < _flash.length; k++) {
      _flash[k] *= decay;
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final ppm = projection.pixelsPerMeter;
    final config = simulation.config;
    for (var k = 0; k < _rodPaints.length; k++) {
      final w = 2 * simulation.rods[k].spec.radius * ppm;
      _rodPaints[k].shader =
          Gradient.linear(Offset(-w / 2, 0), Offset(w / 2, 0), _metal, _metalStops);
    }
    final r = config.clapperRadius * ppm;
    _clapperPaint.shader = Gradient.radial(
      Offset(-0.35 * r, -0.35 * r),
      1.35 * r,
      const [Color(0xFFD9AE7E), Color(0xFFA8744A), Color(0xFF6A4428)],
      const [0, 0.55, 1],
    );
    final sh = config.sailHeight * ppm;
    _sailPaint.shader = Gradient.linear(
      Offset(0, -sh / 2),
      Offset(0, sh / 2),
      const [Color(0xFFE6D5B5), Color(0xFFC4A67E)],
    );
  }

  @override
  void render(Canvas canvas) {
    simulation.interpolatedPositions(_positions);
    final rods = simulation.rods;

    projection.project(0, 0, 0);
    final hookX = projection.x, hookY = projection.y;
    _projectParticle(ChimeSimulation.mountIndex);
    final mountX = projection.x, mountY = projection.y, mountScale = projection.scale;
    _projectParticle(ChimeSimulation.clapperIndex);
    final clapperX = projection.x, clapperY = projection.y, clapperScale = projection.scale;
    _depth[_clapperItem] = projection.depth;

    // The rope hangs from somewhere above the screen.
    canvas
      ..drawLine(Offset(hookX, 0), Offset(hookX, hookY), _ropePaint)
      ..drawLine(Offset(hookX, hookY), Offset(mountX, mountY), _ropePaint);
    _drawMount(canvas, mountX, mountY, mountScale);
    _drawSail(canvas, clapperX, clapperY);

    for (var k = 0; k < rods.length; k++) {
      final rod = rods[k];
      final o = k * _stride;
      rod.top.eval(_positions, _point);
      final topZ = _point[2];
      projection.project(_point[0], _point[1], topZ);
      _rodScreen[o] = projection.x;
      _rodScreen[o + 1] = projection.y;
      var scale = projection.scale;
      var depth = projection.depth;
      rod.bottom.eval(_positions, _point);
      projection.project(_point[0], _point[1], _point[2]);
      _rodScreen[o + 2] = projection.x;
      _rodScreen[o + 3] = projection.y;
      scale = (scale + projection.scale) / 2;
      depth = (depth + projection.depth) / 2;
      _rodScreen[o + 4] = scale;
      _rodScreen[o + 5] = (topZ + _point[2]) / 2;
      rod.anchor.eval(_positions, _point);
      projection.project(_point[0], _point[1], _point[2]);
      _rodScreen[o + 6] = projection.x;
      _rodScreen[o + 7] = projection.y;
      _depth[k] = depth;
    }

    // Back to front.
    for (var i = 0; i < _order.length; i++) {
      _order[i] = i;
    }
    for (var i = 1; i < _order.length; i++) {
      final item = _order[i];
      var j = i - 1;
      while (j >= 0 && _depth[_order[j]] > _depth[item]) {
        _order[j + 1] = _order[j];
        j--;
      }
      _order[j + 1] = item;
    }

    for (final item in _order) {
      if (item == _clapperItem) {
        canvas.drawLine(Offset(mountX, mountY), Offset(clapperX, clapperY), _stringPaint);
        canvas
          ..save()
          ..translate(clapperX, clapperY)
          ..scale(clapperScale)
          ..drawCircle(
              Offset.zero, simulation.config.clapperRadius * projection.pixelsPerMeter, _clapperPaint)
          ..restore();
      } else {
        _drawRod(canvas, item);
      }
    }
  }

  void _projectParticle(int i) =>
      projection.project(_positions[3 * i], _positions[3 * i + 1], _positions[3 * i + 2]);

  void _drawMount(Canvas canvas, double x, double y, double scale) {
    final config = simulation.config;
    final k = projection.pixelsPerMeter * scale;
    final radius = config.mountRadius * k;
    final thickness = config.mountThickness * k * math.cos(projection.pitch);
    final underside = config.mountRadius * k * math.sin(projection.pitch);
    canvas
      ..drawRRect(
        RRect.fromLTRBR(x - radius, y - thickness / 2, x + radius, y + thickness / 2,
            Radius.circular(thickness / 2)),
        _mountSidePaint,
      )
      ..drawOval(
        Rect.fromCenter(center: Offset(x, y + thickness / 2), width: 2 * radius, height: 2 * underside),
        _mountBottomPaint,
      );
  }

  void _drawSail(Canvas canvas, double clapperX, double clapperY) {
    final config = simulation.config;
    final sail = 3 * ChimeSimulation.sailIndex;
    final clapper = 3 * ChimeSimulation.clapperIndex;
    final sx = _positions[sail], sy = _positions[sail + 1], sz = _positions[sail + 2];
    var dx = sx - _positions[clapper];
    var dy = sy - _positions[clapper + 1];
    var dz = sz - _positions[clapper + 2];
    final len = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (len > 1e-9) {
      dx /= len;
      dy /= len;
      dz /= len;
    }
    final half = config.sailHeight / 2;
    projection.project(sx - dx * half, sy - dy * half, sz - dz * half);
    canvas.drawLine(Offset(clapperX, clapperY), Offset(projection.x, projection.y), _stringPaint);

    projection.project(sx, sy, sz);
    final ppm = projection.pixelsPerMeter;
    canvas
      ..save()
      ..translate(projection.x, projection.y)
      ..rotate(math.atan2(-(projection.x - clapperX), projection.y - clapperY))
      ..scale(projection.scale)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: config.sailWidth * ppm, height: config.sailHeight * ppm),
          const Radius.circular(4),
        ),
        _sailPaint,
      )
      ..restore();
  }

  void _drawRod(Canvas canvas, int k) {
    final o = k * _stride;
    final x0 = _rodScreen[o], y0 = _rodScreen[o + 1];
    final dx = _rodScreen[o + 2] - x0, dy = _rodScreen[o + 3] - y0;
    final scale = _rodScreen[o + 4];
    final z = _rodScreen[o + 5];
    canvas.drawLine(Offset(_rodScreen[o + 6], _rodScreen[o + 7]), Offset(x0, y0), _stringPaint);

    final length = math.sqrt(dx * dx + dy * dy);
    final w = 2 * simulation.rods[k].spec.radius * projection.pixelsPerMeter;
    final body = RRect.fromLTRBR(-w / 2, 0, w / 2, length, Radius.circular(w * 0.2));
    canvas
      ..save()
      ..translate(x0, y0)
      ..rotate(math.atan2(-dx, dy))
      ..scale(scale, 1)
      ..drawRRect(body, _rodPaints[k])
      ..drawOval(
        Rect.fromCenter(center: Offset(0, length - w * 0.08), width: w * 0.8, height: w * 0.28),
        _holePaint,
      );

    // Tubes at the back of the ring sit slightly in shadow.
    final back = 1 - ((z / simulation.config.ringRadius + 1) / 2).clamp(0.0, 1.0);
    final shade = 0.32 * back;
    if (shade > 0.01) {
      _shadePaint.color = Color.fromRGBO(4, 8, 20, shade);
      canvas.drawRRect(body, _shadePaint);
    }
    final flash = _flash[k];
    if (flash > 0.01) {
      _flashPaint.color = Color.fromRGBO(255, 246, 224, 0.6 * flash);
      canvas.drawRRect(body, _flashPaint);
    }
    canvas.restore();
  }
}
