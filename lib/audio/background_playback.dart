import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the app alive while the chime plays in the background.
///
/// Android freezes or kills a background app unless it runs a foreground service, which shows a
/// notification; `PlaybackService` in the Android app is that service, running only between
/// [start] and [stop]. Swiping the app away, or the notification's Stop, ends it and the sound
/// with it. iOS needs only the `audio` background mode and the playback session; desktop apps and
/// browser tabs keep running anyway. Everywhere but Android this does nothing.
class BackgroundPlayback {
  const BackgroundPlayback();

  static const _channel = MethodChannel('wind_chimes/background_playback');

  /// Whether playing in the background shows a notification: Android only.
  static bool get hasNotification => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// For the app leaving the screen. Android allows starting the service only for a few seconds
  /// after that.
  Future<void> start() => _call<void>('start');

  Future<void> stop() => _call<void>('stop');

  /// Android 13+ shows the notification only with the user's permission: asks for it, unless it
  /// is granted already or not needed. Returns whether the notification can show. The service
  /// runs either way.
  Future<bool> requestNotifications() async {
    if (!hasNotification) return true;
    return await _call<bool>('requestNotifications') ?? false;
  }

  Future<T?> _call<T>(String method) async {
    if (!hasNotification) return null;
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException catch (e) {
      // Without the service the chime still plays until Android freezes the app.
      debugPrint('BackgroundPlayback: $method failed: ${e.message}');
    } on MissingPluginException {
      // An engine without MainActivity's channel, as in tests.
    }
    return null;
  }
}
