import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/material.dart';

import '../../wind/manual_wind.dart';
import 'dev_card.dart';

/// Development panel for dialing in wind by hand while tuning. Collapses to a one-line summary.
class WindPanel extends StatelessWidget {
  const WindPanel({
    super.key,
    required this.wind,
    required this.onChanged,
    required this.expanded,
    required this.onToggle,
  });

  final ManualWind wind;
  final ValueChanged<ManualWind> onChanged;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return DevCard(
      title: 'Wind',
      summary: Text(expanded
          ? ''
          : '${wind.speed.toStringAsFixed(1)} m/s from ${wind.compass} · '
              'gusts ×${wind.gustFactor.toStringAsFixed(1)} · ${wind.placement.name}'),
      expanded: expanded,
      onToggle: onToggle,
      children: [
        DevSliderRow(
          label: 'Speed',
          value: wind.speed,
          max: 20,
          divisions: 40,
          display: '${wind.speed.toStringAsFixed(1)} m/s at 10 m',
          onChanged: (v) => onChanged(wind.copyWith(speed: v)),
        ),
        DevSliderRow(
          label: 'From',
          value: wind.direction,
          max: 345,
          divisions: 23,
          display: '${wind.direction.round()}° ${wind.compass}',
          onChanged: (v) => onChanged(wind.copyWith(direction: v)),
        ),
        DevSliderRow(
          label: 'Gusts',
          value: wind.gustFactor,
          min: 1,
          max: 2.5,
          divisions: 15,
          display: '×${wind.gustFactor.toStringAsFixed(1)}',
          onChanged: (v) => onChanged(wind.copyWith(gustFactor: v)),
        ),
        const SizedBox(height: 4),
        SegmentedButton<Placement>(
          segments: [
            for (final p in Placement.values)
              ButtonSegment(value: p, label: Text(p.name, style: devTextStyle(context))),
          ],
          selected: {wind.placement},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (s) => onChanged(wind.copyWith(placement: s.first)),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
