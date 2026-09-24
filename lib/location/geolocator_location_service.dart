import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'location.dart';

/// Coarse location through `geolocator`: city-level accuracy is all wind needs, and it is quick and
/// cheap on battery.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  /// A remembered fix younger than this is used without asking for a new one.
  static const freshFix = Duration(minutes: 30);
  static const timeLimit = Duration(seconds: 10);

  @override
  Future<Coordinates> current({bool ask = false}) async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && ask) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        throw const LocationException(LocationFailure.denied);
      case LocationPermission.deniedForever:
        throw const LocationException(LocationFailure.deniedForever);
      case LocationPermission.whileInUse ||
            LocationPermission.always ||
            LocationPermission.unableToDetermine:
        break;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationFailure.servicesOff);
    }

    Position? remembered;
    try {
      remembered = await Geolocator.getLastKnownPosition();
    } catch (_) {
      // Not supported on the web.
    }
    if (remembered != null && DateTime.now().difference(remembered.timestamp) < freshFix) {
      return Coordinates(remembered.latitude, remembered.longitude);
    }
    try {
      final fix = await _fix(ask: ask);
      return Coordinates(fix.latitude, fix.longitude);
    } on LocationServiceDisabledException {
      throw const LocationException(LocationFailure.servicesOff);
    } on PermissionDeniedException {
      throw const LocationException(LocationFailure.denied);
    } catch (_) {
      // No fix in time: an old one still beats none for wind.
      if (remembered != null) return Coordinates(remembered.latitude, remembered.longitude);
      throw const LocationException(LocationFailure.unavailable);
    }
  }

  /// An app with only coarse permission can't switch on GPS (Android caps its requests at low
  /// power), so on Android its fix comes from network location ("Location Accuracy"). When that is
  /// off, Play Services' location client shows a dialog offering to turn it on: fine when the user
  /// has just asked for their location, never at launch. So without [ask], use the platform's
  /// location manager, which never shows a dialog.
  Future<Position> _fix({required bool ask}) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: timeLimit,
        ),
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.low,
        // Time to read the dialog, if it shows.
        timeLimit: ask ? const Duration(minutes: 1) : timeLimit,
        forceLocationManager: !ask,
      ),
    );
  }
}
