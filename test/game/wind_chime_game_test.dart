import 'package:chime_sim/chime_sim.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/game/wind_chime_game.dart';

void main() {
  test('a resize to the same size (a rebuild) leaves the camera alone', () {
    final game = WindChimeGame(simulation: ChimeSimulation(ChimeConfig.pentatonicAluminium()))
      ..onGameResize(Vector2(390, 844));
    final p = game.projection
      ..visibleHeight = 400
      ..zoom = 0.5
      ..panX = 0.2;
    game.onGameResize(Vector2(390, 844));
    expect(p.visibleHeight, 400);
    expect(p.zoom, 0.5);
    expect(p.panX, 0.2);

    game.onGameResize(Vector2(390, 700));
    expect(p.zoom, 1, reason: 'a real resize refits');
    expect(p.visibleHeight, closeTo(400 * 700 / 844, 1e-9), reason: 'keeping the visible share');
  });

  test('headless, the simulation advances from a timer and hears its impacts', () async {
    var frames = 0;
    final game = WindChimeGame(
      simulation: ChimeSimulation(ChimeConfig.pentatonicAluminium()),
      onFrame: (_) => frames++,
    )..runHeadless();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    game.stopHeadless();
    final time = game.simulation.time;
    expect(time, closeTo(0.3, 0.15));
    expect(frames, greaterThan(5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(game.simulation.time, time, reason: 'stopped');
    expect(game.paused, isFalse, reason: "Flame's loop is back");
  });
}
