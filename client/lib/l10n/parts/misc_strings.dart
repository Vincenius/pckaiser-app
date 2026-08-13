/// String-table part for the "misc" UI area — merged into the app-wide
/// table in `l10n/strings.dart`. Keys are prefixed `dec.` (decision
/// dialogs, `widgets/decisions.dart`); `{name}`-style placeholders are
/// filled by `tr(key, params)`.
const Map<String, String> miscDe = {
  'dec.roundReport': 'Rundenbericht',
  // "Albrecht von Brandenburg (34)" — proposer line in the marriage offer.
  'dec.proposerLine': '{name} von {realm} ({age})',
  'dec.marriageProposalTitle': 'Heiratsantrag',
  'dec.marriageProposalBody':
      '{proposer} hält um die Hand von {target} an. Einverstanden?',
  'dec.heirChoiceTitle': '{name} ist gestorben ! Wähle den Erben:',
  'dec.personWithAge': '{name} ({age})',
  'dec.warDeclaredTitle': 'Krieg erklärt !',
  'dec.warDeclarationTitle': 'Kriegserklärung !',
  'dec.warPlanYouDeclared': 'Du hast {realm} den Krieg erklärt.',
  'dec.warPlanEnemyDeclared': '{realm} hat dir den Krieg erklärt !',
  'dec.warPlanBody':
      '{declaration} Willst du deine Truppen selbst befehligen?\n\n'
      'Bei „Nein" übernimmt der Computer diesen Krieg: deine Truppen '
      'folgen ihrer Haltung. Bis zum Kriegsbeginn kannst du jede Truppe '
      'einzeln auf der Karte einstellen (Stellung halten oder '
      'angreifen) — im Kriegsvorbereitungs-Menü über der Karte. Der '
      'Krieg beginnt, sobald beide Seiten gewählt haben — wollen beide '
      'selbst steuern, online zum vereinbarten Zeitpunkt oder nach '
      'Ablauf der Vorbereitungsfrist.',
  'dec.warDefenseBody':
      '{realm} hat dir den Krieg erklärt ! Willst du deine Truppen '
      'selbst befehligen?\n\nBei „Nein" übernimmt der Computer '
      'diesen Krieg: deine Truppen folgen ihrer eingestellten '
      'Haltung (halten / greifen an), und du spielst erst nach '
      'Kriegsende wieder selbst.',
  'dec.childBornBoy': 'Ein Junge ist geboren ! Wie soll er heißen?',
  'dec.childBornGirl': 'Ein Mädchen ist geboren ! Wie soll sie heißen?',
  'dec.electionVoteTitle': 'Kaiserwahl — deine Stimme',
  'dec.electionCandidate': '{name} (Bestechung: {amount} T)',
  'dec.coercionTitle': 'Zwang',
  'dec.coerceConvertOrDie':
      'Willst du {name} vor die Wahl stellen: Bekehrung oder Tod?',
  'dec.coerceForcedMarriage': 'Willst du {name} zur Heirat zwingen?',
  'dec.coerceAbdication': 'Willst du {name} als Kaiser abdanken lassen?',
  'dec.coerceStripSeat': 'Willst du {name} den Kurfürstensitz aberkennen?',
  'dec.coerceOther': 'Willst du {name} zwingen ({option})?',
  'dec.convertOrDieTitle': 'Bekehrung oder Tod',
  'dec.convertOrDieBody': 'Sterben oder sich bekehren — bekehrst du dich?',
  'dec.relocateSeatTitle': 'Dein Sitz ist verloren — wähle einen neuen',
  'dec.relocateSeatMapHint':
      'Sitz verloren — tippe auf der Karte eine Stadt, Burg oder einen Palast',
  'dec.troopTransferTitle': 'Truppen erhalten',
  'dec.troopTransferBody':
      '{source} hat dir {men} Soldaten ({name}) geschickt. Wähle einen Standort.',
  'dec.troopTransferTile': 'Standort ({x}, {y})',
  'dec.today': 'Heute',
  'dec.tomorrow': 'Morgen',
  'dec.weekdayMon': 'Mo',
  'dec.weekdayTue': 'Di',
  'dec.weekdayWed': 'Mi',
  'dec.weekdayThu': 'Do',
  'dec.weekdayFri': 'Fr',
  'dec.weekdaySat': 'Sa',
  'dec.weekdaySun': 'So',
  // "Heute 18:00 Uhr" — {time} is the pre-formatted HH:MM.
  'dec.warStartTime': '{day} {time} Uhr',
  'dec.warStartTitle': 'Wann soll der Krieg beginnen?',
  'dec.warStartHint':
      'Wähle die Zeitpunkte, die dir passen. Passt einer auch '
      'deinem Gegner, beginnt der Krieg zum frühesten '
      'gemeinsamen Zeitpunkt — sonst nach Ablauf der '
      'Vorbereitungsfrist. Ohne Auswahl gilt die Frist.',
  'dec.warStartNow': 'Sofort (diese Stunde)',
  // Was der Gegner angeboten hat (2026-08-09): ohne diesen Hinweis mussten
  // zwei Spieler blind raten, welche Stunde sie noch hinzunehmen sollen.
  'dec.warStartEnemyPending': 'Dein Gegner hat noch nicht gewählt.',
  'dec.warStartEnemyTimes': 'Die mit ✓ markierten Zeiten passen deinem Gegner.',
  'dec.warStartEnemyNoTimes':
      'Dein Gegner hat keine Zeit vorgeschlagen — dann gilt die '
      'Vorbereitungsfrist.',
  'dec.warStartEnemyFits': 'Diese Zeit passt deinem Gegner',
  // An agreed start that already lies in the past — the server starts the
  // duel on its next sweep (within a minute), so it is not "20:00 Uhr"
  // but "any moment now".
  'dec.warStartImminent': 'jeden Moment',
  'dec.warStartNoProposal': 'Ohne Terminvorschlag',
  'dec.warStartConfirmed': 'Kriegstermin steht: {time}.',
  'dec.warStartSaved':
      'Deine Auswahl ist gespeichert. Sobald dein Gegner gewählt hat, '
      'siehst du den Termin — gibt es keinen gemeinsamen, beginnt der '
      'Krieg nach Ablauf der Vorbereitungsfrist.',
  'dec.confirm': 'Bestätigen',
  'dec.cancel': 'Abbrechen',
  'dec.ok': 'OK',
  'dec.yes': 'Ja',
  'dec.no': 'Nein',
  'dec.bribeTitle': 'Bestechung der Kurfürsten',
  'dec.bribeBroke':
      'Deine Schatzkammer ist leer — du kannst diesmal niemanden '
      'bestechen. Bestätige ohne Geschenk.',
  'dec.bribeBudget': 'Ausgegeben: {spent} T   ·   Verbleibend: {remaining} T',
  'dec.bribeNone': 'Ohne Bestechung',
};

const Map<String, String> miscEn = {
  'dec.roundReport': 'Round report',
  'dec.proposerLine': '{name} of {realm} ({age})',
  'dec.marriageProposalTitle': 'Marriage proposal',
  'dec.marriageProposalBody':
      '{proposer} asks for the hand of {target}. Do you accept?',
  'dec.heirChoiceTitle': '{name} has died! Choose the heir:',
  'dec.personWithAge': '{name} ({age})',
  'dec.warDeclaredTitle': 'War declared!',
  'dec.warDeclarationTitle': 'Declaration of war!',
  'dec.warPlanYouDeclared': 'You have declared war on {realm}.',
  'dec.warPlanEnemyDeclared': '{realm} has declared war on you!',
  'dec.warPlanBody':
      '{declaration} Do you want to command your troops yourself?\n\n'
      'If you choose "No", the computer takes over this war: your troops '
      'follow their stance. Until the war begins you can set each troop '
      'individually on the map (hold position or attack) — in the '
      'war-preparation menu above the map. The war begins as soon as '
      'both sides have chosen — if both want to command in person, '
      'online at the agreed time or when the preparation deadline '
      'expires.',
  'dec.warDefenseBody':
      '{realm} has declared war on you! Do you want to command your '
      'troops yourself?\n\nIf you choose "No", the computer takes over '
      'this war: your troops follow their set stance (hold / attack), '
      'and you will not play in person again until the war ends.',
  'dec.childBornBoy': 'A boy is born! What shall he be called?',
  'dec.childBornGirl': 'A girl is born! What shall she be called?',
  'dec.electionVoteTitle': 'Kaiser election — your vote',
  'dec.electionCandidate': '{name} (bribe: {amount} T)',
  'dec.coercionTitle': 'Coercion',
  'dec.coerceConvertOrDie':
      'Do you want to give {name} the choice: conversion or death?',
  'dec.coerceForcedMarriage': 'Do you want to force {name} into marriage?',
  'dec.coerceAbdication': 'Do you want to make {name} abdicate as Kaiser?',
  'dec.coerceStripSeat': 'Do you want to strip {name} of the Elector seat?',
  'dec.coerceOther': 'Do you want to coerce {name} ({option})?',
  'dec.convertOrDieTitle': 'Conversion or death',
  'dec.convertOrDieBody': 'Die or convert — do you convert?',
  'dec.relocateSeatTitle': 'Your seat is lost — choose a new one',
  'dec.relocateSeatMapHint':
      'Seat lost — tap a city, castle or palace on the map',
  'dec.troopTransferTitle': 'Troops received',
  'dec.troopTransferBody':
      '{source} sent you {men} soldiers ({name}). Choose a position.',
  'dec.troopTransferTile': 'Position ({x}, {y})',
  'dec.today': 'Today',
  'dec.tomorrow': 'Tomorrow',
  'dec.weekdayMon': 'Mon',
  'dec.weekdayTue': 'Tue',
  'dec.weekdayWed': 'Wed',
  'dec.weekdayThu': 'Thu',
  'dec.weekdayFri': 'Fri',
  'dec.weekdaySat': 'Sat',
  'dec.weekdaySun': 'Sun',
  'dec.warStartTime': '{day} {time}',
  'dec.warStartTitle': 'When should the war begin?',
  'dec.warStartHint':
      'Pick the times that suit you. If one also suits your opponent, '
      'the war begins at the earliest shared time — otherwise when the '
      'preparation deadline expires. With no selection, the deadline '
      'applies.',
  'dec.warStartNow': 'Immediately (this hour)',
  'dec.warStartEnemyPending': 'Your opponent has not chosen yet.',
  'dec.warStartEnemyTimes': 'The times marked ✓ suit your opponent.',
  'dec.warStartEnemyNoTimes':
      'Your opponent proposed no time — then the preparation deadline '
      'applies.',
  'dec.warStartEnemyFits': 'This time suits your opponent',
  'dec.warStartImminent': 'any moment now',
  'dec.warStartNoProposal': 'No time proposal',
  'dec.warStartConfirmed': 'War start fixed: {time}.',
  'dec.warStartSaved':
      'Your choice is saved. Once your opponent has chosen you will see '
      'the appointment — if there is no shared one, the war begins when '
      'the preparation deadline expires.',
  'dec.confirm': 'Confirm',
  'dec.cancel': 'Cancel',
  'dec.ok': 'OK',
  'dec.yes': 'Yes',
  'dec.no': 'No',
  'dec.bribeTitle': 'Bribing the Electors',
  'dec.bribeBroke':
      'Your treasury is empty — you cannot bribe anyone this time. '
      'Confirm without a gift.',
  'dec.bribeBudget': 'Spent: {spent} T   ·   Remaining: {remaining} T',
  'dec.bribeNone': 'Without a bribe',
};
