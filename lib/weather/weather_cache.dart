import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../location/location.dart';
import '../storage/key_value_store.dart';
import 'wind_timeline.dart';

/// A fetched forecast and what it was fetched for.
@immutable
class WeatherReport {
  const WeatherReport({
    required this.locationKey,
    required this.coordinates,
    required this.fetchedAt,
    required this.timeline,
  });

  /// [LocationChoice.key] of the choice it was fetched for.
  final String locationKey;
  final Coordinates coordinates;
  final DateTime fetchedAt;
  final WindTimeline timeline;

  Map<String, Object?> toJson() => {
        'key': locationKey,
        'lat': coordinates.latitude,
        'lon': coordinates.longitude,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
        'timeline': timeline.toJson(),
      };

  factory WeatherReport.fromJson(Map<String, dynamic> json) => WeatherReport(
        locationKey: json['key'] as String,
        coordinates: Coordinates((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
        fetchedAt:
            DateTime.fromMillisecondsSinceEpoch((json['fetchedAt'] as num).toInt(), isUtc: true),
        timeline: WindTimeline.fromJson(json['timeline'] as List<dynamic>),
      );
}

/// The last forecast, kept on the device so a launch without network still plays real wind.
class WeatherCache {
  WeatherCache(this._store);

  static const key = 'weather.report.v1';

  final KeyValueStore _store;

  /// The saved report, or null if there is none or it can't be read.
  Future<WeatherReport?> load() async {
    try {
      final text = await _store.read(key);
      if (text == null) return null;
      return WeatherReport.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(WeatherReport report) async {
    try {
      await _store.write(key, jsonEncode(report.toJson()));
    } catch (_) {
      // A cache that can't be written only costs the next offline launch its real wind.
    }
  }
}
