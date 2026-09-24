import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/game/render/sky.dart';

void main() {
  const berlin = (lat: 52.52, lon: 13.405);
  double sun(DateTime utc) => solarElevation(utc, latitude: berlin.lat, longitude: berlin.lon);

  test('the sun is where it should be over Berlin', () {
    // Solar noon at the solstices: 90° − latitude ± the tilt of the Earth's axis.
    expect(sun(DateTime.utc(2026, 6, 21, 11, 7)), closeTo(90 - 52.52 + 23.44, 0.6));
    expect(sun(DateTime.utc(2026, 12, 21, 11, 5)), closeTo(90 - 52.52 - 23.44, 0.6));
    // Sunset on the summer solstice is at about 19:33 UTC: the centre is just below the horizon.
    expect(sun(DateTime.utc(2026, 6, 21, 19, 33)), closeTo(-0.8, 1.0));
    expect(sun(DateTime.utc(2026, 6, 21, 23, 30)), lessThan(-12));
  });

  test('palettes run from night through dusk to day', () {
    expect(SkyPalette.at(-40).stars, 1);
    expect(SkyPalette.at(SkyPalette.duskElevation).top, SkyPalette.dusk.top);
    expect(SkyPalette.at(40).light, 1);
    var previous = SkyPalette.at(-30).light;
    for (var e = -29.0; e <= 30; e++) {
      final light = SkyPalette.at(e).light;
      expect(light, greaterThanOrEqualTo(previous), reason: '$e°');
      previous = light;
    }
  });

  test('follows the time where the chime is, or stays at dusk', () {
    var now = DateTime(2026, 6, 21, 13);
    final sky = SkyModel(clock: () => now)
      ..latitude = 52.52
      ..longitude = 13.4
      ..update(0);
    final version = sky.version;
    expect(sky.palette.light, 1, reason: 'midday');

    sky
      ..followsTime = false
      ..invalidate()
      ..update(0);
    expect(sky.palette.top, SkyPalette.dusk.top);
    expect(sky.version, greaterThan(version));

    sky
      ..followsTime = true
      ..previewHour = 1
      ..invalidate()
      ..update(0);
    // A midsummer night in Berlin never gets fully dark.
    expect(sky.palette.stars, greaterThan(0.6), reason: 'a preview at 1 am is night');

    // Only rechecked every so often.
    sky.previewHour = 13;
    now = now.add(const Duration(seconds: 5));
    sky.update(5);
    expect(sky.palette.stars, greaterThan(0.6));
  });
}
