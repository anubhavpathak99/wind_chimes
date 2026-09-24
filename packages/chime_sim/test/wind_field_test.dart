import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chime_sim/chime_sim.dart';
import 'package:test/test.dart';

const dt = ChimeSimulation.stepDt;

SimInputs windInputs(
  double speed, {
  double direction = 270,
  double gustFactor = 1,
  double response = 30,
}) =>
    SimInputs()
      ..windSpeed = speed
      ..windGust = speed * gustFactor
      ..windDirection = direction
      ..windResponseTime = response;

int steps(double seconds) => (seconds / dt).round();

void main() {
  group('chimeSpeed', () {
    test('calm stays calm', () {
      expect(WindField.chimeSpeed(0, Placement.garden), 0);
    });

    test('light wind is scaled by exposure', () {
      expect(WindField.chimeSpeed(1, Placement.garden), closeTo(0.6, 0.01));
      expect(WindField.chimeSpeed(1, Placement.open), closeTo(0.85, 0.01));
    });

    test('rises with wind but never passes the soft cap', () {
      var previous = -1.0;
      for (var speed = 0.0; speed <= 60; speed += 1) {
        final chime = WindField.chimeSpeed(speed, Placement.open);
        expect(chime, greaterThan(previous));
        expect(chime, lessThan(WindField.softCap));
        previous = chime;
      }
    });

    test('sensitivity multiplies', () {
      expect(WindField.chimeSpeed(4, Placement.garden, sensitivity: 2),
          closeTo(2 * WindField.chimeSpeed(4, Placement.garden), 1e-12));
    });
  });

  test('Ornstein–Uhlenbeck noise has zero mean, unit variance and the configured memory', () {
    const tau = 2.0, step = 0.01, lag = 200; // lag = tau / step
    final ou = OrnsteinUhlenbeck(tau, Gaussian(math.Random(3)));
    final values = Float64List(400000);
    for (var i = 0; i < values.length; i++) {
      values[i] = ou.step(step);
    }
    var mean = 0.0;
    for (final v in values) {
      mean += v;
    }
    mean /= values.length;
    var variance = 0.0, covariance = 0.0;
    for (var i = 0; i < values.length; i++) {
      variance += (values[i] - mean) * (values[i] - mean);
      if (i >= lag) covariance += (values[i] - mean) * (values[i - lag] - mean);
    }
    variance /= values.length;
    covariance /= values.length - lag;
    expect(mean, closeTo(0, 0.1));
    expect(variance, closeTo(1, 0.1));
    expect(covariance / variance, closeTo(math.exp(-1), 0.08));
  });

  group('WindField', () {
    test('blows away from where the wind comes from', () {
      // Scene: x = east, z = toward the viewer, who faces north.
      for (final (from, ex, ez) in [
        (270.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
        (90.0, -1.0, 0.0),
        (180.0, 0.0, -1.0),
      ]) {
        final field = WindField(stepDt: dt);
        final inputs = windInputs(5, direction: from);
        field.snapToTarget(inputs);
        var sumX = 0.0, sumZ = 0.0;
        final n = steps(120);
        for (var i = 0; i < n; i++) {
          field.step(inputs);
          sumX += field.x;
          sumZ += field.z;
        }
        final mean = WindField.chimeSpeed(5, Placement.garden);
        expect(sumX / n / mean, closeTo(ex, 0.15), reason: 'from $from°');
        expect(sumZ / n / mean, closeTo(ez, 0.15), reason: 'from $from°');
      }
    });

    test('eases toward a new mean with the response time', () {
      final field = WindField(stepDt: dt);
      final inputs = windInputs(5, response: 30);
      for (var i = 0; i < steps(30); i++) {
        field.step(inputs);
      }
      final target = WindField.chimeSpeed(5, Placement.garden);
      expect(field.meanSpeed / target, closeTo(1 - math.exp(-1), 0.01));
    });

    test('turns through north the short way', () {
      final field = WindField(stepDt: dt);
      final inputs = windInputs(5, direction: 350, response: 5);
      field.snapToTarget(inputs);
      inputs.windDirection = 10;
      final target = WindField.chimeSpeed(5, Placement.garden);
      var weakest = double.infinity;
      for (var i = 0; i < steps(30); i++) {
        field.step(inputs);
        weakest = math.min(weakest, field.meanSpeed / target);
      }
      expect(weakest, greaterThan(0.95));
    });

    test('gusts raise the peaks, not the mean', () {
      ({double mean, double peak}) run(double gustFactor) {
        final field = WindField(stepDt: dt, seed: 9);
        final inputs = windInputs(6, gustFactor: gustFactor);
        field.snapToTarget(inputs);
        var sum = 0.0, peak = 0.0;
        final n = steps(600);
        for (var i = 0; i < n; i++) {
          field.step(inputs);
          sum += field.speed;
          peak = math.max(peak, field.speed);
        }
        return (mean: sum / n, peak: peak);
      }

      final steady = run(1), gusty = run(2);
      expect(gusty.peak, greaterThan(steady.peak * 1.2));
      expect(gusty.mean, lessThan(steady.mean * 1.25));
    });

    test('is reproducible from its seed', () {
      final a = WindField(stepDt: dt, seed: 4), b = WindField(stepDt: dt, seed: 4);
      final inputs = windInputs(6, gustFactor: 1.5);
      for (var i = 0; i < steps(60); i++) {
        a.step(inputs);
        b.step(inputs);
      }
      expect(a.x, b.x);
      expect(a.z, b.z);
    });

    test('reaches downwind points later, at the mean wind speed', () {
      final field = WindField(stepDt: dt, seed: 5);
      final inputs = windInputs(6, gustFactor: 1.5);
      field.snapToTarget(inputs);
      final out = Float64List(2);
      final upwind = <double>[], downwind = <double>[];
      for (var i = 0; i < steps(20); i++) {
        field.step(inputs);
        field.sampleAt(-WindField.reach, 0, out, 0);
        upwind.add(out[0]);
        field.sampleAt(0.1, 0, out, 0);
        downwind.add(out[0]);
      }
      final lag = (0.1 + WindField.reach) / field.meanSpeed / dt;
      expect(lag, greaterThan(2));
      for (var i = 100; i < upwind.length; i++) {
        final back = i - lag;
        final k = back.floor();
        final expected = upwind[k] + (upwind[k + 1] - upwind[k]) * (back - k);
        expect(downwind[i], closeTo(expected, 1e-9));
      }
    });
  });
}
