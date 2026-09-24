import 'dart:math' as math;
import 'dart:typed_data';

import '../collision/clapper_contacts.dart';
import '../config/chime_config.dart';
import '../events/collision_event.dart';
import '../inputs/sim_inputs.dart';
import '../wind/wind_field.dart';
import 'particles.dart';
import 'rod_body.dart';

/// The whole chime: substepped XPBD on particles, in SI units, with x right, y up and z toward
/// the viewer. The hook is fixed at the origin.
///
/// Call [advance] once per rendered frame. It runs whole fixed steps of [stepDt], each split into
/// [substeps], and keeps the remainder so the renderer can interpolate with
/// [interpolatedPositions]. Impacts are queued in [events]. [seed] makes the wind reproducible.
final class ChimeSimulation {
  ChimeSimulation(this.config, {SimInputs? inputs, int seed = 1})
      : inputs = inputs ?? SimInputs(),
        wind = WindField(stepDt: stepDt, seed: seed) {
    _build();
    reset();
  }

  static const double stepDt = 1 / 120;
  static const int substeps = 4;

  /// Frame times are clamped to this, so a hitch or a resume doesn't fast-forward the chime.
  static const double maxFrameDt = 0.1;
  static const int maxStepsPerFrame = 12;

  static const int mountIndex = 0;
  static const int clapperIndex = 1;
  static const int sailIndex = 2;

  final ChimeConfig config;
  final SimInputs inputs;
  final EventRing events = EventRing(64);
  final WindField wind;

  late final Particles particles;
  late final List<RodBody> rods;
  late final List<Link> _links;
  late final ClapperContacts _contacts;
  late final Float64List _rest;
  late final Float64List _stepStart;

  /// Wind velocity at each particle for the current step, packed as x, z pairs.
  late final Float64List _windAt;
  final Float64List _pa = Float64List(3);
  final Float64List _pb = Float64List(3);

  double _accumulator = 0;
  double _time = 0;
  int _steps = 0;
  int _resets = 0;

  double get time => _time;
  int get stepCount => _steps;

  /// How many times a non-finite state forced a reset. Should stay 0.
  int get recoveryCount => _resets;

  /// Fraction of a fixed step elapsed since the last one, in [0, 1).
  double get interpolationAlpha => _accumulator / stepDt;

  bool isTouchingRod(int rod) => _contacts.isTouching(rod);

  /// Substeps in which the clapper had to be kept from escaping the ring. Should stay rare.
  int get clapperConfinements => _contacts.confinements;

  /// Advances by one rendered frame. Returns the number of fixed steps run.
  int advance(double frameDt) {
    if (!(frameDt > 0)) return 0;
    _accumulator += math.min(frameDt, maxFrameDt);
    var steps = 0;
    while (_accumulator >= stepDt && steps < maxStepsPerFrame) {
      step();
      _accumulator -= stepDt;
      steps++;
    }
    if (_accumulator >= stepDt) _accumulator = 0;
    return steps;
  }

  /// Runs exactly one fixed step.
  void step() {
    _stepStart.setAll(0, particles.position);
    wind.step(inputs);
    final pos = particles.position;
    for (var i = 0; i < particles.count; i++) {
      wind.sampleAt(pos[3 * i], pos[3 * i + 2], _windAt, 2 * i);
    }
    const h = stepDt / substeps;
    for (var s = 1; s <= substeps; s++) {
      _substep(h, _time + s * h);
    }
    _time += stepDt;
    _steps++;
    if (!_isFinite()) {
      _resets++;
      reset();
    }
  }

  /// Returns every body to its hanging rest pose, at rest.
  void reset() {
    particles.position.setAll(0, _rest);
    particles.previous.setAll(0, _rest);
    particles.velocity.fillRange(0, particles.velocity.length, 0);
    _stepStart.setAll(0, _rest);
    _accumulator = 0;
    _contacts.reset();
  }

  /// Positions blended between the last two fixed steps, for rendering.
  void interpolatedPositions(Float64List out) {
    final alpha = interpolationAlpha;
    final pos = particles.position;
    for (var i = 0; i < pos.length; i++) {
      final from = _stepStart[i];
      out[i] = from + (pos[i] - from) * alpha;
    }
  }

  /// Rest positions, packed like [Particles.position].
  Float64List get restPositions => Float64List.fromList(_rest);

  /// Kinetic plus gravitational potential energy, J (height measured against gravity).
  double mechanicalEnergy() {
    final pos = particles.position, vel = particles.velocity, w = particles.inverseMass;
    final gx = inputs.gravityDirX, gy = inputs.gravityDirY, gz = inputs.gravityDirZ;
    var energy = 0.0;
    for (var i = 0; i < particles.count; i++) {
      if (w[i] == 0) continue;
      final m = 1 / w[i];
      final k = 3 * i;
      final v2 = vel[k] * vel[k] + vel[k + 1] * vel[k + 1] + vel[k + 2] * vel[k + 2];
      final height = -(gx * pos[k] + gy * pos[k + 1] + gz * pos[k + 2]);
      energy += 0.5 * m * v2 + m * config.gravity * height;
    }
    return energy;
  }

  /// Worst relative violation across all constraints: rigid links in either direction, strings
  /// only when stretched.
  double maxConstraintError() {
    var worst = 0.0;
    for (final link in _links) {
      link.a.eval(particles.position, _pa);
      link.b.eval(particles.position, _pb);
      final dx = _pa[0] - _pb[0], dy = _pa[1] - _pb[1], dz = _pa[2] - _pb[2];
      final c = math.sqrt(dx * dx + dy * dy + dz * dz) - link.length;
      final error = (link.slack ? math.max(c, 0.0) : c.abs()) / link.length;
      worst = math.max(worst, error);
    }
    return worst;
  }

  void _substep(double h, double time) {
    final pos = particles.position;
    final prev = particles.previous;
    final vel = particles.velocity;
    final w = particles.inverseMass;
    final drag = particles.drag;
    final dragAxis = particles.dragAxis;

    final gx = config.gravity * inputs.gravityDirX - inputs.deviceAccelX;
    final gy = config.gravity * inputs.gravityDirY - inputs.deviceAccelY;
    final gz = config.gravity * inputs.gravityDirZ - inputs.deviceAccelZ;
    final damping = math.exp(-config.linearDamping * h);
    final touch = inputs.touchParticle;
    final omega = 2 * math.pi * config.touchFrequency;
    final spring = omega * omega;
    final touchDamping = 2 * config.touchDampingRatio * omega;

    for (var i = 0; i < particles.count; i++) {
      final wi = w[i];
      if (wi == 0) continue;
      final k = 3 * i;
      var vx = vel[k], vy = vel[k + 1], vz = vel[k + 2];

      // Quadratic drag on the velocity relative to the local wind; for tubes and the sail, only
      // its part across the body's axis. A sail blown up at an angle therefore catches less wind.
      var rx = _windAt[2 * i] - vx, ry = -vy, rz = _windAt[2 * i + 1] - vz;
      final axis = dragAxis[i];
      if (axis >= 0) {
        final j = 3 * axis;
        final dx = pos[k] - pos[j], dy = pos[k + 1] - pos[j + 1], dz = pos[k + 2] - pos[j + 2];
        final lengthSq = dx * dx + dy * dy + dz * dz;
        if (lengthSq > 1e-12) {
          final along = (rx * dx + ry * dy + rz * dz) / lengthSq;
          rx -= along * dx;
          ry -= along * dy;
          rz -= along * dz;
        }
      }
      final dragPerSpeed = drag[i] * wi * math.sqrt(rx * rx + ry * ry + rz * rz);
      var ax = gx + dragPerSpeed * rx;
      var ay = gy + dragPerSpeed * ry;
      var az = gz + dragPerSpeed * rz;

      if (i == touch) {
        var tx = spring * (inputs.touchX - pos[k]) - touchDamping * vx;
        var ty = spring * (inputs.touchY - pos[k + 1]) - touchDamping * vy;
        var tz = spring * (inputs.touchZ - pos[k + 2]) - touchDamping * vz;
        final mag = math.sqrt(tx * tx + ty * ty + tz * tz);
        if (mag > config.maxTouchAcceleration) {
          final s = config.maxTouchAcceleration / mag;
          tx *= s;
          ty *= s;
          tz *= s;
        }
        ax += tx;
        ay += ty;
        az += tz;
      }

      vx = (vx + h * ax) * damping;
      vy = (vy + h * ay) * damping;
      vz = (vz + h * az) * damping;
      vel[k] = vx;
      vel[k + 1] = vy;
      vel[k + 2] = vz;
      prev[k] = pos[k];
      prev[k + 1] = pos[k + 1];
      prev[k + 2] = pos[k + 2];
      pos[k] += h * vx;
      pos[k + 1] += h * vy;
      pos[k + 2] += h * vz;
    }

    for (final link in _links) {
      _solveLink(link);
    }
    _contacts.solvePositions(time);
    _contacts.confine();

    final invH = 1 / h;
    for (var i = 0; i < pos.length; i++) {
      vel[i] = (pos[i] - prev[i]) * invH;
    }
    _contacts.solveVelocities(h);

    final maxSpeed = config.maxSpeed;
    for (var i = 0; i < particles.count; i++) {
      final k = 3 * i;
      if (w[i] == 0) {
        vel[k] = vel[k + 1] = vel[k + 2] = 0;
        continue;
      }
      final speed =
          math.sqrt(vel[k] * vel[k] + vel[k + 1] * vel[k + 1] + vel[k + 2] * vel[k + 2]);
      if (speed > maxSpeed) {
        final s = maxSpeed / speed;
        vel[k] *= s;
        vel[k + 1] *= s;
        vel[k + 2] *= s;
      }
    }
  }

  void _solveLink(Link link) {
    final pos = particles.position;
    final w = particles.inverseMass;
    link.a.eval(pos, _pa);
    link.b.eval(pos, _pb);
    final dx = _pa[0] - _pb[0], dy = _pa[1] - _pb[1], dz = _pa[2] - _pb[2];
    final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (dist < 1e-9) return;
    final c = dist - link.length;
    if (link.slack && c <= 0) return;
    final wSum = link.a.inverseMass(w) + link.b.inverseMass(w);
    if (wSum == 0) return;
    final lambda = -c / (wSum * dist);
    link.a.applyCorrection(pos, w, lambda * dx, lambda * dy, lambda * dz);
    link.b.applyCorrection(pos, w, -lambda * dx, -lambda * dy, -lambda * dz);
  }

  bool _isFinite() {
    var sum = 0.0;
    final pos = particles.position, vel = particles.velocity;
    for (var i = 0; i < pos.length; i++) {
      sum += pos[i] + vel[i];
    }
    return sum.isFinite;
  }

  void _build() {
    final rodCount = config.rods.length;
    particles = Particles(3 + 2 * rodCount);
    _rest = Float64List(particles.count * 3);
    _stepStart = Float64List(particles.count * 3);
    _windAt = Float64List(particles.count * 2);
    final w = particles.inverseMass;
    final drag = particles.drag;
    double dragFactor(double cd, double area) => 0.5 * config.airDensity * cd * area;

    final mountY = -config.ropeLength;
    _setRest(mountIndex, 0, mountY, 0);
    w[mountIndex] = 1 / config.mountMass;
    drag[mountIndex] = dragFactor(1.1, 2 * config.mountRadius * config.mountThickness);

    final clapperY = mountY - config.clapperStringLength;
    _setRest(clapperIndex, 0, clapperY, 0);
    w[clapperIndex] = 1 / config.clapperMass;
    drag[clapperIndex] =
        dragFactor(1.0, math.pi * config.clapperRadius * config.clapperRadius);

    _setRest(sailIndex, 0, mountY - config.sailCenterDrop, 0);
    w[sailIndex] = 1 / config.sailMass;
    drag[sailIndex] = dragFactor(1.2, config.sailWidth * config.sailHeight);
    particles.dragAxis[sailIndex] = clapperIndex;

    const hook = PointRef.fixed(0, 0, 0);
    const mount = PointRef.particle(mountIndex);
    const clapper = PointRef.particle(clapperIndex);
    final links = <Link>[Link(hook, mount, config.ropeLength, slack: true)];
    final rodBodies = <RodBody>[];

    for (var k = 0; k < rodCount; k++) {
      final spec = config.rods[k];
      // Offset by half a slot so the camera looks between the two front tubes.
      final angle = math.pi / rodCount + 2 * math.pi * k / rodCount;
      final ax = config.ringRadius * math.sin(angle);
      final az = config.ringRadius * math.cos(angle);
      final rod = RodBody(
        index: k,
        upper: 3 + 2 * k,
        lower: 4 + 2 * k,
        spec: spec,
        ringAngle: angle,
        anchor: PointRef.particle(mountIndex, ox: ax, oy: 0, oz: az),
      );
      final centerY = mountY - spec.stringLength - spec.length / 2;
      final halfSpacing = rod.particleSpacing / 2;
      _setRest(rod.upper, ax, centerY + halfSpacing, az);
      _setRest(rod.lower, ax, centerY - halfSpacing, az);
      w[rod.upper] = w[rod.lower] = 2 / spec.mass;
      drag[rod.upper] =
          drag[rod.lower] = dragFactor(spec.dragCoefficient, 2 * spec.radius * spec.length) / 2;
      particles.dragAxis[rod.upper] = rod.lower;
      particles.dragAxis[rod.lower] = rod.upper;

      links
        ..add(Link(PointRef.particle(rod.upper), PointRef.particle(rod.lower),
            rod.particleSpacing))
        ..add(Link(rod.anchor, rod.top, spec.stringLength, slack: true));
      rodBodies.add(rod);
    }

    links
      ..add(Link(mount, clapper, config.clapperStringLength, slack: true))
      ..add(Link(clapper, const PointRef.particle(sailIndex),
          config.sailStringLength + config.sailHeight / 2,
          slack: true));

    rods = List.unmodifiable(rodBodies);
    _links = List.unmodifiable(links);
    _contacts = ClapperContacts(
      particles: particles,
      rods: rods,
      clapper: clapperIndex,
      config: config,
      events: events,
    );
  }

  void _setRest(int i, double x, double y, double z) {
    _rest[3 * i] = x;
    _rest[3 * i + 1] = y;
    _rest[3 * i + 2] = z;
  }
}
