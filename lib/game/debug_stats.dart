import 'dart:collection';

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
    required this.hitsPerSecond,
    required this.dropped,
    required this.recoveries,
    required this.windNow,
    required this.windMean,
    required this.gust,
    required this.recent,
  });

  static const empty = DebugSnapshot(
    fps: 0,
    stepsPerFrame: 0,
    simTime: 0,
    hits: 0,
    hitsPerSecond: 0,
    dropped: 0,
    recoveries: 0,
    windNow: 0,
    windMean: 0,
    gust: 0,
    recent: [],
  );

  final double fps;
  final double stepsPerFrame;
  final double simTime;
  final int hits;

  /// Over the last [DebugStats.rateWindow] seconds of simulation time.
  final double hitsPerSecond;
  final int dropped;
  final int recoveries;

  /// Wind at the chime right now and its eased mean, m/s, and the gust part of [windNow].
  final double windNow;
  final double windMean;
  final double gust;

  /// Newest first.
  final List<HitRecord> recent;
}

/// Frame timing, wind and impacts, published to the UI a few times a second rather than every
/// frame.
class DebugStats implements CollisionSink {
  static const _publishInterval = 0.25;
  static const _recentCount = 4;
  static const rateWindow = 10.0;

  final ValueNotifier<DebugSnapshot> snapshot = ValueNotifier(DebugSnapshot.empty);
  final List<HitRecord> _recent = [];
  final Queue<double> _hitTimes = Queue();
  int _frames = 0;
  int _steps = 0;
  double _elapsed = 0;
  int _hits = 0;

  void recordFrame(double dt, int steps, ChimeSimulation simulation) {
    _frames++;
    _steps += steps;
    _elapsed += dt;
    if (_elapsed < _publishInterval) return;
    while (_hitTimes.isNotEmpty && _hitTimes.first < simulation.time - rateWindow) {
      _hitTimes.removeFirst();
    }
    final wind = simulation.wind;
    snapshot.value = DebugSnapshot(
      fps: _frames / _elapsed,
      stepsPerFrame: _steps / _frames,
      simTime: simulation.time,
      hits: _hits,
      hitsPerSecond: _hitTimes.length / rateWindow,
      dropped: simulation.events.dropped,
      recoveries: simulation.recoveryCount,
      windNow: wind.speed,
      windMean: wind.meanSpeed,
      gust: wind.gust,
      recent: List.unmodifiable(_recent),
    );
    _frames = 0;
    _steps = 0;
    _elapsed = 0;
  }

  @override
  void onCollision(CollisionEvent event) {
    _hits++;
    _hitTimes.addLast(event.simTime);
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
