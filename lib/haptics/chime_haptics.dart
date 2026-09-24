import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/services.dart';

import '../audio/hit_mapper.dart';

enum HapticStrength { light, medium, heavy }

/// Taps the phone when the chime is struck while you are playing it: dragging it, just after a
/// fling, or shaking the phone. The wind alone never buzzes the phone; a chime left ringing on a
/// table should be heard, not felt.
class ChimeHaptics implements CollisionSink {
  ChimeHaptics({void Function(HapticStrength strength)? output}) : _output = output ?? _platform;

  /// How long after letting go (or after shaking stops) strikes are still felt: a fling's hits
  /// come after the finger leaves the screen.
  static const afterglowSeconds = 1.0;

  /// Taps closer together than this merge into one, so a flurry doesn't become a buzz.
  static const minInterval = 0.06;

  final void Function(HapticStrength strength) _output;
  bool enabled = true;
  double _engaged = 0;
  double _clock = 0;
  double _lastTap = double.negativeInfinity;

  /// Once per frame, with whether the user is playing the chime right now.
  void update(double dt, {required bool playing}) {
    _clock += dt;
    _engaged = playing ? afterglowSeconds : (_engaged - dt).clamp(0.0, afterglowSeconds);
  }

  @override
  void onCollision(CollisionEvent event) {
    if (!enabled || _engaged <= 0 || _clock - _lastTap < minInterval) return;
    final s = HitMapper.intensity(event.impulse);
    if (s <= 0) return;
    _lastTap = _clock;
    _output(switch (s) {
      < 0.4 => HapticStrength.light,
      < 0.75 => HapticStrength.medium,
      _ => HapticStrength.heavy,
    });
  }

  static void _platform(HapticStrength strength) {
    switch (strength) {
      case HapticStrength.light:
        HapticFeedback.lightImpact();
      case HapticStrength.medium:
        HapticFeedback.mediumImpact();
      case HapticStrength.heavy:
        HapticFeedback.heavyImpact();
    }
  }
}
