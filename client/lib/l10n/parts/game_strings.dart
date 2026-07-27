/// String-table part for the "game" UI area — merged into the app-wide
/// table in `l10n/strings.dart`. Keys are prefixed `game.`; `{name}`-style
/// placeholders are filled by `tr(key, params)`.
const Map<String, String> gameDe = {
  // --- game_screen.dart ---
  'game.loadFailed': 'Spiel konnte nicht geladen werden: {error}',
  'game.selectTroopFirstEnemy':
      'Wähle zuerst eine deiner Truppen — dann tippe die '
      'feindliche Armee an, um sie anzugreifen !',
  'game.selectTroopFirst': 'Wähle zuerst eine deiner Truppen !',
  'game.dangerouslyLow': 'gefährlich niedrig',
  'game.popularityDangerLow': 'Beliebtheit gefährlich niedrig!',
  'game.leaveGameQuestion': 'Spiel verlassen?',
  'game.leaveGameOnlineBody':
      'Die Partie läuft auf dem Server weiter — du kannst '
      'jederzeit zurückkehren.',
  'game.leaveGameLocalBody': 'Der letzte abgeschlossene Zug ist gespeichert.',
  'game.leaveGame': 'Spiel verlassen',
  'game.annoRealm': 'Anno {year} — {realm}',
  'game.warTitle': 'Krieg !',
  'game.warBriefing':
      '{attacker} ist mit Armeen in dein Land eingefallen !\n\n'
      'Tippe eine deiner Truppen an (Schild auf farbigem Wappen) '
      'und dann ein Ziel auf der Karte: feindliche Armeen werden '
      'angegriffen. Einmal pro Runde kannst du auf feindlichem '
      'Boden plündern.\n\n'
      'Der Krieg endet, wenn beide Seiten Frieden wünschen '
      '(ohne Gebietsänderungen), spätestens im Winter — oder '
      'wenn eine Armee den gegnerischen Königssitz (Fahne) über '
      'eine volle Runde hält: ihr Herrscher wird gefangen '
      'genommen, und der Sieger wählt, welche Felder er '
      'übernimmt.',
  'game.toArms': 'Zu den Waffen !',
  'game.defeatTail':
      'Keine menschliche Dynastie hält mehr die Macht — '
      'eure Herrschaft ist Geschichte.',
  'game.defeatInternalStrife':
      'Ein Volksaufstand hat deine Dynastie entthront (Popularität unter 20).',
  'game.defeatBankruptcy':
      'Dein Reich ist bankrott gegangen und einem neuen Herrscherhaus zugefallen.',
  'game.defeatSuccessionCrisis':
      'Eine Thronfolgekrise hat dein Reich unter fremde (computergesteuerte) Kontrolle gebracht.',
  'game.defeatRealmInherited':
      'Beim Tod deines Herrschers ging dein Reich durch Erbfolge an ein '
      'fremdes Herrscherhaus über.',
  'game.defeatRulerCaptured':
      'Dein Herrscher wurde im Krieg gefangen genommen und das Reich erobert.',
  'game.defeatRealmOverrun': 'Dein Reich wurde im Krieg vollständig überrannt.',
  'game.defeatDynastyExtinct': 'Deine Dynastie ist ausgestorben.',
  'game.drawBody': 'Alle Dynastien sind erloschen — das Land bleibt herrenlos.',
  'game.victoryBody':
      '{realm} ist der alleinige Herrscher des ganzen Landes!',
  'game.backToMainMenu': 'Zurück zum Hauptmenü',
  // --- tile_sheet.dart ---
  'game.buyShip': 'Schiff kaufen',
  'game.noMovesLeft': 'Du hast keine Züge mehr !',
  'game.notEnoughTaler': 'Du hast nicht genügend Taler !',
  'game.buyShipHint':
      'Das Schiff geht hier im Hafen vor Anker — tippe es '
      'danach an, um es zu steuern',
  'game.steerShip': 'Schiff steuern',
  'game.steerShipHint':
      '1 Zug pro Wasserfeld — ein freies Landfeld '
      'als Ziel gründet dort ein Dorf',
  'game.steerShipPickHint':
      'Schiff steuern: Wasserfeld antippen (1 Zug pro Feld) '
      '— ein freies Landfeld wird kolonisiert',
  'game.colonize': 'Kolonisieren — Dorf gründen',
  'game.colonizeHint': 'Das Schiff wird dabei aufgelöst — die Siedler bleiben',
  'game.troopTileTitle': '„{name}" — {men} Mann',
  'game.troopTileSubtitle': 'Info, Verlegen & Bearbeiten',
  'game.spiedArmyTitle': 'Spionage: Armee von {realm}',
  'game.spiedArmySubtitle': '~{men} Mann {troopClass} — Stand Anno {year}',
  'game.terrainPlain': 'Ebene',
  'game.terrainMountain': 'Berg',
  'game.terrainWater': 'Wasser',
  'game.devastatedUntil': ' (verwüstet bis Anno {year})',
  'game.tileHeaderTrailing': '{treasury} T\nnoch {moves} Züge',
  'game.noActionHere': 'Hier ist keine Aktion möglich',
  // Field-cultivation box select (long-press a tile, then drag the frame;
  // releasing opens the batch-build sheet).
  'game.fieldSheetTitle': '{count} Felder ausgewählt',
  'game.shipsWaterOnly':
      'Schiffe fahren nur auf dem Wasser — oder kolonisieren ein '
      'freies Landfeld !',
  'game.notReachableBySea': 'Dieses Feld ist über See nicht erreichbar !',
  'game.voyageCostsMoves':
      'Fahrt und Dorfgründung kosten {moves} Züge — so viele hast '
      'du nicht mehr !',
  'game.askTownName': 'Wie soll dein Dorf heißen?',
  'game.ok': 'OK',
  // --- turn_report.dart ---
  'game.popularityTierRevolt':
      'Ihr Land steht am Rande einer Revolution !!!',
  'game.popularityTierUprisings':
      'In ihrem Land gibt es kleinere Aufstände !!!',
  'game.popularityTierUnpopular': 'Sie sind nicht gerade sehr beliebt.',
  'game.popularityTierAverage': 'Durchschnittlich',
  'game.popularityTierDecent': 'Nicht gerade niedrig',
  'game.popularityTierHigh': 'Sehr hoch',
  'game.popularityTierVeryHigh': 'Unglaublich hoch',
  'game.yourTurnGreeting': '{title} {name}, Ihr seid am Zug !',
  'game.taxesLine': 'Steuern: +{tax} T',
  'game.harborIncomeSuffix': ' — Häfen: +{income} T',
  'game.kaiserPotLine':
      'Kronschatz: {amount} T warten — '
      '„Staatskasse plündern" im Dynastie-Menü !',
  'game.sultanPotLine':
      'Sultansschatz: {amount} T warten — '
      '„Staatskasse plündern" im Dynastie-Menü !',
  'game.tributeWagesLine': 'Tribut: −{tribute} T — Sold: −{wages} T',
  'game.populationLine': 'Bevölkerung: {population} Einwohner',
  'game.foodShortLine':
      'Deine Felder ernähren nur {production} von {population} Leuten !',
  'game.foodOkLine':
      'Deine Felder ernähren die Bevölkerung ({production} ≥ {population}).',
  'game.foodWarning':
      'Nahrung wird knapp — baue mehr Kornfelder/Weiden, sonst '
      'drohen Hungersnot und Desertion !',
  'game.famineLine': 'Hungersnot: {loss} Soldaten desertieren !',
  'game.buildsThisRoundOne': 'Du kannst diese Runde {moves} Feld bebauen.',
  'game.buildsThisRoundMany': 'Du kannst diese Runde {moves} Felder bebauen.',
  'game.continueButton': 'Weiter',
  // --- empire_card.dart ---
  'game.male': 'Männlich',
  'game.female': 'Weiblich',
  'game.landLabel': 'Land',
  'game.random': 'Zufällig',
  'game.landTaken': '{name} (belegt)',
  'game.firstVillage': 'Erstes Dorf',
  'game.colorLabel': 'Landesfarbe',
  'game.colorAuto': 'Automatisch',
};

const Map<String, String> gameEn = {
  // --- game_screen.dart ---
  'game.loadFailed': 'Could not load the game: {error}',
  'game.selectTroopFirstEnemy':
      'Select one of your troops first — then tap the '
      'enemy army to attack it!',
  'game.selectTroopFirst': 'Select one of your troops first!',
  'game.dangerouslyLow': 'dangerously low',
  'game.popularityDangerLow': 'Popularity dangerously low!',
  'game.leaveGameQuestion': 'Leave the game?',
  'game.leaveGameOnlineBody':
      'The match continues on the server — you can '
      'return at any time.',
  'game.leaveGameLocalBody': 'The last completed turn is saved.',
  'game.leaveGame': 'Leave game',
  'game.annoRealm': 'Anno {year} — {realm}',
  'game.warTitle': 'War!',
  'game.warBriefing':
      '{attacker} has invaded your land with armies!\n\n'
      'Tap one of your troops (a shield on a colored crest), '
      'then a target on the map: enemy armies will be attacked. '
      'Once per round you may plunder on enemy soil.\n\n'
      'The war ends when both sides desire peace '
      '(with no change of territory), at the latest in winter — or '
      'when an army holds the enemy royal seat (the flag) for '
      'a full round: its ruler is taken captive, and the victor '
      'chooses which fields to take.',
  'game.toArms': 'To arms!',
  'game.defeatTail':
      'No human dynasty holds power any longer — '
      'your reign is history.',
  'game.defeatInternalStrife':
      'A popular uprising has dethroned your dynasty (popularity below 20).',
  'game.defeatBankruptcy':
      'Your realm went bankrupt and fell to a new ruling house.',
  'game.defeatSuccessionCrisis':
      'A succession crisis has placed your realm under foreign (computer-controlled) control.',
  'game.defeatRealmInherited':
      'Upon your ruler\'s death, your realm passed by inheritance to a '
      'foreign ruling house.',
  'game.defeatRulerCaptured':
      'Your ruler was captured in war and the realm conquered.',
  'game.defeatRealmOverrun': 'Your realm was completely overrun in war.',
  'game.defeatDynastyExtinct': 'Your dynasty has died out.',
  'game.drawBody':
      'All dynasties have died out — the land remains without a master.',
  'game.victoryBody': '{realm} is the sole ruler of the whole land!',
  'game.backToMainMenu': 'Back to the main menu',
  // --- tile_sheet.dart ---
  'game.buyShip': 'Buy ship',
  'game.noMovesLeft': 'You have no moves left!',
  'game.notEnoughTaler': 'You do not have enough Taler!',
  'game.buyShipHint':
      'The ship drops anchor here in the harbor — tap it '
      'afterwards to steer it',
  'game.steerShip': 'Steer ship',
  'game.steerShipHint':
      '1 move per water tile — a free land tile '
      'as the target founds a village there',
  'game.steerShipPickHint':
      'Steer ship: tap a water tile (1 move per tile) '
      '— a free land tile will be colonized',
  'game.colonize': 'Colonize — found a village',
  'game.colonizeHint':
      'The ship is disbanded in the process — the settlers remain',
  'game.troopTileTitle': '"{name}" — {men} men',
  'game.troopTileSubtitle': 'Info, redeploy & edit',
  'game.spiedArmyTitle': 'Espionage: army of {realm}',
  'game.spiedArmySubtitle': '~{men} men ({troopClass}) — as of Anno {year}',
  'game.terrainPlain': 'Plain',
  'game.terrainMountain': 'Mountain',
  'game.terrainWater': 'Water',
  'game.devastatedUntil': ' (devastated until Anno {year})',
  'game.tileHeaderTrailing': '{treasury} T\n{moves} moves left',
  'game.noActionHere': 'No action is possible here',
  // Field-cultivation box select (long-press a tile, then drag the frame;
  // releasing opens the batch-build sheet).
  'game.fieldSheetTitle': '{count} tiles selected',
  'game.shipsWaterOnly':
      'Ships sail only on water — or colonize a free land tile!',
  'game.notReachableBySea': 'This tile cannot be reached by sea!',
  'game.voyageCostsMoves':
      'The voyage and founding the village cost {moves} moves — '
      'you do not have that many left!',
  'game.askTownName': 'What shall your village be called?',
  'game.ok': 'OK',
  // --- turn_report.dart ---
  'game.popularityTierRevolt':
      'Your land stands on the brink of revolution!!!',
  'game.popularityTierUprisings':
      'There are minor uprisings in your land!!!',
  'game.popularityTierUnpopular': 'You are not exactly well liked.',
  'game.popularityTierAverage': 'Average',
  'game.popularityTierDecent': 'Not exactly low',
  'game.popularityTierHigh': 'Very high',
  'game.popularityTierVeryHigh': 'Unbelievably high',
  'game.yourTurnGreeting': '{title} {name}, it is your turn!',
  'game.taxesLine': 'Taxes: +{tax} T',
  'game.harborIncomeSuffix': ' — harbors: +{income} T',
  'game.kaiserPotLine':
      'Crown treasure: {amount} T await — '
      '"Plunder the state coffers" in the Dynasty menu!',
  'game.sultanPotLine':
      'The Sultan\'s treasure: {amount} T await — '
      '"Plunder the state coffers" in the Dynasty menu!',
  'game.tributeWagesLine': 'Tribute: −{tribute} T — wages: −{wages} T',
  'game.populationLine': 'Population: {population} inhabitants',
  'game.foodShortLine':
      'Your fields feed only {production} of {population} people!',
  'game.foodOkLine':
      'Your fields feed the population ({production} ≥ {population}).',
  'game.foodWarning':
      'Food is running short — build more grain fields and pastures, '
      'or famine and desertion threaten!',
  'game.famineLine': 'Famine: {loss} soldiers desert!',
  'game.buildsThisRoundOne': 'You can build on {moves} field this round.',
  'game.buildsThisRoundMany': 'You can build on {moves} fields this round.',
  'game.continueButton': 'Continue',
  // --- empire_card.dart ---
  'game.male': 'Male',
  'game.female': 'Female',
  'game.landLabel': 'Realm',
  'game.random': 'Random',
  'game.landTaken': '{name} (taken)',
  'game.firstVillage': 'First village',
  'game.colorLabel': 'Realm color',
  'game.colorAuto': 'Automatic',
};
