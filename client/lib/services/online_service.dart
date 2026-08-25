import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'api_client.dart';
import 'push_service.dart';
import 'settings_service.dart';

/// Server URL baked in at build time:
/// `flutter build --dart-define=PCKAISER_SERVER_URL=https://…` — when
/// set, the app connects there and never asks the player for an address
/// (a profile-stored URL is only a fallback for dev builds without the
/// define).
const String kEnvServerUrl = String.fromEnvironment('PCKAISER_SERVER_URL');

/// Dev aid for multiplayer testing on one machine: two desktop instances
/// would otherwise share the same profile file and thus the same player
/// identity. `flutter run --dart-define=PCKAISER_INSTANCE=2` gives the
/// instance its own profile (own UUID + name); unset = normal profile.
const String kEnvInstance = String.fromEnvironment('PCKAISER_INSTANCE');

/// Device identity + server connection for online play (V2). Identity is
/// a device-generated UUID (no auth, ARCHITECTURE.md), persisted next to
/// the local saves together with the chosen name and server URL.
class OnlineService {
  OnlineService._(this._file, this._profile);

  static Future<OnlineService> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final suffix = kEnvInstance.isEmpty ? '' : '_$kEnvInstance';
    final file = File('${dir.path}/pckaiser_online$suffix.json');
    Map<String, dynamic> profile = {};
    if (file.existsSync()) {
      try {
        profile = (jsonDecode(file.readAsStringSync()) as Map)
            .cast<String, dynamic>();
      } on Object {
        profile = {};
      }
    }
    return OnlineService._(file, profile);
  }

  final File _file;
  final Map<String, dynamic> _profile;

  /// The build-time env URL wins; the stored profile URL is the dev
  /// fallback.
  String? get serverUrl => kEnvServerUrl.isNotEmpty
      ? kEnvServerUrl.replaceAll(RegExp(r'/+$'), '')
      : _profile['server_url'] as String?;
  String? get displayName => _profile['display_name'] as String?;
  String? get playerId => _profile['player_id'] as String?;

  bool get isConfigured =>
      serverUrl != null && displayName != null && playerId != null;

  ApiClient get api {
    final url = serverUrl;
    if (url == null) throw StateError('online profile not configured');
    return ApiClient(url);
  }

  /// First-run setup (and later edits): stores the profile and registers
  /// the device with the server. Registration is an upsert — calling it
  /// again with a new name simply renames the player.
  Future<void> configure({
    required String serverUrl,
    required String displayName,
  }) async {
    final id = playerId ?? _uuidV4();
    // A baked-in env URL is authoritative — ignore any passed value.
    if (kEnvServerUrl.isNotEmpty) serverUrl = kEnvServerUrl;
    final client = ApiClient(serverUrl.replaceAll(RegExp(r'/+$'), ''));
    await client.registerPlayer(id: id, displayName: displayName);
    _profile['server_url'] = client.baseUrl;
    _profile['display_name'] = displayName;
    _profile['player_id'] = id;
    await _save();
  }

  /// Push enrolment (ARCHITECTURE.md "FCM"): asks the player for
  /// notification permission, uploads the FCM token (PATCH /players/:id,
  /// "token updated on launch") and keeps it fresh on rotation. No-op
  /// until the profile is configured; push is fire-and-forget, so every
  /// failure is swallowed — the game works without it.
  Future<void> syncPushToken() async {
    final push = PushService.instance;
    if (push == null || !isConfigured) return;
    if (!await push.requestPermission()) return;

    Future<void> upload(String token) async {
      try {
        await api.updatePlayer(id: playerId!, fcmToken: token);
      } on Object {
        // Push is optional; the next launch retries.
      }
    }

    final token = await push.token();
    if (token != null) await upload(token);
    push.onTokenRefresh(upload);
    // Converge the notification choices too: a PATCH that failed while the
    // player was offline (or a device restored from a backup) would
    // otherwise leave the server sending what they switched off.
    await syncPushPrefs();
  }

  /// `[DESIGNED 2026-08-24, user request]` Uploads the player's optional
  /// notification choices (Options ▸ Notifications, stored locally by
  /// [SettingsService]) to their server player record — the server decides
  /// what to send, so a muted kind only truly stops once this lands.
  /// Returns false when it could not be delivered (no profile yet, or the
  /// request failed); the next launch retries via [syncPushToken].
  Future<bool> syncPushPrefs() async {
    final settings = SettingsService.instance;
    if (settings == null || !isConfigured) return false;
    try {
      await api.updatePlayer(id: playerId!, pushOptOut: settings.pushOptOut);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _save() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_profile), flush: true);
    await tmp.rename(_file.path);
  }

  static String _uuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
