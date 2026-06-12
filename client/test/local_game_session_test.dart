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
        dorfName: 'Berlin',
      ),
    ],
    reformationYear: 1020,
    ottomanYear: 1040,
    seed: 7,
  );

  test('create starts the game in year 1000 and saves immediately', () async {
    final session = await LocalGameSession.create(
      slotName: 'Partie 1',
      setup: setup(),
      saves: saves,
    );
    expect(session.state.year, 1000);
    expect(await saves.exists('Partie 1'), isTrue);
    expect((await saves.load('Partie 1')).year, 1000);
  });

  test('create advances past leading AI realms to the first human', () async {
    // Human on slot 5: slots 1–4 (incl. Brandenburg) are AI and must have
    // played before the human ever sees the device.
    final session = await LocalGameSession.create(
      slotName: 'Partie AI',
      setup: GameSetup(
        humans: [
          HumanPlayerSetup(
            founderName: 'Otto',
            gender: 0,
            countrySlot: 5,
            dorfName: 'Ulm',
          ),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 7,
      ),
      saves: saves,
    );
    expect(
      session.state.currentPlayer,
      5,
      reason: 'the human seat must never control an AI realm',
    );
    expect(
      session.state.dynasty(session.state.currentPlayer).status,
      DynastyStatus.human,
    );
  });

  test('endTurn advances the game and auto-saves before handoff', () async {
    final session = await LocalGameSession.create(
      slotName: 'Partie 1',
      setup: setup(),
      saves: saves,
    );
    final result = await session.endTurn();
    expect(result.state.currentPlayer, 2);
    final reloaded = await saves.load('Partie 1');
    expect(
      reloaded.currentPlayer,
      2,
      reason: 'save must reflect the completed turn',
    );
    expect(reloaded.rngSeed, session.state.rngSeed);
  });

  test('visibleState hides other realms from the seated player', () async {
    final session = await LocalGameSession.create(
      slotName: 'Partie 1',
      setup: setup(),
      saves: saves,
    );
    expect(session.state.currentPlayer, 1);
    final view = session.visibleState;
    expect(view.realm(1).treasury, session.state.realm(1).treasury);
    expect(view.realm(2).treasury, 0);
    expect(view.rngSeed, 0);
  });

  test('resume heals saves parked on an AI slot (pre-fix saves)', () async {
    final session = await LocalGameSession.create(
      slotName: 'Alt',
      setup: setup(),
      saves: saves,
    );
    // Simulate an old save: park the game on slot 2 (AI) and persist.
    await session.endTurn(); // completeTurn without AI advance → slot 2
    expect((await saves.load('Alt')).currentPlayer, 2);

    final resumed = await LocalGameSession.resume(
      slotName: 'Alt',
      saves: saves,
    );
    expect(
      resumed.state.currentPlayer,
      1,
      reason: 'resume must advance past AI slots to the human',
    );
    expect(
      (await saves.load('Alt')).currentPlayer,
      1,
      reason: 'the healed state is persisted',
    );
  });

  test('resume continues from the saved state', () async {
    var session = await LocalGameSession.create(
      slotName: 'Partie 1',
      setup: setup(),
      saves: saves,
    );
    await session.endTurn();
    await session.endTurn();
    // The save sits on slot 3 (AI): resume advances the AI realms until
    // the human's next action phase — a full round back to slot 1.
    session = await LocalGameSession.resume(slotName: 'Partie 1', saves: saves);
    expect(session.state.currentPlayer, 1);
    expect(
      session.state.year,
      greaterThan(1000),
      reason: 'the AI realms played through the rest of the round',
    );
  });
}
