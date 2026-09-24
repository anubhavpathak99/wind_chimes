import 'package:flutter/foundation.dart';

@immutable
class Coordinates {
  const Coordinates(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Rounded to two decimals (about 1 km): enough for wind, better for privacy and caching.
  Coordinates get rounded => Coordinates(_round2(latitude), _round2(longitude));

  @override
  bool operator ==(Object other) =>
      other is Coordinates && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => '${latitude.toStringAsFixed(2)}, ${longitude.toStringAsFixed(2)}';
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Where the live wind comes from: the phone's own location, or a place the user picked.
@immutable
sealed class LocationChoice {
  const LocationChoice();

  /// Identifies the choice, so data cached for one is never shown for another.
  String get key;

  Map<String, Object?> toJson();

  static LocationChoice? fromJson(Map<String, Object?> json) => switch (json['kind']) {
        'device' => const DeviceLocation(),
        'place' => Place(
            name: json['name'] as String,
            detail: json['detail'] as String? ?? '',
            coordinates: Coordinates(
              (json['lat'] as num).toDouble(),
              (json['lon'] as num).toDouble(),
            ),
          ),
        _ => null,
      };
}

class DeviceLocation extends LocationChoice {
  const DeviceLocation();

  @override
  String get key => 'device';

  @override
  Map<String, Object?> toJson() => {'kind': 'device'};

  @override
  bool operator ==(Object other) => other is DeviceLocation;

  @override
  int get hashCode => 0;
}

/// A named place, from a search.
class Place extends LocationChoice {
  const Place({required this.name, this.detail = '', required this.coordinates});

  final String name;

  /// Region and country, to tell places with the same name apart.
  final String detail;
  final Coordinates coordinates;

  @override
  String get key => 'place:${coordinates.rounded}';

  @override
  Map<String, Object?> toJson() => {
        'kind': 'place',
        'name': name,
        'detail': detail,
        'lat': coordinates.latitude,
        'lon': coordinates.longitude,
      };

  @override
  bool operator ==(Object other) =>
      other is Place && other.name == name && other.coordinates == coordinates;

  @override
  int get hashCode => Object.hash(name, coordinates);

  @override
  String toString() => detail.isEmpty ? name : '$name, $detail';
}

enum LocationFailure {
  /// The user hasn't granted permission (or declined when asked).
  denied,

  /// Declined for good: only the system settings can change it.
  deniedForever,
  servicesOff,

  /// No fix in time.
  unavailable,
}

class LocationException implements Exception {
  const LocationException(this.reason);

  final LocationFailure reason;

  @override
  String toString() => 'LocationException(${reason.name})';
}

abstract interface class LocationService {
  /// The phone's approximate position. Shows the permission prompt only if [ask] is true, so
  /// launching the app never blocks on one. Throws [LocationException].
  Future<Coordinates> current({bool ask = false});
}

abstract interface class PlaceSearch {
  /// Places matching [query], best first.
  Future<List<Place>> search(String query);
}
