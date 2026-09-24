import 'dart:math' as math;
import 'dart:typed_data';

import '../config/chime_config.dart';
import '../core/particles.dart';
import '../core/rod_body.dart';
import '../events/collision_event.dart';

/// Tubes (capsules) against each other: the clink of a gale or a hard shake, when tubes swing into
/// their neighbours. Same scheme as [ClapperContacts], per pair of tubes: push apart along the
/// closest points of the two axes, restitution in the velocity pass, and a contact cache with
/// hysteresis so tubes leaning together stay silent. Each knock is reported once for each tube.
final class RodContacts {
  RodContacts({
    required this._particles,
    required List<RodBody> rods,
    required this._config,
    required this._events,
  })  : _rods = rods,
        _pairs = rods.length * (rods.length - 1) ~/ 2,
        _pairA = Int32List(rods.length * (rods.length - 1) ~/ 2),
        _pairB = Int32List(rods.length * (rods.length - 1) ~/ 2) {
    var p = 0;
    for (var i = 0; i < rods.length; i++) {
      for (var j = i + 1; j < rods.length; j++) {
        _pairA[p] = i;
        _pairB[p] = j;
        p++;
      }
    }
    _touching = List.filled(_pairs, false);
    _active = List.filled(_pairs, false);
    _lastEvent = Float64List(_pairs);
    _normal = Float64List(_pairs * 3);
    _weights = Float64List(_pairs * 4);
    _closingSpeed = Float64List(_pairs);
    reset();
  }

  final Particles _particles;
  final List<RodBody> _rods;
  final ChimeConfig _config;
  final EventRing _events;
  final int _pairs;
  final Int32List _pairA;
  final Int32List _pairB;
  late final List<bool> _touching;
  late final List<bool> _active;
  late final Float64List _lastEvent;
  late final Float64List _normal;

  /// Per pair: upper and lower particle weights of the contact point on tube A, then on tube B.
  late final Float64List _weights;
  late final Float64List _closingSpeed;
  final Float64List _ends = Float64List(12);
  double _s = 0;
  double _t = 0;

  void reset() {
    _touching.fillRange(0, _pairs, false);
    _active.fillRange(0, _pairs, false);
    _lastEvent.fillRange(0, _pairs, double.negativeInfinity);
  }

  void solvePositions(double time) {
    final pos = _particles.position;
    final vel = _particles.velocity;
    final w = _particles.inverseMass;

    for (var p = 0; p < _pairs; p++) {
      final ra = _rods[_pairA[p]], rb = _rods[_pairB[p]];
      ra.top.eval(pos, _ends, 0);
      ra.bottom.eval(pos, _ends, 3);
      rb.top.eval(pos, _ends, 6);
      rb.bottom.eval(pos, _ends, 9);
      _closestParameters(_ends);
      final s = _s, t = _t;

      final ax = _ends[0] + s * (_ends[3] - _ends[0]);
      final ay = _ends[1] + s * (_ends[4] - _ends[1]);
      final az = _ends[2] + s * (_ends[5] - _ends[2]);
      final bx = _ends[6] + t * (_ends[9] - _ends[6]);
      final by = _ends[7] + t * (_ends[10] - _ends[7]);
      final bz = _ends[8] + t * (_ends[11] - _ends[8]);
      final dx = ax - bx, dy = ay - by, dz = az - bz;
      final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
      final separation = dist - ra.spec.radius - rb.spec.radius;

      if (_touching[p] && separation > _config.contactHysteresis) _touching[p] = false;
      if (separation >= 0 || dist < 1e-9) {
        _active[p] = false;
        continue;
      }

      final nx = dx / dist, ny = dy / dist, nz = dz / dist;
      final au = ra.upperWeight(s), al = ra.lowerWeight(s);
      final bu = rb.upperWeight(t), bl = rb.lowerWeight(t);
      final wau = w[ra.upper], wal = w[ra.lower], wbu = w[rb.upper], wbl = w[rb.lower];
      final wSum = au * au * wau + al * al * wal + bu * bu * wbu + bl * bl * wbl;
      if (wSum == 0) continue;
      final u = 3 * ra.upper, l = 3 * ra.lower, v = 3 * rb.upper, m = 3 * rb.lower;

      final rvx = au * vel[u] + al * vel[l] - bu * vel[v] - bl * vel[m];
      final rvy = au * vel[u + 1] + al * vel[l + 1] - bu * vel[v + 1] - bl * vel[m + 1];
      final rvz = au * vel[u + 2] + al * vel[l + 2] - bu * vel[v + 2] - bl * vel[m + 2];
      final vn = rvx * nx + rvy * ny + rvz * nz;

      _active[p] = true;
      _normal[3 * p] = nx;
      _normal[3 * p + 1] = ny;
      _normal[3 * p + 2] = nz;
      _weights[4 * p] = au;
      _weights[4 * p + 1] = al;
      _weights[4 * p + 2] = bu;
      _weights[4 * p + 3] = bl;
      _closingSpeed[p] = vn;

      final lambda = -separation / wSum;
      _move(pos, u, au * wau * lambda, nx, ny, nz);
      _move(pos, l, al * wal * lambda, nx, ny, nz);
      _move(pos, v, -bu * wbu * lambda, nx, ny, nz);
      _move(pos, m, -bl * wbl * lambda, nx, ny, nz);

      if (_touching[p]) continue;
      _touching[p] = true;
      final closing = -vn;
      if (closing < _config.minApproachSpeed) continue;
      if (time - _lastEvent[p] < _config.retriggerInterval) continue;
      _lastEvent[p] = time;

      final relSpeed = math.sqrt(rvx * rvx + rvy * rvy + rvz * rvz);
      final impulse = (1 + _config.rodRestitution) * closing / wSum;
      final glancing = relSpeed > 0 ? 1 - closing / relSpeed : 0.0;
      _emit(_pairA[p], _pairB[p], s, impulse, closing, glancing, time);
      _emit(_pairB[p], _pairA[p], t, impulse, closing, glancing, time);
    }
  }

  void _emit(int rod, int other, double at, double impulse, double closing, double glancing,
          double time) =>
      _events.claim()
        ..rodId = rod
        ..otherRodId = other
        ..impulse = impulse
        ..normalSpeed = closing
        ..strikePos = at
        ..glancing = glancing
        ..simTime = time;

  /// Restitution and friction, as for the clapper.
  void solveVelocities() {
    final vel = _particles.velocity;
    final w = _particles.inverseMass;
    for (var p = 0; p < _pairs; p++) {
      if (!_active[p]) continue;
      final ra = _rods[_pairA[p]], rb = _rods[_pairB[p]];
      final au = _weights[4 * p], al = _weights[4 * p + 1];
      final bu = _weights[4 * p + 2], bl = _weights[4 * p + 3];
      final wau = w[ra.upper], wal = w[ra.lower], wbu = w[rb.upper], wbl = w[rb.lower];
      final wSum = au * au * wau + al * al * wal + bu * bu * wbu + bl * bl * wbl;
      if (wSum == 0) continue;
      final u = 3 * ra.upper, l = 3 * ra.lower, v = 3 * rb.upper, m = 3 * rb.lower;
      final nx = _normal[3 * p], ny = _normal[3 * p + 1], nz = _normal[3 * p + 2];

      final rvx = au * vel[u] + al * vel[l] - bu * vel[v] - bl * vel[m];
      final rvy = au * vel[u + 1] + al * vel[l + 1] - bu * vel[v + 1] - bl * vel[m + 1];
      final rvz = au * vel[u + 2] + al * vel[l + 2] - bu * vel[v + 2] - bl * vel[m + 2];
      final vn = rvx * nx + rvy * ny + rvz * nz;
      final before = _closingSpeed[p];
      final target = -before > _config.restingSpeed ? -_config.rodRestitution * before : 0.0;
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
      _move(vel, u, au * wau, px, py, pz);
      _move(vel, l, al * wal, px, py, pz);
      _move(vel, v, -bu * wbu, px, py, pz);
      _move(vel, m, -bl * wbl, px, py, pz);
    }
  }

  static void _move(Float64List v, int k, double s, double x, double y, double z) {
    v[k] += s * x;
    v[k + 1] += s * y;
    v[k + 2] += s * z;
  }

  /// Parameters (0–1 along each) of the closest points between segments p0→p1 and q0→q1, packed
  /// in [e] as p0, p1, q0, q1, written to [_s] and [_t] (no allocation in the physics step).
  /// After Ericson, *Real-Time Collision Detection*, §5.1.9.
  void _closestParameters(Float64List e) {
    final d1x = e[3] - e[0], d1y = e[4] - e[1], d1z = e[5] - e[2];
    final d2x = e[9] - e[6], d2y = e[10] - e[7], d2z = e[11] - e[8];
    final rx = e[0] - e[6], ry = e[1] - e[7], rz = e[2] - e[8];
    final a = d1x * d1x + d1y * d1y + d1z * d1z;
    final f = d2x * d2x + d2y * d2y + d2z * d2z;
    final c = d1x * rx + d1y * ry + d1z * rz;
    final ff = d2x * rx + d2y * ry + d2z * rz;
    if (a < 1e-12 || f < 1e-12) {
      _s = _t = 0;
      return;
    }
    final b = d1x * d2x + d1y * d2y + d1z * d2z;
    final denom = a * f - b * b;
    var s = denom > 1e-12 ? ((b * ff - c * f) / denom).clamp(0.0, 1.0) : 0.0;
    var t = (b * s + ff) / f;
    if (t < 0) {
      t = 0;
      s = (-c / a).clamp(0.0, 1.0);
    } else if (t > 1) {
      t = 1;
      s = ((b - c) / a).clamp(0.0, 1.0);
    }
    _s = s;
    _t = t;
  }
}
