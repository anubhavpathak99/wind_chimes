import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

/// Colours of the scene at one sun height: the sky's gradient, how much of the starfield shows,
/// and the light the chime's metal reflects.
@immutable
class SkyPalette {
  const SkyPalette({
    required this.top,
    required this.middle,
    required this.bottom,
    required this.stars,
    required this.light,
  });

  final Color top;
  final Color middle;
  final Color bottom;

  /// Starfield opacity, 0–1.
  final double stars;

  /// Overall brightness of lit surfaces, 0–1.
  final double light;

  static SkyPalette lerp(SkyPalette a, SkyPalette b, double t) => SkyPalette(
        top: Color.lerp(a.top, b.top, t)!,
        middle: Color.lerp(a.middle, b.middle, t)!,
        bottom: Color.lerp(a.bottom, b.bottom, t)!,
        stars: a.stars + (b.stars - a.stars) * t,
        light: a.light + (b.light - a.light) * t,
      );

  /// Keyframes by sun elevation, degrees. Dusk is the app's signature look.
  static const night = SkyPalette(
    top: Color(0xFF060A16),
    middle: Color(0xFF0C142C),
    bottom: Color(0xFF18203C),
    stars: 1,
    light: 0.55,
  );
  static const dusk = SkyPalette(
    top: Color(0xFF0B1426),
    middle: Color(0xFF1B2A4B),
    bottom: Color(0xFF3B3252),
    stars: 0.45,
    light: 0.75,
  );
  static const twilight = SkyPalette(
    top: Color(0xFF16294C),
    middle: Color(0xFF3C4775),
    bottom: Color(0xFFAC6F78),
    stars: 0.08,
    light: 0.85,
  );
  static const golden = SkyPalette(
    top: Color(0xFF26446F),
    middle: Color(0xFF6A7AA2),
    bottom: Color(0xFFDDA27A),
    stars: 0,
    light: 0.95,
  );
  static const day = SkyPalette(
    top: Color(0xFF2B5987),
    middle: Color(0xFF5786B3),
    bottom: Color(0xFF97B9D6),
    stars: 0,
    light: 1,
  );

  static const _keys = [
    (-18.0, night),
    (-8.0, dusk),
    (-2.0, twilight),
    (3.0, golden),
    (12.0, day),
  ];

  /// The sun elevation the fixed dusk look stands for.
  static const duskElevation = -8.0;

  static SkyPalette at(double elevation) {
    if (elevation <= _keys.first.$1) return _keys.first.$2;
    for (var i = 1; i < _keys.length; i++) {
      final (e1, p1) = _keys[i];
      if (elevation <= e1) {
        final (e0, p0) = _keys[i - 1];
        return lerp(p0, p1, (elevation - e0) / (e1 - e0));
      }
    }
    return _keys.last.$2;
  }
}

/// Sun elevation above the horizon, degrees, at [time] and a place: NOAA's low-accuracy solar
/// position equations, good to a fraction of a degree, which is plenty for a sky colour.
double solarElevation(DateTime time, {required double latitude, required double longitude}) {
  final utc = time.toUtc();
  final dayOfYear = utc.difference(DateTime.utc(utc.year)).inDays + 1;
  final hours = utc.hour + utc.minute / 60 + utc.second / 3600;
  final g = 2 * math.pi / 365 * (dayOfYear - 1 + (hours - 12) / 24);
  final equationOfTime = 229.18 *
      (0.000075 +
          0.001868 * math.cos(g) -
          0.032077 * math.sin(g) -
          0.014615 * math.cos(2 * g) -
          0.040849 * math.sin(2 * g));
  final declination = 0.006918 -
      0.399912 * math.cos(g) +
      0.070257 * math.sin(g) -
      0.006758 * math.cos(2 * g) +
      0.000907 * math.sin(2 * g) -
      0.002697 * math.cos(3 * g) +
      0.00148 * math.sin(3 * g);
  final solarMinutes = hours * 60 + equationOfTime + 4 * longitude;
  final hourAngle = (solarMinutes / 4 - 180) * math.pi / 180;
  final lat = latitude * math.pi / 180;
  final cosZenith = math.sin(lat) * math.sin(declination) +
      math.cos(lat) * math.cos(declination) * math.cos(hourAngle);
  return 90 - math.acos(cosZenith.clamp(-1.0, 1.0)) * 180 / math.pi;
}

/// Which sky to show. Follows the sun where the chime is (the chosen location, or a guess from
/// the time zone), or stays at dusk; a preview time can stand in for now while tuning.
class SkyModel {
  SkyModel({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// How often the sun is recomputed, s.
  static const recheckSeconds = 20.0;

  final DateTime Function() _clock;
  bool followsTime = true;
  double? latitude;
  double? longitude;

  /// Local solar time at the chime's place to show instead of now, hours, or null.
  double? previewHour;

  SkyPalette _palette = SkyPalette.dusk;
  double _elevation = SkyPalette.duskElevation;
  double _sinceCheck = double.infinity;

  /// Bumped whenever [palette] changes, so shaders built from it can be rebuilt.
  int version = 0;

  SkyPalette get palette => _palette;
  double get elevation => _elevation;

  /// Recomputes now rather than at the next check.
  void invalidate() => _sinceCheck = double.infinity;

  void update(double dt) {
    _sinceCheck += dt;
    if (_sinceCheck < recheckSeconds) return;
    _sinceCheck = 0;
    final elevation = followsTime ? _sunNow() : SkyPalette.duskElevation;
    if ((elevation - _elevation).abs() < 0.05 && version > 0) return;
    _elevation = elevation;
    _palette = SkyPalette.at(elevation);
    version++;
  }

  double _sunNow() {
    final now = _clock();
    final guess = latitude == null || longitude == null ? _guessPlace(now) : null;
    final lon = longitude ?? guess!.longitude;
    final lat = latitude ?? guess!.latitude;
    final preview = previewHour;
    if (preview == null) return solarElevation(now, latitude: lat, longitude: lon);
    // A preview hour is the local solar time at the chime's place.
    final utc = now.toUtc();
    final day = DateTime.utc(utc.year, utc.month, utc.day);
    final at = day.add(Duration(minutes: ((preview - lon / 15) * 60).round()));
    return solarElevation(at, latitude: lat, longitude: lon);
  }
}

/// Where the phone probably is, from its time zone alone: the standard (winter) offset gives the
/// longitude to within a time zone's width, and daylight saving's direction the hemisphere.
({double latitude, double longitude}) _guessPlace(DateTime now) {
  final january = DateTime(now.year, 1, 1).timeZoneOffset;
  final july = DateTime(now.year, 7, 1).timeZoneOffset;
  final standard = january < july ? january : july;
  final latitude = january == july ? 25.0 : (july > january ? 45.0 : -35.0);
  return (latitude: latitude, longitude: standard.inMinutes / 4);
}

/// Full-bleed sky gradient for the time of day, with twinkling stars when it's dark. The shader
/// is rebuilt only on resize or when the palette changes.
class SkyBackground extends Component {
  SkyBackground(this.sky);

  static const _starCount = 90;
  static const _groups = 3;

  final SkyModel sky;
  final Paint _paint = Paint();
  final List<Paint> _starPaints = [
    for (var i = 0; i < _groups; i++)
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.2 + 0.6 * i,
  ];
  final List<Float32List> _stars = [
    for (var i = 0; i < _groups; i++) Float32List(2 * (_starCount ~/ _groups)),
  ];
  final Float64List _unitStars = _scatter(_starCount);
  Rect _rect = Rect.zero;
  int _builtVersion = -1;
  double _time = 0;

  /// Deterministic star positions in the unit square, denser toward the top.
  static Float64List _scatter(int n) {
    final random = math.Random(7);
    final out = Float64List(2 * n);
    for (var i = 0; i < n; i++) {
      out[2 * i] = random.nextDouble();
      out[2 * i + 1] = math.pow(random.nextDouble(), 1.6) * 0.75;
    }
    return out;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _rect = Offset.zero & Size(size.x, size.y);
    for (var g = 0; g < _groups; g++) {
      final list = _stars[g];
      for (var i = 0; i < list.length ~/ 2; i++) {
        final s = i * _groups + g;
        list[2 * i] = _unitStars[2 * s] * size.x;
        list[2 * i + 1] = _unitStars[2 * s + 1] * size.y;
      }
    }
    _builtVersion = -1;
  }

  @override
  void update(double dt) {
    _time += dt;
    sky.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final p = sky.palette;
    if (_builtVersion != sky.version) {
      _builtVersion = sky.version;
      _paint.shader = Gradient.linear(
        _rect.topLeft,
        _rect.bottomLeft,
        [p.top, p.middle, p.bottom],
        const [0, 0.55, 1],
      );
    }
    canvas.drawRect(_rect, _paint);
    if (p.stars < 0.01) return;
    for (var g = 0; g < _groups; g++) {
      // Each group twinkles at its own slow rate.
      final twinkle = 0.75 + 0.25 * math.sin(_time * (0.7 + 0.45 * g) + 2.1 * g);
      final alpha = p.stars * twinkle * (0.55 + 0.15 * g);
      _starPaints[g].color = Color.fromRGBO(226, 232, 255, alpha.clamp(0.0, 1.0));
      canvas.drawRawPoints(PointMode.points, _stars[g], _starPaints[g]);
    }
  }
}
