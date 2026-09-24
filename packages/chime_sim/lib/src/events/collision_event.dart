/// One clapper–tube impact. Carries physical quantities only; turning them into loudness is the
/// audio layer's job.
///
/// Instances are owned and reused by [EventRing]. Consumers must copy what they keep.
final class CollisionEvent {
  int rodId = 0;

  /// The tube that knocked into [rodId], or -1 when the clapper struck it. A knock between two
  /// tubes is reported twice, once for each.
  int otherRodId = -1;

  bool get isClink => otherRodId >= 0;

  /// Impulse exchanged along the contact normal, N·s.
  double impulse = 0;

  /// Closing speed along the contact normal just before impact, m/s.
  double normalSpeed = 0;

  /// Where the tube was struck: 0 = top, 1 = bottom.
  double strikePos = 0;

  /// 0 = square hit, 1 = grazing.
  double glancing = 0;

  /// Simulation time of the impact, s (substep resolution).
  double simTime = 0;
}

abstract interface class CollisionSink {
  /// [event] is reused as soon as this returns.
  void onCollision(CollisionEvent event);
}

/// Fixed-capacity FIFO of preallocated events, so emitting an event never allocates.
/// When full, the oldest event is overwritten and counted in [dropped].
final class EventRing {
  EventRing(int capacity)
      : assert(capacity > 0),
        _slots = List.generate(capacity, (_) => CollisionEvent(), growable: false);

  final List<CollisionEvent> _slots;
  int _head = 0;
  int _count = 0;
  int _dropped = 0;

  int get length => _count;
  int get capacity => _slots.length;
  int get dropped => _dropped;

  /// Returns the slot to fill for a new event.
  CollisionEvent claim() {
    if (_count == _slots.length) {
      _head = (_head + 1) % _slots.length;
      _count--;
      _dropped++;
    }
    final slot = _slots[(_head + _count) % _slots.length];
    _count++;
    return slot;
  }

  /// Delivers pending events oldest-first and empties the ring.
  void drainTo(CollisionSink sink) {
    while (_count > 0) {
      final event = _slots[_head];
      _head = (_head + 1) % _slots.length;
      _count--;
      sink.onCollision(event);
    }
  }

  void clear() {
    _head = 0;
    _count = 0;
  }
}
