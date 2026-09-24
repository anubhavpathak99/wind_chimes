import 'package:flutter/material.dart';

import '../../location/location.dart';
import '../../wind/wind_controller.dart';
import '../wind_chip.dart';
import '../wind_text.dart';

/// Where live wind comes from: the phone's location, or a searched city.
class LocationSection extends StatefulWidget {
  const LocationSection({
    super.key,
    required this.status,
    required this.wind,
    required this.places,
    required this.searchFocus,
  });

  final WindStatus status;
  final WindController wind;
  final PlaceSearch places;
  final FocusNode searchFocus;

  @override
  State<LocationSection> createState() => _LocationSectionState();
}

class _LocationSectionState extends State<LocationSection> {
  final _query = TextEditingController();
  List<Place> _results = const [];
  String? _note;
  bool _searching = false;
  bool _locating = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _useDevice() async {
    setState(() {
      _note = null;
      _locating = true;
    });
    final failure = await widget.wind.useDeviceLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _note = failure == null ? null : locationFailureText(failure);
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) return;
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
      if (mounted) setState(() => _note = 'Search failed. Are you offline?');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(Place place) {
    widget.wind.usePlace(place);
    widget.searchFocus.unfocus();
    _query.clear();
    setState(() => _results = const []);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.status;
    final dim = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final status = [
      WindText.sourceName(s.source),
      if (s.updatedAt case final at?) 'updated ${WindText.ago(s.asOf.difference(at))}',
      ?WindText.problem(s),
      if (s.busy) 'updating…',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(s.location is DeviceLocation ? Icons.my_location : Icons.place_outlined, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(switch (s.location) {
                    null => 'No location yet',
                    DeviceLocation() => 'Your location',
                    final Place p => '$p',
                  }),
                  Text(status, style: dim),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _locating || s.busy ? null : _useDevice,
          icon: _locating
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location, size: 18),
          label: const Text('Use my location'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _query,
          focusNode: widget.searchFocus,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: 'Search a city',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        for (final place in _results)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.place_outlined, size: 20),
            title: Text(place.name),
            subtitle: place.detail.isEmpty ? null : Text(place.detail),
            onTap: () => _pick(place),
          ),
        if (_note case final note?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(note, style: dim.copyWith(color: WindChip.warning)),
          ),
      ],
    );
  }
}

String locationFailureText(LocationFailure failure) => switch (failure) {
      LocationFailure.denied => 'Location permission was not granted. You can pick a city instead.',
      LocationFailure.deniedForever =>
        'Location is turned off for this app in Settings. You can pick a city instead.',
      LocationFailure.servicesOff => 'Location services are off. You can pick a city instead.',
      LocationFailure.unavailable => 'Could not find your location. You can pick a city instead.',
    };
