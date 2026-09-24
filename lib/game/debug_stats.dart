import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/foundation.dart';

typedef HitRecord = ({int rod, double impulse, double speed, double strikePos, double glancing});

@immutable
class DebugSnapshot {
  const DebugSnapshot({
    required this.fps,
    required this.stepsPerFrame,
    required this.simTime,
    required this.hits,
    required this.dropped,
    required this.recoveries,
    required this.recent,
  });

  static const empty = DebugSnapshot(
    fps: 0,
    stepsPerFrame: 0,
    simTime: 0,
    hits: 0,
    dropped: 0,
    recoveries: 0,
    recent: [],
  );

  final double fps;
  final double stepsPerFrame;
  final double simTime;
  final int hits;
  final int dropped;
  final int recoveries;

  /// Newest first.
  final List<HitRecord> recent;
}

/// Frame timing and impacts, published to the UI a few times a second rather than every frame.
class DebugStats implements CollisionSink {
  static const _publishInterval = 0.25;
  static const _recentCount = 5;

  final ValueNotifier<DebugSnapshot> snapshot = ValueNotifier(DebugSnapshot.empty);
  final List<HitRecord> _recent = [];
  int _frames = 0;
  int _steps = 0;
  double _elapsed = 0;
  int _hits = 0;

  void recordFrame(double dt, int steps, ChimeSimulation simulation) {
    _frames++;
    _steps += steps;
    _elapsed += dt;
    if (_elapsed < _publishInterval) return;
    snapshot.value = DebugSnapshot(
      fps: _frames / _elapsed,
      stepsPerFrame: _steps / _frames,
      simTime: simulation.time,
      hits: _hits,
      dropped: simulation.events.dropped,
      recoveries: simulation.recoveryCount,
      recent: List.unmodifiable(_recent),
    );
    _frames = 0;
    _steps = 0;
    _elapsed = 0;
  }

  @override
  void onCollision(CollisionEvent event) {
    _hits++;
    _recent.insert(0, (
      rod: event.rodId,
      impulse: event.impulse,
      speed: event.normalSpeed,
      strikePos: event.strikePos,
      glancing: event.glancing,
    ));
    if (_recent.length > _recentCount) _recent.removeLast();
  }

  void dispose() => snapshot.dispose();
}
