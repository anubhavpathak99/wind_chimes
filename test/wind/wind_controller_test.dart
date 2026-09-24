import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/location/location.dart';
import 'package:wind_chimes/storage/key_value_store.dart';
import 'package:wind_chimes/weather/ambient_wind.dart';
import 'package:wind_chimes/weather/weather_cache.dart';
import 'package:wind_chimes/weather/weather_provider.dart';
import 'package:wind_chimes/weather/wind_timeline.dart';
import 'package:wind_chimes/wind/manual_wind.dart';
import 'package:wind_chimes/wind/wind_controller.dart';

import 'fake_wind_services.dart';

const munich = Place(
  name: 'Munich',
  detail: 'Bavaria, Germany',
  coordinates: Coordinates(48.13743, 11.57549),
);
const oslo = Place(name: 'Oslo', coordinates: Coordinates(59.91, 10.75));

void main() {
  late DateTime now;
  late SimInputs inputs;
  late FakeWeather weather;
  late FakeLocation location;
  late MemoryStore store;
  late WindController wind;

  WindController controller() => wind = WindController(
        inputs: inputs,
        weather: weather,
        location: location,
        store: store,
        clock: () => now,
        random: math.Random(1),
      );

  /// Moves the clock on, ticking once a second as the app does, and lets fetches finish.
  Future<void> advance(Duration by) async {
    final end = now.add(by);
    while (now.isBefore(end)) {
      now = now.add(const Duration(seconds: 1));
      await wind.tick();
    }
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  void remember(LocationChoice choice) =>
      store.values[WindController.locationKey] = jsonEncode(choice.toJson());

  Future<void> cache(LocationChoice choice, DateTime fetchedAt, {double speed = 6}) =>
      WeatherCache(store).save(WeatherReport(
        locationKey: choice.key,
        coordinates: const Coordinates(0, 0),
        fetchedAt: fetchedAt,
        timeline: steadyTimeline(fetchedAt, speed: speed, gust: speed * 1.5),
      ));

  setUp(() {
    now = DateTime.utc(2026, 9, 24, 12);
    inputs = SimInputs();
    weather = FakeWeather();
    location = FakeLocation();
    store = MemoryStore();
  });

  tearDown(() => wind.dispose());

  group('first launch', () {
    test('plays the ambient breeze at once, without asking for location', () async {
      await controller().start();
      final s = wind.status.value;
      expect(s.source, WindSource.ambient);
      expect(s.problem, WindProblem.noLocation);
      expect(inputs.windSpeed, const AmbientWind().at(now).speed);
      expect(inputs.windResponseTime, 0, reason: 'the first wind is applied, not eased in');
      expect(weather.requests, isEmpty);
      expect(location.calls, 0);
    });

    test('after the first second, changes ease in', () async {
      await controller().start();
      await advance(const Duration(seconds: 2));
      expect(inputs.windResponseTime, WindController.responseTime);
    });
  });

  group('live wind', () {
    test('fetches for a remembered place and plays the forecast', () async {
      remember(munich);
      weather.respond = (_) => steadyTimeline(now, speed: 7, gust: 12, direction: 200);
      await controller().start();
      expect(weather.requests.single, const Coordinates(48.14, 11.58), reason: 'rounded');
      final s = wind.status.value;
      expect(s.source, WindSource.live);
      expect(s.updatedAt, now);
      expect(s.problem, isNull);
      expect(inputs.windSpeed, 7);
      expect(inputs.windGust, 12);
      expect(inputs.windDirection, 200);
    });

    test('interpolates along the forecast as time passes', () async {
      remember(munich);
      weather.respond = (_) => WindTimeline([
            WindSample(now, const WindReading(speed: 2, gust: 3, direction: 270)),
            WindSample(now.add(const Duration(minutes: 15)),
                const WindReading(speed: 8, gust: 12, direction: 270)),
            WindSample(now.add(const Duration(hours: 6)),
                const WindReading(speed: 8, gust: 12, direction: 270)),
          ]);
      await controller().start();
      await advance(const Duration(minutes: 5));
      expect(inputs.windSpeed, closeTo(4, 1e-6));
    });

    test('refreshes about every 30 minutes', () async {
      remember(munich);
      weather.respond = (_) => steadyTimeline(now);
      await controller().start();
      await advance(const Duration(minutes: 26));
      expect(weather.requests.length, 1);
      await advance(const Duration(minutes: 8));
      expect(weather.requests.length, 2);
      expect(wind.status.value.source, WindSource.live);
    });

    test('a new forecast eases in over the weather response time', () async {
      remember(munich);
      weather.respond = (_) => steadyTimeline(now, speed: 3);
      await controller().start();
      await advance(const Duration(seconds: 20));
      weather.respond = (_) => steadyTimeline(now, speed: 12);
      await advance(const Duration(minutes: 35));
      expect(inputs.windSpeed, 12);
      expect(inputs.windResponseTime, WindController.responseTime);
    });

    test('uses the phone location when chosen, without prompting on launch', () async {
      remember(const DeviceLocation());
      location.here = const Coordinates(52.520008, 13.404954);
      weather.respond = (_) => steadyTimeline(now);
      await controller().start();
      expect(location.asked, isFalse);
      expect(weather.requests.single, const Coordinates(52.52, 13.40));
      expect(wind.status.value.source, WindSource.live);
    });
  });

  group('offline', () {
    test('an airplane-mode launch with no cache plays the ambient breeze and retries', () async {
      remember(munich);
      await controller().start();
      var s = wind.status.value;
      expect(s.source, WindSource.ambient);
      expect(s.problem, WindProblem.offline);
      expect(inputs.windSpeed, greaterThan(1));
      final retry = s.retryAt!.difference(now);
      expect(retry.inSeconds, inInclusiveRange(24, 36));

      await advance(retry - const Duration(seconds: 2));
      expect(weather.requests.length, 1, reason: 'not before the retry is due');
      weather.respond = (_) => steadyTimeline(now);
      await advance(const Duration(seconds: 3));
      expect(weather.requests.length, 2);
      s = wind.status.value;
      expect(s.source, WindSource.live);
      expect(s.problem, isNull);
    });

    test('retries back off: 30 s, 1 min, 2 min…', () async {
      remember(munich);
      await controller().start();
      final gaps = <int>[];
      var last = now;
      while (weather.requests.length < 5) {
        final before = weather.requests.length;
        await advance(const Duration(seconds: 1));
        if (weather.requests.length > before) {
          gaps.add(now.difference(last).inSeconds);
          last = now;
        }
      }
      expect(gaps[0], inInclusiveRange(24, 37));
      expect(gaps[1], inInclusiveRange(48, 73));
      expect(gaps[2], inInclusiveRange(96, 145));
      expect(gaps[3], inInclusiveRange(192, 289));
    });

    test('an airplane-mode launch plays the cached forecast', () async {
      remember(munich);
      await cache(munich, now.subtract(const Duration(hours: 3)), speed: 9);
      await controller().start();
      final s = wind.status.value;
      expect(s.source, WindSource.cached);
      expect(s.problem, WindProblem.offline);
      expect(s.updatedAt, now.subtract(const Duration(hours: 3)));
      expect(inputs.windSpeed, 9);
      expect(inputs.windResponseTime, 0, reason: 'the cached wind is the first wind');
    });

    test('a forecast that has run out is not played', () async {
      remember(munich);
      await cache(munich, now.subtract(const Duration(hours: 25)));
      await controller().start();
      expect(wind.status.value.source, WindSource.ambient);
    });

    test('a forecast for another place is not played', () async {
      remember(oslo);
      await cache(munich, now.subtract(const Duration(minutes: 5)));
      await controller().start();
      expect(wind.status.value.source, WindSource.ambient);
    });

    test('live data goes stale, then falls back to the breeze once the forecast ends', () async {
      remember(munich);
      weather.respond = (_) => steadyTimeline(now, hours: 2);
      await controller().start();
      weather.respond = null;
      await advance(const Duration(minutes: 39));
      expect(wind.status.value.source, WindSource.live);
      await advance(const Duration(minutes: 2));
      expect(wind.status.value.source, WindSource.cached);
      await advance(const Duration(hours: 2));
      expect(wind.status.value.source, WindSource.ambient);
    });

    test('a service error is reported as such and retried', () async {
      remember(munich);
      weather.failure = WeatherFailure.badResponse;
      await controller().start();
      expect(wind.status.value.problem, WindProblem.serviceError);
      expect(wind.status.value.retryAt, isNotNull);
    });
  });

  group('lifecycle', () {
    test('nothing is fetched while paused; returning refreshes old data', () async {
      remember(munich);
      weather.respond = (_) => steadyTimeline(now);
      await controller().start();
      wind.pause();
      expect(wind.isRunning, isFalse);
      now = now.add(const Duration(minutes: 5));
      wind.resume();
      await settle();
      expect(weather.requests.length, 1, reason: 'five minutes is fresh enough');

      wind.pause();
      now = now.add(const Duration(minutes: 20));
      wind.resume();
      await settle();
      expect(weather.requests.length, 2);
    });

    test('returning to the app retries at once after a failure', () async {
      remember(munich);
      await controller().start();
      wind.pause();
      now = now.add(const Duration(seconds: 5));
      weather.respond = (_) => steadyTimeline(now);
      wind.resume();
      await settle();
      expect(weather.requests.length, 2);
      expect(wind.status.value.source, WindSource.live);
    });
  });

  group('choices', () {
    test('manual mode plays the sliders, snappily, and does not fetch', () async {
      await controller().start();
      wind.setMode(WindMode.manual);
      wind.setManual(const ManualWind(speed: 10, direction: 90, gustFactor: 2));
      expect(wind.status.value.source, WindSource.manual);
      expect(inputs.windSpeed, 10);
      expect(inputs.windGust, 20);
      expect(inputs.windResponseTime, ManualWind.responseTime);
      wind.setMode(WindMode.live);
      expect(inputs.windResponseTime, WindController.userResponseTime);
      await advance(const Duration(seconds: 11));
      expect(inputs.windResponseTime, WindController.responseTime);
    });

    test('placement reaches the simulation', () async {
      await controller().start();
      wind.setPlacement(Placement.open);
      expect(inputs.placement, Placement.open);
      expect(wind.status.value.placement, Placement.open);
    });

    test('picking a place fetches it, eases it in quickly and remembers it', () async {
      weather.respond = (_) => steadyTimeline(now, speed: 5);
      await controller().start();
      await wind.usePlace(munich);
      expect(wind.status.value.source, WindSource.live);
      expect(wind.status.value.location, munich);
      expect(inputs.windResponseTime, WindController.userResponseTime);
      expect(LocationChoice.fromJson(jsonDecode(store.values[WindController.locationKey]!)),
          munich);
      expect(store.values[WeatherCache.key], isNotNull);
    });

    test('using the phone location asks for permission, then fetches there', () async {
      location.here = const Coordinates(40.4168, -3.7038);
      weather.respond = (_) => steadyTimeline(now);
      await controller().start();
      final failure = await wind.useDeviceLocation();
      expect(failure, isNull);
      expect(location.asked, isTrue);
      expect(location.calls, 1, reason: 'the fix from the permission step is reused');
      expect(weather.requests.single, const Coordinates(40.42, -3.70));
      expect(wind.status.value.location, const DeviceLocation());
    });

    test('a declined permission keeps the previous place', () async {
      remember(munich);
      weather.respond = (_) => steadyTimeline(now);
      await controller().start();
      location.failure = LocationFailure.denied;
      expect(await wind.useDeviceLocation(), LocationFailure.denied);
      expect(wind.status.value.location, munich);
      expect(wind.status.value.source, WindSource.live);
      expect(wind.status.value.busy, isFalse);
    });

    test('permission revoked while away: breeze, no prompt, no retry loop', () async {
      remember(const DeviceLocation());
      location.failure = LocationFailure.denied;
      await controller().start();
      expect(wind.status.value.problem, WindProblem.locationDenied);
      expect(wind.status.value.source, WindSource.ambient);
      expect(location.asked, isFalse);
      await advance(const Duration(minutes: 30));
      expect(location.calls, 1);
    });

    test('no fix on a refresh: the last position is reused', () async {
      remember(const DeviceLocation());
      location.here = const Coordinates(52.520008, 13.404954);
      weather.respond = (_) => steadyTimeline(now);
      await controller().start();
      location.failure = LocationFailure.unavailable;
      await advance(const Duration(minutes: 34));
      expect(weather.requests, hasLength(2));
      expect(weather.requests.last, const Coordinates(52.52, 13.40));
      expect(wind.status.value.problem, isNull);
    });

    test('a slow answer for the old place is dropped after switching', () async {
      remember(munich);
      weather.respond = (at) => steadyTimeline(now, speed: at.latitude > 50 ? 4 : 11);
      weather.gate = Completer();
      unawaited(controller().start());
      await settle();
      expect(weather.requests.single.latitude, closeTo(48.14, 1e-9));
      final switched = wind.usePlace(oslo);
      weather.gate!.complete();
      await switched;
      await settle();
      expect(wind.status.value.location, oslo);
      expect(inputs.windSpeed, 4);
    });
  });
}
