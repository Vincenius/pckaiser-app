import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// 2026-07-14 user report: "Als ich gestorben bin wurde ich nach einem
/// Erben gefragt, hab den Ältesten genommen — aber in der Kaiser-Auswahl
/// war der (provisorische) Nachkomme, und jetzt ist einer meiner
/// Nachkommen Kaiser ohne Reich."
///
/// Root cause: death installs a PROVISIONAL heir as ruler at once; the
/// heirChoice decision is non-blocking, so a round rollover (office phase,
/// Kaiser election) can run before the player answers. The provisional
/// heir — carrying the deceased's König title — could win a Kurfürst seat
/// or the crown; the later heirChoice override then stripped the realm but
/// left the office pointing at a realm-less person forever (elections only
/// re-trigger on a VACANT office).
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
      'a crown won by the provisional heir follows the chosen heir '
      '(no "Kaiser ohne Reich")', () {
    final young = child('Junior', age: 15);
    final eldest = child('Ältester', age: 25);
    final decision = die([young, eldest]);
    expect(state.realm(1).rulerId, young.id,
        reason: 'the FIRST male child is the provisional heir');

    // The round rolls over while the heirChoice is unanswered: the office
    // phase seats the provisional heir as Kurfürst and crowns them Kaiser.
    state.kurfuerstenIds.add(young.id);
    state.kaiserId = young.id;
    state.kaiserChronicle.add(ChronicleRecord(
        name: young.name,
        accessionYear: state.year,
        personId: young.id,
        slot: 1));

    // The player picks the eldest instead.
    final next = applyAction(
            state,
            ResolveDecision(
                slot: 1,
                decisionId: decision.id,
                choice: {'heirId': eldest.id}),
            Rng(state.rngSeed))
        .state;

    expect(next.realm(1).rulerId, eldest.id);
    expect(next.kaiserId, eldest.id,
        reason: 'the crown follows the realm to the true heir');
    expect(next.kurfuerstenIds, contains(eldest.id));
    expect(next.kurfuerstenIds, isNot(contains(young.id)));
    final record = next.kaiserChronicle
        .lastWhere((r) => r.deathYear == null);
    expect(record.personId, eldest.id,
        reason: 'retroactively it was the heir\'s reign all along');
    expect(record.accessionYear, state.year);
  });

  test('an heir ineligible for the office vacates it for a fresh election',
      () {
    final young = child('Junior', age: 15);
    final daughter = child('Tochter', age: 22, gender: 1);
    final decision = die([young, daughter]);
    state.kurfuerstenIds.add(young.id);
    state.kaiserId = young.id;
    state.kaiserChronicle.add(ChronicleRecord(
        name: young.name,
        accessionYear: state.year,
        personId: young.id,
        slot: 1));

    // The player picks the daughter — she can rule the realm, but §17.2
    // bars her from the Kaiser throne: the office falls vacant instead of
    // sticking to the realm-less placeholder.
    final next = applyAction(
            state,
            ResolveDecision(
                slot: 1,
                decisionId: decision.id,
                choice: {'heirId': daughter.id}),
            Rng(state.rngSeed))
        .state;

    expect(next.realm(1).rulerId, daughter.id);
    expect(next.kaiserId, isNull,
        reason: 'vacant throne → the next world phase elects anew');
    expect(next.kurfuerstenIds, isNot(contains(young.id)));
    expect(next.kaiserChronicle.where((r) => r.deathYear == null), isEmpty,
        reason: 'the placeholder\'s record is dropped as never legitimate');
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
