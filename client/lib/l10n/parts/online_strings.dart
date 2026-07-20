/// String-table part for the "online" UI area — merged into the app-wide
/// table in `l10n/strings.dart`. Keys are prefixed `online.`; `{name}`-style
/// placeholders are filled by `tr(key, params)`.
const Map<String, String> onlineDe = {
  // Lobby (online_screen.dart)
  'online.setupTitle': 'Online einrichten',
  'online.choosePlayerName': 'Spielernamen wählen',
  'online.serverAddress': 'Server-Adresse',
  'online.yourName': 'Dein Name',
  'online.connect': 'Verbinden',
  'online.serverAndName': 'Server & Name',
  'online.playerNameTooltip': 'Spielername',
  'online.newMatch': 'Neue Partie',
  'online.joinByCode': 'Beitreten per Code',
  'online.pitchTitle': 'Asynchrones Mehrspieler-Kaisern',
  'online.pitchBody':
      'Wähle deinen Spielernamen, erstelle eine Partie und teile '
      'den Raum-Code — gespielt wird, wenn du am Zug bist.',
  'online.signedInAs': 'Angemeldet als {name}',
  'online.noMatchesYet':
      'Noch keine Online-Partien — erstelle eine oder '
      'tritt per Raum-Code bei.',
  'online.waitingJoined': 'Wartet auf Spieler ({n} beigetreten)',
  'online.finished': 'Beendet',
  'online.warStartLabel': 'Kriegsbeginn',
  'online.deadlineLabel': 'Frist',
  'online.copyRoomCode': 'Raum-Code kopieren',
  'online.roomCodeCopied': 'Raum-Code kopiert',
  'online.deleteGame': 'Partie löschen',
  'online.leaveGame': 'Partie verlassen',
  'online.publicGames': 'Öffentliche Partien',
  'online.noTimeLimit': 'kein Zeitlimit',
  'online.sevenDaysPerTurn': '7 Tage/Zug',
  'online.hoursPerTurn': '{hours} h/Zug',
  'online.gameBy': 'Partie von {name}',
  'online.openGame': 'Offene Partie',
  'online.joinedCount': '{n} beigetreten',
  'online.join': 'Beitreten',
  // Leave/delete dialogs (lobby + match screen)
  'online.deleteGameQ': 'Partie löschen?',
  'online.deleteWaitingBody':
      'Die wartende Partie wird für alle Spieler gelöscht.',
  'online.leaveGameQ': 'Partie verlassen?',
  'online.leaveWaitingBody': 'Dein Platz wird wieder frei.',
  'online.leaveActiveBody':
      'Dein Reich wird ab sofort vom Computer weitergespielt — '
      'eine Rückkehr ist nicht möglich.',
  'online.removeGameQ': 'Partie entfernen?',
  'online.removeFinishedBody':
      'Die beendete Partie verschwindet aus deiner Liste.',
  'online.leave': 'Verlassen',
  // Match screen (online_match_screen.dart)
  'online.matchTitle': 'Online-Partie',
  'online.refresh': 'Aktualisieren',
  'online.isFighting': '{name} ({realm}) kämpft gegen {enemy} …',
  'online.victoryFinished': 'Sieg ! Die Partie ist beendet.',
  'online.gameFinished': 'Die Partie ist beendet.',
  'online.turnDeadlineLabel': 'Zugfrist',
  'online.shareRoomCode':
      'Teile den Raum-Code, damit deine Mitspieler beitreten können:',
  'online.turnOrder': 'Zugreihenfolge',
  'online.players': 'Spieler',
  'online.youSuffix': ' (du)',
  'online.turnNumber': 'Zug {n}',
  'online.idleTurns': '{n} Züge inaktiv',
  'online.kick': 'Rauswerfen',
  'online.eliminated': 'ausgeschieden',
  'online.startGame': 'Spiel starten',
  'online.soloStartHint':
      'Du kannst auch allein gegen die 29 Computer-Reiche '
      'starten — danach kann niemand mehr beitreten.',
  'online.waitForHost': 'Warte, bis der Gastgeber das Spiel startet …',
  'online.playTurn': 'Zug spielen',
  'online.warPrepDeploy': 'Kriegsvorbereitung: Truppen aufstellen',
  'online.viewRealmAndMap': 'Reich & Karte ansehen',
  'online.kickPlayerQ': 'Spieler rauswerfen?',
  'online.kickPlayerBody':
      '{name} hat mehrere Züge in Folge nicht gespielt. Das Reich '
      'wird ab sofort vom Computer weitergeführt.',
  // Setup screen (online_setup_screen.dart)
  'online.enterRoomCode': 'Bitte den 5-stelligen Raum-Code eingeben',
  'online.rulerNeedsName': 'Der Herrscher braucht einen Namen',
  'online.dorfNeedsName': 'Das erste Dorf braucht einen Namen',
  'online.newOnlineGame': 'Neue Online-Partie',
  'online.joinGame': 'Partie beitreten',
  'online.roomCode': 'Raum-Code',
  'online.roomCodeHint': 'z. B. KQXBE',
  'online.matchSection': 'Partie',
  'online.yourRealm': 'Dein Reich',
  'online.rulerName': 'Name des Herrschers',
  'online.createGame': 'Partie erstellen',
  'online.turnTimeLimit': 'Zug-Zeitlimit',
  'online.off': 'Aus',
  'online.sevenDays': '7 Tage',
  'online.visibility': 'Sichtbarkeit',
  'online.private': 'Privat',
  'online.public': 'Öffentlich',
  'online.publicHint':
      'Jeder kann diese Partie in der Liste sehen und beitreten.',
  'online.privateHint': 'Nur Spieler mit dem Raum-Code können beitreten.',
  'online.warTurnTime': 'Zugzeit im Krieg',
};

const Map<String, String> onlineEn = {
  // Lobby (online_screen.dart)
  'online.setupTitle': 'Set up online play',
  'online.choosePlayerName': 'Choose player name',
  'online.serverAddress': 'Server address',
  'online.yourName': 'Your name',
  'online.connect': 'Connect',
  'online.serverAndName': 'Server & name',
  'online.playerNameTooltip': 'Player name',
  'online.newMatch': 'New game',
  'online.joinByCode': 'Join by code',
  'online.pitchTitle': 'Asynchronous multiplayer Kaiser',
  'online.pitchBody':
      'Pick your player name, create a game and share the room code — '
      'you play whenever it is your turn.',
  'online.signedInAs': 'Signed in as {name}',
  'online.noMatchesYet':
      'No online games yet — create one or join with a room code.',
  'online.waitingJoined': 'Waiting for players ({n} joined)',
  'online.finished': 'Finished',
  'online.warStartLabel': 'War begins',
  'online.deadlineLabel': 'Deadline',
  'online.copyRoomCode': 'Copy room code',
  'online.roomCodeCopied': 'Room code copied',
  'online.deleteGame': 'Delete game',
  'online.leaveGame': 'Leave game',
  'online.publicGames': 'Public games',
  'online.noTimeLimit': 'no time limit',
  'online.sevenDaysPerTurn': '7 days/turn',
  'online.hoursPerTurn': '{hours} h/turn',
  'online.gameBy': 'Game by {name}',
  'online.openGame': 'Open game',
  'online.joinedCount': '{n} joined',
  'online.join': 'Join',
  // Leave/delete dialogs (lobby + match screen)
  'online.deleteGameQ': 'Delete game?',
  'online.deleteWaitingBody':
      'The waiting game will be deleted for all players.',
  'online.leaveGameQ': 'Leave game?',
  'online.leaveWaitingBody': 'Your seat becomes free again.',
  'online.leaveActiveBody':
      'Your realm will be played by the computer from now on — '
      'there is no way back.',
  'online.removeGameQ': 'Remove game?',
  'online.removeFinishedBody':
      'The finished game disappears from your list.',
  'online.leave': 'Leave',
  // Match screen (online_match_screen.dart)
  'online.matchTitle': 'Online game',
  'online.refresh': 'Refresh',
  'online.isFighting': '{name} ({realm}) is fighting {enemy} …',
  'online.victoryFinished': 'Victory! The game is over.',
  'online.gameFinished': 'The game is over.',
  'online.turnDeadlineLabel': 'Turn deadline',
  'online.shareRoomCode':
      'Share the room code so your fellow players can join:',
  'online.turnOrder': 'Turn order',
  'online.players': 'Players',
  'online.youSuffix': ' (you)',
  'online.turnNumber': 'Turn {n}',
  'online.idleTurns': '{n} turns idle',
  'online.kick': 'Kick',
  'online.eliminated': 'eliminated',
  'online.startGame': 'Start game',
  'online.soloStartHint':
      'You can also start alone against the 29 computer realms — '
      'after that, nobody else can join.',
  'online.waitForHost': 'Waiting for the host to start the game …',
  'online.playTurn': 'Play turn',
  'online.warPrepDeploy': 'War preparation: deploy troops',
  'online.viewRealmAndMap': 'View realm & map',
  'online.kickPlayerQ': 'Kick player?',
  'online.kickPlayerBody':
      '{name} has missed several turns in a row. The realm will be '
      'run by the computer from now on.',
  // Setup screen (online_setup_screen.dart)
  'online.enterRoomCode': 'Please enter the 5-character room code',
  'online.rulerNeedsName': 'The ruler needs a name',
  'online.dorfNeedsName': 'The first village needs a name',
  'online.newOnlineGame': 'New online game',
  'online.joinGame': 'Join game',
  'online.roomCode': 'Room code',
  'online.roomCodeHint': 'e.g. KQXBE',
  'online.matchSection': 'Game',
  'online.yourRealm': 'Your realm',
  'online.rulerName': 'Ruler name',
  'online.createGame': 'Create game',
  'online.turnTimeLimit': 'Turn time limit',
  'online.off': 'Off',
  'online.sevenDays': '7 days',
  'online.visibility': 'Visibility',
  'online.private': 'Private',
  'online.public': 'Public',
  'online.publicHint': 'Anyone can see this game in the list and join.',
  'online.privateHint': 'Only players with the room code can join.',
  'online.warTurnTime': 'Turn time in war',
};
