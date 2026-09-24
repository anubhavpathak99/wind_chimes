import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Wind as a weather service reports it: 10 m mean speed, gust speed (m/s) and the direction it
/// comes from (degrees clockwise from north).
@immutable
class WindReading {
  const WindReading({required this.speed, required this.gust, required this.direction});

  final double speed;
  final double gust;
  final double direction;

  /// Eight-point compass name for [direction].
  String get compass => compassName(direction);

  static String compassName(double degrees) =>
      const ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][((degrees % 360 + 22.5) ~/ 45) % 8];

  @override
  bool operator ==(Object other) =>
      other is WindReading &&
      other.speed == speed &&
      other.gust == gust &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(speed, gust, direction);

  @override
  String toString() =>
      'WindReading(${speed.toStringAsFixed(1)} m/s, gust ${gust.toStringAsFixed(1)}, '
      '${direction.round()}°)';
}

/// One forecast step.
@immutable
class WindSample {
  const WindSample(this.time, this.reading);

  final DateTime time;
  final WindReading reading;
}

/// A short forecast, interpolated to give the wind at any moment it covers. Fetching a timeline
/// instead of a single value means fewer calls, smooth transitions and hours of offline data.
@immutable
class WindTimeline {
  WindTimeline(List<WindSample> samples)
      : samples = List.unmodifiable([...samples]..sort((a, b) => a.time.compareTo(b.time))) {
    if (samples.isEmpty) throw ArgumentError.value(samples, 'samples', 'must not be empty');
  }

  /// How far past either end the timeline is still trusted, holding the end value.
  static const slack = Duration(minutes: 15);

  final List<WindSample> samples;

  DateTime get start => samples.first.time;
  DateTime get end => samples.last.time;

  bool covers(DateTime time) =>
      !time.isBefore(start.subtract(slack)) && !time.isAfter(end.add(slack));

  /// The wind at [time], held at the end values outside the timeline. Speed and gust are
  /// interpolated linearly; direction as a vector, so 350° → 10° passes through north.
  WindReading at(DateTime time) {
    if (!time.isAfter(start)) return samples.first.reading;
    if (!time.isBefore(end)) return samples.last.reading;
    var i = 1;
    while (samples[i].time.isBefore(time)) {
      i++;
    }
    final a = samples[i - 1], b = samples[i];
    final span = b.time.difference(a.time).inMicroseconds;
    final f = span <= 0 ? 1.0 : time.difference(a.time).inMicroseconds / span;
    final ra = a.reading, rb = b.reading;
    return WindReading(
      speed: _lerp(ra.speed, rb.speed, f),
      gust: _lerp(ra.gust, rb.gust, f),
      direction: _blendDirection(ra, rb, f),
    );
  }

  List<List<num>> toJson() => [
        for (final s in samples)
          [
            s.time.millisecondsSinceEpoch ~/ 1000,
            s.reading.speed,
            s.reading.gust,
            s.reading.direction,
          ],
      ];

  factory WindTimeline.fromJson(List<dynamic> json) => WindTimeline([
        for (final row in json.cast<List<dynamic>>())
          WindSample(
            DateTime.fromMillisecondsSinceEpoch((row[0] as num).toInt() * 1000, isUtc: true),
            WindReading(
              speed: (row[1] as num).toDouble(),
              gust: (row[2] as num).toDouble(),
              direction: (row[3] as num).toDouble(),
            ),
          ),
      ]);
}

double _lerp(double a, double b, double f) => a + (b - a) * f;

/// Direction from the speed-weighted blend of the two wind vectors; the nearer sample's direction
/// when the blend is calm.
double _blendDirection(WindReading a, WindReading b, double f) {
  const toRadians = math.pi / 180;
  final ta = a.direction * toRadians, tb = b.direction * toRadians;
  final x = _lerp(a.speed * math.sin(ta), b.speed * math.sin(tb), f);
  final y = _lerp(a.speed * math.cos(ta), b.speed * math.cos(tb), f);
  if (x * x + y * y < 1e-6) return f < 0.5 ? a.direction : b.direction;
  return (math.atan2(x, y) / toRadians) % 360;
}
