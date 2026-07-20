import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../l10n/strings.dart';

/// App-wide preferences, stored as one small JSON file in the
/// application-documents directory (same pattern as [SaveService]).
/// Currently holds only the UI language.
class SettingsService {
  SettingsService._(this._file, this._data);

  /// Loaded once at startup by `main.dart`; null until then (and in
  /// widget tests, which pump screens directly).
  static SettingsService? instance;

  static Future<SettingsService> init() async {
    final docs = await getApplicationDocumentsDirectory();
    final file = File('${docs.path}/settings.json');
    var data = <String, dynamic>{};
    try {
      if (file.existsSync()) {
        data = (jsonDecode(file.readAsStringSync()) as Map)
            .cast<String, dynamic>();
      }
    } on Object {
      // Corrupt settings file: fall back to defaults rather than crash.
    }
    final service = SettingsService._(file, data);
    instance = service;
    appLocale.value = service.resolvedLocale;
    return service;
  }

  final File _file;
  final Map<String, dynamic> _data;

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
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_data), flush: true);
    await tmp.rename(_file.path);
  }
}
