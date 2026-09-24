import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/foundation.dart';

/// Wind the user dials in by hand, in the same terms a weather service reports: 10 m mean speed,
/// gust factor and the direction it comes from.
@immutable
class ManualWind {
  const ManualWind({
    this.speed = 3,
    this.direction = 270,
    this.gustFactor = 1.5,
    this.placement = Placement.garden,
  });

  /// Manual changes should be felt quickly; weather updates ease in over ~30 s instead.
  static const responseTime = 2.0;

  /// Mean wind at 10 m, m/s.
  final double speed;

  /// Degrees clockwise from north that the wind comes from.
  final double direction;
  final double gustFactor;
  final Placement placement;

  /// Mean wind the chime feels, m/s.
  double get atChime => WindField.chimeSpeed(speed, placement);

  /// Eight-point compass name for [direction].
  String get compass => const ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][
      ((direction % 360 + 22.5) ~/ 45) % 8];

  ManualWind copyWith({
    double? speed,
    double? direction,
    double? gustFactor,
    Placement? placement,
  }) =>
      ManualWind(
        speed: speed ?? this.speed,
        direction: direction ?? this.direction,
        gustFactor: gustFactor ?? this.gustFactor,
        placement: placement ?? this.placement,
      );

  void applyTo(SimInputs inputs) => inputs
    ..windSpeed = speed
    ..windGust = speed * gustFactor
    ..windDirection = direction
    ..placement = placement
    ..windResponseTime = responseTime;
}
