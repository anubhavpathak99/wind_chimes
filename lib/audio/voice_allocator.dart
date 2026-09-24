import 'dart:math' as math;
import 'dart:typed_data';

import 'hit_mapper.dart';

/// Where voices actually sound. [ChimeAudio] implements it with SoLoud; tests use a fake.
abstract interface class VoiceOutput {
  /// Starts [sample]. Returns a voice id, or -1 if it didn't start.
  int play(int sample, {required double volume, required double pan, required double speed});

  /// Ramps a playing voice's volume to [volume].
  void fade(int voice, double volume, Duration time);

  /// Ramps a voice to silence, then stops it. Voices are never cut: that would click.
  void release(int voice, Duration time);
}

/// Decides which voices play and which make room.
///
/// - A tube rings at most [maxVoicesPerRod] times at once; a new strike on a busy tube fades out
///   its oldest ring. The whole chime is capped at [maxVoices], stealing the oldest voice.
/// - In a storm (more than [busyHitsPerSecond] hits in the last second) soft hits are dropped and
///   the rest are turned down a little, so it stays musical.
/// - A clapper resting against a tube damps it: after [dampAfter] of contact, that tube's voices
///   fade to [dampedLevel].
///
/// Voice lifetimes come from the sample length and playback speed, so nothing is polled from the
/// audio engine. Storage is fixed-size; playing a voice doesn't allocate.
class VoiceAllocator {
  VoiceAllocator({
    required this.output,
    required this.rodCount,
    required this.sampleSeconds,
    this.maxVoices = 24,
    this.maxVoicesPerRod = 3,
  })  : _voice = Int32List(maxVoices)..fillRange(0, maxVoices, -1),
        _rod = Int32List(maxVoices),
        _start = Float64List(maxVoices),
        _end = Float64List(maxVoices),
        _volume = Float64List(maxVoices),
        _damped = List.filled(maxVoices, false),
        _contact = Float64List(rodCount),
        _hitTimes = Float64List(_hitHistory)..fillRange(0, _hitHistory, double.negativeInfinity);

  static const stealFade = Duration(milliseconds: 60);
  static const busyHitsPerSecond = 10;
  static const busyQuietestIntensity = 0.2;

  /// At most this many dB off each hit in a storm.
  static const busyMaxCutDb = 6.0;
  static const dampAfter = 0.1;
  static const dampedLevel = 0.35;
  static const dampFade = Duration(milliseconds: 400);
  static const _hitHistory = 32;

  final VoiceOutput output;
  final int rodCount;

  /// Length of every sample at normal speed, s.
  final double sampleSeconds;
  final int maxVoices;
  final int maxVoicesPerRod;

  final Int32List _voice; // -1 = free slot
  final Int32List _rod;
  final Float64List _start;
  final Float64List _end;
  final Float64List _volume;
  final List<bool> _damped;
  final Float64List _contact;
  final Float64List _hitTimes;
  int _hitHead = 0;
  double _time = 0;

  /// Hits dropped because the chime was too busy for them.
  int dropped = 0;

  int get activeVoices {
    var count = 0;
    for (final v in _voice) {
      if (v >= 0) count++;
    }
    return count;
  }

  int voicesOn(int rod) {
    var count = 0;
    for (var i = 0; i < maxVoices; i++) {
      if (_voice[i] >= 0 && _rod[i] == rod) count++;
    }
    return count;
  }

  void update(double dt, bool Function(int rod) isPressing) {
    _time += dt;
    for (var i = 0; i < maxVoices; i++) {
      if (_voice[i] >= 0 && _time >= _end[i]) _voice[i] = -1;
    }
    for (var rod = 0; rod < rodCount; rod++) {
      if (!isPressing(rod)) {
        _contact[rod] = 0;
        continue;
      }
      final before = _contact[rod];
      _contact[rod] += dt;
      if (before < dampAfter && _contact[rod] >= dampAfter) _damp(rod);
    }
  }

  /// Plays [hit] unless the chime is too busy for so soft a hit. Returns whether it played.
  bool play(HitVoice hit) {
    final busy = _hitsInLastSecond();
    _hitTimes[_hitHead] = _time;
    _hitHead = (_hitHead + 1) % _hitHistory;

    var volume = hit.volume;
    if (busy >= busyHitsPerSecond) {
      if (hit.intensity < busyQuietestIntensity) {
        dropped++;
        return false;
      }
      final cutDb = math.min(busyMaxCutDb, (busy - busyHitsPerSecond + 1).toDouble());
      volume *= math.pow(10, -cutDb / 20);
    }

    while (voicesOn(hit.rod) >= maxVoicesPerRod) {
      _releaseOldest(rod: hit.rod);
    }
    var slot = _voice.indexOf(-1);
    if (slot < 0) {
      _releaseOldest();
      slot = _voice.indexOf(-1);
    }

    final id = output.play(hit.sample, volume: volume, pan: hit.pan, speed: hit.speed);
    if (id < 0) return false;
    _voice[slot] = id;
    _rod[slot] = hit.rod;
    _start[slot] = _time;
    _end[slot] = _time + sampleSeconds / hit.speed;
    _volume[slot] = volume;
    _damped[slot] = false;
    return true;
  }

  int _hitsInLastSecond() {
    var count = 0;
    for (final t in _hitTimes) {
      if (t > _time - 1) count++;
    }
    return count;
  }

  /// Releases the oldest voice, on [rod] if given.
  void _releaseOldest({int? rod}) {
    var oldest = -1;
    for (var i = 0; i < maxVoices; i++) {
      if (_voice[i] < 0 || (rod != null && _rod[i] != rod)) continue;
      if (oldest < 0 || _start[i] < _start[oldest]) oldest = i;
    }
    if (oldest < 0) return;
    output.release(_voice[oldest], stealFade);
    _voice[oldest] = -1;
  }

  void _damp(int rod) {
    for (var i = 0; i < maxVoices; i++) {
      if (_voice[i] < 0 || _rod[i] != rod || _damped[i]) continue;
      _damped[i] = true;
      output.fade(_voice[i], _volume[i] * dampedLevel, dampFade);
    }
  }
}
