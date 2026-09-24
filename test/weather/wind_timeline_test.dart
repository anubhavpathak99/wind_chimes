import 'package:flutter_test/flutter_test.dart';
import 'package:wind_chimes/weather/wind_timeline.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 24, 12);
  WindSample sample(int minutes, double speed, double direction, [double? gust]) => WindSample(
        t0.add(Duration(minutes: minutes)),
        WindReading(speed: speed, gust: gust ?? speed * 1.5, direction: direction),
      );

  test('interpolates speed and gust linearly between steps', () {
    final timeline = WindTimeline([sample(0, 2, 270, 3), sample(15, 6, 270, 11)]);
    final r = timeline.at(t0.add(const Duration(minutes: 5)));
    expect(r.speed, closeTo(2 + 4 / 3, 1e-9));
    expect(r.gust, closeTo(3 + 8 / 3, 1e-9));
    expect(r.direction, closeTo(270, 1e-9));
  });

  test('turns through north, not the long way round', () {
    final timeline = WindTimeline([sample(0, 5, 350), sample(15, 5, 10)]);
    final middle = timeline.at(t0.add(const Duration(seconds: 450)));
    expect(middle.direction, anyOf(closeTo(0, 1e-6), closeTo(360, 1e-6)));
    final early = timeline.at(t0.add(const Duration(minutes: 3)));
    expect(early.direction, closeTo(354, 0.5));
  });

  test('a calm step does not drag the direction', () {
    final timeline = WindTimeline([sample(0, 0, 90), sample(15, 4, 180)]);
    expect(timeline.at(t0.add(const Duration(minutes: 3))).direction, closeTo(180, 1e-6));
  });

  test('holds the end values and knows what it covers', () {
    final timeline = WindTimeline([sample(15, 4, 180), sample(0, 2, 90)]);
    expect(timeline.start, t0, reason: 'sorted by time');
    expect(timeline.at(t0.subtract(const Duration(hours: 1))).speed, 2);
    expect(timeline.at(t0.add(const Duration(hours: 1))).speed, 4);
    expect(timeline.covers(t0.subtract(const Duration(minutes: 10))), isTrue);
    expect(timeline.covers(t0.add(const Duration(minutes: 29))), isTrue);
    expect(timeline.covers(t0.add(const Duration(minutes: 31))), isFalse);
  });

  test('survives a round trip through JSON', () {
    final timeline = WindTimeline([sample(0, 2.5, 90, 4), sample(15, 3.25, 95, 5)]);
    final copy = WindTimeline.fromJson(timeline.toJson());
    expect(copy.samples.length, 2);
    expect(copy.start, t0);
    expect(copy.samples[1].reading, timeline.samples[1].reading);
  });

  test('refuses an empty timeline', () {
    expect(() => WindTimeline(const []), throwsArgumentError);
  });
}
