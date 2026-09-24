import 'dart:ui' show lerpDouble;

import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/material.dart';

import '../../location/location.dart';
import '../../motion/motion_controller.dart';
import '../../settings/app_settings.dart';
import '../../wind/manual_wind.dart';
import '../../wind/wind_controller.dart';
import '../wind_text.dart';
import 'direction_dial.dart';
import 'location_section.dart';

typedef SettingsChange = void Function(AppSettings Function(AppSettings current) change);

/// The one sheet for everything the user can change. Collapsed, it is a small pill at the bottom;
/// pulled up or tapped, it opens over the lower part of the screen while the chime keeps playing
/// above it.
class ControlsSheet extends StatefulWidget {
  const ControlsSheet({
    super.key,
    required this.controller,
    required this.settings,
    required this.onChanged,
    required this.wind,
    required this.places,
    required this.motion,
    required this.searchFocus,
    required this.onExtentChanged,
    this.skyPreviewHour,
    this.onSkyPreview,
  });

  static const pillWidth = 168.0;
  static const pillHeight = 48.0;
  static const openSize = 0.6;
  static const fullSize = 0.92;

  /// The collapsed size: the pill, floating just above the system's bottom inset.
  static double minSizeFor(double height, double bottomInset) =>
      ((pillHeight + bottomInset + 12) / height).clamp(0.04, 0.3);

  final DraggableScrollableController controller;
  final AppSettings settings;
  final SettingsChange onChanged;
  final WindController wind;
  final PlaceSearch places;
  final ValueNotifier<MotionSnapshot> motion;
  final FocusNode searchFocus;

  /// The fraction of the screen the sheet covers, and whether it is open (more than the pill).
  final void Function(double extent, bool open) onExtentChanged;

  /// For tuning, with stats on: an hour of the day to show the sky at instead of now.
  final double? skyPreviewHour;
  final ValueChanged<double?>? onSkyPreview;

  @override
  State<ControlsSheet> createState() => _ControlsSheetState();
}

class _ControlsSheetState extends State<ControlsSheet> {
  double? _extent;
  double _minSize = 0.1;

  bool get _open => (_extent ?? _minSize) > _minSize + 0.01;

  void _toggle() => widget.controller.animateTo(
        _open ? _minSize : ControlsSheet.openSize,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        _minSize = ControlsSheet.minSizeFor(box.maxHeight, media.padding.bottom);
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            setState(() => _extent = n.extent);
            widget.onExtentChanged(n.extent, n.extent > n.minExtent + 0.01);
            return false;
          },
          child: DraggableScrollableSheet(
            controller: widget.controller,
            initialChildSize: _minSize,
            minChildSize: _minSize,
            maxChildSize: ControlsSheet.fullSize,
            snap: true,
            snapSizes: const [ControlsSheet.openSize],
            builder: (context, scroll) {
              // Morphs from pill to sheet over the first stretch of the pull.
              final t = (((_extent ?? _minSize) - _minSize) / 0.2).clamp(0.0, 1.0);
              return ClipPath(
                clipper: _PillClipper(t),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.96),
                  child: ListView(
                    controller: scroll,
                    // Collapsed, the pill must fit exactly: any padding would let it scroll.
                    padding: EdgeInsets.only(
                      bottom: t > 0 ? media.padding.bottom + media.viewInsets.bottom + 24 : 0,
                    ),
                    children: [
                      _Header(open: t > 0.5, onTap: _toggle),
                      // Only the pill while collapsed, so hidden controls never reach a screen
                      // reader.
                      if (t > 0) ..._sections(context),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _sections(BuildContext context) {
    final s = widget.settings;
    final change = widget.onChanged;
    return [
      _Section(
        title: 'Wind',
        children: [
          SegmentedButton<WindMode>(
            segments: const [
              ButtonSegment(
                value: WindMode.live,
                icon: Icon(Icons.cloud_outlined),
                label: Text('Live'),
              ),
              ButtonSegment(value: WindMode.manual, icon: Icon(Icons.tune), label: Text('Manual')),
            ],
            selected: {s.mode},
            onSelectionChanged: (m) => change((x) => x.copyWith(mode: m.first)),
          ),
          const SizedBox(height: 16),
          if (s.mode == WindMode.live)
            ValueListenableBuilder<WindStatus>(
              valueListenable: widget.wind.status,
              builder: (context, status, _) => LocationSection(
                status: status,
                wind: widget.wind,
                places: widget.places,
                searchFocus: widget.searchFocus,
              ),
            )
          else
            ManualWindControls(
              manual: s.manual,
              units: s.units,
              onChanged: (m) => change((x) => x.copyWith(manual: m)),
            ),
        ],
      ),
      _Section(
        title: 'Placement',
        children: [
          SegmentedButton<Placement>(
            segments: const [
              ButtonSegment(
                value: Placement.sheltered,
                icon: Icon(Icons.roofing),
                label: Text('Sheltered'),
              ),
              ButtonSegment(value: Placement.garden, icon: Icon(Icons.park), label: Text('Garden')),
              ButtonSegment(
                value: Placement.open,
                icon: Icon(Icons.landscape),
                label: Text('Open'),
              ),
            ],
            selected: {s.placement},
            showSelectedIcon: false,
            onSelectionChanged: (p) => change((x) => x.copyWith(placement: p.first)),
          ),
          const SizedBox(height: 8),
          _Caption(placementText(s.placement)),
        ],
      ),
      _Section(
        title: 'Sound',
        children: [
          _SliderRow(
            icon: Icons.volume_up_outlined,
            label: 'Volume',
            value: s.volume,
            onChanged: (v) => change((x) => x.copyWith(volume: v)),
          ),
          _SliderRow(
            icon: Icons.air,
            label: 'Wind sound',
            value: s.ambience,
            onChanged: (v) => change((x) => x.copyWith(ambience: v)),
          ),
        ],
      ),
      _Section(
        title: 'Motion',
        children: [
          ValueListenableBuilder<MotionSnapshot>(
            valueListenable: widget.motion,
            builder: (context, m, _) => _Caption(motionText(m)),
          ),
          _SliderRow(
            icon: Icons.vibration,
            label: 'Shaking',
            value: s.motion.sensitivity,
            max: 2,
            divisions: 20,
            display: s.motion.sensitivity == 0 ? 'off' : '×${s.motion.sensitivity.toStringAsFixed(1)}',
            onChanged: (v) => change((x) => x.copyWith(motion: x.motion.copyWith(sensitivity: v))),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.screen_rotation_alt_outlined),
            title: const Text('Tilting moves the chime'),
            value: s.motion.tiltEnabled,
            onChanged: (v) => change((x) => x.copyWith(motion: x.motion.copyWith(tiltEnabled: v))),
          ),
        ],
      ),
      _Section(
        title: 'Settings',
        children: [
          Row(
            children: [
              const Expanded(child: Text('Units')),
              SegmentedButton<SpeedUnit>(
                segments: [
                  for (final u in SpeedUnit.values) ButtonSegment(value: u, label: Text(u.label)),
                ],
                selected: {s.units},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (u) => change((x) => x.copyWith(units: u.first)),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibrate when you play it'),
            subtitle: const Text('When you drag the chime or shake the phone'),
            value: s.haptics,
            onChanged: (v) => change((x) => x.copyWith(haptics: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.wb_twilight),
            title: const Text('Sky follows the time of day'),
            subtitle: const Text('Off: always dusk'),
            value: s.skyFollowsTime,
            onChanged: (v) => change((x) => x.copyWith(skyFollowsTime: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.query_stats),
            title: const Text('Show stats'),
            subtitle: const Text('Frame rate, hits and audio, for tuning'),
            value: s.showStats,
            onChanged: (v) => change((x) => x.copyWith(showStats: v)),
          ),
          if (s.showStats && s.skyFollowsTime && widget.onSkyPreview != null)
            _SkyPreviewRow(hour: widget.skyPreviewHour, onChanged: widget.onSkyPreview!),
          const SizedBox(height: 8),
          _Caption(
            '${widget.wind.status.value.attribution} (CC BY 4.0). Your location is only used to '
            'fetch the wind, rounded to about a kilometre.',
          ),
        ],
      ),
    ];
  }
}

/// Shows the sky at any hour, for checking its looks without waiting for dusk.
class _SkyPreviewRow extends StatelessWidget {
  const _SkyPreviewRow({required this.hour, required this.onChanged});

  final double? hour;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final h = hour;
    final label = h == null
        ? 'now'
        : '${h.floor().toString().padLeft(2, '0')}:${((h % 1) * 60).round().toString().padLeft(2, '0')}';
    return Row(
      children: [
        const Icon(Icons.schedule, size: 20),
        const SizedBox(width: 12),
        const SizedBox(width: 92, child: Text('Sky at')),
        Expanded(
          child: Slider(
            value: h ?? 12,
            max: 23.5,
            divisions: 47,
            semanticFormatterCallback: (_) => label,
            onChanged: onChanged,
          ),
        ),
        TextButton(onPressed: h == null ? null : () => onChanged(null), child: Text(label)),
      ],
    );
  }
}

/// Speed on a Beaufort slider, direction on a dial, and how gusty.
class ManualWindControls extends StatelessWidget {
  const ManualWindControls({
    super.key,
    required this.manual,
    required this.units,
    required this.onChanged,
  });

  static const maxForce = 9.0;

  final ManualWind manual;
  final SpeedUnit units;
  final ValueChanged<ManualWind> onChanged;

  static String gustText(double factor) => switch (factor) {
        <= 1.1 => 'steady',
        <= 1.4 => 'a few gusts',
        <= 1.8 => 'gusty',
        _ => 'very gusty',
      };

  @override
  Widget build(BuildContext context) {
    final m = manual;
    final force = WindText.beaufortScale(m.speed).clamp(0.0, maxForce);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${WindText.beaufortName(m.speed)} · ${WindText.speed(m.speed, units)}'),
        Slider(
          value: force,
          max: maxForce,
          divisions: 36,
          semanticFormatterCallback: (_) => WindText.speed(m.speed, units),
          onChanged: (b) => onChanged(m.copyWith(speed: WindText.speedForBeaufort(b))),
        ),
        Row(
          children: [
            DirectionDial(
              from: m.direction,
              onChanged: (d) => onChanged(m.copyWith(direction: d)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('From ${m.compass} · ${m.direction.round()}°'),
                  const SizedBox(height: 16),
                  Text('Gusts: ${gustText(m.gustFactor)}'),
                  Slider(
                    value: m.gustFactor.clamp(1.0, 2.5),
                    min: 1,
                    max: 2.5,
                    divisions: 15,
                    semanticFormatterCallback: (v) => gustText(v),
                    onChanged: (v) => onChanged(m.copyWith(gustFactor: v)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String placementText(Placement p) {
  final percent = '${(p.exposure * 100).round()}%';
  return switch (p) {
    Placement.sheltered => 'A porch or balcony: feels about $percent of the reported wind, in eddies.',
    Placement.garden => 'A garden or tree branch: feels about $percent of the reported wind.',
    Placement.open => 'Open ground or a rooftop: feels about $percent of the reported wind, steadier.',
  };
}

String motionText(MotionSnapshot m) => switch (m.status) {
      MotionStatus.off => 'Motion is paused.',
      MotionStatus.waiting => 'Waiting for the motion sensors…',
      MotionStatus.unavailable => 'This device has no motion sensors.',
      MotionStatus.live => m.shaking
          ? 'Shaking!'
          : m.tiltDegrees.abs() >= 1
              ? 'Tilted ${m.tiltDegrees.abs().round()}° ${m.tiltDegrees > 0 ? 'right' : 'left'}.'
              : 'Tilt or shake the phone to move the chime.',
    };

class _Header extends StatelessWidget {
  const _Header({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: open ? 'Close controls' : 'Open controls',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: ControlsSheet.pillHeight,
          child: Column(
            children: [
              const SizedBox(height: 6),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(open ? Icons.expand_more : Icons.tune, size: 18),
                    const SizedBox(width: 8),
                    Text('Controls', style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall!.copyWith(
              letterSpacing: 1.2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 1,
    this.divisions,
    this.display,
  });

  final IconData icon;
  final String label;
  final double value;
  final double max;
  final int? divisions;
  final String? display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max),
            max: max,
            divisions: divisions,
            semanticFormatterCallback: (v) => display ?? '${(v / max * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
        if (display case final display?) SizedBox(width: 36, child: Text(display)),
      ],
    );
  }
}

/// Clips the sheet to a centered pill when collapsed, widening to the full sheet as it opens.
/// Touches outside the clip fall through to the chime.
class _PillClipper extends CustomClipper<Path> {
  _PillClipper(this.t);

  final double t;

  @override
  Path getClip(Size size) {
    final inset = (size.width - ControlsSheet.pillWidth) / 2 * (1 - t);
    final bottom = lerpDouble(ControlsSheet.pillHeight, size.height, t)!;
    final top = Radius.circular(lerpDouble(ControlsSheet.pillHeight / 2, 24, t)!);
    final low = Radius.circular(lerpDouble(ControlsSheet.pillHeight / 2, 0, t)!);
    return Path()
      ..addRRect(RRect.fromLTRBAndCorners(
        inset,
        0,
        size.width - inset,
        bottom,
        topLeft: top,
        topRight: top,
        bottomLeft: low,
        bottomRight: low,
      ));
  }

  @override
  bool shouldReclip(_PillClipper old) => old.t != t;
}
