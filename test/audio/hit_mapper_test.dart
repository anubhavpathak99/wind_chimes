import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/audio/hit_mapper.dart';
import 'package:wind_chimes/audio/tube_bank.dart';

const layout = TubeBankLayout();

CollisionEvent hit(int rod, double impulse, {double strikePos = 0.5, double glancing = 0}) =>
    CollisionEvent()
      ..rodId = rod
      ..impulse = impulse
      ..strikePos = strikePos
      ..glancing = glancing;

({int tube, int layer, int position, int take}) decode(int sample) {
  final take = sample % layout.takes;
  var rest = sample ~/ layout.takes;
  final position = rest % layout.strikePositions.length;
  rest ~/= layout.strikePositions.length;
  return (tube: rest ~/ layout.layers, layer: rest % layout.layers, position: position, take: take);
}

void main() {
  final sim = ChimeSimulation(ChimeConfig.pentatonicAluminium());
  HitMapper mapper([int seed = 1]) =>
      HitMapper(pans: HitMapper.pansFor(sim.rods), layout: layout, random: math.Random(seed));

  double hardShare(HitMapper m, CollisionEvent Function() event) {
    var hard = 0;
    for (var i = 0; i < 400; i++) {
      if (decode(m.map(event())!.sample).layer == layout.layers - 1) hard++;
    }
    return hard / 400;
  }

  test('intensity rises with impulse from silent to full', () {
    expect(HitMapper.intensity(HitMapper.quietestImpulse / 2), 0);
    expect(HitMapper.intensity(HitMapper.loudestImpulse * 2), 1);
    var previous = 0.0;
    for (var j = 1e-3; j < HitMapper.loudestImpulse; j *= 1.5) {
      expect(HitMapper.intensity(j), greaterThan(previous));
      previous = HitMapper.intensity(j);
    }
  });

  test('taps too soft to hear play nothing', () {
    expect(mapper().map(hit(0, HitMapper.quietestImpulse / 2)), isNull);
  });

  test('hard hits play near full volume, soft ones about 30 dB down', () {
    final m = mapper();
    expect(m.map(hit(0, HitMapper.loudestImpulse))!.volume, greaterThan(0.8));
    final soft = m.map(hit(0, HitMapper.quietestImpulse * 1.01))!.volume;
    expect(20 * math.log(soft) / math.ln10, closeTo(-30, 2));
  });

  test('plays the struck tube, panned by its place on the ring', () {
    final m = mapper();
    for (final rod in sim.rods) {
      final voice = m.map(hit(rod.index, 0.005))!;
      expect(decode(voice.sample).tube, rod.index);
      expect(voice.pan.sign, math.sin(rod.ringAngle).sign);
    }
  });

  test('soft hits sound soft, hard hits mostly bright', () {
    final m = mapper();
    expect(hardShare(m, () => hit(2, 5e-4)), lessThan(0.05));
    expect(hardShare(m, () => hit(2, 1.2e-2)), greaterThan(0.8));
    final middle = hardShare(m, () => hit(2, 2.1e-3));
    expect(middle, inInclusiveRange(0.1, 0.9));
  });

  test('glancing blows sound softer', () {
    final m = mapper();
    expect(hardShare(m, () => hit(2, 4e-3, glancing: 1)),
        lessThan(hardShare(m, () => hit(2, 4e-3)) - 0.2));
  });

  test('uses the variant struck nearest the contact point', () {
    final m = mapper();
    expect(decode(m.map(hit(1, 0.005, strikePos: 0.47))!.sample).position, 0);
    expect(decode(m.map(hit(1, 0.005, strikePos: 0.61))!.sample).position, 1);
  });

  test('never plays the same sample on a tube twice running, and uses every take', () {
    final m = mapper(3);
    final random = math.Random(4);
    final last = List.filled(sim.rods.length, -1);
    final takes = <int>{};
    for (var i = 0; i < 2000; i++) {
      final rod = random.nextInt(sim.rods.length);
      final voice = m.map(hit(rod, 1e-3 + random.nextDouble() * 1e-2,
          strikePos: 0.45 + random.nextDouble() * 0.2))!;
      expect(voice.sample, isNot(last[rod]));
      last[rod] = voice.sample;
      takes.add(decode(voice.sample).take);
    }
    expect(takes, hasLength(layout.takes));
  });

  test('repeated hits vary slightly in pitch, staying in tune', () {
    final m = mapper();
    final speeds = {for (var i = 0; i < 20; i++) m.map(hit(2, 0.005))!.speed};
    expect(speeds.length, greaterThan(10));
    for (final speed in speeds) {
      expect((1200 * math.log(speed) / math.ln2).abs(), lessThanOrEqualTo(HitMapper.detuneCents));
    }
  });
}
