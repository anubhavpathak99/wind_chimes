import 'dart:math' as math;

/// Physical description of one tube. SI units throughout.
final class RodSpec {
  const RodSpec({
    required this.frequency,
    required this.length,
    required this.radius,
    required this.mass,
    required this.stringLength,
    required this.dragCoefficient,
  });

  /// Fundamental frequency in Hz; the audio layer uses it to pick the note.
  final double frequency;

  /// Tube length in meters.
  final double length;

  /// Outer radius in meters.
  final double radius;

  final double mass;

  /// Distance from the mount's attachment point to the top of the tube.
  final double stringLength;

  /// Cross-flow drag coefficient of the tube (a cylinder is about 1.1).
  final double dragCoefficient;
}

/// Everything needed to build a chime. Immutable; a change rebuilds the simulation.
final class ChimeConfig {
  const ChimeConfig({
    required this.rods,
    required this.ropeLength,
    required this.mountRadius,
    required this.mountThickness,
    required this.mountMass,
    required this.ringRadius,
    required this.clapperRadius,
    required this.clapperMass,
    required this.clapperStringLength,
    required this.sailWidth,
    required this.sailHeight,
    required this.sailMass,
    required this.sailStringLength,
    this.restitution = 0.65,
    this.restingSpeed = 0.01,
    this.friction = 0.15,
    this.linearDamping = 0.05,
    this.gravity = 9.81,
    this.airDensity = 1.2,
    this.maxSpeed = 6.0,
    this.minApproachSpeed = 0.02,
    this.retriggerInterval = 0.03,
    this.contactHysteresis = 0.001,
    this.touchFrequency = 6.0,
    this.touchDampingRatio = 0.7,
    this.maxTouchAcceleration = 120.0,
    this.torsionStiffness = 4e-4,
    this.torsionDamping = 3e-4,
    this.rodRestitution = 0.6,
  });

  /// Five aluminium tubes tuned to a major pentatonic scale on C5, with a wooden clapper
  /// centered at 60% of the shortest tube and the sail hanging clear below the longest.
  /// The clapper is wider than the opening between neighbouring tubes, so it can't escape the ring.
  factory ChimeConfig.pentatonicAluminium() {
    const rootHz = 523.25; // C5
    const semitones = [0, 2, 4, 7, 9];
    const outerRadius = 0.009;
    const wall = 0.001;
    const rodString = 0.05;

    final rods = [
      for (final s in semitones)
        _aluminiumRod(
          frequency: rootHz * math.pow(2, s / 12),
          outerRadius: outerRadius,
          wallThickness: wall,
          stringLength: rodString,
        ),
    ];
    final shortest = rods.map((r) => r.length).reduce(math.min);
    final longest = rods.map((r) => r.length).reduce(math.max);

    const sailHeight = 0.13;
    const sailClearance = 0.04;
    final clapperString = rodString + 0.6 * shortest;
    final sailTop = rodString + longest + sailClearance;

    return ChimeConfig(
      rods: rods,
      ropeLength: 0.12,
      mountRadius: 0.07,
      mountThickness: 0.018,
      mountMass: 0.12,
      ringRadius: 0.046,
      clapperRadius: 0.025,
      clapperMass: 0.035,
      clapperStringLength: clapperString,
      sailWidth: 0.09,
      sailHeight: sailHeight,
      sailMass: 0.015,
      sailStringLength: sailTop - clapperString,
    );
  }

  /// A copy with some tuning parameters changed, for live tuning and sweeps.
  ChimeConfig copyWith({
    double? ringRadius,
    double? clapperRadius,
    double? clapperMass,
    double? sailMass,
    double? restitution,
    double? restingSpeed,
    double? friction,
    double? linearDamping,
    double? torsionStiffness,
    double? torsionDamping,
  }) =>
      ChimeConfig(
        rods: rods,
        ropeLength: ropeLength,
        mountRadius: mountRadius,
        mountThickness: mountThickness,
        mountMass: mountMass,
        ringRadius: ringRadius ?? this.ringRadius,
        clapperRadius: clapperRadius ?? this.clapperRadius,
        clapperMass: clapperMass ?? this.clapperMass,
        clapperStringLength: clapperStringLength,
        sailWidth: sailWidth,
        sailHeight: sailHeight,
        sailMass: sailMass ?? this.sailMass,
        sailStringLength: sailStringLength,
        restitution: restitution ?? this.restitution,
        restingSpeed: restingSpeed ?? this.restingSpeed,
        friction: friction ?? this.friction,
        linearDamping: linearDamping ?? this.linearDamping,
        gravity: gravity,
        airDensity: airDensity,
        maxSpeed: maxSpeed,
        minApproachSpeed: minApproachSpeed,
        retriggerInterval: retriggerInterval,
        contactHysteresis: contactHysteresis,
        touchFrequency: touchFrequency,
        touchDampingRatio: touchDampingRatio,
        maxTouchAcceleration: maxTouchAcceleration,
        torsionStiffness: torsionStiffness ?? this.torsionStiffness,
        torsionDamping: torsionDamping ?? this.torsionDamping,
        rodRestitution: rodRestitution,
      );

  final List<RodSpec> rods;

  /// Hook to mount.
  final double ropeLength;
  final double mountRadius;
  final double mountThickness;
  final double mountMass;

  /// Radius of the circle the tubes hang on, measured to the tube axes.
  final double ringRadius;

  final double clapperRadius;
  final double clapperMass;

  /// Mount center to clapper center.
  final double clapperStringLength;

  final double sailWidth;
  final double sailHeight;
  final double sailMass;

  /// Clapper center to the top edge of the sail.
  final double sailStringLength;

  /// Coefficient of restitution for clapper–tube impacts.
  final double restitution;

  /// Impacts slower than this (m/s) don't bounce, so a clapper at rest against a tube settles
  /// instead of jittering.
  final double restingSpeed;

  /// Coulomb friction coefficient for clapper–tube contacts.
  final double friction;

  /// Linear velocity damping in 1/s, so the chime settles in still air.
  final double linearDamping;

  final double gravity;
  final double airDensity;

  /// Speed clamp in m/s; also what guarantees no tunnelling at 480 Hz substeps.
  final double maxSpeed;

  /// Impacts slower than this (m/s) make no sound.
  final double minApproachSpeed;

  /// Minimum time in seconds between two events on the same tube.
  final double retriggerInterval;

  /// A contact must separate by this much (m) before it can begin again.
  final double contactHysteresis;

  /// Natural frequency (Hz) of the spring that pulls a grabbed body toward the finger.
  final double touchFrequency;
  final double touchDampingRatio;
  final double maxTouchAcceleration;

  /// How strongly the twisted rope turns the mount back, N·m/rad. A cord is soft in torsion: the
  /// chime turns slowly to and fro, over seconds.
  final double torsionStiffness;

  /// Damping of the mount's turn, N·m·s/rad.
  final double torsionDamping;

  /// Restitution when two tubes knock together.
  final double rodRestitution;

  /// Moment of inertia of the mount disc about its axis, kg·m².
  double get mountInertia => 0.5 * mountMass * mountRadius * mountRadius;

  /// Where the clapper meets tube [rod] at rest, as a fraction of the tube's length from its top.
  double restStrikePosition(int rod) =>
      (clapperStringLength - rods[rod].stringLength) / rods[rod].length;

  /// Mount center to sail center.
  double get sailCenterDrop => clapperStringLength + sailStringLength + sailHeight / 2;

  /// Clearance between the clapper and a tube at rest.
  double gapToRod(int rod) => ringRadius - rods[rod].radius - clapperRadius;

  /// Narrowest clear opening between two neighbouring tubes at rest.
  double get openingBetweenRods {
    final widest = rods.map((r) => r.radius).reduce(math.max);
    return 2 * ringRadius * math.sin(math.pi / rods.length) - 2 * widest;
  }
}

RodSpec _aluminiumRod({
  required double frequency,
  required double outerRadius,
  required double wallThickness,
  required double stringLength,
}) {
  const youngsModulus = 69e9;
  const density = 2700.0;
  final length = tubeLengthForFrequency(
    frequency,
    outerRadius: outerRadius,
    wallThickness: wallThickness,
    youngsModulus: youngsModulus,
    density: density,
  );
  final innerRadius = outerRadius - wallThickness;
  final linearDensity =
      density * math.pi * (outerRadius * outerRadius - innerRadius * innerRadius);
  return RodSpec(
    frequency: frequency,
    length: length,
    radius: outerRadius,
    mass: linearDensity * length,
    stringLength: stringLength,
    dragCoefficient: 1.1,
  );
}

/// Length of a free–free tube whose first bending mode is at [frequency]:
/// f = (β₁L)² / (2π·L²) · √(E·I / (ρ·A)), with β₁L = 4.730 and I/A = (r_o² + r_i²) / 4.
double tubeLengthForFrequency(
  double frequency, {
  required double outerRadius,
  required double wallThickness,
  required double youngsModulus,
  required double density,
}) {
  const beta1L = 4.730;
  final innerRadius = outerRadius - wallThickness;
  final radiusOfGyrationSq = (outerRadius * outerRadius + innerRadius * innerRadius) / 4;
  final waveSpeed = math.sqrt(youngsModulus / density * radiusOfGyrationSq);
  return math.sqrt(beta1L * beta1L / (2 * math.pi * frequency) * waveSpeed);
}
