import 'dart:math' as math;

import '../location/location.dart';
import '../settings/app_settings.dart';
import '../wind/wind_controller.dart';

/// Words and numbers for wind, shared by the chip and the controls.
abstract final class WindText {
  /// Upper bounds of Beaufort forces 0–11, m/s; 12 above the last.
  static const _beaufortLimits = [0.5, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7];
  static const _beaufortNames = [
    'Calm',
    'Light air',
    'Light breeze',
    'Gentle breeze',
    'Moderate breeze',
    'Fresh breeze',
    'Strong breeze',
    'Near gale',
    'Gale',
    'Strong gale',
    'Storm',
    'Violent storm',
    'Hurricane',
  ];

  static int beaufort(double speed) {
    for (var force = 0; force < _beaufortLimits.length; force++) {
      if (speed < _beaufortLimits[force]) return force;
    }
    return 12;
  }

  static String beaufortName(double speed) => _beaufortNames[beaufort(speed)];

  /// Beaufort force as a continuous number, B = (v / 0.836)^(2/3): what the manual slider moves
  /// in, so equal steps feel like equal changes in the wind.
  static double beaufortScale(double speed) => math.pow(math.max(speed, 0) / 0.836, 2 / 3).toDouble();
  static double speedForBeaufort(double force) => 0.836 * math.pow(math.max(force, 0), 1.5);

  static String speed(double metersPerSecond, SpeedUnit unit) {
    final v = metersPerSecond * unit.perMeterPerSecond;
    final digits = unit == SpeedUnit.metersPerSecond && v < 10 ? 1 : 0;
    return '${v.toStringAsFixed(digits)} ${unit.label}';
  }

  static String sourceName(WindSource source) => switch (source) {
        WindSource.live => 'Live',
        WindSource.cached => 'Cached',
        WindSource.ambient => 'Ambient breeze',
        WindSource.manual => 'Manual',
      };

  static String placeName(LocationChoice choice) => switch (choice) {
        DeviceLocation() => 'Your location',
        Place(:final name) => name,
      };

  static String ago(Duration age) => switch (age.inMinutes) {
        < 1 => 'just now',
        < 60 => '${age.inMinutes} min ago',
        _ => '${age.inHours} h ago',
      };

  static String? problem(WindStatus s) {
    final problem = switch (s.problem) {
      null => null,
      WindProblem.noLocation => 'No location chosen',
      WindProblem.locationDenied => 'Location permission needed',
      WindProblem.locationDeniedForever => 'Location is blocked in Settings',
      WindProblem.locationOff => 'Location services are off',
      WindProblem.locationUnavailable => 'No location fix',
      WindProblem.offline => 'Offline',
      WindProblem.serviceError => 'Weather service error',
    };
    final retry = s.retryAt;
    if (problem == null || retry == null || s.busy) return problem;
    final wait = retry.difference(s.asOf);
    final when = wait.inSeconds < 60 ? '${wait.inSeconds.clamp(0, 59)} s' : '${wait.inMinutes} min';
    return '$problem · retrying in $when';
  }
}
