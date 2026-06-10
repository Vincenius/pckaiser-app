import '../data/tables.dart';
import '../rng/rng.dart';
import '../state/constants.dart';
import '../state/dynasty.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/pending_decision.dart';
import '../state/person.dart';
import 'offices.dart';
import 'protection.dart';

/// End-of-turn dynasty events for the active slot (§6.1 step 3, §14, §15):
/// aging & death rolls (with succession), the annual marriage/birth loop.
/// Mutates [state] in place; the pipeline owns the copy.
void runDynastyPhase(GameState state, int slot, Rng rng,
    List<GameEvent> events) {
  final dynasty = state.dynasty(slot);

  // §15.1 Aging & natural death — iterate over a snapshot; deaths mutate
  // the member list.
  for (final personId in List.of(dynasty.memberIds)) {
    final person = state.persons[personId];
    if (person == null) continue;
    person.age += 1;
    // Protect-new-players rule: no random death rolls in years 1000–1009.
    if (newPlayerProtectionActive(state)) continue;
    final span = 90 - person.age;
    if (span <= 2 || rng.nextInt(span) < 2) {
      events.add(GameEvent(
        year: state.year,
        slot: slot,
        type: 'personDied',
        visibility: EventVisibility.public,
        payload: {'name': person.name, 'age': person.age, 'cause': 'age'},
      ));
      handleDeath(state, person, rng, events);
    }
  }

  // §14.3 / §15.3 Annual marriage & birth loop over the living members.
  for (final personId in List.of(dynasty.memberIds)) {
    final person = state.persons[personId];
    if (person == null) continue;

    if (person.spouseId != null) {
      // Births fire once per couple — processed from the husband's side
      // (single-parent phantom children are handled below).
      if (person.isMale && rng.nextInt(4) == 0) {
        _birth(state, person, state.persons[person.spouseId!], rng, events);
      }
      continue;
    }

    if (person.age >= 14 && rng.nextInt(4) == 0) {
      final candidate = findMarriageCandidate(state, person, rng);
      // [DEVIATION] The original's 50% "phantom birth" (§15.3: a
      // single-parent child when no candidate exists) is removed —
      // children require married parents.
      if (candidate != null) {
        proposeMarriage(state, person, candidate, rng, events);
      }
    }
  }
}

/// §14.1 eligibility: unmarried, opposite gender, age ≥ 14, age gap < 10,
/// different dynasty, same religion. Scans the master list in id order and
/// picks uniformly among the eligible.
Person? findMarriageCandidate(GameState state, Person seeker, Rng rng) {
  final religion = state.dynasty(seeker.dynasty).religion;
  final candidates = <Person>[];
  for (final other in state.persons.values) {
    if (other.spouseId != null ||
        other.gender == seeker.gender ||
        other.age < 14 ||
        (other.age - seeker.age).abs() >= 10 ||
        other.dynasty == seeker.dynasty ||
        state.dynasty(other.dynasty).religion != religion) {
      continue;
    }
    candidates.add(other);
  }
  if (candidates.isEmpty) return null;
  return candidates[rng.nextInt(candidates.length)];
}

/// §14.1 acceptance: an AI-controlled target rolls 25% immediately; a
/// human-controlled target gets a `marriageConsent` pending decision
/// (default fallback on timeout: the same 25% roll).
void proposeMarriage(GameState state, Person proposer, Person target,
    Rng rng, List<GameEvent> events) {
  final targetDynasty = state.dynasty(target.dynasty);
  if (targetDynasty.status == DynastyStatus.human) {
    state.pendingDecisions.add(PendingDecision(
      id: 'marriage-${proposer.id}-${target.id}-${state.year}',
      type: 'marriageConsent',
      decidingSlot: target.dynasty,
      payload: {'proposerId': proposer.id, 'targetId': target.id},
    ));
    return;
  }
  if (rng.nextInt(4) == 0) {
    marry(state, proposer, target, events); // "Angenommen !"
  } else {
    events.add(GameEvent(
      year: state.year,
      slot: proposer.dynasty,
      type: 'marriageRejected',
      visibility: EventVisibility.participants,
      participants: [proposer.dynasty, target.dynasty],
      payload: {'proposerId': proposer.id, 'targetId': target.id},
    ));
  }
}

/// §14.2 the wedding: spouse pointers set; the children lists merge and
/// attach to the husband, the wife's is cleared.
void marry(GameState state, Person a, Person b, List<GameEvent> events) {
  a.spouseId = b.id;
  b.spouseId = a.id;
  final husband = a.isMale ? a : b;
  final wife = a.isMale ? b : a;
  husband.childrenIds.addAll(wife.childrenIds);
  wife.childrenIds.clear();
  events.add(GameEvent(
    year: state.year,
    slot: a.dynasty,
    type: 'wedding',
    visibility: EventVisibility.public,
    payload: {'a': a.name, 'b': b.name, 'aId': a.id, 'bId': b.id},
  ));
}

/// §14.4: a religion change dissolves religiously incompatible marriages.
void divorceIncompatibleCouples(GameState state, int slot,
    List<GameEvent> events) {
  final religion = state.dynasty(slot).religion;
  for (final personId in List.of(state.dynasty(slot).memberIds)) {
    final person = state.persons[personId];
    final spouse = state.person(person?.spouseId);
    if (person == null || spouse == null) continue;
    if (state.dynasty(spouse.dynasty).religion != religion) {
      person.spouseId = null;
      spouse.spouseId = null;
      events.add(GameEvent(
        year: state.year,
        slot: slot,
        type: 'divorce',
        visibility: EventVisibility.public,
        payload: {'a': person.name, 'b': spouse.name},
      ));
    }
  }
}

/// §15.3 birth. [mother] is null for the 50% phantom birth. Children of
/// human dynasties get a provisional table name plus a `childName` pending
/// decision (non-blocking rename).
void _birth(GameState state, Person parent, Person? partner, Rng rng,
    List<GameEvent> events) {
  final dynasty = state.dynasty(parent.dynasty);
  final gender = rng.nextInt(2);
  final muslim = dynasty.religion == Religion.moslemisch;
  final List<String> names = muslim
      ? (gender == 0 ? ottomanMaleNames : ottomanFemaleNames)
      : (gender == 0 ? europeanMaleNames : europeanFemaleNames);
  final child = Person(
    id: state.nextPersonId++,
    name: names[rng.nextInt(names.length)],
    age: 0, // original left this uninitialized — deliberate fix
    dynasty: parent.dynasty,
    gender: gender,
  );
  state.persons[child.id] = child;
  dynasty.memberIds.add(child.id);
  parent.childrenIds.add(child.id);
  partner?.childrenIds.add(child.id);

  if (dynasty.status == DynastyStatus.human) {
    state.pendingDecisions.add(PendingDecision(
      id: 'childname-${child.id}',
      type: 'childName',
      decidingSlot: parent.dynasty,
      payload: {'childId': child.id, 'suggestedName': child.name},
    ));
  }
  events.add(GameEvent(
    year: state.year,
    slot: parent.dynasty,
    type: 'birth',
    visibility: EventVisibility.public,
    payload: {
      'parent': parent.name,
      'partner': partner?.name,
      'child': child.name,
      'gender': gender,
    },
  ));
}

/// Design decision (2026-06-10, CHECKLIST resolved-questions log): when a
/// slot's ruler pointer is overwritten with a ruler from another dynasty —
/// conquest (§11.2) or cross-dynasty inheritance (§15.4) — control of the
/// slot follows the new ruler: the slot's dispatch entry adopts the
/// controller (status + humanPlayer) of the ruler's home dynasty. Without
/// this, a captured human slot would still be dealt to the old player.
void alignSlotControl(GameState state, int slot, int? rulerId) {
  final ruler = state.person(rulerId);
  if (ruler == null || ruler.dynasty == slot) return;
  final home = state.dynasty(ruler.dynasty);
  final dynasty = state.dynasty(slot);
  dynasty.status = home.status;
  dynasty.humanPlayer = home.humanPlayer;
}

/// Death of any person (§15.4): removes them everywhere; rulers trigger
/// succession across all their slots, office holders get their chronicle
/// closed (§17.5).
void handleDeath(
    GameState state, Person deceased, Rng rng, List<GameEvent> events) {
  final dynasty = state.dynasty(deceased.dynasty);

  // Remove from the world.
  state.persons.remove(deceased.id);
  dynasty.memberIds.remove(deceased.id);
  final spouse = state.person(deceased.spouseId);
  spouse?.spouseId = null;
  for (final person in state.persons.values) {
    person.childrenIds.remove(deceased.id);
  }
  state.kurfuerstenIds.remove(deceased.id); // seat refilled next round

  closeChronicleIfOfficeHolder(state, deceased, rng, events);

  final ruledSlots = [
    for (final realm in state.realms)
      if (realm.rulerId == deceased.id) realm.slot,
  ];
  if (ruledSlots.isEmpty) return;

  final heir = _chooseHeirByPriority(state, deceased, dynasty, rng);
  if (heir != null) {
    // §15.5 Islamic succession crisis: a Muslim realm cannot be ruled by a
    // woman — the realm falls to computer control (heir still crowned).
    if (dynasty.religion == Religion.moslemisch &&
        !heir.isMale &&
        dynasty.status == DynastyStatus.human) {
      dynasty.status = DynastyStatus.ai;
      dynasty.humanPlayer = null;
      events.add(GameEvent(
        year: state.year,
        slot: deceased.dynasty,
        type: 'islamicSuccessionCrisis',
        visibility: EventVisibility.public,
        payload: {'heir': heir.name},
      ));
    }
    for (final slot in ruledSlots) {
      state.realm(slot).rulerId = heir.id;
      alignSlotControl(state, slot, heir.id);
    }
    events.add(GameEvent(
      year: state.year,
      slot: deceased.dynasty,
      type: 'succession',
      visibility: EventVisibility.public,
      payload: {'deceased': deceased.name, 'heir': heir.name},
    ));
    // A human dynasty picks from a menu — the priority heir is provisional
    // until the decision is resolved (non-blocking).
    if (dynasty.status == DynastyStatus.human &&
        dynasty.memberIds.length > 1) {
      state.pendingDecisions.add(PendingDecision(
        id: 'heir-${deceased.id}-${state.year}',
        type: 'heirChoice',
        decidingSlot: deceased.dynasty,
        payload: {
          'deceasedName': deceased.name,
          'candidateIds': List.of(dynasty.memberIds),
          'provisionalHeirId': heir.id,
          'slots': ruledSlots,
        },
      ));
    }
    return;
  }

  // No members remain: everything passes to a random other living ruler.
  final livingRulers = <int>{
    for (final realm in state.realms)
      if (realm.rulerId != null && realm.rulerId != deceased.id)
        realm.rulerId!,
  }.toList();
  if (livingRulers.isEmpty) {
    events.add(GameEvent(
      year: state.year,
      slot: 0,
      type: 'totalExtinction',
      visibility: EventVisibility.public,
    ));
    for (final slot in ruledSlots) {
      state.realm(slot).rulerId = null;
    }
    return;
  }
  final inheritor = livingRulers[rng.nextInt(livingRulers.length)];
  for (final slot in ruledSlots) {
    state.realm(slot).rulerId = inheritor;
    alignSlotControl(state, slot, inheritor);
  }
  events.add(GameEvent(
    year: state.year,
    slot: deceased.dynasty,
    type: 'dynastyExtinct',
    visibility: EventVisibility.public,
    payload: {
      'deceased': deceased.name,
      'inheritor': state.persons[inheritor]?.name,
    },
  ));
}

/// §15.4 heir priority: first male child → first male member → spouse →
/// first child → first member → random member. The deceased is already
/// removed from all lists; the spouse may belong to another dynasty (the
/// peaceful inheritance path).
Person? _chooseHeirByPriority(
    GameState state, Person deceased, Dynasty dynasty, Rng rng) {
  Person? firstAlive(Iterable<int> ids, {bool? male}) {
    for (final id in ids) {
      final p = state.persons[id];
      if (p != null && (male == null || p.isMale == male)) return p;
    }
    return null;
  }

  final spouse = state.person(deceased.spouseId);
  final heir = firstAlive(deceased.childrenIds, male: true) ??
      firstAlive(dynasty.memberIds, male: true) ??
      spouse ??
      firstAlive(deceased.childrenIds) ??
      firstAlive(dynasty.memberIds);
  if (heir != null) return heir;
  if (dynasty.memberIds.isEmpty) return null;
  return state.persons[
      dynasty.memberIds[rng.nextInt(dynasty.memberIds.length)]];
}
