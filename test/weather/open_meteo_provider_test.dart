import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wind_chimes/location/location.dart';
import 'package:wind_chimes/weather/open_meteo_provider.dart';
import 'package:wind_chimes/weather/weather_provider.dart';

/// Shaped like a real response (Berlin, 2026-09-24).
Map<String, Object?> response({
  List<Object?> times = const [1790244900, 1790245800, 1790246700],
  List<Object?> speeds = const [4.22, 4.53, 4.75],
  List<Object?> directions = const [301, 301, 300],
  List<Object?>? gusts = const [10.8, 10.9, 11.1],
}) =>
    {
      'latitude': 52.52,
      'longitude': 13.419998,
      'utc_offset_seconds': 0,
      'minutely_15_units': {'time': 'unixtime', 'wind_speed_10m': 'm/s'},
      'minutely_15': {
        'time': times,
        'wind_speed_10m': speeds,
        'wind_direction_10m': directions,
        'wind_gusts_10m': ?gusts,
      },
    };

void main() {
  const berlin = Coordinates(52.520008, 13.404954);

  test('asks for a day of 15-minute wind in m/s at rounded coordinates', () {
    final uri = OpenMeteoProvider.uriFor(berlin);
    expect(uri.host, 'api.open-meteo.com');
    expect(uri.queryParameters['latitude'], '52.52');
    expect(uri.queryParameters['longitude'], '13.40');
    expect(uri.queryParameters['minutely_15'], 'wind_speed_10m,wind_direction_10m,wind_gusts_10m');
    expect(uri.queryParameters['forecast_minutely_15'], '96');
    expect(uri.queryParameters['wind_speed_unit'], 'ms');
    expect(uri.queryParameters['timeformat'], 'unixtime');
  });

  test('parses a response into a timeline', () async {
    final provider = OpenMeteoProvider(MockClient((request) async {
      expect(request.url.queryParameters['latitude'], '52.52');
      return http.Response(jsonEncode(response()), 200);
    }));
    final timeline = await provider.fetchWind(berlin);
    expect(timeline.samples.length, 3);
    expect(timeline.start, DateTime.fromMillisecondsSinceEpoch(1790244900000, isUtc: true));
    expect(timeline.samples[1].reading.speed, 4.53);
    expect(timeline.samples[1].reading.gust, 10.9);
    expect(timeline.samples[2].reading.direction, 300);
  });

  test('skips missing or implausible values and fills in missing gusts', () {
    final timeline = OpenMeteoProvider.parse(response(
      times: [1, 2, 3, 4, 5],
      speeds: [3, null, 80, 2, 5],
      directions: [90, 90, 90, 400, 360],
      gusts: [null, 5, 5, 5, 4],
    ));
    expect(timeline.samples.length, 2);
    final first = timeline.samples[0].reading, last = timeline.samples[1].reading;
    expect(first.gust, 3 * OpenMeteoProvider.defaultGustFactor);
    expect(last.gust, 5, reason: 'a gust below the mean is raised to it');
    expect(last.direction, 0);
  });

  test('a response with no gust series still works', () {
    final timeline = OpenMeteoProvider.parse(response(gusts: null));
    expect(timeline.samples.first.reading.gust, closeTo(4.22 * 1.5, 1e-9));
  });

  test('network failures and timeouts are "offline"', () async {
    final unreachable = OpenMeteoProvider(
      MockClient((_) async => throw http.ClientException('Failed host lookup')),
    );
    await expectLater(
      unreachable.fetchWind(berlin),
      throwsA(isA<WeatherException>().having((e) => e.failure, 'failure', WeatherFailure.offline)),
    );
    final slow = OpenMeteoProvider(
      MockClient((_) => Future.delayed(const Duration(seconds: 1), () => http.Response('', 200))),
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      slow.fetchWind(berlin),
      throwsA(isA<WeatherException>().having((e) => e.failure, 'failure', WeatherFailure.offline)),
    );
  });

  test('error statuses and unusable bodies are "bad response"', () async {
    for (final (status, body) in [
      (400, '{"error":true,"reason":"Latitude must be in range of -90 to 90°."}'),
      (200, 'not json'),
      (200, '{"minutely_15":{"time":[1],"wind_speed_10m":[null],"wind_direction_10m":[90]}}'),
      (200, '{}'),
    ]) {
      final provider = OpenMeteoProvider(MockClient((_) async => http.Response(body, status)));
      await expectLater(
        provider.fetchWind(berlin),
        throwsA(isA<WeatherException>()
            .having((e) => e.failure, 'failure', WeatherFailure.badResponse)),
        reason: body,
      );
    }
  });
}
