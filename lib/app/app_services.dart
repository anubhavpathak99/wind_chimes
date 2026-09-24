import 'package:http/http.dart' as http;

import '../location/geolocator_location_service.dart';
import '../location/location.dart';
import '../location/open_meteo_place_search.dart';
import '../motion/motion_source.dart';
import '../storage/key_value_store.dart';
import '../weather/open_meteo_provider.dart';
import '../weather/weather_provider.dart';

/// Everything the app needs from outside itself, replaceable in tests.
class AppServices {
  AppServices({
    required this.weather,
    required this.location,
    required this.places,
    required this.store,
    required this.motion,
    this.onDispose,
  });

  /// Open-Meteo for forecasts and city search, `geolocator` for location, shared preferences for
  /// settings and the cache, `sensors_plus` for motion.
  factory AppServices.standard() {
    final client = http.Client();
    return AppServices(
      weather: OpenMeteoProvider(client),
      location: const GeolocatorLocationService(),
      places: OpenMeteoPlaceSearch(client),
      store: SharedPreferencesStore(),
      motion: const SensorsPlusMotionSource(),
      onDispose: client.close,
    );
  }

  final WeatherProvider weather;
  final LocationService location;
  final PlaceSearch places;
  final KeyValueStore store;
  final MotionSource motion;
  final void Function()? onDispose;

  void dispose() => onDispose?.call();
}
