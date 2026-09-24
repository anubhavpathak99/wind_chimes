import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/audio/hit_mapper.dart';

CollisionEvent hit(int rod, double impulse) => CollisionEvent()
  ..rodId = rod
  ..impulse = impulse;

void main() {
  final sim = ChimeSimulation(ChimeConfig.pentatonicAluminium());
  final mapper = HitMapper(pans: HitMapper.pansFor(sim.rods), random: math.Random(1));

  test('intensity rises with impulse from silent to full', () {
    expect(HitMapper.intensity(HitMapper.quietestImpulse / 2), 0);
    expect(HitMapper.intensity(HitMapper.loudestImpulse * 2), 1);
    var previous = 0.0;
    for (var j = 1e-3; j < HitMapper.loudestImpulse; j *= 1.5) {
      final s = HitMapper.intensity(j);
      expect(s, greaterThan(previous));
      previous = s;
    }
  });

  test('taps too soft to hear play nothing', () {
    expect(mapper.map(hit(0, HitMapper.quietestImpulse / 2)), isNull);
  });

  test('hard hits play near full volume, soft ones about 30 dB down', () {
    expect(mapper.map(hit(0, HitMapper.loudestImpulse))!.volume, greaterThan(0.8));
    final soft = mapper.map(hit(0, HitMapper.quietestImpulse * 1.01))!.volume;
    expect(20 * math.log(soft) / math.ln10, closeTo(-30, 2));
  });

  test('tubes on the right pan right', () {
    for (final rod in sim.rods) {
      expect(mapper.map(hit(rod.index, 0.005))!.pan.sign, math.sin(rod.ringAngle).sign);
    }
  });

  test('repeated hits vary slightly in pitch, staying in tune', () {
    final speeds = {for (var i = 0; i < 20; i++) mapper.map(hit(2, 0.005))!.speed};
    expect(speeds.length, greaterThan(10));
    for (final speed in speeds) {
      expect((1200 * math.log(speed) / math.ln2).abs(), lessThanOrEqualTo(HitMapper.detuneCents));
    }
  });
}
