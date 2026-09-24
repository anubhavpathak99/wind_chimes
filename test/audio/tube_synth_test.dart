import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/audio/tube_synth.dart';

const rate = 32000;

/// Signal power at [frequency] (Goertzel).
double power(Float64List x, double frequency, int from, int count) {
  final w = 2 * math.pi * frequency / rate;
  final c = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (var i = from; i < from + count; i++) {
    final s = x[i] + c * s1 - s2;
    s2 = s1;
    s1 = s;
  }
  return s1 * s1 + s2 * s2 - c * s1 * s2;
}

double rms(Float64List x, int from, int count) {
  var sum = 0.0;
  for (var i = from; i < from + count; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / count);
}

/// Energy of the first difference relative to the signal's: higher means brighter.
double brightness(Float64List x, int from, int count) {
  var diff = 0.0, raw = 0.0;
  for (var i = from + 1; i < from + count; i++) {
    final d = x[i] - x[i - 1];
    diff += d * d;
    raw += x[i] * x[i];
  }
  return math.sqrt(diff / raw);
}

void main() {
  const f = 587.33; // D5

  group('free tube physics', () {
    test('mode shapes are ±1 at the ends', () {
      for (var m = 0; m < tubeModeRatios.length; m++) {
        expect(freeTubeModeShape(m, 0), closeTo(1, 1e-6));
        expect(freeTubeModeShape(m, 1).abs(), closeTo(1, 1e-3));
      }
    });

    test('striking the middle cannot excite mode 2; mode 1 has a node near 22.4%', () {
      expect(freeTubeModeShape(1, 0.5).abs(), lessThan(1e-5));
      expect(freeTubeModeShape(0, 0.224).abs(), lessThan(0.01));
      expect(freeTubeModeShape(0, 0.5).abs(), greaterThan(0.5));
    });

    test('a shorter strike reaches higher', () {
      expect(strikeSpectrum(0, 0.4e-3), closeTo(1, 1e-9));
      expect(strikeSpectrum(3000, 0.25e-3), greaterThan(5 * strikeSpectrum(3000, 0.6e-3)));
    });
  });

  group('synthesizeTubeStrike', () {
    final soft = synthesizeTubeStrike(f, contactSeconds: 0.6e-3, strikePosition: 0.62);
    final hard = synthesizeTubeStrike(f, contactSeconds: 0.25e-3, strikePosition: 0.62);

    test('is 5 s long, peaks just below full scale and fades to silence', () {
      expect(soft.length, 5 * rate);
      expect(soft.map((s) => s.abs()).reduce(math.max), closeTo(0.9, 1e-9));
      expect(soft.last, closeTo(0, 1e-12));
    });

    test('rings at its pitch', () {
      const window = 8192;
      expect(power(soft, f, 1000, window),
          greaterThan(20 * power(soft, f * math.pow(2, 1 / 12), 1000, window)));
    });

    test('hard strikes are brighter than soft ones', () {
      expect(brightness(hard, 100, rate ~/ 4), greaterThan(brightness(soft, 100, rate ~/ 4) * 1.3));
    });

    test('where it is struck changes which partials sound', () {
      final middle = synthesizeTubeStrike(f, strikePosition: 0.5);
      final offCenter = synthesizeTubeStrike(f, strikePosition: 0.62);
      final mode2 = f * tubeModeRatios[1];
      const window = 4096;
      expect(power(offCenter, mode2, 1000, window),
          greaterThan(100 * power(middle, mode2, 1000, window)));
    });

    test('two takes differ but share the pitch', () {
      final a = synthesizeTubeStrike(f, seed: 1), b = synthesizeTubeStrike(f, seed: 2);
      var difference = 0.0;
      for (var i = 0; i < rate; i++) {
        difference += (a[i] - b[i]).abs();
      }
      expect(difference / rate, greaterThan(0.01));
      const window = 8192;
      expect(power(b, f, 1000, window) / power(a, f, 1000, window), inInclusiveRange(0.2, 5));
    });

    test('decays', () {
      expect(rms(soft, 3 * rate, rate ~/ 2), lessThan(rms(soft, 0, rate) * 0.5));
    });
  });

  group('synthesizeWindLoop', () {
    final loop = synthesizeWindLoop(seconds: 4);

    test('loops without a seam', () {
      var step = 0.0;
      for (var i = 1; i < loop.length; i++) {
        step += (loop[i] - loop[i - 1]).abs();
      }
      step /= loop.length - 1;
      expect((loop.first - loop.last).abs(), lessThan(5 * step));
    });

    test('is a soft rush, not hiss', () {
      final white = Float64List.fromList(
          List.generate(loop.length, (_) => math.Random().nextDouble() * 2 - 1));
      expect(brightness(loop, 0, rate), lessThan(brightness(white, 0, rate) / 4));
    });

    test('has no offset', () {
      final mean = loop.reduce((a, b) => a + b) / loop.length;
      expect(mean.abs(), lessThan(0.02));
    });
  });

  test('encodes a 16-bit mono PCM WAV', () {
    final wav = encodeWav16(Float64List.fromList([0, 0.5, -0.5, 1]), rate);
    final header = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 16)), 'WAVEfmt ');
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), rate);
    expect(header.getUint32(40, Endian.little), 8);
    expect(header.getInt16(46, Endian.little), 16384);
    expect(header.getInt16(50, Endian.little), 32767);
  });
}
