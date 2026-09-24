import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../storage/key_value_store.dart';
import 'app_settings.dart';

/// Holds the settings and saves them shortly after they change, so dragging a slider writes once
/// rather than sixty times a second.
class SettingsController {
  SettingsController(this._store, AppSettings initial) : settings = ValueNotifier(initial);

  static const key = 'settings.v1';
  static const saveDelay = Duration(milliseconds: 500);

  /// The saved settings, or defaults (with units for [region]) if there are none or they can't
  /// be read. Quick enough to await before the first frame, so the app never starts in the wrong
  /// mode and then flips.
  static Future<AppSettings> load(KeyValueStore store, {String? region}) async {
    final defaults = AppSettings(units: SpeedUnit.forRegion(region));
    try {
      final text = await store.read(key);
      if (text == null) return defaults;
      return AppSettings.fromJson(jsonDecode(text) as Map<String, dynamic>, defaults: defaults);
    } catch (_) {
      return defaults;
    }
  }

  final KeyValueStore _store;
  final ValueNotifier<AppSettings> settings;
  Timer? _pending;

  AppSettings get value => settings.value;

  void update(AppSettings Function(AppSettings current) change) {
    settings.value = change(settings.value);
    _pending?.cancel();
    _pending = Timer(saveDelay, flush);
  }

  /// Saves now if a change is waiting, for when the app is being hidden.
  Future<void> flush() async {
    if (_pending == null) return;
    _pending!.cancel();
    _pending = null;
    try {
      await _store.write(key, jsonEncode(settings.value.toJson()));
    } catch (_) {
      // Only costs the change next launch.
    }
  }

  Future<void> dispose() async {
    await flush();
    settings.dispose();
  }
}
