import 'package:flutter/material.dart';

/// Small, legible text for the development overlays.
TextStyle devTextStyle(BuildContext context) => Theme.of(context).textTheme.bodySmall!.copyWith(
      color: Colors.white.withValues(alpha: 0.85),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// A translucent development card that collapses to its title and a one-line summary.
class DevCard extends StatelessWidget {
  const DevCard({
    super.key,
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final Widget summary;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = devTextStyle(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onToggle,
                child: Row(
                  children: [
                    Text(title, style: text.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DefaultTextStyle(
                        style: text,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        child: summary,
                      ),
                    ),
                    IconButton(
                      onPressed: onToggle,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(expanded ? Icons.expand_more : Icons.expand_less, size: 20),
                    ),
                  ],
                ),
              ),
              if (expanded) ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled slider with its current value spelled out.
class DevSliderRow extends StatelessWidget {
  const DevSliderRow({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = devTextStyle(context);
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label, style: style)),
        Expanded(
          child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
        ),
        SizedBox(width: 104, child: Text(display, style: style)),
      ],
    );
  }
}
