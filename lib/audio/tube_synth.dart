import 'dart:math' as math;
import 'dart:typed_data';

/// Bending-mode frequency ratios of a free–free tube, and the matching β·L values.
const tubeModeRatios = [1.0, 2.757, 5.404, 8.933];
const _betaL = [4.7300, 7.8532, 10.9956, 14.1372];

/// How strongly each mode radiates, before strike position and hardness.
const _modeLevels = [1.0, 0.8, 0.6, 0.45];

/// Displacement of free–free mode [mode] (0-based) at [x] along the tube (0 to 1), normalized so
/// the tube's ends are ±1. A strike at a node of a mode can't excite it: striking the middle
/// leaves out mode 2 entirely, which is why where the clapper lands changes the timbre.
double freeTubeModeShape(int mode, double x) {
  final b = _betaL[mode];
  final sigma = (_cosh(b) - math.cos(b)) / (_sinh(b) - math.sin(b));
  final bx = b * x;
  return (_cosh(bx) + math.cos(bx) - sigma * (_sinh(bx) + math.sin(bx))) / 2;
}

/// Relative spectrum of a half-sine strike lasting [contactSeconds] at [frequency]: a harder, shorter
/// contact reaches higher, which is what makes a hard hit sound bright. 1 at 0 Hz.
double strikeSpectrum(double frequency, double contactSeconds) {
  final x = frequency * contactSeconds;
  final denominator = 1 - 4 * x * x;
  if (denominator.abs() < 1e-6) return math.pi / 4;
  return (math.cos(math.pi * x) / denominator).abs();
}

/// One strike of a tube tuned to [frequency], as mono samples in -1..1.
///
/// Decaying partials at the tube's mode ratios, weighted by the mode shapes at [strikePosition]
/// and by the spectrum of a strike lasting [contactSeconds]; higher modes die faster. Each
/// partial is split into two close frequencies for the slow shimmer of a real, slightly
/// out-of-round tube, and a short click marks the strike. [seed] varies the phases, the split and
/// a hint of inharmonicity, so two takes of the same strike are not identical. The tail fades out
/// over the last [releaseSeconds]. Each partial is a damped two-pole oscillator, so no
/// trigonometry runs per sample.
Float64List synthesizeTubeStrike(
  double frequency, {
  double strikePosition = 0.5,
  double contactSeconds = 0.4e-3,
  double seconds = 5,
  double releaseSeconds = 1.5,
  int sampleRate = 32000,
  int seed = 0,
}) {
  final n = (seconds * sampleRate).round();
  final samples = Float64List(n);
  final random = math.Random(seed);
  // Higher tubes ring shorter.
  final fundamentalDecay = 2.8 * math.sqrt(523.25 / frequency);

  for (var m = 0; m < tubeModeRatios.length; m++) {
    final inharmonicity = m == 0 ? 0.0 : 0.002 * (random.nextDouble() * 2 - 1);
    final modeFrequency = frequency * tubeModeRatios[m] * (1 + inharmonicity);
    final level = _modeLevels[m] *
        freeTubeModeShape(m, strikePosition).abs() *
        strikeSpectrum(modeFrequency, contactSeconds);
    if (level < 1e-4) continue;
    final decay = fundamentalDecay / math.pow(tubeModeRatios[m], 0.8);
    final r = math.exp(-1 / (decay * sampleRate));
    final split = 0.0012 * (m + 1) * (0.7 + 0.6 * random.nextDouble());
    for (final detune in [0.0, split]) {
      final f = modeFrequency * (1 + detune);
      if (f >= sampleRate / 2) continue;
      _addDampedSine(samples, f / sampleRate, r, level / 2, random.nextDouble() * 2 * math.pi);
    }
  }

  // The strike itself: a brief, high-passed noise click, louder and shorter for hard hits.
  final hardness = (0.6e-3 - contactSeconds).clamp(0.0, 0.5e-3) / 0.5e-3;
  final clickLevel = 0.06 + 0.14 * hardness;
  final clickDecay = contactSeconds * sampleRate;
  var previous = 0.0;
  for (var i = 0; i < 6 * clickDecay && i < n; i++) {
    final noise = random.nextDouble() * 2 - 1;
    samples[i] += clickLevel * (noise - previous) * math.exp(-i / clickDecay);
    previous = noise;
  }

  // Soften the first millisecond and fade the tail so nothing clicks.
  final attack = (0.001 * sampleRate).round();
  for (var i = 0; i < attack && i < n; i++) {
    samples[i] *= i / attack;
  }
  final release = (releaseSeconds * sampleRate).round().clamp(1, n);
  for (var i = 0; i < release; i++) {
    samples[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / release);
  }
  _normalize(samples, 0.9);
  return samples;
}

/// A seamless loop of wind noise: pink noise, rolled off below ~120 Hz and above ~900 Hz, with the
/// end crossfaded into the start so it repeats without a seam.
Float64List synthesizeWindLoop({double seconds = 8, int sampleRate = 32000, int seed = 7}) {
  final n = (seconds * sampleRate).round();
  final overlap = (0.5 * sampleRate).round();
  final raw = Float64List(n + overlap);
  final random = math.Random(seed);
  // Paul Kellet's economy pink-noise filter.
  var b0 = 0.0, b1 = 0.0, b2 = 0.0;
  final lowCut = math.exp(-2 * math.pi * 120 / sampleRate);
  final highCut = math.exp(-2 * math.pi * 900 / sampleRate);
  var low = 0.0, high = 0.0;
  for (var i = 0; i < raw.length; i++) {
    final white = random.nextDouble() * 2 - 1;
    b0 = 0.99765 * b0 + white * 0.0990460;
    b1 = 0.96300 * b1 + white * 0.2965164;
    b2 = 0.57000 * b2 + white * 1.0526913;
    final pink = b0 + b1 + b2 + white * 0.1848;
    high = highCut * high + (1 - highCut) * pink;
    low = lowCut * low + (1 - lowCut) * high;
    raw[i] = high - low;
  }
  final loop = Float64List(n);
  for (var i = 0; i < n; i++) {
    loop[i] = raw[i];
  }
  for (var i = 0; i < overlap; i++) {
    final t = i / overlap;
    // Equal-power crossfade of the overshoot into the head.
    loop[i] = raw[i] * math.sin(t * math.pi / 2) + raw[n + i] * math.cos(t * math.pi / 2);
  }
  _normalize(loop, 0.8);
  return loop;
}

/// Encodes [samples] (-1..1) as a 16-bit mono PCM WAV file.
Uint8List encodeWav16(Float64List samples, int sampleRate) {
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
    bytes.setInt16(44 + 2 * i, (samples[i] * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Adds amplitude·r^i·sin(2π·cycles·i + phase) using the recurrence
/// y[i] = 2r·cos(w)·y[i−1] − r²·y[i−2].
void _addDampedSine(Float64List out, double cycles, double r, double amplitude, double phase) {
  final w = 2 * math.pi * cycles;
  final c = 2 * r * math.cos(w);
  final r2 = r * r;
  var y1 = amplitude * math.sin(phase); // y[0]
  var y2 = amplitude * math.sin(phase - w) / r; // y[−1]
  out[0] += y1;
  for (var i = 1; i < out.length; i++) {
    final y = c * y1 - r2 * y2;
    out[i] += y;
    y2 = y1;
    y1 = y;
  }
}

void _normalize(Float64List samples, double peak) {
  var max = 0.0;
  for (final s in samples) {
    max = math.max(max, s.abs());
  }
  if (max == 0) return;
  final gain = peak / max;
  for (var i = 0; i < samples.length; i++) {
    samples[i] *= gain;
  }
}

double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
