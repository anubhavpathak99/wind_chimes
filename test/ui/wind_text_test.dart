import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/settings/app_settings.dart';
import 'package:wind_chimes/ui/wind_text.dart';

void main() {
  test('speeds in each unit', () {
    expect(WindText.speed(3, SpeedUnit.kilometersPerHour), '11 km/h');
    expect(WindText.speed(3, SpeedUnit.milesPerHour), '7 mph');
    expect(WindText.speed(3, SpeedUnit.knots), '6 kn');
    expect(WindText.speed(3.04, SpeedUnit.metersPerSecond), '3.0 m/s');
    expect(WindText.speed(12.4, SpeedUnit.metersPerSecond), '12 m/s');
  });

  test('Beaufort forces and names', () {
    expect(WindText.beaufort(0.2), 0);
    expect(WindText.beaufortName(0.2), 'Calm');
    expect(WindText.beaufortName(3), 'Light breeze');
    expect(WindText.beaufortName(4.5), 'Gentle breeze');
    expect(WindText.beaufortName(9), 'Fresh breeze');
    expect(WindText.beaufortName(18), 'Gale');
    expect(WindText.beaufort(40), 12);
  });

  test('the Beaufort slider scale inverts, and lands inside each force', () {
    for (final v in [0.5, 2.0, 4.3, 9.0, 20.0]) {
      expect(WindText.speedForBeaufort(WindText.beaufortScale(v)), closeTo(v, 1e-9));
    }
    for (var force = 1; force <= 9; force++) {
      expect(WindText.beaufort(WindText.speedForBeaufort(force.toDouble())), force);
    }
  });
}
