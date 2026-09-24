import 'dart:math' as math;
import 'dart:typed_data';

/// Bending-mode frequency ratios of a free–free tube.
const tubeModeRatios = [1.0, 2.757, 5.404, 8.933];
const _modeLevels = [1.0, 0.55, 0.28, 0.14];

/// Synthesizes one strike of a tube tuned to [frequency] as a 16-bit mono WAV file.
///
/// A stand-in until recorded samples arrive (Phase 3): decaying partials at the tube's mode
/// ratios, higher modes dying faster, each split into two close frequencies for the slow shimmer
/// of a real, slightly out-of-round tube, plus a brief noise click for the strike itself. Each
/// partial is a damped two-pole oscillator, so no trigonometry runs per sample.
Uint8List synthesizeTubeStrike(
  double frequency, {
  double seconds = 4,
  int sampleRate = 44100,
  int seed = 0,
}) {
  final n = (seconds * sampleRate).round();
  final samples = Float64List(n);
  final random = math.Random(seed);
  // Higher tubes ring shorter.
  final fundamentalDecay = 3.0 * math.sqrt(523.25 / frequency);

  for (var m = 0; m < tubeModeRatios.length; m++) {
    final decay = fundamentalDecay / math.pow(tubeModeRatios[m], 0.8);
    final r = math.exp(-1 / (decay * sampleRate));
    for (final split in [0.0, 0.0012 * (m + 1)]) {
      final f = frequency * tubeModeRatios[m] * (1 + split);
      if (f >= sampleRate / 2) continue;
      final w = 2 * math.pi * f / sampleRate;
      final phase = random.nextDouble() * 2 * math.pi;
      // y[i] = 2r·cos(w)·y[i−1] − r²·y[i−2] generates r^i·sin(w·i + phase).
      final c = 2 * r * math.cos(w);
      final r2 = r * r;
      final amplitude = _modeLevels[m] / 2;
      // Seed with y[0] and y[−1].
      var y1 = amplitude * math.sin(phase);
      var y2 = amplitude * math.sin(phase - w) / r;
      samples[0] += y1;
      for (var i = 1; i < n; i++) {
        final y = c * y1 - r2 * y2;
        samples[i] += y;
        y2 = y1;
        y1 = y;
      }
    }
  }

  final clickLength = (0.003 * sampleRate).round();
  for (var i = 0; i < clickLength && i < n; i++) {
    samples[i] += 0.15 * (random.nextDouble() * 2 - 1) * math.exp(-i / (0.0006 * sampleRate));
  }

  // Soften the very first millisecond and the tail so nothing clicks.
  final attack = (0.001 * sampleRate).round();
  for (var i = 0; i < attack && i < n; i++) {
    samples[i] *= i / attack;
  }
  final release = (0.05 * sampleRate).round();
  for (var i = 0; i < release && i < n; i++) {
    samples[n - 1 - i] *= i / release;
  }

  var peak = 0.0;
  for (final s in samples) {
    peak = math.max(peak, s.abs());
  }
  final gain = peak > 0 ? 0.9 / peak : 0.0;
  return _wav16(samples, sampleRate, gain);
}

Uint8List _wav16(Float64List samples, int sampleRate, double gain) {
  final dataBytes = samples.length * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i] * gain * 32767).round().clamp(-32768, 32767);
    bytes.setInt16(44 + 2 * i, v, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
