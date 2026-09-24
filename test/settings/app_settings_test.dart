import 'dart:convert';

import 'package:chime_sim/chime_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/motion/motion_settings.dart';
import 'package:wind_chimes/settings/app_settings.dart';
import 'package:wind_chimes/settings/settings_controller.dart';
import 'package:wind_chimes/storage/key_value_store.dart';
import 'package:wind_chimes/wind/manual_wind.dart';
import 'package:wind_chimes/wind/wind_controller.dart';

void main() {
  const custom = AppSettings(
    mode: WindMode.manual,
    manual: ManualWind(speed: 7.5, direction: 45, gustFactor: 2),
    placement: Placement.open,
    volume: 0.4,
    ambience: 0.2,
    motion: MotionSettings(sensitivity: 1.5, tiltEnabled: false),
    units: SpeedUnit.knots,
    liveWindOffered: true,
    showStats: true,
    haptics: false,
    skyFollowsTime: false,
  );

  test('survives a round trip through JSON', () {
    final copy = AppSettings.fromJson(jsonDecode(jsonEncode(custom.toJson())));
    expect(copy.toJson(), custom.toJson());
  });

  test('unreadable or missing values keep their defaults', () {
    final s = AppSettings.fromJson({
      'mode': 'sideways',
      'volume': 'loud',
      'ambience': 7,
      'manual': {'speed': -3, 'direction': 400},
      'units': 'furlongs per fortnight',
      'someFutureSetting': true,
    });
    expect(s.mode, WindMode.live);
    expect(s.volume, 1);
    expect(s.ambience, 1, reason: 'clamped');
    expect(s.manual.speed, 0);
    expect(s.manual.direction, 0);
    expect(s.units, SpeedUnit.kilometersPerHour);
  });

  test('units default to the region', () {
    expect(SpeedUnit.forRegion('US'), SpeedUnit.milesPerHour);
    expect(SpeedUnit.forRegion('gb'), SpeedUnit.milesPerHour);
    expect(SpeedUnit.forRegion('IN'), SpeedUnit.kilometersPerHour);
    expect(SpeedUnit.forRegion(null), SpeedUnit.kilometersPerHour);
  });

  group('SettingsController', () {
    test('loads defaults when nothing is saved, or the file is corrupt', () async {
      expect((await SettingsController.load(MemoryStore(), region: 'US')).units,
          SpeedUnit.milesPerHour);
      final corrupt = MemoryStore({SettingsController.key: '{not json'});
      expect((await SettingsController.load(corrupt)).mode, WindMode.live);
    });

    test('saves once, shortly after a burst of changes, and loads them back', () async {
      final store = MemoryStore();
      final controller = SettingsController(store, const AppSettings());
      for (var v = 0.0; v <= 0.5; v += 0.05) {
        controller.update((s) => s.copyWith(volume: v));
      }
      expect(store.values, isEmpty, reason: 'not while the slider moves');
      await Future<void>.delayed(SettingsController.saveDelay + const Duration(milliseconds: 50));
      expect((await SettingsController.load(store)).volume, closeTo(0.5, 1e-9));
      await controller.dispose();
    });

    test('flush saves a pending change at once', () async {
      final store = MemoryStore();
      final controller = SettingsController(store, const AppSettings())
        ..update((s) => s.copyWith(units: SpeedUnit.knots));
      await controller.flush();
      expect((await SettingsController.load(store)).units, SpeedUnit.knots);
      await controller.dispose();
    });
  });
}
