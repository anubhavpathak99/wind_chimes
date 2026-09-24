import 'dart:math' as math;
import 'dart:typed_data';

import '../config/chime_config.dart';
import '../core/particles.dart';
import '../core/rod_body.dart';
import '../events/collision_event.dart';

/// Clapper (sphere) against tubes (capsules), with a per-tube contact cache.
///
/// Per substep, [solvePositions] runs after the constraints and [solveVelocities] after velocities
/// are rebuilt from positions. The cache is what keeps resting contact silent: a contact must
/// separate by [ChimeConfig.contactHysteresis] before it can begin, and emit, again.
final class ClapperContacts {
  ClapperContacts({
    required this._particles,
    required List<RodBody> rods,
    required this.clapper,
    required this._config,
    required this._events,
  })  : _rods = rods,
        _touching = List.filled(rods.length, false),
        _active = List.filled(rods.length, false),
        _pressed = List.filled(rods.length, false),
        _lastEvent = Float64List(rods.length),
        _normal = Float64List(rods.length * 3),
        _upperWeight = Float64List(rods.length),
        _lowerWeight = Float64List(rods.length),
        _closingSpeed = Float64List(rods.length) {
    reset();
  }

  final Particles _particles;
  final List<RodBody> _rods;
  final ChimeConfig _config;
  final EventRing _events;
  final int clapper;

  /// Persistent contact state, with hysteresis.
  final List<bool> _touching;

  /// Penetrating during the current substep; needs a velocity pass.
  final List<bool> _active;

  /// In actual contact at some substep of the current step.
  final List<bool> _pressed;
  final Float64List _lastEvent;
  final Float64List _normal;
  final Float64List _upperWeight;
  final Float64List _lowerWeight;

  /// Normal velocity before this substep's corrections (negative = approaching).
  final Float64List _closingSpeed;
  final Float64List _ends = Float64List(6);

  bool isTouching(int rod) => _touching[rod];

  bool isPressing(int rod) => _pressed[rod];

  /// Call at the start of every fixed step.
  void beginStep() => _pressed.fillRange(0, _pressed.length, false);

  /// How many substeps [confine] had to pull the clapper back.
  int get confinements => _confinements;
  int _confinements = 0;
  bool _inside = true;

  void reset() {
    _touching.fillRange(0, _touching.length, false);
    _active.fillRange(0, _active.length, false);
    _pressed.fillRange(0, _pressed.length, false);
    _lastEvent.fillRange(0, _lastEvent.length, double.negativeInfinity);
    _inside = true;
  }

  void solvePositions(double time) {
    final pos = _particles.position;
    final vel = _particles.velocity;
    final w = _particles.inverseMass;
    final c = 3 * clapper;
    final wc = w[clapper];

    for (var k = 0; k < _rods.length; k++) {
      final rod = _rods[k];
      rod.top.eval(pos, _ends, 0);
      rod.bottom.eval(pos, _ends, 3);

      // Closest point on the tube's axis to the clapper's center.
      final p0x = _ends[0], p0y = _ends[1], p0z = _ends[2];
      final sx = _ends[3] - p0x, sy = _ends[4] - p0y, sz = _ends[5] - p0z;
      final cx = pos[c], cy = pos[c + 1], cz = pos[c + 2];
      final segSq = sx * sx + sy * sy + sz * sz;
      var t = segSq > 0 ? ((cx - p0x) * sx + (cy - p0y) * sy + (cz - p0z) * sz) / segSq : 0.0;
      t = t < 0 ? 0 : (t > 1 ? 1 : t);
      final dx = cx - (p0x + t * sx), dy = cy - (p0y + t * sy), dz = cz - (p0z + t * sz);
      final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
      final separation = dist - _config.clapperRadius - rod.spec.radius;

      if (_touching[k] && separation > _config.contactHysteresis) _touching[k] = false;
      if (separation >= 0 || dist < 1e-9) {
        _active[k] = false;
        continue;
      }

      final nx = dx / dist, ny = dy / dist, nz = dz / dist;
      final aw = rod.upperWeight(t), bw = rod.lowerWeight(t);
      final a = 3 * rod.upper, b = 3 * rod.lower;
      final wa = w[rod.upper], wb = w[rod.lower];
      final wSum = wc + aw * aw * wa + bw * bw * wb;

      final rvx = vel[c] - (aw * vel[a] + bw * vel[b]);
      final rvy = vel[c + 1] - (aw * vel[a + 1] + bw * vel[b + 1]);
      final rvz = vel[c + 2] - (aw * vel[a + 2] + bw * vel[b + 2]);
      final vn = rvx * nx + rvy * ny + rvz * nz;

      _active[k] = true;
      _pressed[k] = true;
      _normal[3 * k] = nx;
      _normal[3 * k + 1] = ny;
      _normal[3 * k + 2] = nz;
      _upperWeight[k] = aw;
      _lowerWeight[k] = bw;
      _closingSpeed[k] = vn;

      final lambda = -separation / wSum;
      pos[c] += wc * lambda * nx;
      pos[c + 1] += wc * lambda * ny;
      pos[c + 2] += wc * lambda * nz;
      pos[a] -= aw * wa * lambda * nx;
      pos[a + 1] -= aw * wa * lambda * ny;
      pos[a + 2] -= aw * wa * lambda * nz;
      pos[b] -= bw * wb * lambda * nx;
      pos[b + 1] -= bw * wb * lambda * ny;
      pos[b + 2] -= bw * wb * lambda * nz;

      if (_touching[k]) continue;
      _touching[k] = true;
      final closing = -vn;
      if (closing < _config.minApproachSpeed) continue;
      if (time - _lastEvent[k] < _config.retriggerInterval) continue;
      _lastEvent[k] = time;

      final relSpeed = math.sqrt(rvx * rvx + rvy * rvy + rvz * rvz);
      _events.claim()
        ..rodId = k
        ..impulse = (1 + _config.restitution) * closing / wSum
        ..normalSpeed = closing
        ..strikePos = t
        ..glancing = relSpeed > 0 ? 1 - closing / relSpeed : 0
        ..simTime = time;
    }
  }

  /// Safety net against the clapper escaping the ring sideways. Tubes are free pendulums, so a
  /// clapper pressed hard enough between two of them can force them apart and slip out. While the
  /// clapper is inside the ring and level with the tubes, its center is kept within the circle of
  /// tube axes (measured at its own height); contacts stop it well inside that circle in normal
  /// play. A clapper that is already outside, say lifted over the top by a finger, is left alone
  /// until it comes back in.
  void confine() {
    final pos = _particles.position;
    final c = 3 * clapper;
    final cy = pos[c + 1];
    var sumX = 0.0, sumZ = 0.0;
    var levelWithTubes = true;
    for (final rod in _rods) {
      rod.top.eval(pos, _ends, 0);
      rod.bottom.eval(pos, _ends, 3);
      final dy = _ends[4] - _ends[1];
      var t = dy.abs() > 1e-9 ? (cy - _ends[1]) / dy : 0.0;
      if (t < 0 || t > 1) {
        levelWithTubes = false;
        t = t.clamp(0.0, 1.0);
      }
      sumX += _ends[0] + t * (_ends[3] - _ends[0]);
      sumZ += _ends[2] + t * (_ends[5] - _ends[2]);
    }
    final centerX = sumX / _rods.length, centerZ = sumZ / _rods.length;
    final dx = pos[c] - centerX, dz = pos[c + 2] - centerZ;
    final dist = math.sqrt(dx * dx + dz * dz);
    final limit = _config.ringRadius;
    if (dist <= limit) {
      _inside = true;
      return;
    }
    if (!_inside || !levelWithTubes) {
      _inside = false;
      return;
    }
    _confinements++;
    pos[c] = centerX + dx * limit / dist;
    pos[c + 2] = centerZ + dz * limit / dist;
  }

  /// Restitution and friction. Below [ChimeConfig.restingSpeed] the bounce is dropped, which is
  /// what lets resting contact settle instead of jittering.
  void solveVelocities() {
    final vel = _particles.velocity;
    final w = _particles.inverseMass;
    final c = 3 * clapper;
    final wc = w[clapper];

    for (var k = 0; k < _rods.length; k++) {
      if (!_active[k]) continue;
      final rod = _rods[k];
      final aw = _upperWeight[k], bw = _lowerWeight[k];
      final a = 3 * rod.upper, b = 3 * rod.lower;
      final wa = w[rod.upper], wb = w[rod.lower];
      final wSum = wc + aw * aw * wa + bw * bw * wb;
      final nx = _normal[3 * k], ny = _normal[3 * k + 1], nz = _normal[3 * k + 2];

      final rvx = vel[c] - (aw * vel[a] + bw * vel[b]);
      final rvy = vel[c + 1] - (aw * vel[a + 1] + bw * vel[b + 1]);
      final rvz = vel[c + 2] - (aw * vel[a + 2] + bw * vel[b + 2]);
      final vn = rvx * nx + rvy * ny + rvz * nz;

      final before = _closingSpeed[k];
      final target = -before > _config.restingSpeed ? -_config.restitution * before : 0.0;
      final dvn = target - vn;

      var dx = dvn * nx, dy = dvn * ny, dz = dvn * nz;
      final tx = rvx - vn * nx, ty = rvy - vn * ny, tz = rvz - vn * nz;
      final tangential = math.sqrt(tx * tx + ty * ty + tz * tz);
      if (tangential > 1e-9) {
        final cut = math.min(_config.friction * dvn.abs(), tangential) / tangential;
        dx -= cut * tx;
        dy -= cut * ty;
        dz -= cut * tz;
      }

      final px = dx / wSum, py = dy / wSum, pz = dz / wSum;
      vel[c] += wc * px;
      vel[c + 1] += wc * py;
      vel[c + 2] += wc * pz;
      vel[a] -= aw * wa * px;
      vel[a + 1] -= aw * wa * py;
      vel[a + 2] -= aw * wa * pz;
      vel[b] -= bw * wb * px;
      vel[b + 1] -= bw * wb * py;
      vel[b + 2] -= bw * wb * pz;
    }
  }
}
