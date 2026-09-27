import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/audio/background_playback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wind_chimes/background_playback');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const playback = BackgroundPlayback();
  final calls = <String>[];

  void answer(Object? Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return handler(call);
      });

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('starts and stops the service', () async {
    answer((_) => null);
    await playback.start();
    await playback.stop();
    expect(calls, ['start', 'stop']);
  });

  test("reports Android's answer to the notification question", () async {
    answer((_) => false);
    expect(await playback.requestNotifications(), isFalse);
    answer((_) => true);
    expect(await playback.requestNotifications(), isTrue);
  });

  test('a refusal to start, or no channel at all, is survived', () async {
    answer((_) => throw PlatformException(code: 'not_allowed'));
    await playback.start();
    expect(await playback.requestNotifications(), isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    await playback.stop();
    expect(await playback.requestNotifications(), isFalse);
  });

  test('elsewhere than Android, nothing is called', () async {
    answer((_) => null);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await playback.start();
    expect(await playback.requestNotifications(), isTrue);
    expect(calls, isEmpty);
  });
}
