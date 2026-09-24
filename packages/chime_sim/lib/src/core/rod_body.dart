import 'dart:math' as math;

import '../config/chime_config.dart';
import 'particles.dart';

/// A rigid tube made of two particles of m/2 each, placed ±L/(2√3) from its center so that the
/// pair has the rotational inertia of a uniform tube (mL²/12). The tube's ends lie outside the
/// particles and are expressed as linear extrapolations of them.
final class RodBody {
  RodBody({
    required this.index,
    required this.upper,
    required this.lower,
    required this.spec,
    required this.ringAngle,
    required this.anchor,
  })  : top = PointRef.blend(upper, 1 + extrapolation, lower, -extrapolation),
        bottom = PointRef.blend(lower, 1 + extrapolation, upper, -extrapolation);

  /// How far each end lies beyond its particle, as a fraction of the particle spacing:
  /// (L/2 − d) / 2d with d = L/(2√3), which is (√3 − 1)/2 for any length.
  static const double extrapolation = 0.36602540378443865;

  final int index;
  final int upper;
  final int lower;
  final RodSpec spec;

  /// Position on the ring, radians, measured from +z (toward the viewer) toward +x.
  final double ringAngle;

  /// Where the tube's string attaches to the mount.
  final PointRef anchor;

  final PointRef top;
  final PointRef bottom;

  /// Distance between the two particles.
  double get particleSpacing => spec.length / math.sqrt(3);

  /// Weight of the upper particle for the point at [t] along top (0) → bottom (1).
  double upperWeight(double t) => 1 + extrapolation - t * (1 + 2 * extrapolation);

  /// Weight of the lower particle for the point at [t] along top (0) → bottom (1).
  double lowerWeight(double t) => t * (1 + 2 * extrapolation) - extrapolation;
}
