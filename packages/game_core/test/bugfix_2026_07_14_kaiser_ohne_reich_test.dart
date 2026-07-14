import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// 2026-07-14 user report: "Als ich gestorben bin wurde ich nach einem
/// Erben gefragt, hab den Ältesten genommen — aber in der Kaiser-Auswahl
/// war der (provisorische) Nachkomme, und jetzt ist einer meiner
/// Nachkommen Kaiser ohne Reich."
///
/// Root cause: death installs a PROVISIONAL heir as ruler at once; the
/// heirChoice decision is non-blocking, so a round rollover (office phase,
/// Kaiser election) can run before the player answers. ROOT FIX
/// (cleanup round, same day): a provisional heir is office-INELIGIBLE
/// while the choice is open (`rulesOnlyProvisionally`) — no seat or crown
/// can accrue to the placeholder, so nothing needs to be transferred or
/// voided when the player picks a different heir. The election tally
/// additionally refuses to crown a winner who lost every realm
/// MID-election (conquest deposition — a case the ineligibility window
/// cannot cover).
void main() {
  late GameState state;

  setUp(() {
    state = startGame(
            newGame(GameSetup(
              humans: [
                HumanPlayerSetup(
                    founderName: 'Anna',
                    gender: 1,
                    countrySlot: 1,
                    dorfName: 'A'),
                HumanPlayerSetup(
                    founderName: 'Berta',
                    gender: 1,
                    countrySlot: 2,
                    dorfName: 'B'),
              ],
              reformationYear: 1020,
              ottomanYear: 1040,
              seed: 2026,
            )),
            Rng(7))
        .state;
    state.year = 1012;
  });

  /// Kills slot 1's ruler after giving them [children]; returns the
  /// heirChoice decision (the priority heir is provisional ruler now).
  PendingDecision die(List<Person> children) {
    final dynasty = state.dynasty(1);
    final ruler = state.person(state.realm(1).rulerId)!;
    for (final p in children) {
      state.persons[p.id] = p;
      dynasty.memberIds.add(p.id);
      ruler.childrenIds.add(p.id);
    }
    handleDeath(state, ruler, Rng(5), <GameEvent>[]);
    return state.pendingDecisions.singleWhere((d) => d.type == 'heirChoice');
  }

  Person child(String name, {required int age, int gender = 0}) => Person(
      id: state.nextPersonId++,
      name: name,
      age: age,
      dynasty: 1,
      gender: gender);

  test(
      'a provisional heir gains no Kurfürst seat and no crown while the '
      'heirChoice is open (no "Kaiser ohne Reich")', () {
    final young = child('Junior', age: 15);
    final eldest = child('Ältester', age: 25);
    final decision = die([young, eldest]);
    expect(state.realm(1).rulerId, young.id,
        reason: 'the FIRST male child is the provisional heir');
    expect(rulesOnlyProvisionally(state, young.id), isTrue);

    // The round rolls over while the heirChoice is unanswered: the office
    // phase runs — seats fill and a Kaiser election may complete — but the
    // placeholder must be passed over everywhere.
    final events = <GameEvent>[];
    runOfficePhase(state, Rng(9), events);

    expect(state.kurfuerstenIds, isNot(contains(young.id)),
        reason: 'a provisional heir must not take a Kurfürst seat');
    expect(state.kaiserId, isNot(young.id),
        reason: 'a provisional heir must not be crowned');

    // The player picks the eldest: the realm re-crowns, the placeholder
    // holds nothing that would need transferring, and the chosen heir is
    // a fully eligible ruler from now on.
    final next = applyAction(
            state,
            ResolveDecision(
                slot: 1,
                decisionId: decision.id,
                choice: {'heirId': eldest.id}),
            Rng(state.rngSeed))
        .state;

    expect(next.realm(1).rulerId, eldest.id);
    expect(next.kurfuerstenIds, isNot(contains(young.id)));
    expect(next.kaiserId, isNot(young.id));
    expect(rulesOnlyProvisionally(next, eldest.id), isFalse,
        reason: 'the resolved choice ends the ineligibility window');
  });

  test(
      'a provisional heir who already rules another realm stays a '
      'legitimate ruler and office candidate', () {
    final young = child('Junior', age: 20);
    final sibling = child('Bruder', age: 18);
    // Junior already rules slot 3 in his own right.
    state.realm(3).rulerId = young.id;
    die([young, sibling]);

    expect(state.realm(1).rulerId, young.id, reason: 'provisional for slot 1');
    expect(rulesOnlyProvisionally(state, young.id), isFalse,
        reason: 'slot 3 is his outside the pending choice — he is a real '
            'ruler, only slot 1 is provisional');
  });

  test('a finalist who lost every realm mid-election is never crowned', () {
    // A landless person wins the vote (their realm was reassigned by an
    // heirChoice while the election was running): the result is void, the
    // throne stays vacant for a fresh election.
    final landless = child('Landlos', age: 30);
    state.persons[landless.id] = landless;
    final rival = state.person(state.realm(2).rulerId)!;
    final elector = state.person(state.realm(3).rulerId)!;

    state.activeElection = ActiveElection(
      office: Office.kaiser,
      finalistIds: [landless.id, rival.id],
      electorIds: [elector.id],
      bribesDone: {landless.id, rival.id},
      votes: {elector.id: landless.id},
    );

    final events = <GameEvent>[];
    advanceElection(state, Rng(3), events);

    expect(state.kaiserId, isNull,
        reason: 'a throne without a realm behind it must not be filled');
    expect(state.activeElection, isNull);
    expect(events.any((e) => e.type == 'interregnum'), isTrue);
  });
}
