import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DisplayLanguage { system, english, spanish }

enum DisplayTheme { system, light, dark }

abstract interface class DisplaySettingsStore {
  Future<String?> getString(String key);

  Future<void> setString(String key, String value);

  Future<void> remove(String key);
}

class SharedPreferencesDisplaySettingsStore implements DisplaySettingsStore {
  SharedPreferencesDisplaySettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }
}

class DisplaySettingsController extends ChangeNotifier {
  DisplaySettingsController({DisplaySettingsStore? store})
    : _store = store ?? SharedPreferencesDisplaySettingsStore();

  static const _languageKey = 'display_language';
  static const _themeKey = 'display_theme';

  final DisplaySettingsStore _store;

  DisplayLanguage _language = DisplayLanguage.system;
  DisplayTheme _theme = DisplayTheme.system;

  DisplayLanguage get language => _language;
  DisplayTheme get theme => _theme;

  Locale? get locale => switch (_language) {
    DisplayLanguage.system => null,
    DisplayLanguage.english => const Locale('en'),
    DisplayLanguage.spanish => const Locale('es'),
  };

  ThemeMode get themeMode => switch (_theme) {
    DisplayTheme.system => ThemeMode.system,
    DisplayTheme.light => ThemeMode.light,
    DisplayTheme.dark => ThemeMode.dark,
  };

  /// The BCP 47 tag this device is effectively displaying in: the picked
  /// language, or the platform's own when following the system.
  ///
  /// Everything that reports a locale to the backend goes through this, so the
  /// `Accept-Language` header on auth requests, the `/v1/config` query and
  /// `LanguageSyncController` can never disagree about what this device is set
  /// to. Full tag rather than just the language, so the server keeps the region
  /// (`es-AR`) for formatting outbound messages.
  String get localeTag =>
      (locale ?? WidgetsBinding.instance.platformDispatcher.locale)
          .toLanguageTag();

  Future<void> load() async {
    final values = await Future.wait([
      _store.getString(_languageKey),
      _store.getString(_themeKey),
    ]);
    _language = _enumByName(
      DisplayLanguage.values,
      values[0],
      DisplayLanguage.system,
    );
    _theme = _enumByName(DisplayTheme.values, values[1], DisplayTheme.system);
  }

  Future<void> setLanguage(DisplayLanguage value) async {
    if (value == _language) return;
    await _persist(_languageKey, value.name, value == DisplayLanguage.system);
    _language = value;
    notifyListeners();
  }

  Future<void> setTheme(DisplayTheme value) async {
    if (value == _theme) return;
    await _persist(_themeKey, value.name, value == DisplayTheme.system);
    _theme = value;
    notifyListeners();
  }

  Future<void> _persist(String key, String value, bool remove) =>
      remove ? _store.remove(key) : _store.setString(key, value);

  T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
