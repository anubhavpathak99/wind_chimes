import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether the chip and the controls pill are showing. They fade after a few seconds without
/// interaction, so the chime has the screen to itself; tapping empty sky brings them back.
class OverlayVisibility extends ValueNotifier<bool> {
  OverlayVisibility({
    this.delay = const Duration(seconds: 4),
    this.longDelay = const Duration(seconds: 10),
  }) : super(true) {
    _restart();
  }

  final Duration delay;

  /// Used instead of [delay] while [linger] is set, e.g. while the first-run offer waits.
  final Duration longDelay;
  final Set<Object> _holds = {};
  Timer? _timer;
  bool _linger = false;

  set linger(bool value) {
    if (value == _linger) return;
    _linger = value;
    if (this.value) _restart();
  }

  /// Shows the overlays and starts the countdown again.
  void poke() {
    value = true;
    _restart();
  }

  void toggle() => value && _holds.isEmpty ? hide() : poke();

  void hide() {
    if (_holds.isNotEmpty) return;
    _timer?.cancel();
    value = false;
  }

  /// Keeps the overlays up while [on] for [reason] (an open sheet, an expanded chip).
  void hold(Object reason, bool on) {
    if (on ? !_holds.add(reason) : !_holds.remove(reason)) return;
    if (on) value = true;
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    if (_holds.isNotEmpty) return;
    _timer = Timer(_linger ? longDelay : delay, hide);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
