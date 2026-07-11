import 'package:app/settings/display_settings.dart';

class MemoryDisplaySettingsStore implements DisplaySettingsStore {
  MemoryDisplaySettingsStore([Map<String, String>? values])
    : values = {...?values};

  final Map<String, String> values;
  bool failWrites = false;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    if (failWrites) throw StateError('Write failed');
    values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    if (failWrites) throw StateError('Write failed');
    values[key] = value;
  }
}
