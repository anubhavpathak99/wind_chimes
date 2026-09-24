import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';
import 'package:test/test.dart';

void main() {
  group('tubeLengthForFrequency', () {
    double aluminium(double hz) => tubeLengthForFrequency(hz,
        outerRadius: 0.009, wallThickness: 0.001, youngsModulus: 69e9, density: 2700);

    test('an 18 mm aluminium tube sounds C5 at about 45 cm', () {
      expect(aluminium(523.25), closeTo(0.455, 0.01));
    });

    test('an octave up is 1/√2 the length', () {
      expect(aluminium(880) / aluminium(440), closeTo(1 / math.sqrt(2), 1e-12));
    });
  });

  group('pentatonicAluminium', () {
    final config = ChimeConfig.pentatonicAluminium();

    test('has five tubes, higher notes on shorter tubes', () {
      expect(config.rods, hasLength(5));
      for (var i = 1; i < config.rods.length; i++) {
        expect(config.rods[i].frequency, greaterThan(config.rods[i - 1].frequency));
        expect(config.rods[i].length, lessThan(config.rods[i - 1].length));
      }
    });

    test('clapper meets the shortest tube 60% down, with clearance at rest', () {
      final shortest = config.rods.length - 1;
      expect(config.restStrikePosition(shortest), closeTo(0.6, 1e-9));
      for (var k = 0; k < config.rods.length; k++) {
        expect(config.gapToRod(k), greaterThan(0.01));
      }
    });

    test('clapper is too wide to slip between neighbouring tubes', () {
      expect(2 * config.clapperRadius, greaterThan(config.openingBetweenRods + 0.005));
    });

    test('sail hangs clear below the longest tube', () {
      final longest = config.rods.first;
      final sailTop = config.sailCenterDrop - config.sailHeight / 2;
      expect(sailTop, greaterThan(longest.stringLength + longest.length));
    });
  });
}
