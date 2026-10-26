/// The OPTIONAL online notifications a player can switch off under
/// Options ▸ Notifications (`[DESIGNED 2026-08-24, user request]`).
///
/// The strings are the WIRE contract with the server's `PushKind`
/// (`backend/lib/src/models.dart`): they travel as `push_opt_out` in
/// `PATCH /players/:id` and the server refuses to mute anything outside
/// its own optional set. Keep both lists in sync when a kind is added.
///
/// Everything NOT listed here is essential and always sent: "you are up"
/// (`your_turn`), "a decision is waiting" (`your_decision`) and the
/// warning that a long-silent match is about to be deleted
/// (`match_expiring`) — switching those off would mean losing turns, or
/// a match, without ever being told.
library;

/// "{Realm} declared war on you" — sent when the preparation window opens.
const String pushWarStarted = 'war_started';

/// "The war appointment is set" — sent to the side that was waiting once
/// both combatants have chosen their times.
const String pushWarStartFixed = 'war_start_fixed';

/// "Your war starts shortly" — ~15 minutes before an AGREED duel start.
const String pushWarStartSoon = 'war_start_soon';

/// "The Weltmeisterschaft sign-up is open" — once a year, to an FCM TOPIC
/// rather than to the player record (it must reach players who never
/// played online). Switching it off unsubscribes the device
/// (`championship_topic.dart`); it is also uploaded like the others.
const String pushChampionship = 'championship';

/// Every switchable kind, in the order the options screen lists them
/// (chronological along a war: declaration → appointment → reminder; the
/// yearly championship announcement last).
const List<String> optionalPushKinds = [
  pushWarStarted,
  pushWarStartFixed,
  pushWarStartSoon,
  pushChampionship,
];

/// The `notify.*` string-table keys for [kind]'s label and explanation.
String pushKindTitleKey(String kind) => 'notify.$kind.title';
String pushKindSubtitleKey(String kind) => 'notify.$kind.subtitle';
