import 'dart:math' as math;
import 'dart:typed_data';

/// Structure-of-arrays particle storage. Vector quantities are packed as x, y, z triples, so
/// particle i's position is `position[3*i .. 3*i+2]`.
final class Particles {
  Particles(this.count)
      : position = Float64List(count * 3),
        previous = Float64List(count * 3),
        velocity = Float64List(count * 3),
        inverseMass = Float64List(count),
        drag = Float64List(count),
        dragAxis = Int32List(count)..fillRange(0, count, -1);

  final int count;
  final Float64List position;

  /// Position at the start of the current substep.
  final Float64List previous;
  final Float64List velocity;

  /// 1/m; 0 pins a particle in place.
  final Float64List inverseMass;

  /// Quadratic drag factor ½·ρ·C_d·A, kg/m.
  final Float64List drag;

  /// For slender or flat bodies, the particle whose direction from this one is the body's axis:
  /// only the flow across that axis creates drag (the cross-flow principle). -1 = isotropic.
  final Int32List dragAxis;
}

/// The turn of a body about the vertical (y) axis. Points attached to the body ([PointRef.onBody])
/// rotate with it, and take the rotational share of any constraint correction applied at them.
final class Yaw {
  Yaw(this.inverseInertia);

  /// 1/I about the vertical axis; 0 locks the rotation.
  final double inverseInertia;

  double _angle = 0;
  double _cos = 1;
  double _sin = 0;

  /// Radians; positive turns +x toward −z (counterclockwise seen from above).
  double get angle => _angle;
  double get cos => _cos;
  double get sin => _sin;

  set angle(double value) {
    _angle = value;
    _cos = math.cos(value);
    _sin = math.sin(value);
  }
}

/// A point expressed as `c0·x[i0] + c1·x[i1] + offset`, the offset optionally turned by a [Yaw].
///
/// This covers a fixed anchor (no particles), a single particle with an offset, the mount's
/// attachment points (a particle plus an offset that turns with the mount), and a linear blend
/// of two particles (a tube's ends, which lie outside its two particles). Constraints acting on
/// the point spread their correction over the particles in proportion to `c·w`, which is what
/// makes a hit near a tube's end spin it, and over the yaw by its lever arm.
final class PointRef {
  const PointRef.fixed(this.ox, this.oy, this.oz)
      : i0 = -1,
        c0 = 0,
        i1 = -1,
        c1 = 0,
        yaw = null;

  const PointRef.particle(this.i0, {this.ox = 0, this.oy = 0, this.oz = 0})
      : c0 = 1,
        i1 = -1,
        c1 = 0,
        yaw = null;

  /// Fixed on the body at particle [i0], at an offset in the body's own frame that turns with
  /// [yaw].
  const PointRef.onBody(this.i0, Yaw this.yaw, {this.ox = 0, this.oy = 0, this.oz = 0})
      : c0 = 1,
        i1 = -1,
        c1 = 0;

  const PointRef.blend(this.i0, this.c0, this.i1, this.c1)
      : ox = 0,
        oy = 0,
        oz = 0,
        yaw = null;

  final int i0;
  final double c0;
  final int i1;
  final double c1;
  final double ox;
  final double oy;
  final double oz;
  final Yaw? yaw;

  /// The offset's x and z after turning with [yaw].
  double get _rx {
    final yaw = this.yaw;
    return yaw == null ? ox : ox * yaw.cos + oz * yaw.sin;
  }

  double get _rz {
    final yaw = this.yaw;
    return yaw == null ? oz : oz * yaw.cos - ox * yaw.sin;
  }

  /// Writes the point's coordinates from [positions] into `out[at .. at+2]`.
  void eval(Float64List positions, Float64List out, [int at = 0]) {
    var x = _rx, y = oy, z = _rz;
    if (i0 >= 0) {
      final k = 3 * i0;
      x += c0 * positions[k];
      y += c0 * positions[k + 1];
      z += c0 * positions[k + 2];
    }
    if (i1 >= 0) {
      final k = 3 * i1;
      x += c1 * positions[k];
      y += c1 * positions[k + 1];
      z += c1 * positions[k + 2];
    }
    out[at] = x;
    out[at + 1] = y;
    out[at + 2] = z;
  }

  /// Generalized inverse mass of the point along the unit direction ([nx], [ny], [nz]):
  /// Σ c²·w, plus the turn's share, (r × n)_y² / I.
  double inverseMass(Float64List inverseMasses, double nx, double ny, double nz) {
    var w = (i0 >= 0 ? c0 * c0 * inverseMasses[i0] : 0.0) +
        (i1 >= 0 ? c1 * c1 * inverseMasses[i1] : 0.0);
    final yaw = this.yaw;
    if (yaw != null) {
      final arm = _rz * nx - _rx * nz;
      w += yaw.inverseInertia * arm * arm;
    }
    return w;
  }

  /// Moves the point by `w·(dx, dy, dz)` in the least-effort way: each particle moves by
  /// `c·w_i·(dx, dy, dz)`, and the body turns by `(r × d)_y / I`.
  void applyCorrection(
      Float64List positions, Float64List inverseMasses, double dx, double dy, double dz) {
    final yaw = this.yaw;
    if (yaw != null) yaw.angle += yaw.inverseInertia * (_rz * dx - _rx * dz);
    if (i0 >= 0) {
      final s = c0 * inverseMasses[i0];
      final k = 3 * i0;
      positions[k] += s * dx;
      positions[k + 1] += s * dy;
      positions[k + 2] += s * dz;
    }
    if (i1 >= 0) {
      final s = c1 * inverseMasses[i1];
      final k = 3 * i1;
      positions[k] += s * dx;
      positions[k + 1] += s * dy;
      positions[k + 2] += s * dz;
    }
  }
}

/// Distance constraint between two points. Strings are [slack]: they only pull when stretched.
final class Link {
  const Link(this.a, this.b, this.length, {this.slack = false});

  final PointRef a;
  final PointRef b;
  final double length;
  final bool slack;
}
