import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/app/app.dart';
import 'package:wind_chimes/game/wind_chime_game.dart';

import 'motion/fake_motion_source.dart';
import 'wind/fake_wind_services.dart';

void main() {
  testWidgets('opens straight onto the chime, playing the ambient breeze', (tester) async {
    await tester.pumpWidget(WindChimesApp(
      audioEnabled: false,
      motionSource: FakeMotionSource(),
      windServices: fakeWindServices(),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GameWidget<WindChimeGame>), findsOneWidget);
    expect(find.text('Reset chime'), findsOneWidget);
    expect(find.text('Wind'), findsOneWidget);
    expect(find.textContaining('ambient breeze'), findsOneWidget);
    expect(find.textContaining('choose a location'), findsOneWidget);
    expect(find.text('Motion'), findsOneWidget);
    expect(find.text('waiting for sensors…'), findsOneWidget);
    expect(find.text('audio disabled'), findsOneWidget);
  });

  testWidgets('the wind panel switches to manual and back', (tester) async {
    await tester.pumpWidget(WindChimesApp(
      audioEnabled: false,
      motionSource: FakeMotionSource(),
      windServices: fakeWindServices(),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Wind'));
    await tester.pump();
    expect(find.text('Search a city…'), findsOneWidget);

    await tester.tap(find.text('manual'));
    await tester.pump();
    expect(find.text('Speed'), findsOneWidget);
    expect(find.textContaining('manual · 3.0 m/s W'), findsOneWidget);

    await tester.tap(find.text('live'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });
}
