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

  List<AudioSource> _samples = const [];
  SoundHandle? _windBed;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  bool _starting = false;
  bool _running = false;
  bool _suspended = false;
  double _bedClock = 0;
  double _statusClock = 0;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_starting || _running) return;
    _starting = true;
    status.value = 'starting…';
    try {
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) await soloud.init(bufferSize: 1024);
      // Headroom above the allocator's cap for the wind bed.
      soloud.setMaxActiveVoiceCount(_voices.maxVoices + 4);
      if (!kIsWeb) {
        _interruptions = await configureAudioSession(onInterrupted: suspend, onResumed: resume);
      }

      status.value = 'synthesizing…';
      final bank = await compute(buildTubeBank, (frequencies: _frequencies, layout: layout));
      _samples = [
        for (var i = 0; i < bank.tubes.length; i++) await soloud.loadMem('tube_$i.wav', bank.tubes[i]),
      ];
      final wind = await soloud.loadMem('wind.wav', bank.wind);

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
    } catch (error) {
      status.value = 'unavailable: $error';
    } finally {
      _starting = false;
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
          ..fadeVolume(bed, level.volume, const Duration(milliseconds: 80))
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
    SoLoud.instance.fadeGlobalVolume(1, _resumeFade);
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
      return SoLoud.instance.play(_samples[sample], volume: volume, pan: pan, scale: speed).id;
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
