import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/material.dart';

import '../../wind/manual_wind.dart';

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
    final text = Theme.of(context).textTheme.bodySmall!.copyWith(
          color: Colors.white.withValues(alpha: 0.85),
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final summary = '${wind.speed.toStringAsFixed(1)} m/s from ${wind.compass} · '
        'gusts ×${wind.gustFactor.toStringAsFixed(1)} · ${wind.placement.name}';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onToggle,
                child: Row(
                  children: [
                    Text('Wind', style: text.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(expanded ? '' : summary, style: text, overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(
                      onPressed: onToggle,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(expanded ? Icons.expand_more : Icons.expand_less, size: 20),
                    ),
                  ],
                ),
              ),
              if (expanded) ...[
                _SliderRow(
                  label: 'Speed',
                  value: wind.speed,
                  max: 20,
                  divisions: 40,
                  display: '${wind.speed.toStringAsFixed(1)} m/s at 10 m',
                  style: text,
                  onChanged: (v) => onChanged(wind.copyWith(speed: v)),
                ),
                _SliderRow(
                  label: 'From',
                  value: wind.direction,
                  max: 345,
                  divisions: 23,
                  display: '${wind.direction.round()}° ${wind.compass}',
                  style: text,
                  onChanged: (v) => onChanged(wind.copyWith(direction: v)),
                ),
                _SliderRow(
                  label: 'Gusts',
                  value: wind.gustFactor,
                  min: 1,
                  max: 2.5,
                  divisions: 15,
                  display: '×${wind.gustFactor.toStringAsFixed(1)}',
                  style: text,
                  onChanged: (v) => onChanged(wind.copyWith(gustFactor: v)),
                ),
                const SizedBox(height: 4),
                SegmentedButton<Placement>(
                  segments: [
                    for (final p in Placement.values)
                      ButtonSegment(value: p, label: Text(p.name, style: text)),
                  ],
                  selected: {wind.placement},
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  onSelectionChanged: (s) => onChanged(wind.copyWith(placement: s.first)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    this.min = 0,
    required this.max,
    required this.divisions,
    required this.display,
    required this.style,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final TextStyle style;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 44, child: Text(label, style: style)),
        Expanded(
          child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
        ),
        SizedBox(width: 104, child: Text(display, style: style)),
      ],
    );
  }
}
