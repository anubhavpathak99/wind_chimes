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
/// [collisionSink] (the debug stats now, the audio engine from Phase 2).
class WindChimeGame extends FlameGame implements CollisionSink {
  WindChimeGame({required this.simulation, this.collisionSink, this.stats});

  final ChimeSimulation simulation;
  final CollisionSink? collisionSink;
  final DebugStats? stats;
  final ChimeProjection projection = ChimeProjection();
  late final ChimeRenderer _renderer = ChimeRenderer(simulation, projection);

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
    final steps = simulation.advance(dt);
    simulation.events.drainTo(this);
    stats?.recordFrame(dt, steps, simulation);
    super.update(dt);
  }

  @override
  void onCollision(CollisionEvent event) {
    _renderer.strike(event.rodId, event.impulse);
    collisionSink?.onCollision(event);
  }
}
