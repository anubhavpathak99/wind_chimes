import 'package:chime_sim/chime_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/haptics/chime_haptics.dart';

CollisionEvent hit(double impulse) => CollisionEvent()..impulse = impulse;

void main() {
  late List<HapticStrength> taps;
  late ChimeHaptics haptics;

  setUp(() {
    taps = [];
    haptics = ChimeHaptics(output: taps.add);
  });

  test('the wind alone never buzzes the phone', () {
    haptics
      ..update(1 / 60, playing: false)
      ..onCollision(hit(5e-3));
    expect(taps, isEmpty);
  });

  test('strikes are felt while playing, harder ones harder', () {
    haptics
      ..update(0.1, playing: true)
      ..onCollision(hit(5e-4))
      ..update(0.1, playing: true)
      ..onCollision(hit(3e-3))
      ..update(0.1, playing: true)
      ..onCollision(hit(1.5e-2));
    expect(taps, [HapticStrength.light, HapticStrength.medium, HapticStrength.heavy]);
  });

  test("a fling's hits after letting go are felt, for a moment", () {
    haptics
      ..update(0.1, playing: true)
      ..update(0.5, playing: false)
      ..onCollision(hit(3e-3));
    expect(taps, hasLength(1));
    haptics
      ..update(1.0, playing: false)
      ..onCollision(hit(3e-3));
    expect(taps, hasLength(1));
  });

  test('a flurry becomes separate taps, not a buzz, and can be switched off', () {
    haptics.update(0.1, playing: true);
    for (var i = 0; i < 10; i++) {
      haptics
        ..update(0.01, playing: true)
        ..onCollision(hit(3e-3));
    }
    expect(taps.length, lessThanOrEqualTo(2));
    taps.clear();
    haptics
      ..enabled = false
      ..update(0.2, playing: true)
      ..onCollision(hit(3e-3));
    expect(taps, isEmpty);
  });
}
