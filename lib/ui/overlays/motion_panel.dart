import 'package:flutter/material.dart';

import '../../motion/motion_controller.dart';
import '../../motion/motion_settings.dart';
import 'dev_card.dart';

/// Development panel showing what the phone's motion is doing to the chime, with its settings.
class MotionPanel extends StatelessWidget {
  const MotionPanel({
    super.key,
    required this.motion,
    required this.settings,
    required this.onChanged,
    required this.expanded,
    required this.onToggle,
  });

  final ValueNotifier<MotionSnapshot> motion;
  final MotionSettings settings;
  final ValueChanged<MotionSettings> onChanged;
  final bool expanded;
  final VoidCallback onToggle;

  static String describe(MotionSnapshot m) => switch (m.status) {
        MotionStatus.off => 'off',
        MotionStatus.waiting => 'waiting for sensors…',
        MotionStatus.unavailable => 'no motion sensors',
        MotionStatus.live => 'tilt ${m.tiltDegrees.round()}° · '
            'push ${m.acceleration.toStringAsFixed(1)} m/s²'
            '${m.shaking ? ' · shaking ${(m.shakeIntensity * 100).round()}%' : ''}',
      };

  @override
  Widget build(BuildContext context) {
    return DevCard(
      title: 'Motion',
      summary: ValueListenableBuilder<MotionSnapshot>(
        valueListenable: motion,
        builder: (context, m, _) => Text(describe(m)),
      ),
      expanded: expanded,
      onToggle: onToggle,
      children: [
        DevSliderRow(
          label: 'Sensitivity',
          value: settings.sensitivity,
          max: 2,
          divisions: 20,
          display: settings.sensitivity == 0 ? 'ignore shaking' : '×${settings.sensitivity.toStringAsFixed(1)}',
          onChanged: (v) => onChanged(settings.copyWith(sensitivity: v)),
        ),
        Row(
          children: [
            SizedBox(width: 70, child: Text('Tilt', style: devTextStyle(context))),
            Switch(
              value: settings.tiltEnabled,
              onChanged: (v) => onChanged(settings.copyWith(tiltEnabled: v)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                settings.tiltEnabled ? 'chime hangs plumb as you tilt' : 'always hangs straight down',
                style: devTextStyle(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
