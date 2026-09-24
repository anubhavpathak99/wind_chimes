import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'hit_mapper.dart';
import 'tube_tone.dart';

/// Plays a tone for every impact. Phase 2 placeholder: one synthesized strike per tube at the
/// tube's own pitch, varied by [HitMapper]. Phase 3 replaces the tones with sample layers and adds
/// a voice allocator, reverb and wind ambience.
///
/// Never throws: if the audio engine can't start, [status] says why and impacts are ignored.
class ChimeAudio implements CollisionSink {
  ChimeAudio(List<RodBody> rods, {HitMapper? mapper})
      : _frequencies = [for (final rod in rods) rod.spec.frequency],
        _mapper = mapper ?? HitMapper(pans: HitMapper.pansFor(rods));

  final List<double> _frequencies;
  final HitMapper _mapper;
  final ValueNotifier<String> status = ValueNotifier('off');
  List<AudioSource> _tones = const [];
  bool _starting = false;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_starting || _running) return;
    _starting = true;
    status.value = 'starting…';
    try {
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) await soloud.init(bufferSize: 1024);
      soloud.setMaxActiveVoiceCount(32);
      final wavs = await compute(_synthesizeAll, _frequencies);
      _tones = [
        for (var k = 0; k < wavs.length; k++) await soloud.loadMem('tube_$k.wav', wavs[k]),
      ];
      _running = true;
      status.value = 'on · placeholder tones';
    } catch (error) {
      status.value = 'unavailable: $error';
    } finally {
      _starting = false;
    }
  }

  @override
  void onCollision(CollisionEvent event) {
    if (!_running) return;
    final voice = _mapper.map(event);
    if (voice == null) return;
    SoLoud.instance.play(
      _tones[event.rodId],
      volume: voice.volume,
      pan: voice.pan,
      scale: voice.speed,
    );
  }

  Future<void> dispose() async {
    if (_running) {
      _running = false;
      await SoLoud.instance.deinitAsync();
    }
    status.dispose();
  }
}

List<Uint8List> _synthesizeAll(List<double> frequencies) => [
      for (var k = 0; k < frequencies.length; k++) synthesizeTubeStrike(frequencies[k], seed: k),
    ];
