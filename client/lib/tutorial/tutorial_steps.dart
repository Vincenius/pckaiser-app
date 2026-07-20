import 'package:game_core/game_core.dart' as gc;

import '../l10n/labels.dart';
import '../l10n/strings.dart';
import '../state/game_controller.dart';

/// Session name for the tutorial game. The tutorial is ephemeral: its
/// session never persists, so it does not appear in the saved-games list.
const String tutorialSlotName = 'Tutorial';

/// Single-player setup for the tutorial: the player rules Brandenburg on
/// a fixed-seed map, so every tutorial run plays out the same way.
gc.GameSetup tutorialSetup() => gc.GameSetup(
  humans: [
    gc.HumanPlayerSetup(
      founderName: 'Albrecht',
      gender: 0,
      countrySlot: 1,
      dorfName: gc.cityNames[0],
    ),
  ],
  reformationYear: 1020,
  ottomanYear: 1040,
  // Pinned so the scripted overlay stays reproducible even if the setup
  // default ever changes (the tutorial ends within the first turn anyway).
  aiDifficulty: gc.AiDifficulty.mittel,
  seed: 1099, // fixed: reproducible tutorial map
);

/// Snapshot of the player's realm taken when a step becomes active, so a
/// step's completion check only counts what happened during that step.
class TutorialBaseline {
  TutorialBaseline(GameController c)
    : buildingTiles = c.currentRealm.tileCount.fold(0, (a, b) => a + b),
      armySize = c.currentRealm.armySize;

  final int buildingTiles;
  final int armySize;
}

/// One tutorial step: explanation text plus, for interactive steps, the
/// task instruction and a completion check against the live game state.
class TutorialStep {
  const TutorialStep({
    required this.title,
    required this.body,
    this.task,
    this.isDone,
  });

  final String title;
  final String body;

  /// Imperative instruction shown highlighted; null = explanation-only
  /// step that advances with the "Weiter" button.
  final String? task;

  /// Completion check for interactive steps, polled on every controller
  /// change; null = explanation-only step.
  final bool Function(GameController c, TutorialBaseline since)? isDone;
}

/// The tutorial script. KEEP IN SYNC with gameplay/UI changes (CLAUDE.md):
/// every menu name, price and rule quoted here must match the live game —
/// steps that name a menu entry receive it via `tr()` params so the wording
/// can never drift. A getter (not a final list) so a live language switch
/// rebuilds the script in the new locale.
/// The whole tutorial plays out within the first turn — no step may
/// require ending the turn, so the player never hits the round-start
/// handoff/recap flow while the overlay is up.
List<TutorialStep> get tutorialSteps => [
  TutorialStep(
    title: tr('tut.welcomeTitle'),
    // Slot 1 = Brandenburg, the tutorial's fixed starting realm.
    body: tr('tut.welcomeBody', {'realm': realmName(1)}),
  ),
  TutorialStep(title: tr('tut.statsTitle'), body: tr('tut.statsBody')),
  TutorialStep(
    title: tr('tut.buildTitle'),
    body: tr('tut.buildBody'),
    task: tr('tut.buildTask'),
    isDone: (c, since) =>
        c.currentRealm.tileCount.fold(0, (a, b) => a + b) > since.buildingTiles,
  ),
  TutorialStep(
    title: tr('commerce'),
    body: tr('tut.tradeBody'),
    task: tr('tut.tradeTask', {'menu': tr('commerce')}),
    isDone: (c, since) =>
        c.currentRealm.soldGrainThisTurn || c.currentRealm.soldCattleThisTurn,
  ),
  TutorialStep(
    title: tr('military'),
    body: tr('tut.militaryBody'),
    task: tr('tut.militaryTask', {
      'military': tr('military'),
      'recruit': tr('recruit'),
    }),
    isDone: (c, since) => c.currentRealm.armySize > since.armySize,
  ),
  TutorialStep(title: tr('espionage'), body: tr('tut.espionageBody')),
  TutorialStep(
    title: tr('misc'),
    body: tr('tut.dynastyBody', {'menu': tr('misc')}),
  ),
  TutorialStep(
    title: tr('endTurn'),
    body: tr('tut.endTurnBody', {'endTurn': tr('endTurn')}),
  ),
  TutorialStep(
    title: tr('tut.readyTitle'),
    body: tr('tut.readyBody', {
      'info': tr('info'),
      'finish': tr('tut.finish'),
    }),
  ),
];
