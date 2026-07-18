import 'package:app/settings/display_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_display_settings_store.dart';

void main() {
  test('loads persisted language and theme choices', () async {
    final controller = DisplaySettingsController(
      store: MemoryDisplaySettingsStore({
        'display_language': 'spanish',
        'display_theme': 'dark',
      }),
    );

    await controller.load();

    expect(controller.language, DisplayLanguage.spanish);
    expect(controller.locale, const Locale('es'));
    expect(controller.theme, DisplayTheme.dark);
    expect(controller.themeMode, ThemeMode.dark);
  });

  test('falls back to system settings for unknown persisted values', () async {
    final controller = DisplaySettingsController(
      store: MemoryDisplaySettingsStore({
        'display_language': 'unknown',
        'display_theme': 'unknown',
      }),
    );

    await controller.load();

    expect(controller.language, DisplayLanguage.system);
    expect(controller.locale, isNull);
    expect(controller.theme, DisplayTheme.system);
    expect(controller.themeMode, ThemeMode.system);
  });

  test('persists explicit choices and removes system defaults', () async {
    final store = MemoryDisplaySettingsStore();
    final controller = DisplaySettingsController(store: store);

    await controller.setLanguage(DisplayLanguage.english);
    await controller.setTheme(DisplayTheme.light);

    expect(store.values['display_language'], 'english');
    expect(store.values['display_theme'], 'light');

    await controller.setLanguage(DisplayLanguage.system);
    await controller.setTheme(DisplayTheme.system);

    expect(store.values, isEmpty);
  });

  test('does not change the active choice when persistence fails', () async {
    final store = MemoryDisplaySettingsStore()..failWrites = true;
    final controller = DisplaySettingsController(store: store);

    await expectLater(
      controller.setLanguage(DisplayLanguage.spanish),
      throwsStateError,
    );
    await expectLater(controller.setTheme(DisplayTheme.dark), throwsStateError);

    expect(controller.language, DisplayLanguage.system);
    expect(controller.theme, DisplayTheme.system);
  });
}
