import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Configures the OS audio session for a sound-first app and reports interruptions.
///
/// iOS uses the playback category, so the chime isn't silenced by the ringer switch, and mixes
/// with other apps' audio so music or a podcast can play alongside. Android plays as media and
/// doesn't take audio focus, which mixes the same way. [onInterrupted] fires when a call or Siri
/// takes over and [onResumed] when it is safe to continue. Native platforms only.
Future<StreamSubscription<AudioInterruptionEvent>> configureAudioSession({
  required VoidCallback onInterrupted,
  required VoidCallback onResumed,
}) async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
    avAudioSessionMode: AVAudioSessionMode.defaultMode,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.music,
      usage: AndroidAudioUsage.media,
    ),
    androidWillPauseWhenDucked: false,
  ));
  if (defaultTargetPlatform == TargetPlatform.iOS) await session.setActive(true);
  return session.interruptionEventStream.listen((event) {
    if (event.type == AudioInterruptionType.duck) return;
    if (event.begin) {
      onInterrupted();
    } else if (event.type == AudioInterruptionType.pause) {
      onResumed();
    }
  });
}
