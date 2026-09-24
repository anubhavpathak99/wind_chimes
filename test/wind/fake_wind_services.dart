import 'dart:async';

import 'package:wind_chimes/location/location.dart';
import 'package:wind_chimes/storage/key_value_store.dart';
import 'package:wind_chimes/weather/weather_provider.dart';
import 'package:wind_chimes/weather/wind_timeline.dart';
import 'package:wind_chimes/wind/wind_services.dart';

/// A timeline of steady wind from [from] for [hours], starting at [start].
WindTimeline steadyTimeline(
  DateTime start, {
  double speed = 6,
  double gust = 9,
  double direction = 200,
  int hours = 24,
}) =>
    WindTimeline([
      for (var i = 0; i <= hours * 4; i++)
        WindSample(
          start.add(Duration(minutes: 15 * i)),
          WindReading(speed: speed, gust: gust, direction: direction),
        ),
    ]);

/// Answers with [respond], or fails with [failure] if set. Records every request.
class FakeWeather implements WeatherProvider {
  FakeWeather({this.respond, this.failure});

  WindTimeline Function(Coordinates at)? respond;
  WeatherFailure? failure;

  /// When set, requests wait for the test to complete it.
  Completer<void>? gate;
  final requests = <Coordinates>[];

  @override
  String get attribution => 'Fake weather';

  @override
  Future<WindTimeline> fetchWind(Coordinates at) async {
    requests.add(at);
    await gate?.future;
    final failure = this.failure;
    if (failure != null) throw WeatherException(failure);
    final respond = this.respond;
    if (respond == null) throw const WeatherException(WeatherFailure.offline);
    return respond(at);
  }
}

class FakeLocation implements LocationService {
  FakeLocation({this.here = const Coordinates(48.13743, 11.57549), this.failure});

  Coordinates here;
  LocationFailure? failure;

  /// Whether the permission prompt would show: set by a request with `ask`.
  bool asked = false;
  int calls = 0;

  @override
  Future<Coordinates> current({bool ask = false}) async {
    calls++;
    if (ask) asked = true;
    final failure = this.failure;
    if (failure != null) throw LocationException(failure);
    return here;
  }
}

class FakePlaces implements PlaceSearch {
  List<Place> results = const [];

  @override
  Future<List<Place>> search(String query) async => results;
}

/// Offline by default: no network, no location chosen.
WindServices fakeWindServices({FakeWeather? weather, KeyValueStore? store}) => WindServices(
      weather: weather ?? FakeWeather(),
      location: FakeLocation(),
      places: FakePlaces(),
      store: store ?? MemoryStore(),
    );
