import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chime_sim/chime_sim.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../render/chime_projection.dart';

/// Lets a finger grab the nearest body and drag it. The simulation pulls the grabbed particle
/// toward the finger with a damped spring, so letting go mid-swing flings it.
///
/// The finger moves on a plane at the grabbed particle's depth, fixed at grab time.
class ChimeDragInput extends PositionComponent with DragCallbacks {
  ChimeDragInput(this.simulation, this.projection);

  /// How far outside a body's drawn outline a touch still grabs it, logical pixels.
  static const grabSlop = 28.0;

  final ChimeSimulation simulation;
  final ChimeProjection projection;
  final Float64List _point = Float64List(6);

  int? _pointer;
  double _grabDepth = 0;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_pointer != null) return;
    final touch = event.canvasPosition;
    final particle = _pick(touch.x, touch.y);
    if (particle < 0) return;

    _pointer = event.pointerId;
    final p = simulation.particles.position;
    projection.project(p[3 * particle], p[3 * particle + 1], p[3 * particle + 2]);
    _grabDepth = projection.depth;
    projection.unproject(touch.x, touch.y, _grabDepth);
    simulation.inputs.grab(particle, projection.worldX, projection.worldY, projection.worldZ);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _pointer) return;
    final touch = event.canvasEndPosition;
    projection.unproject(touch.x, touch.y, _grabDepth);
    simulation.inputs.moveTouch(projection.worldX, projection.worldY, projection.worldZ);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId != _pointer) return;
    _pointer = null;
    simulation.inputs.release();
  }

  /// Returns the particle to grab at canvas point ([x], [y]), or -1 if nothing is close enough.
  int _pick(double x, double y) {
    final config = simulation.config;
    final ppm = projection.pixelsPerMeter;
    final p = simulation.particles.position;
    var best = -1;
    var bestGap = grabSlop;

    void consider(int particle, double radius) {
      projection.project(p[3 * particle], p[3 * particle + 1], p[3 * particle + 2]);
      final gap = _distance(x, y, projection.x, projection.y) - radius * ppm * projection.scale;
      if (gap < bestGap) {
        bestGap = gap;
        best = particle;
      }
    }

    consider(ChimeSimulation.clapperIndex, config.clapperRadius);
    consider(ChimeSimulation.sailIndex, config.sailWidth / 2);
    consider(ChimeSimulation.mountIndex, config.mountRadius);

    for (final rod in simulation.rods) {
      rod.top.eval(p, _point);
      rod.bottom.eval(p, _point, 3);
      projection.project(_point[0], _point[1], _point[2]);
      final x0 = projection.x, y0 = projection.y;
      projection.project(_point[3], _point[4], _point[5]);
      final sx = projection.x - x0, sy = projection.y - y0;
      final lengthSq = sx * sx + sy * sy;
      final t = lengthSq > 0 ? (((x - x0) * sx + (y - y0) * sy) / lengthSq).clamp(0.0, 1.0) : 0.0;
      final gap = _distance(x, y, x0 + t * sx, y0 + t * sy) -
          rod.spec.radius * ppm * projection.scale;
      if (gap < bestGap) {
        bestGap = gap;
        best = t < 0.5 ? rod.upper : rod.lower;
      }
    }
    return best;
  }

  static double _distance(double ax, double ay, double bx, double by) {
    final dx = ax - bx, dy = ay - by;
    return math.sqrt(dx * dx + dy * dy);
  }
}
