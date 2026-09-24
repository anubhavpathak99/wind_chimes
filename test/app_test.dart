import 'dart:convert';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/app/app.dart';
import 'package:wind_chimes/game/wind_chime_game.dart';
import 'package:wind_chimes/location/location.dart';
import 'package:wind_chimes/settings/app_settings.dart';
import 'package:wind_chimes/settings/settings_controller.dart';
import 'package:wind_chimes/storage/key_value_store.dart';
import 'package:wind_chimes/ui/controls/controls_sheet.dart';
import 'package:wind_chimes/wind/manual_wind.dart';
import 'package:wind_chimes/wind/wind_controller.dart';

import 'wind/fake_wind_services.dart';

void main() {
  late MemoryStore store;
  late FakeWeather weather;
  late FakeLocation location;

  setUp(() {
    store = MemoryStore();
    weather = FakeWeather();
    location = FakeLocation();
  });

  /// Launches the app the way `main` does: settings loaded first, on a phone-sized screen.
  Future<void> launch(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final settings = await tester.runAsync(() => SettingsController.load(store));
    await tester.pumpWidget(WindChimesApp(
      audioEnabled: false,
      settings: settings!,
      services: fakeServices(weather: weather, location: location, store: store),
    ));
    // Frames enough for the chip to finish growing to fit the offer.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The game schedules a frame every tick, so nothing ever "settles": step frames instead.
  Future<void> frames(WidgetTester tester, [Duration total = const Duration(milliseconds: 500)]) async {
    for (var t = Duration.zero; t < total; t += const Duration(milliseconds: 50)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  double opacityOf(WidgetTester tester, Finder finder) => tester
      .widget<AnimatedOpacity>(find.ancestor(of: finder, matching: find.byType(AnimatedOpacity)))
      .opacity;

  testWidgets('opens on the chime and the ambient breeze, offering live wind without asking yet',
      (tester) async {
    await launch(tester);
    expect(find.byType(GameWidget<WindChimeGame>), findsOneWidget);
    expect(find.textContaining('km/h'), findsOneWidget);
    expect(find.text('Hear the real wind where you are?'), findsOneWidget);
    expect(find.text('Controls'), findsOneWidget);
    expect(location.calls, 0, reason: 'no permission prompt on launch');
    expect(weather.requests, isEmpty);
  });

  testWidgets('"Use my location" plays live wind and answers the offer for good', (tester) async {
    weather.respond = (_) => steadyTimeline(DateTime.now(), speed: 5);
    await launch(tester);
    await tester.tap(find.text('Use my location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(location.asked, isTrue);
    expect(find.text('Hear the real wind where you are?'), findsNothing);
    expect(find.text('18 km/h'), findsOneWidget);

    await tester.pump(SettingsController.saveDelay);
    final saved = jsonDecode(store.values[SettingsController.key]!) as Map<String, dynamic>;
    expect(saved['liveWindOffered'], isTrue);
  });

  testWidgets('a declined permission explains and keeps the offer open', (tester) async {
    location.failure = LocationFailure.denied;
    await launch(tester);
    await tester.tap(find.text('Use my location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('You can pick a city instead'), findsOneWidget);
    expect(find.text('Pick a city'), findsOneWidget);
  });

  testWidgets('"Not now" dismisses the offer; the overlays then fade and a sky tap brings them back',
      (tester) async {
    await launch(tester);
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(find.text('Hear the real wind where you are?'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacityOf(tester, find.text('Controls')), 0);

    await tester.tapAt(const Offset(40, 450));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacityOf(tester, find.text('Controls')), 1);
  });

  testWidgets('the pill opens the controls; manual wind, placement and units reach the chip',
      (tester) async {
    await launch(tester);
    await tester.tap(find.text('Not now'));
    await tester.tap(find.text('Controls'));
    await frames(tester);
    expect(find.text('WIND'), findsOneWidget);
    expect(find.text('Search a city'), findsOneWidget);

    await tester.tap(find.text('Manual'));
    await tester.pump();
    expect(find.textContaining('Light breeze'), findsOneWidget);
    expect(find.text('11 km/h'), findsWidgets);

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('kn'),
      200,
      scrollable: find
          .descendant(of: find.byType(ControlsSheet), matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(find.text('kn'));
    await tester.pump();
    expect(find.text('6 kn'), findsWidgets);

    await tester.pump(SettingsController.saveDelay);
    final saved = await tester.runAsync(() => SettingsController.load(store));
    expect(saved!.mode, WindMode.manual);
    expect(saved.units, SpeedUnit.knots);
    expect(saved.placement.name, 'open');
  });

  testWidgets('saved settings are there from the first frame', (tester) async {
    store.values[SettingsController.key] = jsonEncode(const AppSettings(
      mode: WindMode.manual,
      manual: ManualWind(speed: 10, direction: 90),
      units: SpeedUnit.metersPerSecond,
      liveWindOffered: true,
    ).toJson());
    await launch(tester);
    expect(find.text('10 m/s'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
    expect(find.text('Hear the real wind where you are?'), findsNothing);
  });

  testWidgets('tapping the chip shows the details', (tester) async {
    await launch(tester);
    await tester.tap(find.textContaining('km/h'));
    await tester.pump();
    expect(find.text('Ambient breeze · no location yet'), findsOneWidget);
    expect(find.textContaining(' · gusts '), findsOneWidget, reason: 'Beaufort name and gusts');
  });

  testWidgets('after scrolling the open sheet and closing it, the pill is whole again',
      (tester) async {
    await launch(tester);
    await tester.tap(find.text('Not now'));
    await tester.tap(find.text('Controls'));
    await frames(tester);
    final list = find
        .descendant(of: find.byType(ControlsSheet), matching: find.byType(Scrollable))
        .first;
    await tester.drag(list, const Offset(0, -900));
    await frames(tester);
    await tester.tapAt(const Offset(370, 30));
    await frames(tester, const Duration(seconds: 1));
    final position = tester.state<ScrollableState>(list).position;
    expect(position.pixels, 0);
    expect(position.maxScrollExtent, 0);
  });
}
