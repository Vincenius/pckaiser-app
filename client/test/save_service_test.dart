import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:pckaiser/services/save_service.dart';

GameState minimalState({int year = 1000}) => GameState(
      year: year,
      reformationYear: 1020,
      ottomanYear: 1040,
      map: generateMap(Rng(1)),
      realms: [
        for (var s = 1; s <= World.realmCount; s++) Realm(slot: s),
      ],
      dynasties: [
        for (var s = 1; s <= World.realmCount; s++)
          Dynasty(
            index: s,
            status: s <= 2 ? DynastyStatus.human : DynastyStatus.ai,
            humanPlayer: s <= 2 ? s - 1 : null,
            religion: Religion.katholisch,
          ),
      ],
      rngSeed: 7,
    );

void main() {
  late Directory tmp;
  late SaveService saves;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pckaiser_saves_');
    saves = SaveService(tmp);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('save → load round-trips the game state', () async {
    final state = minimalState(year: 1007);
    await saves.save('Erste Partie', state);
    final loaded = await saves.load('Erste Partie');
    expect(loaded.year, 1007);
    expect(loaded.map.terrain, state.map.terrain);
    expect(loaded.realms, hasLength(World.realmCount));
  });

  test('listSlots returns metadata, most recent first', () async {
    await saves.save('Alt', minimalState(year: 1003),
        now: DateTime(2026, 6, 1));
    await saves.save('Neu', minimalState(year: 1010),
        now: DateTime(2026, 6, 9));
    final slots = await saves.listSlots();
    expect(slots.map((s) => s.name), ['Neu', 'Alt']);
    expect(slots.first.year, 1010);
    expect(slots.first.humanCount, 2);
  });

  test('saving the same slot overwrites it', () async {
    await saves.save('Partie', minimalState(year: 1001));
    await saves.save('Partie', minimalState(year: 1002));
    expect((await saves.listSlots()), hasLength(1));
    expect((await saves.load('Partie')).year, 1002);
  });

  test('slot names with special characters are safe', () async {
    const name = 'Käsespiel / Test #2';
    await saves.save(name, minimalState());
    expect(await saves.exists(name), isTrue);
    expect((await saves.load(name)).year, 1000);
  });

  test('delete removes the slot', () async {
    await saves.save('Weg damit', minimalState());
    await saves.delete('Weg damit');
    expect(await saves.exists('Weg damit'), isFalse);
    expect(await saves.listSlots(), isEmpty);
  });
}
