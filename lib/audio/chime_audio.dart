import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_session_setup.dart';
import 'hit_mapper.dart';
import 'tube_bank.dart';
import 'voice_allocator.dart';
import 'wind_bed.dart';

/// The chime's sound: a sample bank synthesized from the tubes' physics, voices chosen by
/// [HitMapper] and managed by [VoiceAllocator], a wind ambience that follows the live wind, a
/// shared reverb and a limiter.
///
/// Never throws: if the engine can't start, [status] says why and impacts are ignored.
class ChimeAudio implements CollisionSink, VoiceOutput {
  ChimeAudio(List<RodBody> rods, {this.layout = const TubeBankLayout()})
      : _frequencies = [for (final rod in rods) rod.spec.frequency],
        _mapper = HitMapper(pans: HitMapper.pansFor(rods), layout: layout) {
    _voices = VoiceAllocator(
      output: this,
      rodCount: rods.length,
      sampleSeconds: layout.seconds,
    );
  }

  static const reverbRoomSize = 0.6;
  static const reverbDamp = 0.5;
  static const reverbWet = 0.25;
  static const _bedInterval = 0.05;
  static const _statusInterval = 0.5;
  static const _suspendFade = Duration(milliseconds: 250);
  static const _resumeFade = Duration(milliseconds: 800);

  final TubeBankLayout layout;
  final List<double> _frequencies;
  final HitMapper _mapper;
  late final VoiceAllocator _voices;
  final ValueNotifier<String> status = ValueNotifier('off');

  List<AudioSource?> _samples = const [];
  SoundHandle? _windBed;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  bool _starting = false;
  bool _running = false;
  bool _suspended = false;
  double _bedClock = 0;
  double _statusClock = 0;
  double _volume = 1;
  double _ambience = 1;

  bool get isRunning => _running;

  /// Master volume, 0–1 on a perceptual scale: the gain is its square.
  double get volume => _volume;
  set volume(double value) {
    _volume = value.clamp(0.0, 1.0);
    if (_running && !_suspended) _guard(() => SoLoud.instance.setGlobalVolume(_gain));
  }

  /// Level of the wind ambience relative to its default, 0–1.
  double get ambience => _ambience;
  set ambience(double value) => _ambience = value.clamp(0.0, 1.0);

  double get _gain => _volume * _volume;

  Future<void> start() async {
    if (_starting || _running) return;
    _starting = true;
    status.value = 'starting…';
    final clock = Stopwatch()..start();
    try {
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) await soloud.init(bufferSize: 1024);
      soloud.setGlobalVolume(_gain);
      // Headroom above the allocator's cap for the wind bed.
      soloud.setMaxActiveVoiceCount(_voices.maxVoices + 4);
      if (!kIsWeb) {
        _interruptions = await configureAudioSession(onInterrupted: suspend, onResumed: resume);
      }

      // Sound starts as soon as each tube has one sample; the rest follow in the background.
      status.value = 'synthesizing…';
      final first = [for (var t = 0; t < _frequencies.length; t++) layout.firstSampleOf(t)];
      final bank = await compute(
        buildTubeBank,
        (frequencies: _frequencies, layout: layout, only: first, wind: true),
      );
      _samples = List.filled(_frequencies.length * layout.samplesPerTube, null);
      for (final sample in bank.tubes.entries) {
        _samples[sample.key] = await soloud.loadMem('tube_${sample.key}.wav', sample.value);
      }
      final wind = await soloud.loadMem('wind.wav', bank.wind!);

      // Reverb first; the limiter last, so it catches everything.
      final reverb = soloud.filters.freeverbFilter..activate();
      reverb.roomSize.value = reverbRoomSize;
      reverb.damp.value = reverbDamp;
      reverb.wet.value = reverbWet;
      final limiter = soloud.filters.limiterFilter..activate();
      limiter.threshold.value = -3;
      limiter.outputCeiling.value = -1;

      _windBed = soloud.play(wind, volume: 0, looping: true);
      _running = true;
      status.value = 'on';
      if (!kReleaseMode) debugPrint('ChimeAudio: ready in ${clock.elapsedMilliseconds} ms');
      unawaited(_completeBank(first, clock));
    } catch (error) {
      status.value = 'unavailable: $error';
    } finally {
      _starting = false;
    }
  }

  /// Synthesizes and loads the rest of the bank once sound has started. Until a sample arrives,
  /// its tube's first sample plays in its place.
  Future<void> _completeBank(List<int> loaded, Stopwatch clock) async {
    try {
      final rest = await compute(buildTubeBank, (
        frequencies: _frequencies,
        layout: layout,
        only: [for (var i = 0; i < _samples.length; i++) if (!loaded.contains(i)) i],
        wind: false,
      ));
      for (final sample in rest.tubes.entries) {
        if (!_running) return;
        _samples[sample.key] = await SoLoud.instance.loadMem('tube_${sample.key}.wav', sample.value);
      }
      if (!kReleaseMode) debugPrint('ChimeAudio: full bank in ${clock.elapsedMilliseconds} ms');
    } catch (_) {
      // The first samples keep standing in for the rest.
    }
  }

  /// Per frame: voice lifetimes, contact damping and the wind bed. [windSpeed] is the wind at the
  /// chime right now, m/s; [isPressing] says whether the clapper is pressing on a tube.
  void update(double dt, {required double windSpeed, required bool Function(int rod) isPressing}) {
    if (!_running || _suspended) return;
    _voices.update(dt, isPressing);

    _bedClock += dt;
    final bed = _windBed;
    if (_bedClock >= _bedInterval && bed != null) {
      _bedClock = 0;
      final level = windBedLevel(windSpeed);
      _guard(() {
        SoLoud.instance
          ..fadeVolume(bed, level.volume * _ambience, const Duration(milliseconds: 80))
          ..setRelativePlaySpeed(bed, level.speed);
      });
    }

    _statusClock += dt;
    if (_statusClock >= _statusInterval) {
      _statusClock = 0;
      final dropped = _voices.dropped > 0 ? ' · ${_voices.dropped} soft hits skipped' : '';
      status.value = 'on · ${_voices.activeVoices} voices$dropped';
    }
  }

  @override
  void onCollision(CollisionEvent event) {
    if (!_running || _suspended) return;
    final hit = _mapper.map(event);
    if (hit != null) _voices.play(hit);
  }

  /// Fades out and stops the audio device, for the app going to the background or an
  /// interruption. Loaded sounds and playing voices are kept.
  Future<void> suspend() async {
    if (!_running || _suspended) return;
    _suspended = true;
    status.value = 'paused';
    SoLoud.instance.fadeGlobalVolume(0, _suspendFade);
    await Future<void>.delayed(_suspendFade + const Duration(milliseconds: 50));
    if (_suspended && !kIsWeb) await SoLoud.instance.stopAudioDevice();
  }

  Future<void> resume() async {
    if (!_running || !_suspended) return;
    _suspended = false;
    if (!kIsWeb) await SoLoud.instance.startAudioDevice();
    SoLoud.instance.fadeGlobalVolume(_gain, _resumeFade);
    status.value = 'on';
  }

  Future<void> dispose() async {
    await _interruptions?.cancel();
    if (_running) {
      _running = false;
      await SoLoud.instance.deinitAsync();
    }
    status.dispose();
  }

  @override
  int play(int sample, {required double volume, required double pan, required double speed}) {
    try {
      final source = _samples[sample] ?? _samples[layout.firstSampleOf(layout.tubeOf(sample))];
      if (source == null) return -1;
      return SoLoud.instance.play(source, volume: volume, pan: pan, scale: speed).id;
    } catch (_) {
      return -1;
    }
  }

  @override
  void fade(int voice, double volume, Duration time) =>
      _guard(() => SoLoud.instance.fadeVolume(SoundHandle(voice), volume, time));

  @override
  void release(int voice, Duration time) => _guard(() {
        final handle = SoundHandle(voice);
        SoLoud.instance
          ..fadeVolume(handle, 0, time)
          ..scheduleStop(handle, time);
      });

  /// A voice can end on its own just before we reach it; that is not an error.
  static void _guard(void Function() action) {
    try {
      action();
    } catch (_) {}
  }
}
