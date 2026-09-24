import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';

typedef HitVoice = ({double volume, double pan, double speed});

/// Turns an impact's physics into playback parameters.
///
/// Loudness follows the logarithm of the impulse, since impulses span about two orders of
/// magnitude and hearing is logarithmic; small random gain and pitch offsets keep repeated hits on
/// one tube from sounding identical. Phase 3 adds sample layers, strike-position variants and
/// brightness.
class HitMapper {
  HitMapper({required this.pans, math.Random? random}) : _random = random ?? math.Random();

  /// Stereo position per tube, -1 (left) to 1 (right).
  final List<double> pans;
  final math.Random _random;

  /// Softest impulse that makes a sound, and the impulse that reaches full volume, N·s.
  static const double quietestImpulse = 3e-4;
  static const double loudestImpulse = 1.5e-2;
  static const double quietestDb = -30;
  static const double gainJitterDb = 1.5;
  static const double detuneCents = 6;

  /// Stereo spread of the ring: a tube at the far right pans this far.
  static const double panWidth = 0.35;

  /// Tube pans from their positions on the ring as the viewer sees it.
  static List<double> pansFor(List<RodBody> rods) =>
      [for (final rod in rods) panWidth * math.sin(rod.ringAngle)];

  /// Where [impulse] falls between the quietest and loudest hit, 0 to 1.
  static double intensity(double impulse) {
    if (!(impulse > quietestImpulse)) return 0;
    final s = math.log(impulse / quietestImpulse) / math.log(loudestImpulse / quietestImpulse);
    return s.clamp(0.0, 1.0);
  }

  /// Playback for [event], or null if it is too soft to hear.
  HitVoice? map(CollisionEvent event) {
    if (!(event.impulse > quietestImpulse)) return null;
    final db = quietestDb * (1 - intensity(event.impulse)) + gainJitterDb * _jitter();
    final cents = detuneCents * _jitter();
    return (
      volume: math.pow(10, db / 20).toDouble().clamp(0.0, 1.0),
      pan: pans[event.rodId],
      speed: math.pow(2, cents / 1200).toDouble(),
    );
  }

  double _jitter() => _random.nextDouble() * 2 - 1;
}
