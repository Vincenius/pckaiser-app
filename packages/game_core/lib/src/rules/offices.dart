import '../data/tables.dart';
import '../rng/rng.dart';
import '../state/chronicle.dart';
import '../state/constants.dart';
import '../state/dynasty.dart';
import '../state/election.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/pending_decision.dart';
import '../state/person.dart';
import '../state/realm.dart';
import 'protection.dart';

/// World-phase office bookkeeping (§17): refill Kurfürst seats, then start
/// or advance a Kaiser/Sultan election.
void runOfficePhase(GameState state, Rng rng, List<GameEvent> events) {
  refillKurfuersten(state, rng, events);
  if (state.activeElection == null) {
    if (state.kaiserId == null) {
      maybeStartElection(state, Office.kaiser, rng, events);
    }
    if (state.activeElection == null && state.sultanId == null) {
      maybeStartElection(state, Office.sultan, rng, events);
    }
  }
  advanceElection(state, rng, events);
}

/// The realm a person rules (first slot found), or null.
Realm? realmRuledBy(GameState state, int personId) {
  for (final realm in state.realms) {
    if (realm.rulerId == personId) return realm;
  }
  return null;
}

/// Base (male-form) title class a ruler holds — the highest across all
/// their slots (ruler aliasing).
int _rulerTitleClass(GameState state, int personId) {
  var best = 0;
  for (final realm in state.realms) {
    if (realm.rulerId != personId) continue;
    final base =
        realm.titleClass > 12 ? realm.titleClass - 12 : realm.titleClass;
    if (base > best) best = base;
  }
  return best;
}

/// §17.2 eligibility: a living dynasty's ruler, male, age ≥ 14, dynasty
/// religion ≠ Muslim, not already an elector.
List<Person> _kurfuerstCandidates(GameState state) {
  final seen = <int>{};
  final candidates = <Person>[];
  for (final realm in state.realms) {
    final ruler = state.person(realm.rulerId);
    if (ruler == null || !seen.add(ruler.id)) continue;
    if (!ruler.isMale ||
        ruler.age < 14 ||
        state.dynasty(ruler.dynasty).religion == Religion.moslemisch ||
        state.kurfuerstenIds.contains(ruler.id)) {
      continue;
    }
    candidates.add(ruler);
  }
  return candidates;
}

/// §17.2: every round, while seats < 7, the eligible ruler with the
/// highest titleClass takes a seat (the current Kaiser counts +2; ties
/// break by random draw).
void refillKurfuersten(GameState state, Rng rng, List<GameEvent> events) {
  while (state.kurfuerstenIds.length < World.kurfuerstSeats) {
    final candidates = _kurfuerstCandidates(state);
    if (candidates.isEmpty) return; // "Der Posten bleibt vakant."

    var bestScore = -1;
    final best = <Person>[];
    for (final candidate in candidates) {
      var score = _rulerTitleClass(state, candidate.id);
      if (state.kaiserId == candidate.id) score += 2;
      if (score > bestScore) {
        bestScore = score;
        best
          ..clear()
          ..add(candidate);
      } else if (score == bestScore) {
        best.add(candidate);
      }
    }
    final winner = best[rng.nextInt(best.length)];
    state.kurfuerstenIds.add(winner.id);
    events.add(GameEvent(
      year: state.year,
      slot: winner.dynasty,
      type: 'newKurfuerst',
      visibility: EventVisibility.public,
      payload: {'name': winner.name},
    ));
  }
}

/// §17.3/§17.4 trigger: no office holder, year ≥ 1010, and voters exist
/// (Kaiser: ≥ 1 elector; Sultan: ≥ 1 Muslim ruler).
void maybeStartElection(
    GameState state, Office office, Rng rng, List<GameEvent> events) {
  if (state.year < firstWarYear) return;

  final List<int> electorIds;
  final List<Person> candidates;
  if (office == Office.kaiser) {
    electorIds = List.of(state.kurfuerstenIds);
    // A seated Kurfürst who no longer rules any realm (deposed
    // by internal strife, realm captured) keeps the vote but is no longer
    // a candidate — a throne without a realm could never collect the pot.
    candidates = _kurfuerstCandidates(state)
      ..addAll([
        for (final id in state.kurfuerstenIds)
          // Candidates must currently rule a realm — a deposed Kurfürst
          // must not be electable to a throne with no realm behind it.
          if (state.persons[id] != null && realmRuledBy(state, id) != null)
            state.persons[id]!,
      ]);
  } else {
    // Sultan mirror office: candidates and voters are the Muslim rulers.
    final seen = <int>{};
    candidates = [];
    for (final realm in state.realms) {
      final ruler = state.person(realm.rulerId);
      if (ruler == null || !seen.add(ruler.id)) continue;
      if (state.dynasty(ruler.dynasty).religion != Religion.moslemisch) {
        continue;
      }
      if (ruler.isMale && ruler.age >= 14) candidates.add(ruler);
    }
    electorIds = [for (final c in candidates) c.id];
  }
  if (electorIds.isEmpty) return;

  if (candidates.isEmpty) {
    // "Die dunkle Zeit des Interregnums bricht an." — retried next round.
    events.add(GameEvent(
      year: state.year,
      slot: 0,
      type: 'interregnum',
      visibility: EventVisibility.public,
      payload: {'office': office.name},
    ));
    return;
  }

  events.add(GameEvent(
    year: state.year,
    slot: 0,
    type: 'electionStarted',
    visibility: EventVisibility.public,
    payload: {'office': office.name},
  ));

  if (candidates.length == 1) {
    _crown(state, office, candidates.single, events, acclaimed: true);
    return;
  }

  // Eliminate down to 2 finalists by title score; ties break randomly:
  // shuffle, then sort by (score desc, shuffled position asc). The
  // explicit position tiebreaker keeps the shuffle effective — Dart's
  // List.sort is not stable.
  final pool = List.of(candidates);
  for (var i = pool.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = pool[i];
    pool[i] = pool[j];
    pool[j] = tmp;
  }
  final shuffledIndex = {
    for (var i = 0; i < pool.length; i++) pool[i].id: i,
  };
  pool.sort((a, b) {
    final byScore =
        _rulerTitleClass(state, b.id).compareTo(_rulerTitleClass(state, a.id));
    if (byScore != 0) return byScore;
    return shuffledIndex[a.id]!.compareTo(shuffledIndex[b.id]!);
  });
  final finalists = pool.take(2).toList();

  state.activeElection = ActiveElection(
    office: office,
    finalistIds: [for (final f in finalists) f.id],
    electorIds: electorIds,
  );
}

/// Advances the bribery → vote → tally state machine. AI participants act
/// immediately; human participants get pending decisions, and this
/// function is re-entered when they resolve.
void advanceElection(GameState state, Rng rng, List<GameEvent> events) {
  final election = state.activeElection;
  if (election == null) return;

  // Bribery phase (§17.3), one finalist at a time.
  for (final finalistId in election.finalistIds) {
    if (election.bribesDone.contains(finalistId)) continue;
    final finalist = state.persons[finalistId];
    final realm = finalist == null ? null : realmRuledBy(state, finalistId);
    if (finalist == null || realm == null) {
      election.bribesDone.add(finalistId); // died/deposed mid-election
      continue;
    }
    if (state.dynasty(finalist.dynasty).status == DynastyStatus.human) {
      final decisionId = 'bribe-${election.office.name}-$finalistId';
      if (!state.pendingDecisions.any((d) => d.id == decisionId)) {
        state.pendingDecisions.add(PendingDecision(
          id: decisionId,
          type: 'electionBribe',
          decidingSlot: finalist.dynasty,
          payload: {
            'office': election.office.name,
            'finalistId': finalistId,
            'electorIds': election.electorIds,
          },
        ));
      }
      return; // wait for the human
    }
    // AI finalist: gift random amounts to random electors until a roll is
    // 0. [DEVIATION] The original drew random(treasury) each time, which
    // in expectation handed out nearly the whole treasury per election and
    // wrecked AI economies — the clone caps the campaign budget at half
    // the treasury and draws from what remains of it.
    var budget = realm.treasury ~/ 2;
    for (var guard = 0; guard < 1000; guard++) {
      if (budget <= 0) break;
      final amount = rng.nextInt(budget);
      if (amount == 0) break;
      final electorId =
          election.electorIds[rng.nextInt(election.electorIds.length)];
      budget -= amount;
      realm.treasury -= amount;
      realmRuledBy(state, electorId)?.treasury += amount;
      election.addBribe(electorId, finalistId, amount);
    }
    election.bribesDone.add(finalistId);
  }
  if (election.bribesDone.length < election.finalistIds.length) return;

  // Vote phase.
  for (final electorId in election.electorIds) {
    if (election.votes.containsKey(electorId)) continue;
    final elector = state.persons[electorId];
    if (elector == null) {
      election.votes[electorId] = -1; // died mid-election: abstains
      continue;
    }
    if (election.finalistIds.contains(electorId)) {
      election.votes[electorId] = electorId; // votes for themself
      continue;
    }
    if (state.dynasty(elector.dynasty).status == DynastyStatus.human) {
      final decisionId = 'vote-${election.office.name}-$electorId';
      if (!state.pendingDecisions.any((d) => d.id == decisionId)) {
        state.pendingDecisions.add(PendingDecision(
          id: decisionId,
          type: 'electorVote',
          decidingSlot: elector.dynasty,
          payload: {
            'office': election.office.name,
            'electorId': electorId,
            'finalistIds': election.finalistIds,
            'bribes': {
              for (final f in election.finalistIds)
                '$f': election.bribeFor(electorId, f),
            },
          },
        ));
      }
      continue; // other electors may still vote meanwhile
    }
    // AI elector: whoever bribed more; equal → coin flip.
    final a = election.finalistIds[0];
    final b = election.finalistIds.length > 1 ? election.finalistIds[1] : a;
    final bribeA = election.bribeFor(electorId, a);
    final bribeB = election.bribeFor(electorId, b);
    election.votes[electorId] = bribeA > bribeB
        ? a
        : bribeB > bribeA
            ? b
            : (rng.nextInt(2) == 0 ? a : b);
  }
  if (election.votes.length < election.electorIds.length) return;

  // Tally: strict majority among cast votes.
  final counts = <int, int>{};
  for (final vote in election.votes.values) {
    if (vote != -1) counts[vote] = (counts[vote] ?? 0) + 1;
  }
  state.activeElection = null;
  Person? winner;
  var bestVotes = -1;
  var tied = false;
  for (final entry in counts.entries) {
    if (entry.value > bestVotes) {
      bestVotes = entry.value;
      winner = state.persons[entry.key];
      tied = false;
    } else if (entry.value == bestVotes) {
      tied = true;
    }
  }
  if (winner == null || tied) {
    // "Die Kurfürsten können sich nicht einigen." — original keeps the
    // throne vacant on a tie, even with willing candidates.
    events.add(GameEvent(
      year: state.year,
      slot: 0,
      type: 'electionTie',
      visibility: EventVisibility.public,
      payload: {'office': election.office.name},
    ));
    return;
  }
  _crown(state, election.office, winner, events);
}

void _crown(
    GameState state, Office office, Person winner, List<GameEvent> events,
    {bool acclaimed = false}) {
  if (office == Office.kaiser) {
    state.kaiserId = winner.id;
    state.kaiserChronicle.add(ChronicleRecord(
        name: winner.name,
        accessionYear: state.year,
        personId: winner.id,
        slot: winner.dynasty));
  } else {
    state.sultanId = winner.id;
    state.sultanChronicle.add(ChronicleRecord(
        name: winner.name,
        accessionYear: state.year,
        personId: winner.id,
        slot: winner.dynasty));
  }
  events.add(GameEvent(
    year: state.year,
    slot: winner.dynasty,
    type: 'crowned',
    visibility: EventVisibility.public,
    payload: {
      'office': office.name,
      'name': winner.name,
      'acclaimed': acclaimed,
    },
  ));
}

/// §17.5: a Kaiser/Sultan dying in office gets their chronicle record
/// closed and possibly an epithet (50% none; pool by reign > 10 years ×
/// weight > 60). Clears the office; the next world phase elects anew.
/// Must run while the deceased's realms still point at them.
void closeChronicleIfOfficeHolder(
    GameState state, Person deceased, Rng rng, List<GameEvent> events) {
  final List<ChronicleRecord> chronicle;
  final Office office;
  if (state.kaiserId == deceased.id) {
    chronicle = state.kaiserChronicle;
    office = Office.kaiser;
    state.kaiserId = null;
  } else if (state.sultanId == deceased.id) {
    chronicle = state.sultanChronicle;
    office = Office.sultan;
    state.sultanId = null;
  } else {
    return;
  }

  // Match the open record by person id (names from the tables repeat);
  // fall back to name matching only for pre-personId saves.
  var record = chronicle.lastWhere(
    (r) =>
        r.deathYear == null &&
        (r.personId == deceased.id ||
            (r.personId == null && r.name == deceased.name)),
    orElse: () {
      final r = ChronicleRecord(
          name: deceased.name,
          accessionYear: state.year,
          personId: deceased.id,
          slot: deceased.dynasty);
      chronicle.add(r);
      return r;
    },
  );
  record.deathYear = state.year;

  if (rng.nextInt(2) == 0) {
    final reign = state.year - record.accessionYear;
    final weight = realmRuledBy(state, deceased.id)?.popularity ?? 50;
    final pool = epithetPools[(reign > 10 ? 0 : 2) + (weight > 60 ? 0 : 1)];
    final roll = rng.nextInt(20);
    record.epithet = pool[roll < pool.length ? roll : 0];
  }

  events.add(GameEvent(
    year: state.year,
    slot: deceased.dynasty,
    type: 'officeHolderDied',
    visibility: EventVisibility.public,
    payload: {
      'office': office.name,
      'name': deceased.name,
      'epithet': record.epithet,
    },
  ));
}
