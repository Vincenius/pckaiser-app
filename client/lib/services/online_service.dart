import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'api_client.dart';

/// Device identity + server connection for online play (V2). Identity is
/// a device-generated UUID (no auth, ARCHITECTURE.md), persisted next to
/// the local saves together with the chosen name and server URL.
class OnlineService {
  OnlineService._(this._file, this._profile);

  static Future<OnlineService> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/pckaiser_online.json');
    Map<String, dynamic> profile = {};
    if (file.existsSync()) {
      try {
        profile =
            (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();
      } on Object {
        profile = {};
      }
    }
    return OnlineService._(file, profile);
  }

  final File _file;
  final Map<String, dynamic> _profile;

  String? get serverUrl => _profile['server_url'] as String?;
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
    final client = ApiClient(serverUrl.replaceAll(RegExp(r'/+$'), ''));
    await client.registerPlayer(id: id, displayName: displayName);
    _profile['server_url'] = client.baseUrl;
    _profile['display_name'] = displayName;
    _profile['player_id'] = id;
    await _save();
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
