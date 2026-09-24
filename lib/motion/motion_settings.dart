import 'package:flutter/foundation.dart';

import 'motion_processor.dart';

/// How much the phone's own movement moves the chime.
@immutable
class MotionSettings {
  const MotionSettings({this.sensitivity = 1, this.tiltEnabled = true});

  /// Multiplier on the phone's acceleration: 0 ignores shaking, 2 exaggerates it.
  final double sensitivity;

  /// Whether tilting the phone rotates gravity.
  final bool tiltEnabled;

  MotionSettings copyWith({double? sensitivity, bool? tiltEnabled}) => MotionSettings(
        sensitivity: sensitivity ?? this.sensitivity,
        tiltEnabled: tiltEnabled ?? this.tiltEnabled,
      );

  void applyTo(MotionProcessor processor) => processor
    ..sensitivity = sensitivity
    ..tiltEnabled = tiltEnabled;
}
