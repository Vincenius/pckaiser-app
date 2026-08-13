import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../l10n/strings.dart';

/// App-wide preferences, stored as one small JSON file in the
/// application-documents directory (same pattern as [SaveService]).
/// Holds the UI language and the last-seen "What's new" version.
class SettingsService {
  SettingsService._(this._file, this._data, this.hadStoredSettings);

  /// Loaded once at startup by `main.dart`; null until then (and in
  /// widget tests, which pump screens directly).
  static SettingsService? instance;

  static Future<SettingsService> init() async {
    final docs = await getApplicationDocumentsDirectory();
    final file = File('${docs.path}/settings.json');
    final existed = file.existsSync();
    var data = <String, dynamic>{};
    try {
      if (existed) {
        data = (jsonDecode(file.readAsStringSync()) as Map)
            .cast<String, dynamic>();
      }
    } on Object {
      // Corrupt settings file: fall back to defaults rather than crash.
    }
    final service = SettingsService._(file, data, existed);
    instance = service;
    appLocale.value = service.resolvedLocale;
    return service;
  }

  final File _file;
  final Map<String, dynamic> _data;

  /// True when a settings file was already on disk at startup — one half
  /// of the "is this a first launch" test (the other is whether any save
  /// exists). A returning player who never changed a setting has none.
  final bool hadStoredSettings;

  /// The app version the "What's new" modal was last shown for (null =
  /// never shown — a fresh install or an upgrade from before the modal
  /// existed). Compared against `appVersion` on launch; only one version
  /// is remembered, so re-installing an old build cannot resurrect a
  /// dismissed dialog.
  String? get lastSeenWhatsNewVersion =>
      _data['lastSeenWhatsNewVersion'] as String?;

  /// Records [version] as seen, so its "What's new" modal never shows
  /// again (called after the modal is dismissed).
  Future<void> markWhatsNewSeen(String version) async {
    _data['lastSeenWhatsNewVersion'] = version;
    await _persist();
  }

  /// The stored choice: 'system' (default — follow the device language),
  /// 'de' or 'en'.
  String get languageChoice {
    final v = _data['language'] as String?;
    return v == 'de' || v == 'en' ? v! : 'system';
  }

  /// The UI locale the choice resolves to: 'system' maps German devices
  /// to German and every other device language to English.
  String get resolvedLocale {
    final choice = languageChoice;
    if (choice != 'system') return choice;
    final device = ui.PlatformDispatcher.instance.locale.languageCode;
    return device == 'de' ? 'de' : 'en';
  }

  /// Persists [choice] ('system' | 'de' | 'en') and switches the live UI
  /// language immediately.
  Future<void> setLanguageChoice(String choice) async {
    _data['language'] = choice;
    appLocale.value = resolvedLocale;
    await _persist();
  }

  /// Atomic write of the whole settings JSON (tmp + rename, same pattern
  /// as SaveService) — shared by every setter.
  Future<void> _persist() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_data), flush: true);
    await tmp.rename(_file.path);
  }
}
