import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/settings_service.dart';
import 'package:flutter/material.dart';

void main() {
  group('SettingsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('getThemeMode', () {
      test('returns ThemeMode.system by default when no preference stored',
          () async {
        SharedPreferences.setMockInitialValues({});
        final service = SettingsService();

        final result = await service.getThemeMode();

        expect(result, equals(ThemeMode.system));
      });

      test('returns ThemeMode.light when light theme was stored', () async {
        SharedPreferences.setMockInitialValues({
          'theme_mode': ThemeMode.light.index,
        });
        final service = SettingsService();

        final result = await service.getThemeMode();

        expect(result, equals(ThemeMode.light));
      });

      test('returns ThemeMode.dark when dark theme was stored', () async {
        SharedPreferences.setMockInitialValues({
          'theme_mode': ThemeMode.dark.index,
        });
        final service = SettingsService();

        final result = await service.getThemeMode();

        expect(result, equals(ThemeMode.dark));
      });

      test('returns ThemeMode.system when system theme was stored', () async {
        SharedPreferences.setMockInitialValues({
          'theme_mode': ThemeMode.system.index,
        });
        final service = SettingsService();

        final result = await service.getThemeMode();

        expect(result, equals(ThemeMode.system));
      });
    });

    group('setThemeMode', () {
      test('stores ThemeMode.light correctly', () async {
        SharedPreferences.setMockInitialValues({});
        final service = SettingsService();
        final prefs = await SharedPreferences.getInstance();

        await service.setThemeMode(ThemeMode.light);

        expect(prefs.getInt('theme_mode'), equals(ThemeMode.light.index));
      });

      test('stores ThemeMode.dark correctly', () async {
        SharedPreferences.setMockInitialValues({});
        final service = SettingsService();
        final prefs = await SharedPreferences.getInstance();

        await service.setThemeMode(ThemeMode.dark);

        expect(prefs.getInt('theme_mode'), equals(ThemeMode.dark.index));
      });

      test('stores ThemeMode.system correctly', () async {
        SharedPreferences.setMockInitialValues({});
        final service = SettingsService();
        final prefs = await SharedPreferences.getInstance();

        await service.setThemeMode(ThemeMode.system);

        expect(prefs.getInt('theme_mode'), equals(ThemeMode.system.index));
      });

      test('overwrites previous theme mode', () async {
        SharedPreferences.setMockInitialValues({
          'theme_mode': ThemeMode.light.index,
        });
        final service = SettingsService();
        final prefs = await SharedPreferences.getInstance();

        await service.setThemeMode(ThemeMode.dark);

        expect(prefs.getInt('theme_mode'), equals(ThemeMode.dark.index));
      });
    });

    group('integration (set then get)', () {
      test('setting then getting returns same value - light', () async {
        SharedPreferences.setMockInitialValues({});
        final service = SettingsService();

        await service.setThemeMode(ThemeMode.light);
        final result = await service.getThemeMode();

        expect(result, equals(ThemeMode.light));
      });

      test('setting then getting returns same value - dark', () async {
        SharedPreferences.setMockInitialValues({});
        final service = SettingsService();

        await service.setThemeMode(ThemeMode.dark);
        final result = await service.getThemeMode();

        expect(result, equals(ThemeMode.dark));
      });

      test('setting then getting returns same value - system', () async {
        SharedPreferences.setMockInitialValues({});
        final service = SettingsService();

        await service.setThemeMode(ThemeMode.system);
        final result = await service.getThemeMode();

        expect(result, equals(ThemeMode.system));
      });
    });
  });
}
