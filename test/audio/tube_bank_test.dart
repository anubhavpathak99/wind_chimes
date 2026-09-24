import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/audio/tube_bank.dart';

void main() {
  const layout = TubeBankLayout(seconds: 0.2);
  const frequencies = [523.25, 587.33, 659.26];

  test('a sample comes out the same whether built first or with the rest', () {
    final first = [for (var t = 0; t < frequencies.length; t++) layout.firstSampleOf(t)];
    final starter = buildTubeBank((frequencies: frequencies, layout: layout, only: first, wind: true));
    final full = buildTubeBank((frequencies: frequencies, layout: layout, only: null, wind: false));

    expect(starter.tubes.keys, unorderedEquals(first));
    expect(starter.wind, isNotNull);
    expect(full.wind, isNull);
    expect(full.tubes.length, frequencies.length * layout.samplesPerTube);
    for (final i in first) {
      expect(starter.tubes[i], full.tubes[i], reason: 'sample $i');
    }
  });

  test("every sample maps back to its tube and that tube's first sample", () {
    for (var tube = 0; tube < frequencies.length; tube++) {
      for (var layer = 0; layer < layout.layers; layer++) {
        final i = layout.sampleIndex(tube, layer: layer, position: 1, take: 1);
        expect(layout.tubeOf(i), tube);
      }
      expect(layout.tubeOf(layout.firstSampleOf(tube)), tube);
    }
  });
}
