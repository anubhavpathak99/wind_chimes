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

/// A point expressed as `c0·x[i0] + c1·x[i1] + offset`.
///
/// This covers a fixed anchor (no particles), a single particle with an offset (the mount's
/// attachment points), and a linear blend of two particles (a tube's ends, which lie outside its
/// two particles). Constraints acting on the point spread their correction over the particles in
/// proportion to `c·w`, which is what makes a hit near a tube's end spin it.
final class PointRef {
  const PointRef.fixed(this.ox, this.oy, this.oz)
      : i0 = -1,
        c0 = 0,
        i1 = -1,
        c1 = 0;

  const PointRef.particle(this.i0, {this.ox = 0, this.oy = 0, this.oz = 0})
      : c0 = 1,
        i1 = -1,
        c1 = 0;

  const PointRef.blend(this.i0, this.c0, this.i1, this.c1)
      : ox = 0,
        oy = 0,
        oz = 0;

  final int i0;
  final double c0;
  final int i1;
  final double c1;
  final double ox;
  final double oy;
  final double oz;

  /// Writes the point's coordinates from [positions] into `out[at .. at+2]`.
  void eval(Float64List positions, Float64List out, [int at = 0]) {
    var x = ox, y = oy, z = oz;
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

  /// Generalized inverse mass of the point: Σ c²·w.
  double inverseMass(Float64List inverseMasses) =>
      (i0 >= 0 ? c0 * c0 * inverseMasses[i0] : 0) +
      (i1 >= 0 ? c1 * c1 * inverseMasses[i1] : 0);

  /// Moves the point by `w·λ·n` in the least-effort way: each particle moves by `c·w·(dx,dy,dz)`.
  void applyCorrection(
      Float64List positions, Float64List inverseMasses, double dx, double dy, double dz) {
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
