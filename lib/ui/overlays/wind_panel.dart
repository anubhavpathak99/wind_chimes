import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/material.dart';

import '../../location/location.dart';
import '../../wind/wind_controller.dart';
import 'dev_card.dart';

/// Development panel for the wind: where it comes from and how fresh it is, live or manual, the
/// location for live wind, and the chime's placement. Collapses to a one-line summary.
class WindPanel extends StatelessWidget {
  const WindPanel({
    super.key,
    required this.wind,
    required this.places,
    required this.expanded,
    required this.onToggle,
  });

  final WindController wind;
  final PlaceSearch places;
  final bool expanded;
  final VoidCallback onToggle;

  static const sourceColors = {
    WindSource.live: Color(0xFF7BE495),
    WindSource.cached: Color(0xFFF5C26B),
    WindSource.ambient: Color(0xFF9EC9F5),
    WindSource.manual: Color(0xFFE0E0E0),
  };

  /// One line: source, the wind being played, and anything worth knowing about it.
  static String describe(WindStatus s) {
    final r = s.reading;
    final wind = '${r.speed.toStringAsFixed(1)} m/s ${r.compass}';
    if (s.mode == WindMode.manual) {
      return 'manual · $wind · gusts ×${s.manual.gustFactor.toStringAsFixed(1)}';
    }
    return [
      if (s.source == WindSource.ambient) 'ambient breeze' else s.source.name,
      if (s.source == WindSource.ambient) wind else '$wind, gusts ${r.gust.toStringAsFixed(1)}',
      if (s.location case final where? when s.source != WindSource.ambient) placeName(where),
      if (s.updatedAt case final at?) ago(s.asOf.difference(at)),
      ?problemText(s),
      if (s.busy) 'updating…',
    ].join(' · ');
  }

  static String placeName(LocationChoice choice) => switch (choice) {
        DeviceLocation() => 'your location',
        Place(:final name) => name,
      };

  static String ago(Duration age) => switch (age.inMinutes) {
        < 1 => 'just now',
        < 60 => '${age.inMinutes} min ago',
        _ => '${age.inHours} h ago',
      };

  static String? problemText(WindStatus s) {
    final problem = switch (s.problem) {
      null => null,
      WindProblem.noLocation => 'choose a location',
      WindProblem.locationDenied => 'location permission needed',
      WindProblem.locationDeniedForever => 'location blocked in Settings',
      WindProblem.locationOff => 'location services off',
      WindProblem.locationUnavailable => 'no location fix',
      WindProblem.offline => 'offline',
      WindProblem.serviceError => 'weather service error',
    };
    final retry = s.retryAt;
    if (problem == null || retry == null || s.busy) return problem;
    final wait = retry.difference(s.asOf);
    final when = wait.inSeconds < 60 ? '${wait.inSeconds.clamp(0, 59)} s' : '${wait.inMinutes} min';
    return '$problem, retrying in $when';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WindStatus>(
      valueListenable: wind.status,
      builder: (context, s, _) {
        final text = devTextStyle(context);
        return DevCard(
          title: 'Wind',
          summary: Row(
            children: [
              Icon(Icons.circle, size: 8, color: sourceColors[s.source]),
              const SizedBox(width: 6),
              Expanded(child: Text(describe(s), overflow: TextOverflow.ellipsis)),
            ],
          ),
          expanded: expanded,
          onToggle: onToggle,
          children: [
            SegmentedButton<WindMode>(
              segments: [
                for (final m in WindMode.values)
                  ButtonSegment(value: m, label: Text(m.name, style: text)),
              ],
              selected: {s.mode},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (m) => wind.setMode(m.first),
            ),
            const SizedBox(height: 4),
            if (s.mode == WindMode.live)
              _LiveControls(status: s, wind: wind, places: places)
            else
              ..._manualSliders(s),
            const SizedBox(height: 4),
            SegmentedButton<Placement>(
              segments: [
                for (final p in Placement.values)
                  ButtonSegment(value: p, label: Text(p.name, style: text)),
              ],
              selected: {s.placement},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (p) => wind.setPlacement(p.first),
            ),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  List<Widget> _manualSliders(WindStatus s) {
    final m = s.manual;
    return [
      DevSliderRow(
        label: 'Speed',
        value: m.speed,
        max: 20,
        divisions: 40,
        display: '${m.speed.toStringAsFixed(1)} m/s at 10 m',
        onChanged: (v) => wind.setManual(m.copyWith(speed: v)),
      ),
      DevSliderRow(
        label: 'From',
        value: m.direction,
        max: 345,
        divisions: 23,
        display: '${m.direction.round()}° ${m.compass}',
        onChanged: (v) => wind.setManual(m.copyWith(direction: v)),
      ),
      DevSliderRow(
        label: 'Gusts',
        value: m.gustFactor,
        min: 1,
        max: 2.5,
        divisions: 15,
        display: '×${m.gustFactor.toStringAsFixed(1)}',
        onChanged: (v) => wind.setManual(m.copyWith(gustFactor: v)),
      ),
    ];
  }
}

/// Location for live wind: the phone's, or a searched city.
class _LiveControls extends StatefulWidget {
  const _LiveControls({required this.status, required this.wind, required this.places});

  final WindStatus status;
  final WindController wind;
  final PlaceSearch places;

  @override
  State<_LiveControls> createState() => _LiveControlsState();
}

class _LiveControlsState extends State<_LiveControls> {
  final _query = TextEditingController();
  List<Place> _results = const [];
  String? _note;
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _useDevice() async {
    setState(() => _note = null);
    final failure = await widget.wind.useDeviceLocation();
    if (!mounted || failure == null) return;
    setState(() => _note = switch (failure) {
          LocationFailure.denied => 'Location permission was not granted.',
          LocationFailure.deniedForever => 'Location is blocked for this app in Settings.',
          LocationFailure.servicesOff => 'Location services are off.',
          LocationFailure.unavailable => 'Could not get a location fix.',
        });
  }

  Future<void> _search(String query) async {
    setState(() {
      _searching = true;
      _note = null;
    });
    try {
      final results = await widget.places.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _note = results.isEmpty ? 'No places found.' : null;
      });
    } catch (_) {
      if (mounted) setState(() => _note = 'Search failed. Offline?');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(Place place) {
    widget.wind.usePlace(place);
    _query.clear();
    setState(() => _results = const []);
  }

  @override
  Widget build(BuildContext context) {
    final text = devTextStyle(context);
    final s = widget.status;
    final where = switch (s.location) {
      null => 'none yet: using the ambient breeze',
      DeviceLocation() => 'your location',
      final Place p => '$p',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 70, child: Text('Location', style: text)),
            Expanded(child: Text(where, style: text)),
            TextButton.icon(
              onPressed: s.busy ? null : _useDevice,
              icon: const Icon(Icons.my_location, size: 16),
              label: Text('Mine', style: text),
            ),
          ],
        ),
        TextField(
          controller: _query,
          style: text,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search a city…',
            hintStyle: text,
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.search, size: 18),
                    onPressed: () => _search(_query.text),
                  ),
          ),
        ),
        for (final place in _results)
          InkWell(
            onTap: () => _pick(place),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(width: double.infinity, child: Text('$place', style: text)),
            ),
          ),
        if (_note case final note?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(note, style: text.copyWith(color: const Color(0xFFF5C26B))),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${WindPanel.describe(s)}\n${s.attribution}',
            style: text.copyWith(color: Colors.white54),
          ),
        ),
      ],
    );
  }
}
