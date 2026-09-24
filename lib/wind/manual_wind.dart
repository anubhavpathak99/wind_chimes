import 'package:flutter/foundation.dart';

import '../weather/wind_timeline.dart';

/// Wind the user dials in by hand, in the same terms a weather service reports: 10 m mean speed,
/// gust factor and the direction it comes from.
@immutable
class ManualWind {
  const ManualWind({this.speed = 3, this.direction = 270, this.gustFactor = 1.5});

  /// Manual changes should be felt quickly; weather updates ease in over ~30 s instead.
  static const responseTime = 2.0;

  /// Mean wind at 10 m, m/s.
  final double speed;

  /// Degrees clockwise from north that the wind comes from.
  final double direction;
  final double gustFactor;

  WindReading get reading =>
      WindReading(speed: speed, gust: speed * gustFactor, direction: direction);

  String get compass => WindReading.compassName(direction);

  ManualWind copyWith({double? speed, double? direction, double? gustFactor}) => ManualWind(
        speed: speed ?? this.speed,
        direction: direction ?? this.direction,
        gustFactor: gustFactor ?? this.gustFactor,
      );
}
