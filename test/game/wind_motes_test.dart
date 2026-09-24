import 'package:chime_sim/chime_sim.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/game/render/sky.dart';
import 'package:wind_chimes/game/render/wind_motes.dart';

void main() {
  test('specks drift the way the wind blows', () {
    final inputs = SimInputs()
      ..windSpeed = 8
      ..windDirection = 270 // from the west: blows to screen right
      ..windResponseTime = 0;
    final wind = WindField(stepDt: 1 / 120)..snapToTarget(inputs);
    wind.step(inputs);
    final motes = WindMotes(wind, SkyModel(), count: 30)..onGameResize(Vector2(400, 800));
    final before = motes.meanX;
    for (var i = 0; i < 30; i++) {
      wind.step(inputs);
      motes.update(1 / 60);
    }
    expect(motes.meanX, greaterThan(before));
    expect(motes.visibility, greaterThan(0.1));
  });

  test('calm air leaves no specks', () {
    final wind = WindField(stepDt: 1 / 120);
    final motes = WindMotes(wind, SkyModel())..onGameResize(Vector2(400, 800));
    for (var i = 0; i < 120; i++) {
      motes.update(1 / 60);
    }
    expect(motes.visibility, lessThan(0.01));
  });
}
