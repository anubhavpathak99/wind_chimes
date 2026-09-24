import 'package:chime_sim/chime_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/wind/manual_wind.dart';

void main() {
  test('names the compass point the wind comes from', () {
    expect(const ManualWind(direction: 0).compass, 'N');
    expect(const ManualWind(direction: 350).compass, 'N');
    expect(const ManualWind(direction: 45).compass, 'NE');
    expect(const ManualWind(direction: 270).compass, 'W');
  });

  test('writes reported-style wind into the simulation inputs', () {
    final inputs = SimInputs();
    const ManualWind(speed: 6, direction: 90, gustFactor: 2, placement: Placement.open).applyTo(inputs);
    expect(inputs.windSpeed, 6);
    expect(inputs.windGust, 12);
    expect(inputs.windDirection, 90);
    expect(inputs.placement, Placement.open);
    expect(inputs.windResponseTime, ManualWind.responseTime);
  });
}
