import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/foundation.dart';

import '../location/location.dart';
import '../storage/key_value_store.dart';
import '../weather/ambient_wind.dart';
import '../weather/backoff.dart';
import '../weather/weather_cache.dart';
import '../weather/weather_provider.dart';
import '../weather/wind_timeline.dart';
import 'manual_wind.dart';

enum WindMode { live, manual }

/// Where the wind the chime is playing comes from right now.
enum WindSource {
  /// Real wind, fetched within [WindController.liveFor].
  live,

  /// Real wind from an older forecast that still covers now.
  cached,

  /// The built-in breeze: no location yet, or no usable forecast.
  ambient,
  manual,
}

/// Why live wind isn't (fully) working.
enum WindProblem {
  noLocation,
  locationDenied,
  locationDeniedForever,
  locationOff,
  locationUnavailable,
  offline,
  serviceError,
}

@immutable
class WindStatus {
  const WindStatus({
    required this.asOf,
    required this.mode,
    required this.source,
    required this.reading,
    required this.placement,
    required this.manual,
    this.location,
    this.updatedAt,
    this.problem,
    this.retryAt,
    this.busy = false,
    this.attribution = '',
  });

  /// When this status was computed; "updated 5 min ago" is measured from here.
  final DateTime asOf;
  final WindMode mode;
  final WindSource source;

  /// The 10 m wind being played.
  final WindReading reading;
  final Placement placement;
  final ManualWind manual;
  final LocationChoice? location;

  /// When the forecast being played was fetched.
  final DateTime? updatedAt;
  final WindProblem? problem;

  /// When the next automatic retry is due, while there is a problem.
  final DateTime? retryAt;

  /// Locating or fetching.
  final bool busy;
  final String attribution;
}

/// Decides which wind the chime plays and writes it into [SimInputs]:
///
/// * **Manual:** the user's sliders.
/// * **Live:** a forecast for the chosen location, fetched on launch, every ~30 minutes in the
///   foreground and on return to the app if it is 15 minutes old. Interpolated once a second.
///   While it can't be fetched: the cached forecast while it covers now, else the ambient breeze.
///
/// The simulation never waits for any of this: it plays the ambient breeze (or the cached
/// forecast) from the first frame, and every change after that eases in over [responseTime], so a
/// new forecast is never heard as a jump. Changes the user makes ease in faster.
///
/// Nothing is fetched in the background: [pause] stops the clock, [resume] restarts it.
class WindController {
  WindController({
    required this.inputs,
    required this._weather,
    required LocationService location,
    required this._store,
    DateTime Function()? clock,
    math.Random? random,
    this.ambient = const AmbientWind(),
  })  : _locator = location,
        _cache = WeatherCache(_store),
        _clock = clock ?? DateTime.now,
        _random = random ?? math.Random(),
        _backoff = Backoff(random: random) {
    status = ValueNotifier(_status(_clock()));
  }

  /// Data younger than this is "live"; after that, "cached" until the forecast runs out.
  static const liveFor = Duration(minutes: 40);
  static const refreshEvery = Duration(minutes: 30);
  static const refreshOnResumeAfter = Duration(minutes: 15);
  static const maxAge = Duration(hours: 24);

  /// Time constant for forecast changes to reach the chime, s.
  static const responseTime = 30.0;

  /// Time constant, and how long it applies, after the user changes something.
  static const userResponseTime = 5.0;
  static const userChangeWindow = Duration(seconds: 10);
  static const locationKey = 'wind.location.v1';

  final SimInputs inputs;
  final AmbientWind ambient;
  late final ValueNotifier<WindStatus> status;

  final WeatherProvider _weather;
  final LocationService _locator;
  final KeyValueStore _store;
  final WeatherCache _cache;
  final DateTime Function() _clock;
  final math.Random _random;
  final Backoff _backoff;

  WindMode _mode = WindMode.live;
  Placement _placement = Placement.garden;
  ManualWind _manual = const ManualWind();
  LocationChoice? _location;
  WeatherReport? _report;
  WindProblem? _problem;
  DateTime? _nextRefresh;
  DateTime? _snapUntil;
  DateTime? _quickUntil;
  bool _busy = false;
  bool _paused = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _timer;

  bool get isRunning => _timer != null;

  /// Restores the saved location and forecast, starts the chime in the best wind available and
  /// begins fetching. The first wind is applied at once rather than eased in.
  Future<void> start() async {
    _location = await _loadLocation();
    final cached = await _cache.load();
    if (_disposed) return;
    if (cached != null && cached.locationKey == _location?.key) _report = cached;
    final now = _clock();
    _snapUntil = now.add(const Duration(seconds: 1));
    _nextRefresh = now;
    if (_paused) {
      _update(now);
      return;
    }
    _startTimer();
    await tick();
  }

  /// Stops fetching and the once-a-second update, for when the app is hidden.
  void pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Restarts after [pause], refreshing now if the forecast is old or something had failed.
  void resume() {
    _paused = false;
    if (_disposed || isRunning) return;
    _refreshIfStale(_clock());
    _startTimer();
    unawaited(tick());
  }

  void dispose() {
    _disposed = true;
    _generation++;
    pause();
    status.dispose();
  }

  /// Once a second: fetch if due, and write the current wind into [inputs].
  Future<void> tick() {
    if (_disposed) return Future.value();
    final now = _clock();
    final next = _nextRefresh;
    Future<void>? work;
    if (_mode == WindMode.live &&
        _location != null &&
        !_busy &&
        next != null &&
        !now.isBefore(next)) {
      work = _refresh();
    }
    _update(now);
    return work ?? Future.value();
  }

  void setMode(WindMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    final now = _clock();
    _userChanged(now);
    if (mode == WindMode.live) _refreshIfStale(now);
    unawaited(tick());
  }

  void setManual(ManualWind manual) {
    _manual = manual;
    _update(_clock());
  }

  void setPlacement(Placement placement) {
    _placement = placement;
    final now = _clock();
    _userChanged(now);
    _update(now);
  }

  /// Plays the live wind at [place] from now on.
  Future<void> usePlace(Place place) => _choose(place, null);

  /// Asks for the phone's location (showing the permission prompt if needed) and plays the wind
  /// there. On failure, returns why and keeps the previous choice.
  Future<LocationFailure?> useDeviceLocation() async {
    final generation = ++_generation;
    _busy = true;
    _update(_clock());
    try {
      final here = await _locator.current(ask: true);
      if (generation != _generation) return null;
      await _choose(const DeviceLocation(), here);
      return null;
    } on LocationException catch (e) {
      if (generation == _generation) {
        _busy = false;
        _update(_clock());
      }
      return e.reason;
    }
  }

  Future<void> _choose(LocationChoice choice, Coordinates? at) {
    if (choice.key != _location?.key) _report = null;
    _location = choice;
    unawaited(_saveLocation(choice));
    _mode = WindMode.live;
    _problem = null;
    _backoff.reset();
    _generation++;
    _busy = false;
    _userChanged(_clock());
    return _refresh(at: at);
  }

  /// What the user changes eases in faster than weather does (and ends the launch snap).
  void _userChanged(DateTime now) {
    _snapUntil = null;
    _quickUntil = now.add(userChangeWindow);
  }

  void _refreshIfStale(DateTime now) {
    final report = _report;
    if (report == null ||
        now.difference(report.fetchedAt) > refreshOnResumeAfter ||
        _problem != null) {
      _backoff.reset();
      _nextRefresh = now;
    }
  }

  Future<void> _refresh({Coordinates? at}) async {
    final choice = _location;
    if (choice == null) return;
    final generation = _generation;
    _busy = true;
    _update(_clock());
    try {
      final coordinates = (at ?? switch (choice) {
                Place(:final coordinates) => coordinates,
                DeviceLocation() => await _locate(),
              })
          .rounded;
      final timeline = await _weather.fetchWind(coordinates);
      if (generation != _generation) return;
      final now = _clock();
      final report = WeatherReport(
        locationKey: choice.key,
        coordinates: coordinates,
        fetchedAt: now,
        timeline: timeline,
      );
      _report = report;
      _problem = null;
      _backoff.reset();
      _nextRefresh = now.add(refreshEvery * (0.9 + 0.2 * _random.nextDouble()));
      unawaited(_cache.save(report));
    } on LocationException catch (e) {
      if (generation != _generation) return;
      _problem = switch (e.reason) {
        LocationFailure.denied => WindProblem.locationDenied,
        LocationFailure.deniedForever => WindProblem.locationDeniedForever,
        LocationFailure.servicesOff => WindProblem.locationOff,
        LocationFailure.unavailable => WindProblem.locationUnavailable,
      };
      // Permission only changes through the user: wait for them, or for a return to the app.
      _nextRefresh = e.reason == LocationFailure.unavailable
          ? _clock().add(_backoff.next())
          : null;
    } on WeatherException catch (e) {
      if (generation != _generation) return;
      _problem =
          e.failure == WeatherFailure.offline ? WindProblem.offline : WindProblem.serviceError;
      _nextRefresh = _clock().add(_backoff.next());
    } catch (_) {
      if (generation != _generation) return;
      _problem = WindProblem.serviceError;
      _nextRefresh = _clock().add(_backoff.next());
    } finally {
      if (generation == _generation && !_disposed) {
        _busy = false;
        _update(_clock());
      }
    }
  }

  /// The phone's position; if there's no fix right now, the last one that worked, since a phone
  /// rarely moves far between refreshes.
  Future<Coordinates> _locate() async {
    try {
      return await _locator.current();
    } on LocationException catch (e) {
      final previous = _report;
      if (e.reason != LocationFailure.unavailable || previous == null) rethrow;
      if (previous.locationKey != const DeviceLocation().key) rethrow;
      return previous.coordinates;
    }
  }

  /// The forecast to play at [now], if there is one for the current location that covers it.
  WeatherReport? _usableReport(DateTime now) {
    final report = _report;
    if (report == null || report.locationKey != _location?.key) return null;
    if (now.difference(report.fetchedAt) > maxAge || !report.timeline.covers(now)) return null;
    return report;
  }

  WindSource _source(DateTime now) {
    if (_mode == WindMode.manual) return WindSource.manual;
    final report = _usableReport(now);
    if (report == null) return WindSource.ambient;
    return now.difference(report.fetchedAt) < liveFor ? WindSource.live : WindSource.cached;
  }

  WindReading _reading(DateTime now, WindSource source) => switch (source) {
        WindSource.manual => _manual.reading,
        WindSource.ambient => ambient.at(now),
        WindSource.live || WindSource.cached => _usableReport(now)!.timeline.at(now),
      };

  void _update(DateTime now) {
    if (_disposed) return;
    final source = _source(now);
    final reading = _reading(now, source);
    final snapUntil = _snapUntil, quickUntil = _quickUntil;
    inputs
      ..windSpeed = reading.speed
      ..windGust = reading.gust
      ..windDirection = reading.direction
      ..placement = _placement
      ..windResponseTime = switch (source) {
        _ when snapUntil != null && now.isBefore(snapUntil) => 0,
        WindSource.manual => ManualWind.responseTime,
        _ when quickUntil != null && now.isBefore(quickUntil) => userResponseTime,
        _ => responseTime,
      };
    status.value = _status(now, source: source, reading: reading);
  }

  WindStatus _status(DateTime now, {WindSource? source, WindReading? reading}) {
    source ??= _source(now);
    final live = _mode == WindMode.live;
    final problem = _problem ?? (live && _location == null ? WindProblem.noLocation : null);
    return WindStatus(
      asOf: now,
      mode: _mode,
      source: source,
      reading: reading ?? _reading(now, source),
      placement: _placement,
      manual: _manual,
      location: _location,
      updatedAt: live ? _usableReport(now)?.fetchedAt : null,
      problem: live ? problem : null,
      retryAt: live && _problem != null ? _nextRefresh : null,
      busy: _busy,
      attribution: _weather.attribution,
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<LocationChoice?> _loadLocation() async {
    try {
      final text = await _store.read(locationKey);
      if (text == null) return null;
      return LocationChoice.fromJson(jsonDecode(text) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLocation(LocationChoice choice) async {
    try {
      await _store.write(locationKey, jsonEncode(choice.toJson()));
    } catch (_) {
      // Only costs picking the place again next launch.
    }
  }
}
