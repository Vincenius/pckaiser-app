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
  'dec.warStartNow': 'Sofort — sobald beide gewählt haben',
  'dec.warStartNoProposal': 'Ohne Terminvorschlag',
  'dec.confirm': 'Bestätigen',
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
  'dec.warStartNow': 'Immediately — as soon as both have chosen',
  'dec.warStartNoProposal': 'No time proposal',
  'dec.confirm': 'Confirm',
  'dec.yes': 'Yes',
  'dec.no': 'No',
  'dec.bribeTitle': 'Bribing the Electors',
  'dec.bribeBroke':
      'Your treasury is empty — you cannot bribe anyone this time. '
      'Confirm without a gift.',
  'dec.bribeBudget': 'Spent: {spent} T   ·   Remaining: {remaining} T',
  'dec.bribeNone': 'Without a bribe',
};
