import 'package:flutter/material.dart';

import '../../game/debug_stats.dart';

/// Development overlay: frame timing, simulation health and the latest impacts.
class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key, required this.stats, required this.onReset});

  static const overlayId = 'debug';

  final DebugStats stats;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodySmall!.copyWith(
          color: Colors.white.withValues(alpha: 0.85),
          fontFeatures: const [FontFeature.tabularFigures()],
          height: 1.35,
        );
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: ValueListenableBuilder<DebugSnapshot>(
                valueListenable: stats.snapshot,
                builder: (context, s, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.fps.toStringAsFixed(0)} fps · '
                      '${s.stepsPerFrame.toStringAsFixed(1)} steps/frame · '
                      '${s.simTime.toStringAsFixed(1)} s',
                      style: text,
                    ),
                    Text(
                      '${s.hits} hits · ${s.dropped} dropped · ${s.recoveries} resets',
                      style: text,
                    ),
                    const SizedBox(height: 4),
                    if (s.recent.isEmpty)
                      Text('Drag the clapper, sail or a tube, then let go.', style: text)
                    else
                      for (final hit in s.recent)
                        Text(
                          'tube ${hit.rod}  '
                          'J ${(hit.impulse * 1000).toStringAsFixed(1)} mN·s  '
                          'v ${hit.speed.toStringAsFixed(2)} m/s  '
                          'at ${(hit.strikePos * 100).toStringAsFixed(0)}%',
                          style: text,
                        ),
                    TextButton(
                      onPressed: onReset,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Reset chime'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
