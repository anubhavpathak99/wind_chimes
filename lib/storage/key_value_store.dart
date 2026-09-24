import 'package:shared_preferences/shared_preferences.dart';

/// Small persistent strings: the chosen location, the cached forecast.
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SharedPreferencesStore implements KeyValueStore {
  SharedPreferencesStore([SharedPreferencesAsync? preferences])
      : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _preferences.remove(key) : _preferences.setString(key, value);
}

/// For tests, and a fallback where storage fails.
class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}
