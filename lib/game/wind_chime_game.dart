import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:chime_sim/chime_sim.dart';
import 'package:flame/game.dart';

import 'debug_stats.dart';
import 'input/chime_drag_input.dart';
import 'render/chime_projection.dart';
import 'render/chime_renderer.dart';
import 'render/sky_background.dart';

/// Runs the simulation from Flame's loop and draws it. Owns no physics: it advances the
/// simulation by each frame's time, then forwards the frame's impacts to the renderer and to
/// [collisionSinks] (audio, debug stats). [beforePhysics] runs first each frame, so inputs such as
/// phone motion land in this frame's steps; [onFrame] runs once the frame's physics is done.
class WindChimeGame extends FlameGame implements CollisionSink {
  WindChimeGame({
    required this.simulation,
    this.collisionSinks = const [],
    this.beforePhysics,
    this.onFrame,
    this.stats,
  });

  final ChimeSimulation simulation;
  final List<CollisionSink> collisionSinks;
  final void Function(double dt)? beforePhysics;
  final void Function(double dt)? onFrame;
  final DebugStats? stats;
  final ChimeProjection projection = ChimeProjection();
  late final ChimeRenderer _renderer = ChimeRenderer(simulation, projection);
  final Float64List _end = Float64List(3);

  /// Room kept around the chime's outermost particles when framing it, meters: enough for the
  /// sail's corners when it flies sideways.
  static const _frameMargin = 0.1;

  @override
  Color backgroundColor() => SkyBackground.top;

  @override
  Future<void> onLoad() async {
    await addAll([SkyBackground(), _renderer, ChimeDragInput(simulation, projection)]);
  }

  @override
  void onGameResize(Vector2 size) {
    final config = simulation.config;
    projection.fit(
      width: size.x,
      height: size.y,
      chimeBottom: -(config.ropeLength + config.sailCenterDrop + config.sailHeight / 2),
      halfWidth: config.mountRadius,
    );
    super.onGameResize(size);
  }

  @override
  void update(double dt) {
    beforePhysics?.call(dt);
    final steps = simulation.advance(dt);
    simulation.events.drainTo(this);
    // Hold the camera still while a finger drags, so the world doesn't slide under it.
    if (!simulation.inputs.isTouching) _frameChime(dt);
    onFrame?.call(dt);
    stats?.recordFrame(dt, steps, simulation);
    super.update(dt);
  }

  void _frameChime(double dt) {
    final p = simulation.particles.position;
    var minX = double.infinity, maxX = double.negativeInfinity, minY = double.infinity;
    void include(double x, double y) {
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
    }

    for (var i = 0; i < simulation.particles.count; i++) {
      include(p[3 * i], p[3 * i + 1]);
    }
    for (final rod in simulation.rods) {
      rod.bottom.eval(p, _end);
      include(_end[0], _end[1]);
    }
    projection.follow(
      minX: minX - _frameMargin,
      maxX: maxX + _frameMargin,
      minY: minY - simulation.config.sailHeight / 2,
      dt: dt,
    );
  }

  @override
  void onCollision(CollisionEvent event) {
    _renderer.strike(event.rodId, event.impulse);
    for (final sink in collisionSinks) {
      sink.onCollision(event);
    }
  }
}
