import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:chime_sim/chime_sim.dart';
import 'package:flame/components.dart';

import 'chime_projection.dart';
import 'sky.dart';

/// Draws the chime from the simulation's interpolated state.
///
/// One component draws every body, so depth ordering is an insertion sort over a handful of
/// indices instead of re-prioritizing components each frame. Shaders are built on resize or when
/// the sky's light changes, and drawn in local coordinates, so they are reused every frame.
///
/// The metal reflects the sky's colours; a soft glint slides across each tube as the chime turns
/// on its rope; the sail is drawn as cloth on a dowel that billows and ripples with the wind.
class ChimeRenderer extends Component {
  ChimeRenderer(this.simulation, this.projection, this.sky)
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
  static const _sailColors = [Color(0xFFE9D9BA), Color(0xFFD6BD95), Color(0xFFC2A37B)];

  /// Direction the light comes from, as an angle around the ring (radians from the viewer
  /// toward +x): up and to the left.
  static const _lightAngle = -0.7;

  final ChimeSimulation simulation;
  final ChimeProjection projection;
  final SkyModel sky;

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
  final Paint _eyeletPaint = Paint()..color = const Color(0xFF2E1E12);
  final Paint _grainPaint = Paint()
    ..color = const Color(0x55402A18)
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  final Paint _shadePaint = Paint();
  final Paint _flashPaint = Paint();
  final Paint _glintPaint = Paint();
  final Paint _foldPaint = Paint();
  final Paint _dowelPaint = Paint()..color = const Color(0xFF6E4A2C);
  final Paint _hemPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;
  final Path _sailPath = Path();
  final Path _hemPath = Path();
  int _litVersion = -1;
  double _flutter = 0;

  int get _clapperItem => simulation.rods.length;

  /// Brightens [rod] briefly; harder hits flash brighter.
  void strike(int rod, double impulse) {
    final level = (impulse / 0.02).clamp(0.3, 1.0);
    if (level > _flash[rod]) _flash[rod] = level;
  }

  @override
  void update(double dt) {
    // Accumulated, so a change in the wind changes the flutter's pace without a jump.
    _flutter += dt * (2.2 + 1.1 * simulation.wind.speed);
    final decay = math.exp(-dt / _flashSeconds);
    for (var k = 0; k < _flash.length; k++) {
      _flash[k] *= decay;
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _litVersion = -1;
  }

  /// A colour as lit by the sky: darker at night, a touch brighter by day.
  static Color _lit(Color c, double light) => light >= 0.75
      ? Color.lerp(c, const Color(0xFFFFFFFF), (light - 0.75) * 0.4)!
      : Color.lerp(const Color(0xFF000000), c, 0.7 + 0.3 * light / 0.75)!;

  /// Builds the shaders for the base scale and the current sky.
  void _buildShaders() {
    final p = sky.palette;
    final light = p.light;
    final ppm = projection.basePixelsPerMeter;
    final config = simulation.config;
    // Metal reflects the sky: the upper sky in its edges, the horizon in its lower half.
    final metal = [
      Color.lerp(_metal[0], p.top, 0.25)!,
      Color.lerp(_metal[1], p.middle, 0.3)!,
      Color.lerp(_metal[2], p.bottom, 0.12)!,
      Color.lerp(_metal[3], p.middle, 0.2)!,
      Color.lerp(_metal[4], p.bottom, 0.25)!,
      Color.lerp(_metal[5], p.top, 0.25)!,
    ].map((c) => _lit(c, light)).toList();
    for (var k = 0; k < _rodPaints.length; k++) {
      final w = 2 * simulation.rods[k].spec.radius * ppm;
      _rodPaints[k].shader = Gradient.linear(Offset(-w / 2, 0), Offset(w / 2, 0), metal, _metalStops);
    }
    final w = 2 * simulation.rods.first.spec.radius * ppm;
    final glint = 0.55 * light;
    _glintPaint.shader = Gradient.linear(
      Offset(-0.2 * w, 0),
      Offset(0.2 * w, 0),
      [
        const Color(0x00FFFFFF),
        Color.fromRGBO(255, 255, 255, glint),
        const Color(0x00FFFFFF),
      ],
      const [0, 0.5, 1],
    );
    final r = config.clapperRadius * ppm;
    _clapperPaint.shader = Gradient.radial(
      Offset(-0.35 * r, -0.35 * r),
      1.35 * r,
      [
        _lit(const Color(0xFFD9AE7E), light),
        _lit(const Color(0xFFA8744A), light),
        _lit(const Color(0xFF6A4428), light),
      ],
      const [0, 0.55, 1],
    );
    final sh = config.sailHeight * ppm, sw = config.sailWidth * ppm;
    _sailPaint.shader = Gradient.linear(
      Offset(0, -sh / 2),
      Offset(0, sh / 2),
      [for (final c in _sailColors) _lit(c, light)],
      const [0, 0.6, 1],
    );
    // Soft vertical folds across the cloth.
    _foldPaint.shader = Gradient.linear(
      Offset(-sw / 2, 0),
      Offset(sw / 2, 0),
      const [
        Color(0x00000000),
        Color(0x1F3A2A14),
        Color(0x00000000),
        Color(0x14FFFFFF),
        Color(0x00000000),
        Color(0x1A3A2A14),
        Color(0x00000000),
      ],
      const [0, 0.18, 0.34, 0.5, 0.64, 0.82, 1],
    );
    _hemPaint.color = _lit(const Color(0x66806040), light);
    _dowelPaint.color = _lit(const Color(0xFF6E4A2C), light);
    _mountSidePaint.color = _lit(const Color(0xFF5E4029), light);
    _mountBottomPaint.color = _lit(const Color(0xFF7C5636), light);
    _litVersion = sky.version;
  }

  @override
  void render(Canvas canvas) {
    if (_litVersion != sky.version) _buildShaders();
    simulation.interpolatedPositions(_positions);
    final rods = simulation.rods;

    projection.project(0, 0, 0);
    final hookX = projection.x, hookY = projection.y;
    _projectParticle(ChimeSimulation.mountIndex);
    final mountX = projection.x, mountY = projection.y, mountScale = projection.scale;
    _projectParticle(ChimeSimulation.clapperIndex);
    final clapperX = projection.x, clapperY = projection.y, clapperScale = projection.scale;
    _depth[_clapperItem] = projection.depth;

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

    // The rope hangs from somewhere above the screen.
    canvas
      ..drawLine(Offset(hookX, 0), Offset(hookX, hookY), _ropePaint)
      ..drawLine(Offset(hookX, hookY), Offset(mountX, mountY), _ropePaint);
    _drawMount(canvas, mountX, mountY, mountScale);
    _drawEyelets(canvas, mountScale);
    _drawSail(canvas, clapperX, clapperY);

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
          ..scale(clapperScale * projection.zoom)
          ..drawCircle(Offset.zero,
              simulation.config.clapperRadius * projection.basePixelsPerMeter, _clapperPaint)
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
    final bottomY = y + thickness / 2;
    canvas
      ..drawRRect(
        RRect.fromLTRBR(x - radius, y - thickness / 2, x + radius, y + thickness / 2,
            Radius.circular(thickness / 2)),
        _mountSidePaint,
      )
      ..drawOval(
        Rect.fromCenter(center: Offset(x, bottomY), width: 2 * radius, height: 2 * underside),
        _mountBottomPaint,
      );

    // Grain marks turn with the mount, so its twist on the rope shows.
    final m = 3 * ChimeSimulation.mountIndex;
    final mx = _positions[m], my = _positions[m + 1] - config.mountThickness / 2;
    final mz = _positions[m + 2];
    final yaw = simulation.interpolatedMountYaw;
    for (var i = 0; i < 6; i++) {
      final a = yaw + i * math.pi / 3 + 0.3;
      final sn = math.sin(a), c = math.cos(a);
      projection.project(mx + 0.45 * config.mountRadius * sn, my, mz + 0.45 * config.mountRadius * c);
      final x0 = projection.x, y0 = projection.y;
      projection.project(mx + 0.8 * config.mountRadius * sn, my, mz + 0.8 * config.mountRadius * c);
      canvas.drawLine(Offset(x0, y0), Offset(projection.x, projection.y), _grainPaint);
    }
  }

  /// The eyelet each tube's string hangs from, at its attachment point on the mount.
  void _drawEyelets(Canvas canvas, double scale) {
    final r = 0.0022 * projection.pixelsPerMeter * scale;
    for (var k = 0; k < simulation.rods.length; k++) {
      final o = k * _stride;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(_rodScreen[o + 6], _rodScreen[o + 7]), width: 2 * r, height: 1.2 * r),
        _eyeletPaint,
      );
    }
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
    final ppm = projection.basePixelsPerMeter;
    final w = config.sailWidth * ppm, h = config.sailHeight * ppm;
    final top = -h / 2, bottom = h / 2, left = -w / 2, right = w / 2;
    // Billow and flutter grow with the wind: the sides bow, the hem ripples.
    final gust = simulation.wind.speed;
    final billow = (gust / 8).clamp(0.0, 1.0);
    final phase = _flutter;
    final bow = w * (0.015 + 0.05 * billow);
    final ripple = h * (0.012 + 0.045 * billow);
    final hemLeft = bottom + ripple * math.sin(phase + 1.7);
    final hemRight = bottom + ripple * math.sin(phase);
    _sailPath
      ..reset()
      ..moveTo(left, top)
      ..lineTo(right, top)
      ..quadraticBezierTo(right + bow * math.sin(phase * 0.6), 0, right, hemRight)
      ..cubicTo(w / 6, bottom + ripple * math.sin(phase + 0.6), -w / 6,
          bottom - ripple * math.sin(phase + 1.1), left, hemLeft)
      ..quadraticBezierTo(left - bow * math.sin(phase * 0.6 + 0.8), 0, left, top)
      ..close();
    _hemPath
      ..reset()
      ..moveTo(right - 2, hemRight - 3)
      ..cubicTo(w / 6, bottom - 3 + ripple * math.sin(phase + 0.6), -w / 6,
          bottom - 3 - ripple * math.sin(phase + 1.1), left + 2, hemLeft - 3);

    canvas
      ..save()
      ..translate(projection.x, projection.y)
      ..rotate(math.atan2(-(projection.x - clapperX), projection.y - clapperY))
      ..scale(projection.scale * projection.zoom)
      ..drawPath(_sailPath, _sailPaint)
      ..drawPath(_sailPath, _foldPaint)
      ..drawPath(_hemPath, _hemPaint)
      ..drawRRect(
        RRect.fromLTRBR(left - 0.06 * w, top - 0.035 * h, right + 0.06 * w, top + 0.025 * h,
            Radius.circular(0.03 * h)),
        _dowelPaint,
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
    // Widths use the base scale the shader was built for; zoom is applied on the canvas.
    final w = 2 * simulation.rods[k].spec.radius * projection.basePixelsPerMeter;
    final body = RRect.fromLTRBR(-w / 2, 0, w / 2, length, Radius.circular(w * 0.2));
    canvas
      ..save()
      ..translate(x0, y0)
      ..rotate(math.atan2(-dx, dy))
      ..scale(scale * projection.zoom, 1)
      ..drawRRect(body, _rodPaints[k])
      ..drawOval(
        Rect.fromCenter(center: Offset(0, length - w * 0.08), width: w * 0.8, height: w * 0.28),
        _holePaint,
      );

    // A soft glint that slides across the tube as the chime turns and the tube tilts.
    final facing = simulation.rods[k].ringAngle + simulation.interpolatedMountYaw - _lightAngle;
    final tilt = math.atan2(-dx, dy).clamp(-0.5, 0.5);
    final glintX = (w * (0.18 * math.sin(facing) - 0.3 * tilt)).clamp(-0.28 * w, 0.28 * w);
    canvas
      ..translate(glintX, 0)
      ..drawRRect(
        RRect.fromLTRBR(-0.2 * w, w * 0.3, 0.2 * w, length - w * 0.3, Radius.circular(w * 0.1)),
        _glintPaint,
      )
      ..translate(-glintX, 0);

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
