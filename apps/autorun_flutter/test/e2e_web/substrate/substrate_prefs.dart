// ignore_for_file: lines_longer_than_80_chars

/// SharedPreferences substrate for the Web e2e harness.
///
/// Single call to the SDK-blessed [SharedPreferences.setMockInitialValues]:
/// installs an in-memory prefs store that BOTH `SharedPreferences.getInstance()`
/// (used by `SettingsService`, `OnboardingService`, `SpotlightService`, …)
/// AND `WebJsonStore` (used by `ProfileRepository`/`ScriptRepository` on Web
/// under the `icp_cc_store_` prefix) read from / write to. Direct call —
/// no app code touched.
///
/// On Web this is the right substrate: `SharedPreferencesWeb` is a thin
/// localStorage wrapper, and `setMockInitialValues` swaps the platform
/// channel for an in-memory map (see
/// `shared_preferences/lib/shared_preferences.dart`). Plugin round-trips
/// succeed synchronously — no `runAsync` needed for prefs alone.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Install (or reset) the SharedPreferences in-memory mock with optional
/// [initialValues]. Idempotent; safe to call from `setUpAll` / `setUp`.
void installSubstratePrefs([Map<String, Object> initialValues = const {}]) {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(initialValues));
}
