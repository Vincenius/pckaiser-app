import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import 'serialization_test.dart' show sampleState;

void main() {
  group('schema versioning', () {
    test('new games carry the current schema and rules versions', () {
      final state = newGame(GameSetup(
        humans: [],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 7,
      ));
      expect(state.schemaVersion, currentSchemaVersion);
      expect(state.rulesVersion, currentRulesVersion);
      expect(state.toJson()['schemaVersion'], currentSchemaVersion);
      expect(state.toJson()['rulesVersion'], currentRulesVersion);
    });

    test('documents without version fields load as version 1', () {
      final json = sampleState().toJson()
        ..remove('schemaVersion')
        ..remove('rulesVersion');
      final state = GameState.fromJson(json);
      expect(state.schemaVersion, currentSchemaVersion);
      expect(state.rulesVersion, 1);
    });

    test('documents from a newer app version are rejected, not guessed at',
        () {
      final json = sampleState().toJson()
        ..['schemaVersion'] = currentSchemaVersion + 1;
      expect(
        () => GameState.fromJson(json),
        throwsA(isA<UnsupportedSchemaVersionException>()),
      );
    });

    test('rulesVersion is pinned through save/load and copy', () {
      final state = sampleState();
      final reloaded = GameState.fromJson(state.toJson());
      expect(reloaded.rulesVersion, state.rulesVersion);
      expect(state.copy().rulesVersion, state.rulesVersion);
    });

    test('migrations run sequentially from the document version up', () {
      final migrated = migrateGameStateJson(
        {'schemaVersion': 1, 'trail': <String>[]},
        toVersion: 3,
        migrations: {
          1: (json) => json..['trail'] = [...json['trail'] as List, '1→2'],
          2: (json) => json..['trail'] = [...json['trail'] as List, '2→3'],
        },
      );
      expect(migrated['trail'], ['1→2', '2→3']);
      expect(migrated['schemaVersion'], 3);
    });

    test('migration leaves the original document untouched', () {
      final original = {'schemaVersion': 1, 'value': 'old'};
      migrateGameStateJson(
        original,
        toVersion: 2,
        migrations: {1: (json) => json..['value'] = 'new'},
      );
      expect(original['value'], 'old');
      expect(original['schemaVersion'], 1);
    });

    test('a gap in the migration chain fails loudly', () {
      expect(
        () => migrateGameStateJson(
          {'schemaVersion': 1},
          toVersion: 3,
          migrations: {2: (json) => json},
        ),
        throwsStateError,
      );
    });

    test('full save/load round-trip preserves both versions', () {
      final state = sampleState();
      final reloaded = GameState.fromJson(state.toJson());
      expect(reloaded.schemaVersion, state.schemaVersion);
      expect(reloaded.toJson(), state.toJson());
    });
  });
}
