import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/audio/hit_mapper.dart';
import 'package:wind_chimes/audio/tube_bank.dart';
import 'package:wind_chimes/audio/voice_allocator.dart';
import 'package:wind_chimes/audio/wind_bed.dart';

import 'fake_voice_output.dart';

/// Real impacts from the simulation, through the mapper and allocator, as the app wires them.
class _Pipeline implements CollisionSink {
  _Pipeline(this.sim)
      : output = FakeVoiceOutput(),
        mapper = HitMapper(
          pans: HitMapper.pansFor(sim.rods),
          layout: const TubeBankLayout(),
          random: math.Random(1),
        ) {
    voices = VoiceAllocator(output: output, rodCount: sim.rods.length, sampleSeconds: 5);
  }

  final ChimeSimulation sim;
  final FakeVoiceOutput output;
  final HitMapper mapper;
  late final VoiceAllocator voices;
  final lastSampleOnTube = <int, int>{};
  var repeats = 0;
  var peakVoices = 0;
  var peakOnOneTube = 0;

  @override
  void onCollision(CollisionEvent event) {
    final hit = mapper.map(event);
    if (hit == null || !voices.play(hit)) return;
    if (lastSampleOnTube[hit.rod] == hit.sample) repeats++;
    lastSampleOnTube[hit.rod] = hit.sample;
  }

  void run(double seconds) {
    for (var i = 0; i < (seconds / ChimeSimulation.stepDt).round(); i++) {
      sim.step();
      sim.events.drainTo(this);
      voices.update(ChimeSimulation.stepDt, sim.isPressingRod);
      peakVoices = math.max(peakVoices, voices.activeVoices);
      for (var rod = 0; rod < sim.rods.length; rod++) {
        peakOnOneTube = math.max(peakOnOneTube, voices.voicesOn(rod));
      }
    }
  }
}

_Pipeline _pipelineAt(double windSpeed) {
  final sim = ChimeSimulation(ChimeConfig.pentatonicAluminium());
  sim.inputs
    ..windSpeed = windSpeed
    ..windGust = windSpeed * 1.5;
  sim.wind.snapToTarget(sim.inputs);
  return _Pipeline(sim);
}

void main() {
  test('five minutes of gentle breeze never repeats itself on a tube and never clicks', () {
    final p = _pipelineAt(3)..run(300);
    final samples = p.output.plays.map((play) => play.sample).toSet();

    expect(p.output.plays.length, greaterThan(150));
    expect(p.repeats, 0);
    expect(samples.length, greaterThanOrEqualTo(12));
    expect(p.peakOnOneTube, lessThanOrEqualTo(p.voices.maxVoicesPerRod));
    for (final release in p.output.releases) {
      expect(release.time.inMilliseconds, greaterThanOrEqualTo(30));
    }
  });

  test('a gale stays within the voice budget', () {
    final p = _pipelineAt(20)..run(120);
    expect(p.output.plays.length, greaterThan(200));
    expect(p.peakVoices, lessThanOrEqualTo(p.voices.maxVoices));
    expect(p.peakOnOneTube, lessThanOrEqualTo(p.voices.maxVoicesPerRod));
    for (final release in p.output.releases) {
      expect(release.time.inMilliseconds, greaterThanOrEqualTo(30));
    }
  });

  test('the wind bed is silent in calm air and swells with the wind', () {
    expect(windBedLevel(0).volume, 0);
    var previous = -1.0;
    for (var speed = 0.5; speed <= 10; speed += 0.5) {
      final level = windBedLevel(speed);
      expect(level.volume, greaterThanOrEqualTo(previous));
      expect(level.volume, lessThanOrEqualTo(0.35));
      expect(level.speed, inInclusiveRange(0.8, 1.3));
      previous = level.volume;
    }
    expect(windBedLevel(3).volume, greaterThan(0.05));
  });
}
