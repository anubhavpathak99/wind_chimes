import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/weather/ambient_wind.dart';

void main() {
  test('is a gentle breeze that changes slowly', () {
    const ambient = AmbientWind();
    final start = DateTime.utc(2026, 9, 24);
    var previous = ambient.at(start);
    var lowest = previous.speed, highest = previous.speed;
    for (var s = 1; s < 3 * 3600; s++) {
      final r = ambient.at(start.add(Duration(seconds: s)));
      expect((r.speed - previous.speed).abs(), lessThan(0.02), reason: 'at $s s');
      expect(r.direction, inInclusiveRange(225, 285));
      expect(r.gust, closeTo(r.speed * AmbientWind.gustFactor, 1e-9));
      lowest = r.speed < lowest ? r.speed : lowest;
      highest = r.speed > highest ? r.speed : highest;
      previous = r;
    }
    expect(lowest, greaterThan(1.5));
    expect(highest, lessThan(3.6));
    expect(highest - lowest, greaterThan(1), reason: 'it does vary');
  });
}
