import 'package:chime_sim/chime_sim.dart';
import 'package:flutter/foundation.dart';

import '../motion/motion_settings.dart';
import '../wind/manual_wind.dart';
import '../wind/wind_controller.dart';

enum SpeedUnit {
  metersPerSecond('m/s', 1),
  kilometersPerHour('km/h', 3.6),
  milesPerHour('mph', 2.2369363),
  knots('kn', 1.9438445);

  const SpeedUnit(this.label, this.perMeterPerSecond);

  final String label;
  final double perMeterPerSecond;

  /// Miles per hour where road signs use them, km/h elsewhere.
  static SpeedUnit forRegion(String? countryCode) =>
      const {'US', 'GB', 'LR', 'MM'}.contains(countryCode?.toUpperCase())
          ? milesPerHour
          : kilometersPerHour;
}

/// Everything the user can set, saved between launches. The chosen location is saved by
/// [WindController] with the forecast cache.
@immutable
class AppSettings {
  const AppSettings({
    this.mode = WindMode.live,
    this.manual = const ManualWind(),
    this.placement = Placement.garden,
    this.volume = 1,
    this.ambience = 1,
    this.motion = const MotionSettings(),
    this.units = SpeedUnit.kilometersPerHour,
    this.liveWindOffered = false,
    this.showStats = false,
    this.haptics = true,
    this.skyFollowsTime = true,
  });

  final WindMode mode;
  final ManualWind manual;
  final Placement placement;

  /// Master volume, 0–1, on a perceptual scale.
  final double volume;

  /// Level of the wind ambience relative to its default, 0–1.
  final double ambience;
  final MotionSettings motion;
  final SpeedUnit units;

  /// Whether the first-run "use live wind?" offer has been answered.
  final bool liveWindOffered;
  final bool showStats;

  /// Tap the phone when the chime is struck while being played by hand or by shaking.
  final bool haptics;

  /// Sky and light follow the sun where the chime is; otherwise always dusk.
  final bool skyFollowsTime;

  AppSettings copyWith({
    WindMode? mode,
    ManualWind? manual,
    Placement? placement,
    double? volume,
    double? ambience,
    MotionSettings? motion,
    SpeedUnit? units,
    bool? liveWindOffered,
    bool? showStats,
    bool? haptics,
    bool? skyFollowsTime,
  }) =>
      AppSettings(
        mode: mode ?? this.mode,
        manual: manual ?? this.manual,
        placement: placement ?? this.placement,
        volume: volume ?? this.volume,
        ambience: ambience ?? this.ambience,
        motion: motion ?? this.motion,
        units: units ?? this.units,
        liveWindOffered: liveWindOffered ?? this.liveWindOffered,
        showStats: showStats ?? this.showStats,
        haptics: haptics ?? this.haptics,
        skyFollowsTime: skyFollowsTime ?? this.skyFollowsTime,
      );

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'manual': {
          'speed': manual.speed,
          'direction': manual.direction,
          'gustFactor': manual.gustFactor,
        },
        'placement': placement.name,
        'volume': volume,
        'ambience': ambience,
        'sensitivity': motion.sensitivity,
        'tilt': motion.tiltEnabled,
        'units': units.name,
        'liveWindOffered': liveWindOffered,
        'showStats': showStats,
        'haptics': haptics,
        'skyFollowsTime': skyFollowsTime,
      };

  /// Reads what it can: anything missing or unreadable keeps its value from [defaults], so a
  /// setting added in a later version never breaks an older file.
  factory AppSettings.fromJson(Map<String, dynamic> json, {AppSettings defaults = const AppSettings()}) {
    T pick<T>(String key, T fallback) {
      final v = json[key];
      return v is T ? v : fallback;
    }

    double number(Map<String, dynamic> from, String key, double fallback, double min, double max) {
      final v = from[key];
      return v is num && v.isFinite ? v.toDouble().clamp(min, max) : fallback;
    }

    E named<E extends Enum>(List<E> values, String key, E fallback) =>
        values.asNameMap()[json[key]] ?? fallback;

    final manual = pick<Map<String, dynamic>>('manual', const {});
    final d = defaults;
    return AppSettings(
      mode: named(WindMode.values, 'mode', d.mode),
      manual: ManualWind(
        speed: number(manual, 'speed', d.manual.speed, 0, 40),
        direction: number(manual, 'direction', d.manual.direction, 0, 360) % 360,
        gustFactor: number(manual, 'gustFactor', d.manual.gustFactor, 1, 3),
      ),
      placement: named(Placement.values, 'placement', d.placement),
      volume: number(json, 'volume', d.volume, 0, 1),
      ambience: number(json, 'ambience', d.ambience, 0, 1),
      motion: MotionSettings(
        sensitivity: number(json, 'sensitivity', d.motion.sensitivity, 0, 2),
        tiltEnabled: pick('tilt', d.motion.tiltEnabled),
      ),
      units: named(SpeedUnit.values, 'units', d.units),
      liveWindOffered: pick('liveWindOffered', d.liveWindOffered),
      showStats: pick('showStats', d.showStats),
      haptics: pick('haptics', d.haptics),
      skyFollowsTime: pick('skyFollowsTime', d.skyFollowsTime),
    );
  }
}
