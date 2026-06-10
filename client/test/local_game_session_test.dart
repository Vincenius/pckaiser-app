import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:pckaiser/services/local_game_session.dart';
import 'package:pckaiser/services/save_service.dart';

void main() {
  late Directory tmp;
  late SaveService saves;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pckaiser_session_');
    saves = SaveService(tmp);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  GameSetup setup() => GameSetup(
        humans: [
          HumanPlayerSetup(
              founderName: 'Anna',
              gender: 1,
              countrySlot: 1,
              dorfName: 'Berlin'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 7,
      );

  test('create starts the game in year 1000 and saves immediately', () async {
    final session = await LocalGameSession.create(
        slotName: 'Partie 1', setup: setup(), saves: saves);
    expect(session.state.year, 1000);
    expect(await saves.exists('Partie 1'), isTrue);
    expect((await saves.load('Partie 1')).year, 1000);
  });

  test('endTurn advances the game and auto-saves before handoff', () async {
    final session = await LocalGameSession.create(
        slotName: 'Partie 1', setup: setup(), saves: saves);
    final result = await session.endTurn();
    expect(result.state.currentPlayer, 2);
    final reloaded = await saves.load('Partie 1');
    expect(reloaded.currentPlayer, 2,
        reason: 'save must reflect the completed turn');
    expect(reloaded.rngSeed, session.state.rngSeed);
  });

  test('visibleState hides other realms from the seated player', () async {
    final session = await LocalGameSession.create(
        slotName: 'Partie 1', setup: setup(), saves: saves);
    expect(session.state.currentPlayer, 1);
    final view = session.visibleState;
    expect(view.realm(1).treasury, session.state.realm(1).treasury);
    expect(view.realm(2).treasury, 0);
    expect(view.rngSeed, 0);
  });

  test('resume continues from the saved state', () async {
    var session = await LocalGameSession.create(
        slotName: 'Partie 1', setup: setup(), saves: saves);
    await session.endTurn();
    await session.endTurn();
    session =
        await LocalGameSession.resume(slotName: 'Partie 1', saves: saves);
    expect(session.state.currentPlayer, 3);
  });
}
