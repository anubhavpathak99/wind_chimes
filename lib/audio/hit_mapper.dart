import 'dart:math' as math;

import 'package:chime_sim/chime_sim.dart';

import 'tube_bank.dart';

typedef HitVoice = ({
  int rod,
  int sample,
  double volume,
  double pan,
  double speed,
  double intensity,
});

/// Turns an impact's physics into a voice to play.
///
/// Loudness follows the logarithm of the impulse, since impulses span about two orders of
/// magnitude and hearing is logarithmic. Harder hits tend to the bright layer, with a random
/// overlap so the switch is never audible; glancing blows sound softer. The strike position picks
/// the variant struck nearest that point. Takes alternate so a tube never plays the same sample
/// twice running, and small gain and pitch offsets keep even identical samples from sounding
/// identical.
class HitMapper {
  HitMapper({required this.pans, required this.layout, math.Random? random})
      : _random = random ?? math.Random(),
        _lastSample = List.filled(pans.length, -1);

  /// Stereo position per tube, -1 (left) to 1 (right).
  final List<double> pans;
  final TubeBankLayout layout;
  final math.Random _random;
  final List<int> _lastSample;

  /// Softest impulse that makes a sound, and the impulse that reaches full volume, N·s.
  static const double quietestImpulse = 3e-4;
  static const double loudestImpulse = 1.5e-2;
  static const double quietestDb = -30;
  static const double gainJitterDb = 1.5;
  static const double detuneCents = 6;

  /// How much a fully grazing blow is darkened, in intensity units.
  static const double glancingDarkening = 0.25;

  /// Width of the random overlap between layers, in intensity units.
  static const double layerOverlap = 0.6;

  /// A tube knocking a tube is a brief metal-on-metal contact, brighter than the wooden clapper;
  /// and since both tubes sound, each plays a little quieter.
  static const double clinkBrightening = 0.4;
  static const double clinkDb = -6;

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

  /// The voice for [event], or null if it is too soft to hear.
  HitVoice? map(CollisionEvent event) {
    if (!(event.impulse > quietestImpulse)) return null;
    final rod = event.rodId;
    final s = intensity(event.impulse);

    final clink = event.isClink;
    final brightness =
        (s - glancingDarkening * event.glancing + (clink ? clinkBrightening : 0)).clamp(0.0, 1.0);
    final layer = (brightness * (layout.layers - 1) + (_random.nextDouble() - 0.5) * layerOverlap)
        .round()
        .clamp(0, layout.layers - 1);
    final position = layout.nearestPosition(event.strikePos);
    var take = _random.nextInt(layout.takes);
    var sample = layout.sampleIndex(rod, layer: layer, position: position, take: take);
    if (sample == _lastSample[rod] && layout.takes > 1) {
      take = (take + 1) % layout.takes;
      sample = layout.sampleIndex(rod, layer: layer, position: position, take: take);
    }
    _lastSample[rod] = sample;

    final db = quietestDb * (1 - s) + gainJitterDb * _jitter() + (clink ? clinkDb : 0);
    final cents = detuneCents * _jitter();
    return (
      rod: rod,
      sample: sample,
      volume: math.pow(10, db / 20).toDouble().clamp(0.0, 1.0),
      pan: pans[rod],
      speed: math.pow(2, cents / 1200).toDouble(),
      intensity: s,
    );
  }

  double _jitter() => _random.nextDouble() * 2 - 1;
}
