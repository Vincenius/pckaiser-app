import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:path_provider/path_provider.dart';

/// Summary shown in the load-game list without deserializing the full state.
class SaveSlotInfo {
  SaveSlotInfo({
    required this.name,
    required this.savedAt,
    required this.year,
    required this.humanCount,
    this.schemaVersion = currentSchemaVersion,
  });

  factory SaveSlotInfo.fromJson(Map<String, dynamic> json) => SaveSlotInfo(
        name: json['name'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
        year: json['year'] as int,
        humanCount: json['humanCount'] as int,
        schemaVersion: json['schemaVersion'] as int? ?? 1,
      );

  final String name;
  final DateTime savedAt;
  final int year;
  final int humanCount;

  /// Schema version of the stored state, duplicated here so the load list
  /// can flag saves from a newer app version without parsing the state.
  final int schemaVersion;

  /// False when the save was written by a newer app version than this
  /// build can read — the UI offers "update the app" instead of loading.
  bool get isSupported => schemaVersion <= currentSchemaVersion;

  Map<String, dynamic> toJson() => {
        'name': name,
        'savedAt': savedAt.toIso8601String(),
        'year': year,
        'humanCount': humanCount,
        'schemaVersion': schemaVersion,
      };
}

/// Local persistence: multiple named game slots, one JSON file each —
/// the same `GameState` schema the online server stores in JSONB
/// (PROJECT_REQUIREMENTS.md "Local").
///
/// Writes are atomic (temp file + rename): auto-save runs after every
/// completed turn and must finish before the device is handed to the next
/// player.
class SaveService {
  SaveService(this._dir);

  /// Uses the platform application-documents directory.
  static Future<SaveService> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/saves');
    await dir.create(recursive: true);
    return SaveService(dir);
  }

  final Directory _dir;

  File _fileFor(String slotName) =>
      File('${_dir.path}/${Uri.encodeComponent(slotName)}.json');

  /// All existing slots, most recently saved first.
  Future<List<SaveSlotInfo>> listSlots() async {
    final infos = <SaveSlotInfo>[];
    await for (final entry in _dir.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final doc =
            jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
        infos.add(SaveSlotInfo.fromJson(
            (doc['meta'] as Map).cast<String, dynamic>()));
      } on Object {
        // Unreadable/corrupt slot: skip it rather than break the list.
      }
    }
    infos.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return infos;
  }

  /// Auto-save: called after every completed turn.
  Future<void> save(String slotName, GameState state, {DateTime? now}) async {
    final humanCount = state.dynasties
        .where((d) => d.status == DynastyStatus.human)
        .length;
    final doc = {
      'meta': SaveSlotInfo(
        name: slotName,
        savedAt: now ?? DateTime.now(),
        year: state.year,
        humanCount: humanCount,
        schemaVersion: state.schemaVersion,
      ).toJson(),
      'state': state.toJson(),
    };
    final file = _fileFor(slotName);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(doc), flush: true);
    await tmp.rename(file.path);
  }

  Future<GameState> load(String slotName) async {
    final doc = jsonDecode(await _fileFor(slotName).readAsString())
        as Map<String, dynamic>;
    return GameState.fromJson((doc['state'] as Map).cast<String, dynamic>());
  }

  Future<bool> exists(String slotName) => _fileFor(slotName).exists();

  Future<void> delete(String slotName) async {
    final file = _fileFor(slotName);
    if (await file.exists()) await file.delete();
  }
}
