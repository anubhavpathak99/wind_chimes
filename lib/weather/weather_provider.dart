import '../location/location.dart';
import 'wind_timeline.dart';

/// A source of wind forecasts. Open-Meteo while building; MET Norway can replace it for a
/// commercial release without touching anything else.
abstract interface class WeatherProvider {
  /// Credit to show with the data.
  String get attribution;

  /// A forecast timeline starting at about now. Throws [WeatherException].
  Future<WindTimeline> fetchWind(Coordinates at);
}

enum WeatherFailure {
  /// No answer: offline, timed out, or the service is unreachable. Worth retrying.
  offline,

  /// An answer that can't be used: an error status or data that fails validation.
  badResponse,
}

class WeatherException implements Exception {
  const WeatherException(this.failure, [this.message = '']);

  final WeatherFailure failure;
  final String message;

  @override
  String toString() => 'WeatherException(${failure.name}${message.isEmpty ? '' : ': $message'})';
}
