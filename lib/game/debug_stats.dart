import 'dart:collection';

import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

typedef HitRecord = ({int rod, double impulse, double speed, double strikePos, double glancing});

@immutable
class DebugSnapshot {
  const DebugSnapshot({
    required this.fps,
    required this.stepsPerFrame,
    required this.simTime,
    required this.hits,
    required this.hitsPerSecond,
    this.clinks = 0,
    this.buildMs = 0,
    this.rasterMs = 0,
    this.worstFrameMs = 0,
    this.physicsMs = 0,
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

  /// Knocks between tubes, counted once per knock and not in [hits].
  final int clinks;

  /// Average UI-thread build and raster-thread times per frame, and the slowest frame's total,
  /// over the last publish interval, ms. From the engine's frame timings (profile and release
  /// builds report them; debug builds are much slower anyway).
  final double buildMs;
  final double rasterMs;
  final double worstFrameMs;

  /// Physics time per frame, ms.
  final double physicsMs;
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
  int _clinkReports = 0;
  int _physicsMicros = 0;
  int _timedFrames = 0;
  int _buildMicros = 0;
  int _rasterMicros = 0;
  int _worstMicros = 0;
  bool _timing = false;

  /// Starts collecting the engine's frame timings.
  void watchFrameTimings() {
    if (_timing) return;
    _timing = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _timedFrames++;
      _buildMicros += t.buildDuration.inMicroseconds;
      _rasterMicros += t.rasterDuration.inMicroseconds;
      if (t.totalSpan.inMicroseconds > _worstMicros) _worstMicros = t.totalSpan.inMicroseconds;
    }
  }

  void recordFrame(double dt, int steps, ChimeSimulation simulation, {int physicsMicros = 0}) {
    _frames++;
    _steps += steps;
    _elapsed += dt;
    _physicsMicros += physicsMicros;
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
      clinks: _clinkReports ~/ 2,
      buildMs: _timedFrames == 0 ? 0 : _buildMicros / _timedFrames / 1000,
      rasterMs: _timedFrames == 0 ? 0 : _rasterMicros / _timedFrames / 1000,
      worstFrameMs: _worstMicros / 1000,
      physicsMs: _physicsMicros / _frames / 1000,
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
    _physicsMicros = 0;
    _timedFrames = _buildMicros = _rasterMicros = _worstMicros = 0;
  }

  @override
  void onCollision(CollisionEvent event) {
    if (event.isClink) {
      _clinkReports++;
    } else {
      _hits++;
    }
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

  void dispose() {
    if (_timing) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    snapshot.dispose();
  }
}
