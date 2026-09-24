import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/wind/manual_wind.dart';

void main() {
  test('names the compass point the wind comes from', () {
    expect(const ManualWind(direction: 0).compass, 'N');
    expect(const ManualWind(direction: 350).compass, 'N');
    expect(const ManualWind(direction: 45).compass, 'NE');
    expect(const ManualWind(direction: 270).compass, 'W');
  });

  test('reads like a weather report', () {
    final r = const ManualWind(speed: 6, direction: 90, gustFactor: 2).reading;
    expect(r.speed, 6);
    expect(r.gust, 12);
    expect(r.direction, 90);
  });
}
