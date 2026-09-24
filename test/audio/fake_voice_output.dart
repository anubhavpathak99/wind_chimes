import 'package:wind_chimes/audio/voice_allocator.dart';

/// Records what the allocator asks of the audio engine.
class FakeVoiceOutput implements VoiceOutput {
  final plays = <({int voice, int sample, double volume})>[];
  final fades = <({int voice, double volume, Duration time})>[];
  final releases = <({int voice, Duration time})>[];
  final playing = <int>{};
  int _next = 0;

  @override
  int play(int sample, {required double volume, required double pan, required double speed}) {
    final voice = _next++;
    plays.add((voice: voice, sample: sample, volume: volume));
    playing.add(voice);
    return voice;
  }

  @override
  void fade(int voice, double volume, Duration time) =>
      fades.add((voice: voice, volume: volume, time: time));

  @override
  void release(int voice, Duration time) {
    releases.add((voice: voice, time: time));
    playing.remove(voice);
  }
}
