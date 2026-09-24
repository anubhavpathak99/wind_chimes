import 'package:http/http.dart' as http;

import '../location/geolocator_location_service.dart';
import '../location/location.dart';
import '../location/open_meteo_place_search.dart';
import '../storage/key_value_store.dart';
import '../weather/open_meteo_provider.dart';
import '../weather/weather_provider.dart';

/// Everything live wind needs from outside the app, replaceable in tests.
class WindServices {
  WindServices({
    required this.weather,
    required this.location,
    required this.places,
    required this.store,
    this.onDispose,
  });

  /// Open-Meteo for forecasts and city search, `geolocator` for location, shared preferences for
  /// the cache.
  factory WindServices.standard() {
    final client = http.Client();
    return WindServices(
      weather: OpenMeteoProvider(client),
      location: const GeolocatorLocationService(),
      places: OpenMeteoPlaceSearch(client),
      store: SharedPreferencesStore(),
      onDispose: client.close,
    );
  }

  final WeatherProvider weather;
  final LocationService location;
  final PlaceSearch places;
  final KeyValueStore store;
  final void Function()? onDispose;

  void dispose() => onDispose?.call();
}
