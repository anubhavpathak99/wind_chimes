import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/audio/hit_mapper.dart';
import 'package:wind_chimes/audio/voice_allocator.dart';

import 'fake_voice_output.dart';

HitVoice voice(int rod, {double volume = 0.5, double intensity = 0.5, double speed = 1}) => (
      rod: rod,
      sample: rod * 10,
      volume: volume,
      pan: 0,
      speed: speed,
      intensity: intensity,
    );

bool nothingTouching(int rod) => false;

void main() {
  late FakeVoiceOutput output;
  VoiceAllocator allocator({int maxVoices = 24}) {
    output = FakeVoiceOutput();
    return VoiceAllocator(output: output, rodCount: 5, sampleSeconds: 5, maxVoices: maxVoices);
  }

  test('a tube rings at most three times at once; the oldest ring fades out', () {
    final voices = allocator();
    for (var i = 0; i < 4; i++) {
      voices.play(voice(0));
      voices.update(0.2, nothingTouching);
    }
    expect(voices.voicesOn(0), 3);
    expect(output.releases.single.voice, output.plays.first.voice);
    expect(output.releases.single.time, VoiceAllocator.stealFade);
  });

  test('the whole chime is capped, stealing the oldest voice', () {
    final voices = allocator(maxVoices: 6);
    for (var i = 0; i < 8; i++) {
      voices.play(voice(i % 5));
      voices.update(0.2, nothingTouching);
    }
    expect(voices.activeVoices, 6);
    expect(output.releases.map((r) => r.voice), [0, 1]);
  });

  test('voices end when their sample does, without being stopped', () {
    final voices = allocator();
    voices.play(voice(0, speed: 1.0));
    voices.play(voice(1, speed: 1.01));
    voices.update(4.9, nothingTouching);
    expect(voices.activeVoices, 2);
    voices.update(0.2, nothingTouching);
    expect(voices.activeVoices, 0);
    expect(output.releases, isEmpty);
  });

  test('in a storm, soft hits are skipped and the rest turned down', () {
    final voices = allocator();
    for (var i = 0; i < VoiceAllocator.busyHitsPerSecond; i++) {
      expect(voices.play(voice(i % 5, intensity: 0.1)), isTrue);
      voices.update(0.05, nothingTouching);
    }
    expect(voices.play(voice(0, intensity: 0.1)), isFalse);
    expect(voices.dropped, 1);
    expect(voices.play(voice(1, volume: 0.5, intensity: 0.6)), isTrue);
    expect(output.plays.last.volume, lessThan(0.5));
    expect(output.plays.last.volume, greaterThanOrEqualTo(0.5 * 0.5));

    voices.update(2, nothingTouching);
    expect(voices.play(voice(2, intensity: 0.1)), isTrue);
  });

  test('a clapper resting on a ringing tube damps it, once per contact', () {
    final voices = allocator();
    voices.play(voice(1, volume: 0.8));
    voices.play(voice(2, volume: 0.8));
    bool touchingTube1(int rod) => rod == 1;

    voices.update(0.05, touchingTube1);
    expect(output.fades, isEmpty);
    voices.update(0.06, touchingTube1);
    expect(output.fades.single.voice, output.plays.first.voice);
    expect(output.fades.single.volume, closeTo(0.8 * VoiceAllocator.dampedLevel, 1e-12));
    voices.update(0.5, touchingTube1);
    expect(output.fades, hasLength(1));

    voices.update(0.1, nothingTouching);
    voices.play(voice(1, volume: 0.6));
    voices.update(0.15, touchingTube1);
    expect(output.fades, hasLength(2));
    expect(output.fades.last.voice, output.plays.last.voice);
  });
}
