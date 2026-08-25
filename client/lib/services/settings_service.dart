import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../l10n/strings.dart';
import 'push_kinds.dart';

/// App-wide preferences, stored as one small JSON file in the
/// application-documents directory (same pattern as [SaveService]).
/// Holds the UI language, the last-seen "What's new" version and the
/// optional-notification opt-outs.
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

  /// `[DESIGNED 2026-08-24, user request]` The OPTIONAL online
  /// notifications the player switched off — [optionalPushKinds] values.
  /// Stored as an opt-OUT list (all notifications are on by default, and a
  /// kind added by a later build starts out on, exactly as on a fresh
  /// install). The server holds the authoritative copy on the player
  /// record — this is the local mirror the options screen renders and
  /// `OnlineService.syncPushPrefs` uploads.
  Set<String> get pushOptOut => {
        for (final k in (_data['pushOptOut'] as List? ?? const []))
          if (k is String && optionalPushKinds.contains(k)) k,
      };

  /// Whether [kind] is currently switched on (the default for every kind).
  bool pushEnabled(String kind) => !pushOptOut.contains(kind);

  /// Switches notification [kind] on/off. Persists locally; uploading the
  /// new set to the server is the caller's job (`OnlineService`) so the
  /// screen can report a failed sync.
  Future<void> setPushEnabled(String kind, bool enabled) async {
    final next = pushOptOut;
    if (enabled) {
      next.remove(kind);
    } else {
      next.add(kind);
    }
    _data['pushOptOut'] = next.toList()..sort();
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
