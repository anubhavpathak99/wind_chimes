import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../location/location.dart';
import 'weather_provider.dart';
import 'wind_timeline.dart';

/// Wind from Open-Meteo: no key, 15-minute steps, speeds in m/s. The free tier is for
/// non-commercial use only.
class OpenMeteoProvider implements WeatherProvider {
  OpenMeteoProvider(this._client, {this.timeout = const Duration(seconds: 8)});

  /// A day of 15-minute steps: a single fetch keeps the chime on real wind through a day offline.
  static const forecastSteps = 96;

  /// Used when the service has no gust value; typical over land.
  static const defaultGustFactor = 1.5;
  static const maxSpeed = 75.0;

  final http.Client _client;
  final Duration timeout;

  @override
  String get attribution => 'Weather data by Open-Meteo.com';

  static Uri uriFor(Coordinates at) {
    final c = at.rounded;
    return Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': c.latitude.toStringAsFixed(2),
      'longitude': c.longitude.toStringAsFixed(2),
      'minutely_15': 'wind_speed_10m,wind_direction_10m,wind_gusts_10m',
      'past_minutely_15': '1',
      'forecast_minutely_15': '$forecastSteps',
      'wind_speed_unit': 'ms',
      'timeformat': 'unixtime',
    });
  }

  @override
  Future<WindTimeline> fetchWind(Coordinates at) async {
    final http.Response response;
    try {
      response = await _client.get(uriFor(at)).timeout(timeout);
    } on TimeoutException {
      throw const WeatherException(WeatherFailure.offline, 'timed out');
    } catch (e) {
      throw WeatherException(WeatherFailure.offline, '$e');
    }
    if (response.statusCode != 200) {
      throw WeatherException(WeatherFailure.badResponse, 'HTTP ${response.statusCode}');
    }
    try {
      return parse(jsonDecode(response.body) as Map<String, dynamic>);
    } on WeatherException {
      rethrow;
    } catch (e) {
      throw WeatherException(WeatherFailure.badResponse, '$e');
    }
  }

  /// Builds a timeline from a response, skipping steps with missing or implausible values.
  static WindTimeline parse(Map<String, dynamic> json) {
    final series = json['minutely_15'] as Map<String, dynamic>;
    final times = series['time'] as List<dynamic>;
    final speeds = series['wind_speed_10m'] as List<dynamic>;
    final directions = series['wind_direction_10m'] as List<dynamic>;
    final gusts = series['wind_gusts_10m'] as List<dynamic>?;

    final samples = <WindSample>[];
    for (var i = 0; i < times.length; i++) {
      final time = times[i], speed = _at(speeds, i), direction = _at(directions, i);
      if (time is! num || speed == null || direction == null) continue;
      if (speed < 0 || speed > maxSpeed || direction < 0 || direction > 360) continue;
      var gust = _at(gusts, i);
      if (gust == null || gust > maxSpeed * 1.5) gust = speed * defaultGustFactor;
      samples.add(WindSample(
        DateTime.fromMillisecondsSinceEpoch(time.toInt() * 1000, isUtc: true),
        WindReading(speed: speed, gust: gust < speed ? speed : gust, direction: direction % 360),
      ));
    }
    if (samples.isEmpty) {
      throw const WeatherException(WeatherFailure.badResponse, 'no usable wind values');
    }
    return WindTimeline(samples);
  }

  static double? _at(List<dynamic>? values, int i) {
    if (values == null || i >= values.length) return null;
    final v = values[i];
    return v is num && v.isFinite ? v.toDouble() : null;
  }
}
