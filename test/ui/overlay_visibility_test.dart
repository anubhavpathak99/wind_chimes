import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/ui/overlay_visibility.dart';

void main() {
  test('fades after the delay; a poke starts the countdown again', () {
    fakeAsync((time) {
      final o = OverlayVisibility();
      time.elapse(const Duration(seconds: 3));
      o.poke();
      time.elapse(const Duration(seconds: 3));
      expect(o.value, isTrue);
      time.elapse(const Duration(seconds: 2));
      expect(o.value, isFalse);
      o.dispose();
    });
  });

  test('tapping toggles', () {
    fakeAsync((time) {
      final o = OverlayVisibility()..toggle();
      expect(o.value, isFalse);
      o.toggle();
      expect(o.value, isTrue);
      o.dispose();
    });
  });

  test('stays up while held, and lingers longer when asked', () {
    fakeAsync((time) {
      final o = OverlayVisibility()..hold(#sheet, true);
      time.elapse(const Duration(minutes: 1));
      o.toggle();
      expect(o.value, isTrue, reason: 'an open sheet keeps it up');
      o.hold(#sheet, false);
      time.elapse(const Duration(seconds: 5));
      expect(o.value, isFalse);

      o
        ..linger = true
        ..poke();
      time.elapse(const Duration(seconds: 8));
      expect(o.value, isTrue);
      time.elapse(const Duration(seconds: 3));
      expect(o.value, isFalse);
      o.dispose();
    });
  });
}
