import 'package:game_core/game_core.dart' show formatTemplate;

/// Player-facing texts for the REST API's rejections (de/en), written for
/// non-technical people: each says what happened in plain words and — where
/// the player can do anything about it — what to do next. `[DESIGNED
/// 2026-08-08, user feedback]` Before this, the server sent raw developer
/// English ("not your turn", "match is full") which the client shows as-is.
///
/// `ApiException` carries a KEY into this catalog (plus optional `{param}`
/// values); the API layer formats it in the language of the request's
/// `Accept-Language` header ([resolveApiLocale]) at response time — no
/// global locale state, so concurrent requests cannot race each other.
/// A message that is no key (the engine's already-localized rule
/// rejections) passes through unchanged, exactly like `coreMessage`.
const Map<String, Map<String, String>> _apiMessages = {
  'de': {
    // Turn handling.
    'api.notYourTurn':
        'Du bist gerade nicht am Zug. Sobald du an der Reihe bist, '
            'bekommst du eine Benachrichtigung.',
    'api.warBlocksTurn':
        'Der laufende Krieg muss erst enden, bevor der Zug beendet '
            'werden kann.',
    'api.actionNotAwaited':
        'Diese Aktion ist gerade nicht möglich — vermutlich ist die Partie '
            'inzwischen weitergelaufen. Die Ansicht wird aktualisiert.',
    'api.updateRequired':
        'Diese Partie läuft auf App-Version {version}. Bitte '
            'aktualisiere die App, um deinen Zug zu machen.',

    // Joining and starting.
    'api.matchNotOpen':
        'Dieser Partie kann nicht mehr beigetreten werden — sie hat '
            'bereits begonnen oder ist vorbei.',
    'api.alreadyJoined': 'Du bist dieser Partie bereits beigetreten.',
    'api.matchFull': 'Diese Partie ist schon voll besetzt.',
    'api.matchAlreadyStarted': 'Diese Partie hat bereits begonnen.',
    'api.matchStartsAutomatically':
        'Diese Partie startet von selbst, sobald genug Spieler '
            'beigetreten sind.',
    'api.onlyCreatorStarts':
        'Nur wer die Partie erstellt hat, kann sie starten.',
    'api.matchNotActive':
        'Diese Partie läuft nicht — sie ist entweder noch nicht gestartet '
            'oder schon vorbei.',
    'api.slotTaken':
        'Dieses Reich hat sich schon ein anderer Spieler ausgesucht — '
            'bitte wähle ein anderes.',
    'api.slotInvalid':
        'Dieses Reich gibt es in dieser Partie nicht — bitte wähle ein '
            'anderes.',
    'api.setupNamesRequired':
        'Bitte gib einen Namen für deinen Herrscher und dein Dorf an.',
    'api.nameRequired': 'Bitte gib einen Spielernamen ein.',

    // Managing players.
    'api.notInMatch': 'Du bist kein Teilnehmer dieser Partie.',
    'api.playerNotInMatch': 'Dieser Spieler ist nicht Teil der Partie.',
    'api.onlyCreatorKicks':
        'Nur wer die Partie erstellt hat, kann Spieler entfernen.',
    'api.creatorCannotKickSelf':
        'Du kannst dich nicht selbst entfernen — verlasse stattdessen '
            'die Partie.',
    'api.notIdleEnough':
        'Dieser Spieler kann noch nicht ersetzt werden — er hat seinen '
            'Zug noch nicht lange genug versäumt.',

    // Lookups.
    'api.unknownMatch':
        'Diese Partie wurde nicht gefunden. Vielleicht wurde sie gelöscht, '
            'oder der Raum-Code stimmt nicht.',
    'api.unknownPlayer':
        'Dein Spielerkonto wurde auf dem Server nicht gefunden. Öffne die '
            'Online-Einstellungen, um dich neu anzumelden.',

    // Catch-alls: a malformed request can only come from a client bug or
    // an outdated build — updating is the one thing a player can DO.
    'api.badRequest':
        'Die App hat eine ungültige Anfrage gesendet. Bitte aktualisiere '
            'die App und versuche es noch einmal.',
    'api.internalError':
        'Auf dem Server ist ein Fehler aufgetreten. Deine Partie ist nicht '
            'verloren — bitte versuche es gleich noch einmal.',
  },
  'en': {
    'api.notYourTurn':
        'It is not your turn right now. You will be notified as soon as '
            'it is.',
    'api.warBlocksTurn':
        'The war under way has to end before the turn can.',
    'api.actionNotAwaited':
        'That is not possible right now — the game has probably moved on '
            'in the meantime. The view will refresh.',
    'api.updateRequired':
        'This match runs on app version {version}. Please update the app '
            'to take your turn.',
    'api.matchNotOpen':
        'This match can no longer be joined — it has already started or '
            'is over.',
    'api.alreadyJoined': 'You have already joined this match.',
    'api.matchFull': 'This match is already full.',
    'api.matchAlreadyStarted': 'This match has already started.',
    'api.matchStartsAutomatically':
        'This match starts on its own once enough players have joined.',
    'api.onlyCreatorStarts':
        'Only the player who created the match can start it.',
    'api.matchNotActive':
        'This match is not running — it has either not started yet or is '
            'already over.',
    'api.slotTaken':
        'Another player has already picked that realm — please choose a '
            'different one.',
    'api.slotInvalid':
        'That realm does not exist in this match — please choose a '
            'different one.',
    'api.setupNamesRequired':
        'Please enter a name for your ruler and your village.',
    'api.nameRequired': 'Please enter a player name.',
    'api.notInMatch': 'You are not a participant of this match.',
    'api.playerNotInMatch': 'That player is not part of this match.',
    'api.onlyCreatorKicks':
        'Only the player who created the match can remove players.',
    'api.creatorCannotKickSelf':
        'You cannot remove yourself — leave the match instead.',
    'api.notIdleEnough':
        'That player cannot be replaced yet — they have not missed their '
            'turn for long enough.',
    'api.unknownMatch':
        'This match could not be found. It may have been deleted, or the '
            'room code is wrong.',
    'api.unknownPlayer':
        'Your player account was not found on the server. Open the online '
            'settings to sign in again.',
    'api.badRequest':
        'The app sent an invalid request. Please update the app and try '
            'again.',
    'api.internalError':
        'Something went wrong on the server. Your match is not lost — '
            'please try again in a moment.',
  },
};

/// The message language for a request: its `Accept-Language` header boiled
/// down to the two the game speaks. German is the fallback — the app only
/// ever sends `de` or `en`, and clients from before the header (≤ 0.2.4)
/// sent nothing, exactly like the engine's `messageLocale` default.
String resolveApiLocale(String? acceptLanguage) =>
    (acceptLanguage ?? '').toLowerCase().startsWith('en') ? 'en' : 'de';

/// Formats [key] in [locale], substituting `{name}` placeholders from
/// [params]. Unknown keys come back verbatim — that is the pass-through
/// for the engine's already-localized rule rejections (and means a typo'd
/// key degrades to readable-if-terse text, never a crash).
String apiMessage(String key, String locale, [Map<String, Object?>? params]) {
  final catalog = _apiMessages[locale] ?? _apiMessages['de']!;
  final text = catalog[key] ?? _apiMessages['de']![key] ?? key;
  return formatTemplate(text, params);
}
