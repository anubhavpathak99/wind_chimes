import 'package:chime_sim/chime_sim.dart';
import 'package:test/test.dart';

class _Recorder implements CollisionSink {
  final rods = <int>[];

  @override
  void onCollision(CollisionEvent event) => rods.add(event.rodId);
}

void main() {
  test('drains oldest first and empties', () {
    final ring = EventRing(4);
    for (var i = 0; i < 3; i++) {
      ring.claim().rodId = i;
    }
    final recorder = _Recorder();
    ring.drainTo(recorder);
    expect(recorder.rods, [0, 1, 2]);
    expect(ring.length, 0);
  });

  test('overwrites the oldest when full and counts the drop', () {
    final ring = EventRing(3);
    for (var i = 0; i < 5; i++) {
      ring.claim().rodId = i;
    }
    final recorder = _Recorder();
    ring.drainTo(recorder);
    expect(recorder.rods, [2, 3, 4]);
    expect(ring.dropped, 2);
  });

  test('keeps working across wrap-around', () {
    final ring = EventRing(2);
    final recorder = _Recorder();
    for (var i = 0; i < 7; i++) {
      ring.claim().rodId = i;
      ring.drainTo(recorder);
    }
    expect(recorder.rods, [0, 1, 2, 3, 4, 5, 6]);
    expect(ring.dropped, 0);
  });
}
