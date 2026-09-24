import 'dart:typed_data';

import 'tube_synth.dart';

/// Layout of the synthesized sample bank: for every tube, one sample per combination of strike
/// hardness (layer), strike position and take.
class TubeBankLayout {
  const TubeBankLayout({
    this.contactSeconds = const [0.6e-3, 0.25e-3],
    this.strikePositions = const [0.5, 0.62],
    this.takes = 2,
    this.seconds = 5,
    this.sampleRate = 32000,
  });

  /// Strike contact time per layer, softest first. Shorter contact is a harder, brighter hit.
  final List<double> contactSeconds;

  /// Where along the tube (0 top, 1 bottom) each position variant is struck. The middle leaves out
  /// mode 2; off-center brings it in.
  final List<double> strikePositions;

  /// Alternate takes per variant, for round-robin.
  final int takes;
  final double seconds;
  final int sampleRate;

  int get layers => contactSeconds.length;
  int get samplesPerTube => layers * strikePositions.length * takes;

  int sampleIndex(int tube, {required int layer, required int position, required int take}) =>
      ((tube * layers + layer) * strikePositions.length + position) * takes + take;

  /// The position variant closest to [strikePos].
  int nearestPosition(double strikePos) {
    var best = 0;
    for (var i = 1; i < strikePositions.length; i++) {
      if ((strikePositions[i] - strikePos).abs() < (strikePositions[best] - strikePos).abs()) {
        best = i;
      }
    }
    return best;
  }
}

typedef TubeBankRequest = ({List<double> frequencies, TubeBankLayout layout});
typedef TubeBank = ({List<Uint8List> tubes, Uint8List wind});

/// Synthesizes every sample in the layout, as WAV files in sample-index order, plus the wind loop.
/// Self-contained so it can run in a background isolate.
TubeBank buildTubeBank(TubeBankRequest request) {
  final layout = request.layout;
  final tubes = <Uint8List>[];
  for (var tube = 0; tube < request.frequencies.length; tube++) {
    for (var layer = 0; layer < layout.layers; layer++) {
      for (var position = 0; position < layout.strikePositions.length; position++) {
        for (var take = 0; take < layout.takes; take++) {
          final samples = synthesizeTubeStrike(
            request.frequencies[tube],
            strikePosition: layout.strikePositions[position],
            contactSeconds: layout.contactSeconds[layer],
            seconds: layout.seconds,
            sampleRate: layout.sampleRate,
            seed: layout.sampleIndex(tube, layer: layer, position: position, take: take),
          );
          tubes.add(encodeWav16(samples, layout.sampleRate));
        }
      }
    }
  }
  final wind = encodeWav16(synthesizeWindLoop(sampleRate: layout.sampleRate), layout.sampleRate);
  return (tubes: tubes, wind: wind);
}
