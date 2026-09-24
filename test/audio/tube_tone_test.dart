import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/audio/tube_tone.dart';

const sampleRate = 44100;

Float64List pcm(Uint8List wav) {
  final data = ByteData.sublistView(wav, 44);
  return Float64List.fromList(
      [for (var i = 0; i < data.lengthInBytes ~/ 2; i++) data.getInt16(2 * i, Endian.little) / 32768]);
}

/// Signal power at [frequency] (Goertzel).
double power(Float64List x, double frequency, int from, int count) {
  final w = 2 * math.pi * frequency / sampleRate;
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

void main() {
  const f = 587.33; // D5
  final wav = synthesizeTubeStrike(f, seconds: 3);
  final samples = pcm(wav);

  test('is a 16-bit mono PCM WAV of the requested length', () {
    final header = ByteData.sublistView(wav, 0, 44);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 16)), 'WAVEfmt ');
    expect(header.getUint16(20, Endian.little), 1);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), sampleRate);
    expect(header.getUint16(34, Endian.little), 16);
    expect(samples.length, 3 * sampleRate);
  });

  test('peaks just below full scale and ends in silence', () {
    final peak = samples.map((s) => s.abs()).reduce(math.max);
    expect(peak, closeTo(0.9, 0.01));
    expect(samples.last, 0);
  });

  test('rings at its pitch with the tube overtones', () {
    const window = 8192;
    final fundamental = power(samples, f, 2000, window);
    expect(fundamental, greaterThan(20 * power(samples, f * math.pow(2, 1 / 12), 2000, window)));
    expect(power(samples, f * tubeModeRatios[1], 2000, window),
        greaterThan(20 * power(samples, f * 2, 2000, window)));
  });

  test('decays, overtones first', () {
    expect(rms(samples, 2 * sampleRate, sampleRate), lessThan(rms(samples, 0, sampleRate) * 0.6));
    // Brightness: energy of the first difference (which weights overtones) relative to the
    // signal's. Averaged over half a second so the partials' slow beating doesn't dominate.
    double brightness(int from) {
      const n = sampleRate ~/ 2;
      var diff = 0.0, raw = 0.0;
      for (var i = from + 1; i < from + n; i++) {
        final d = samples[i] - samples[i - 1];
        diff += d * d;
        raw += samples[i] * samples[i];
      }
      return math.sqrt(diff / raw);
    }

    expect(brightness(2 * sampleRate), lessThan(brightness(1000) * 0.8));
  });
}
