import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../wind/wind_controller.dart';
import 'wind_text.dart';

/// The quiet readout in the corner: wind speed, an arrow the way it blows, where it comes from,
/// and a dot for its source. Tapping it shows the details. Hosts the first-run offer.
class WindChip extends StatelessWidget {
  const WindChip({
    super.key,
    required this.status,
    required this.units,
    required this.expanded,
    required this.onTap,
    this.offer,
  });

  static const sourceColors = {
    WindSource.live: Color(0xFF7BE495),
    WindSource.cached: Color(0xFFF5C26B),
    WindSource.ambient: Color(0xFF9EC9F5),
    WindSource.manual: Color(0xFFE0E0E0),
  };
  static const warning = Color(0xFFF5C26B);

  final WindStatus status;
  final SpeedUnit units;
  final bool expanded;
  final VoidCallback onTap;
  final Widget? offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = status.reading;
    final dim = theme.textTheme.bodySmall!.copyWith(color: Colors.white70);
    final speed = WindText.speed(r.speed, units);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: Colors.black.withValues(alpha: 0.32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: '${WindText.sourceName(status.source)} wind, $speed from ${r.compass}',
                    excludeSemantics: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: sourceColors[status.source]),
                        const SizedBox(width: 8),
                        Text(
                          speed,
                          style: theme.textTheme.titleSmall!.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 6),
                        // The way it blows: opposite to where it comes from.
                        Transform.rotate(
                          angle: (r.direction + 180) * math.pi / 180,
                          child: const Icon(Icons.north, size: 14),
                        ),
                        const SizedBox(width: 2),
                        Text(r.compass, style: theme.textTheme.titleSmall),
                      ],
                    ),
                  ),
                  if (expanded) ..._details(dim),
                  ?offer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _details(TextStyle dim) {
    final r = status.reading;
    final where = status.location;
    final source = switch (status.source) {
      WindSource.live || WindSource.cached => [
          WindText.sourceName(status.source),
          if (where != null) WindText.placeName(where),
          if (status.updatedAt case final at?) 'updated ${WindText.ago(status.asOf.difference(at))}',
        ].join(' · '),
      WindSource.ambient =>
        where == null ? 'Ambient breeze · no location yet' : 'Ambient breeze until real wind arrives',
      WindSource.manual => 'Manual wind',
    };
    return [
      const SizedBox(height: 6),
      Text(
        '${WindText.beaufortName(r.speed)} · gusts ${WindText.speed(r.gust, units)}',
        style: dim.copyWith(color: Colors.white),
      ),
      Text(source, style: dim),
      if (WindText.problem(status) case final problem?)
        Text(problem, style: dim.copyWith(color: warning)),
      if (status.source == WindSource.live || status.source == WindSource.cached)
        Text(status.attribution, style: dim.copyWith(color: Colors.white38, fontSize: 11)),
    ];
  }
}

/// The first-run question, shown inside the chip: the app starts on the ambient breeze, and only
/// this asks for location.
class LiveWindOffer extends StatelessWidget {
  const LiveWindOffer({
    super.key,
    required this.onUseLocation,
    required this.onPickCity,
    required this.onDismiss,
    this.busy = false,
    this.error,
  });

  final VoidCallback onUseLocation;
  final VoidCallback onPickCity;
  final VoidCallback onDismiss;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hear the real wind where you are?', style: text),
          if (error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(error, style: text.copyWith(color: WindChip.warning, fontSize: 13)),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonal(
                onPressed: busy ? null : onUseLocation,
                child: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Use my location'),
              ),
              TextButton(onPressed: onPickCity, child: const Text('Pick a city')),
              TextButton(onPressed: onDismiss, child: const Text('Not now')),
            ],
          ),
        ],
      ),
    );
  }
}
