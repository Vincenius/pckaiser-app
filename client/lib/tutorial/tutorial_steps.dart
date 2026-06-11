import 'package:game_core/game_core.dart' as gc;

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
/// every menu name, price and rule quoted here must match the live game.
/// The whole tutorial plays out within the first turn — no step may
/// require ending the turn, so the player never hits the round-start
/// handoff/recap flow while the overlay is up.
final List<TutorialStep> tutorialSteps = [
  TutorialStep(
    title: 'Willkommen, Ritter!',
    body: 'Du herrschst über Brandenburg, eines von 30 Reichen. Ziel des '
        'Spiels: Erhebe deine Dynastie vom Ritter zum Kaiser und '
        'werde alleiniger Herrscher des ganzen Landes.\n\n'
        'Die Karte: Ziehe mit dem Finger, zoome mit zwei '
        'Fingern. Die Fahne markiert deinen Königssitz (deine Burg).',
  ),
  TutorialStep(
    title: 'Deine Werte',
    body: 'Oben rechts siehst du deine Taler (Münze) und deine '
        'verbleibenden Züge (Hammer) — Bauen und Erweitern auf der '
        'Karte kostet einen Zug, Truppen verlegen ist kostenlos. '
        'Die Leiste unten zeigt Jahr und Reich; tippe auf beides für '
        'alle Werte deines Reichs ("Mein Reich"). Der Pfeil macht '
        'Aktionen innerhalb des Zuges rückgängig.',
  ),
  TutorialStep(
    title: 'Bauen & Erweitern',
    body: 'Dein Reich wächst, indem du auf freien Feldern neben deinem '
        'Gebiet baust: Kornfelder (100 T) und Weiden (150 T) ernähren '
        'das Volk, Dörfer (1000 T) bringen Einwohner und Steuern, '
        'Häfen (700 T) erlauben Handelsschiffe. In einem Hafen kannst '
        'du außerdem ein Schiff kaufen (700 T), es über See steuern '
        '(1 Zug pro Feld) und neben einem freien Landfeld ein Dorf '
        'gründen — so kolonisierst du z. B. Inseln.',
    task: 'Tippe ein freies Feld neben deinem Gebiet an und baue '
        'ein Kornfeld oder eine Weide.',
    isDone: (c, since) =>
        c.currentRealm.tileCount.fold(0, (a, b) => a + b) >
        since.buildingTiles,
  ),
  TutorialStep(
    title: 'Handel',
    body: 'Überschüssiges Korn und Vieh verkaufst du auf dem Markt — '
        'die Preise schwanken von Jahr zu Jahr. Mit einem Hafen kannst '
        'du außerdem Taler in Handelsschiffe investieren.',
    task: 'Öffne unten „Handel" und verkaufe Korn oder Rinder.',
    isDone: (c, since) =>
        c.currentRealm.soldGrainThisTurn || c.currentRealm.soldCattleThisTurn,
  ),
  TutorialStep(
    title: 'Militär',
    body: 'Truppen schützen dein Reich und führen Kriege: Rekruten kosten '
        '5 T pro Mann (Söldner 50 T), die Kapazität kommt aus deinen '
        'Siedlungen. Bestehende Truppen kannst du ausbilden (5 T pro '
        'Mann, stärkt die Qualität) oder zu Kavallerie/Artillerie '
        'umrüsten. Krieg erklären kannst du ab dem Jahr 1010 — nur '
        'Nachbarn, einmal pro Jahr.',
    task: 'Öffne „Militär" → „Truppe bilden" und stationiere '
        'Rekruten am Hauptsitz.',
    isDone: (c, since) => c.currentRealm.armySize > since.armySize,
  ),
  TutorialStep(
    title: 'Spionage',
    body: 'Andere Reiche sind verdeckt: Schatzkammer, Truppen und Vorräte '
        'siehst du nur durch Spione (200 T pro Agent, ungefähre Werte). '
        'Attentäter (250 T pro Agent) können fremde Herrscher beseitigen. '
        'Die Spionageabwehr (100 T pro Mann) schützt dich vor beidem.',
  ),
  TutorialStep(
    title: 'Dynastie',
    body: 'Unter „Sonstiges" verwaltest du deine Dynastie: Heirate in '
        'fremde Häuser ein oder bürgerlich — ohne Erben stirbt deine '
        'Dynastie aus und das Spiel ist für dich verloren. Die Kurfürsten '
        'wählen den Kaiser; Titel steigen mit der Größe deines Reichs.',
  ),
  TutorialStep(
    title: 'Zug beenden',
    body: 'Mit „Zug beenden" unten rechts schließt du deinen Zug ab: die '
        'anderen Reiche spielen, ein Jahr vergeht, und Ernte, Steuern und '
        'Ereignisse werden abgerechnet. Jeder abgeschlossene Zug wird '
        'automatisch gespeichert, und zu Beginn des nächsten Zuges fasst '
        'eine Übersicht zusammen, was seither geschah.',
  ),
  TutorialStep(
    title: 'Bereit zur Herrschaft',
    body: 'Das waren die Grundlagen! Alles Weitere findest du unter '
        '„Info": Ereignisse, Siedlungen, Dynastien und die Kaiserchronik. '
        'Verlassen kannst du das Spiel jederzeit über das rote Symbol '
        'links in der Leiste unten.\n\n'
        'Diese Übungspartie wird nicht gespeichert — mit „Tutorial '
        'abschließen" kehrst du zum Hauptmenü zurück und kannst dein '
        'erstes richtiges Spiel starten.',
  ),
];
