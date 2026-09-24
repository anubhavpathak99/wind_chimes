import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/app/app.dart';
import 'package:wind_chimes/game/wind_chime_game.dart';

void main() {
  testWidgets('opens straight onto the chime', (tester) async {
    await tester.pumpWidget(const WindChimesApp(audioEnabled: false));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GameWidget<WindChimeGame>), findsOneWidget);
    expect(find.text('Reset chime'), findsOneWidget);
    expect(find.text('Wind'), findsOneWidget);
    expect(find.text('audio disabled'), findsOneWidget);
  });
}
