/// String-table part for the "war" UI area — merged into the app-wide
/// table in `l10n/strings.dart`. Keys are prefixed `war.`; `{name}`-style
/// placeholders are filled by `tr(key, params)`.
const Map<String, String> warDe = {
  // --- War panel: preparation window ---
  'war.prepTitle': 'Kriegsvorbereitung',
  'war.prepVs': '{attacker} gegen {defender}',
  // Eine Statuszeile statt eines Absatzes (2026-08-13): kurz, mit Icon.
  'war.scheduledStart': 'Beginn: {time}',
  // Wer die erste Kriegsrunde eröffnet, schon während der Vorbereitung
  // (2026-08-24, Nutzerwunsch) — damit klar ist, ob man zum Termin
  // selbst am Zug ist.
  'war.scheduledStartYouFirst': 'Beginn: {time} — du ziehst zuerst',
  'war.scheduledStartEnemyFirst': 'Beginn: {time} — {realm} zieht zuerst',
  'war.prepWaitingBoth': 'Der Krieg beginnt, sobald beide Seiten bereit sind.',
  'war.prepOwesPlan': 'Lege fest, wer dein Heer führt.',
  'war.stanceSection': 'Truppenhaltung',
  'war.tapTroopHint': 'Truppe wählen, um ihre Haltung zu setzen.',
  'war.choose': 'Kriegsplan wählen',
  // Revisable plan (2026-08-09): Führung umstellen + Zeiten anpassen,
  // solange die Vorbereitung läuft.
  'war.planLive': 'Selbst führen',
  'war.planAuto': 'Computer führt',
  'war.adjustTimes': 'Zeiten anpassen',
  'war.noCommonTime': 'Kein gemeinsamer Termin — passe deine Zeiten an.',
  'war.enemyStillChoosing': 'Wartet auf {realm}',
  // Die ausführliche Erklärung steckt hinter dem ⓘ des Panels, damit die
  // Leiste über der Karte schlank bleibt (2026-08-13, Nutzerwunsch).
  'war.prepHelpTooltip': 'Erklärung',
  'war.prepHelpBody':
      '• Führung: „Selbst führen" — du befiehlst jede Kriegsrunde selbst. '
      '„Computer führt" — dein Heer kämpft nach den Truppenhaltungen.\n\n'
      '• Haltung: Truppe antippen, dann „Halten" (verteidigt ihre Stellung) '
      'oder „Angreifen" (marschiert auf den feindlichen Sitz). Sie gilt, '
      'wenn der Computer führt oder deine Zeit abläuft.\n\n'
      '• Beginn: Online schlagen beide Seiten Zeiten vor; die früheste '
      'gemeinsame Stunde wird der Kriegsbeginn. Findet sich keine, beginnt '
      'der Krieg am Ende der Vorbereitungsfrist.\n\n'
      '• Bis dahin bleibt alles änderbar.',

  // --- War panel: header & banners ---
  'war.headerVs': 'Krieg gegen {enemy}',
  'war.winterRuleTooltip':
      'Nach Runde 20 beendet der Winter den Krieg — dann entscheidet, wer '
      'mehr (und wertvolleres) feindliches Gebiet besetzt hält und wer '
      'mehr Schlachten gewonnen hat.',
  'war.roundCounter': 'Runde {round}/20',
  'war.openMenuTooltip': 'Kriegsmenü öffnen',
  'war.collapse': 'Einklappen',
  'war.autopilotBanner':
      'Die KI führt gerade deine Truppen in diesem Krieg gegen {enemy}, weil '
      'du den Beginn verpasst hast.',
  'war.resumeCommand': 'Kontrolle übernehmen',
  'war.capitalHeldSealBanner':
      'Du hältst den gegnerischen Königssitz ! „Runde beenden" besiegelt '
      'jetzt den Sieg — halte das Feld bis dahin.',
  'war.capitalHeldBanner':
      'Du hältst den gegnerischen Königssitz ! Übersteht deine Armee dort '
      'die nächste Runde, ist der Krieg gewonnen.',
  'war.capitalLostBanner':
      'Der Feind hält deinen Königssitz ! Erobere das Feld zurück — sonst '
      'ist der Krieg verloren.',
  'war.enemyWantsPeaceBanner':
      'Der Gegner wünscht Frieden ! „Frieden" und „Runde beenden" beendet '
      'den Krieg ohne Gebietsänderungen.',
  'war.peaceWishSentBanner':
      'Friedenswunsch geäußert — der Gegner muss zustimmen.',
  'war.objectiveBanner':
      'Ziel: Erobere den gegnerischen Königssitz (Fahne) und halte ihn '
      'eine volle Runde — ab Runde 20 beendet der Winter den Krieg.',

  // --- War panel: unit selection & troop sheet ---
  'war.selectUnitHint':
      'Tippe eine Truppe auf der Karte oder unter „Truppen" an, dann ein '
      'Ziel auf der Karte.',
  'war.selectedUnitMoves': '{name} · Züge {moves}',
  'war.clearSelection': 'Auswahl aufheben',
  'war.detailsTitle': 'Truppen & Feindheer',
  'war.yourTroopsHint': 'Deine Truppen — tippen zum Auswählen',
  'war.autoWarStance': 'Bei Auto-Krieg: ',
  'war.stanceHold': 'Halten',
  'war.stanceAttack': 'Angreifen',
  'war.stanceHoldPosition': 'Position halten',
  'war.enemyArmyDestroyed': 'Das feindliche Heer ist vernichtet !',
  'war.troopOne': 'Truppe',
  'war.troopMany': 'Truppen',
  'war.classCount': '{count}× {class}',
  'war.enemyArmyIntel':
      'Feindliches Heer: {units} {unitWord} ({classes}) · laut Spionage '
      '~{men} Mann (Stand Anno {year})',
  'war.enemyArmyUnknown':
      'Feindliches Heer: {units} {unitWord} ({classes}) — die Mannstärke '
      'bleibt ohne Spionage verborgen.',
  'war.movesLeftTooltip': 'Verbleibende Züge: {moves}',
  'war.occupiesEnemySuffix': ' — besetzt feindliches Gebiet',
  'war.occupiesEnemy': 'Besetzt feindliches Gebiet',
  'war.stanceTooltip': 'Haltung: {stance}',
  'war.unitChipLabel': '{name} · {men} Mann · ⚔ {strength}',

  // --- War panel: action tiles ---
  'war.plunderNeedUnit': 'Erst eine Truppe wählen',
  'war.plunderAlreadyDone': 'Diese Armee hat diese Runde schon geplündert',
  'war.plunderNotEnemyLand': 'Die Truppe muss auf feindlichem Gebiet stehen',
  'war.plunderNothingHere': 'Hier steht nichts zum Plündern',
  'war.plunderHint': 'Bebautes feindliches Feld plündern',
  'war.troopsAction': 'Truppen',
  'war.troopsTooltip': 'Deine Truppen & das Feindheer',
  'war.plunderAction': 'Plündern',
  'war.plunderReportTitle': 'Plünderung',
  'war.withdrawPeace': 'Zurückziehen',
  'war.peaceAction': 'Frieden',
  'war.withdrawPeaceTooltip': 'Friedenswunsch zurückziehen',
  'war.peaceTooltip':
      'Frieden wünschen — stimmen beide Seiten zu, endet der Krieg ohne '
      'Gebietsänderungen',
  'war.handOver': 'Übergeben',
  'war.endRound': 'Runde beenden',
  'war.roundReportTitle': 'Rundenbericht',

  // --- War panel: claim settlement ---
  'war.victoryClaim': 'Sieg ! Anspruch: {claim}',
  'war.defeatClaim': 'Niederlage — Anspruch des Siegers: {claim}',
  'war.showExplanation': 'Erklärung zeigen',
  'war.done': 'Fertig',
  'war.settlementWinnerHelp':
      'Wähle deine Beute: Tippe Felder des Verlierers an, die an dein '
      'Land grenzen, um sie zu übernehmen. Jedes Feld kostet seinen Wert '
      '(Markt {market}, Stadt {town}, leeres Land {bare}). „Auto-Annexion" '
      'nimmt automatisch bezahlbare Felder ab deiner Grenze. Der nicht '
      'genutzte Rest wird in Talern ausgezahlt.',
  'war.settlementLoserHelp': 'Der Sieger wählt nun Felder deines Landes.',
  'war.takeWholeLand': 'Ganzes Land übernehmen',
  'war.autoAnnex': 'Auto-Annexion',
  'war.doneRemainderTaler': 'Fertig — Rest in Talern',
  // Box-select annexation (long-press an enemy tile, then drag the frame).
  'war.annexDragHint':
      'Halte ein gegnerisches Feld gedrückt und ziehe den Rahmen über '
      'die Felder, die du übernehmen willst.',
  'war.annexSelectionStatus': '{selected} ausgewählt · {plan} annektierbar',
  'war.annexSelected': 'Annektieren: {count} · {value} T',
  'war.peaceTreatyTitle': 'Friedensschluss',

  // --- War report popup ---
  'war.reportTitle': 'Kriegsbericht',
  'war.continueLabel': 'Weiter',
  'war.totalLossesTitle': 'Verluste gesamt',
  'war.totalLossesBody':
      'Du: −{own} Mann · Gegner: −{enemy} Mann ({battles} Schlachten).',
  'war.conquestTitle': 'Eroberung',
  'war.conquestOne': '{realm} übernimmt 1 Feld.',
  'war.conquestMany': '{realm} übernimmt {count} Felder.',
  'war.summaryTitle': 'Kriegsbilanz',
  'war.summaryRounds': '{rounds} Runden, {battles} Schlachten.',
  'war.sideYou': '{realm} (du)',
  'war.tallyLine': '{side}: {parts}.',
  'war.tallyMenLost': '−{n} Mann',
  'war.tallyBattleWonOne': '{n} Schlacht gewonnen',
  'war.tallyBattlesWon': '{n} Schlachten gewonnen',
  'war.tallyLoot': '{n} T erbeutet',
  'war.tallyTileOne': '{n} Feld erobert',
  'war.tallyTilesMany': '{n} Felder erobert',
  'war.theEnemy': 'der Feind',
  'war.battleLoss': '{realm}: „{unit}" verliert {losses} Mann.',
  'war.battleLossDestroyed':
      '{realm}: „{unit}" verliert {losses} Mann — vernichtet !',
  'war.attackRepelled': 'Der Angriff wurde abgeschlagen.',
  'war.attackSucceeded': 'Der Angriff war erfolgreich.',
  'war.attackPrevailed': 'Die Angreifer behalten die Oberhand.',
  'war.defenderPrevailed': 'Die Verteidiger schlagen den Angriff zurück.',
  'war.battleAt': 'Schlacht bei ({x}, {y})',
  'war.bareTile': 'Feld',
  'war.plunderEntryTitle': 'Plünderung: {building} von {victim}',
  'war.plunderDevastated':
      'Das Feld ist verwüstet und liegt {years} Jahre brach.',
  'war.plunderLoot': '{loot} Taler erbeutet.',
  'war.plunderKilled': '{count} Einwohner getötet.',
  'war.plunderAt': '{realm} plündert bei ({x}, {y}).',
  'war.rulerCapturedTitle': 'Herrscher gefangen !',
  'war.theRuler': 'den Herrscher',
  'war.rulerCapturedBody':
      '{realm} nimmt {ruler} von {loser} gefangen — der Krieg ist '
      'entschieden.',
  'war.capitalSeizedTitle': 'Königssitz besetzt !',
  'war.capitalLostTitle': 'Dein Königssitz ist besetzt !',
  'war.capitalSeizedBody':
      'Deine Armee hält den Königssitz von {besieged} — übersteht sie dort '
      'die nächste Runde, ist der Krieg gewonnen. Besetzen deine Armeen '
      'dabei ALLE festen Plätze des Feindes (jede Stadt, Burg und jeden '
      'Palast), wird sein gesamtes Land deinem Reich einverleibt — sonst '
      'stellst du Ansprüche nach Punkten.',
  'war.capitalLostBody':
      '{realm} hält deinen Königssitz ! Erobere das Feld in der nächsten '
      'Runde zurück — sonst ist der Krieg verloren. Sind dabei ALLE deine '
      'Städte, Burgen und Paläste besetzt, wird dein ganzes Land dem Feind '
      'einverleibt !',
  'war.warEndTitle': 'Kriegsende',
  'war.warWonConquered':
      '{realm} gewinnt den Krieg und übernimmt das gesamte Reich von '
      '{loser} !',
  'war.warWonClaim':
      '{realm} gewinnt den Krieg gegen {loser} (Anspruch: {claim} Punkte).',
  'war.peaceTitle': 'Frieden',
  'war.warDrawBody':
      'Der Krieg endet unentschieden — alle Truppen kehren heim.',
  'war.peaceAgreedTitle': 'Frieden geschlossen',
  'war.peaceAgreedBody':
      'Beide Seiten beenden den Krieg. Alle Truppen kehren heim — das Land '
      'bleibt unverändert.',
  'war.winterTitle': 'Winter',
  'war.winterBody':
      'Der Krieg musste wegen des hereinbrechenden Winters beendet werden.',
  'war.claimPaidTitle': 'Kriegsentschädigung',
  'war.claimPaidBody': '{realm} erhält {amount} Taler von {from}.',
  'war.allLostTitle': 'Alles verloren !',
  'war.totalConquestTitle': 'Totale Eroberung !',
  'war.allLostBody':
      'Du hast dein gesamtes Land verloren — dir bleibt kein einziges Feld '
      'mehr.',
  'war.realmOverrunBody':
      '{realm} hat sein gesamtes Land verloren — das Reich ist von der '
      'Karte getilgt.',
  'war.peaceWishTitle': 'Friedenswunsch',
  'war.peaceWishBody': '{realm} wünscht Frieden.',
  'war.enemyMovedTitle': 'Feindbewegung',
  'war.enemyMovedBody':
      '„{unit}" rückt von ({fromX}, {fromY}) nach ({x}, {y}) vor.',
  'war.enemyHoldsTitle': 'Feindlage',
  'war.enemyHoldsBody': '{realm} hält seine Stellungen — keine Bewegung.',
  'war.forcedMarriageTitle': 'Zwangsheirat',
  'war.forcedMarriageBody': '{victor} heiratet {spouse}.',
  'war.abdicationTitle': 'Abdankung',
  'war.abdicationBody': '{name} muss die Kaiserwürde niederlegen.',
  'war.conversionTitle': 'Bekehrung',
  'war.conversionBody': 'Die Dynastie von {realm} wechselt den Glauben.',
  'war.executionTitle': 'Hinrichtung',
  'war.executionBody': '{name} wird hingerichtet.',
  'war.electorStrippedTitle': 'Kurwürde verloren',
  'war.electorStrippedBody': '{name} verliert die Kurwürde.',
};

const Map<String, String> warEn = {
  // --- War panel: preparation window ---
  'war.prepTitle': 'Preparations for war',
  'war.prepVs': '{attacker} against {defender}',
  'war.scheduledStart': 'Start: {time}',
  'war.scheduledStartYouFirst': 'Start: {time} — you move first',
  'war.scheduledStartEnemyFirst': 'Start: {time} — {realm} moves first',
  'war.prepWaitingBoth': 'The war begins as soon as both sides are ready.',
  'war.prepOwesPlan': 'Decide who commands your army.',
  'war.stanceSection': 'Troop stances',
  'war.tapTroopHint': 'Pick a troop to set its stance.',
  'war.choose': 'Choose war plan',
  'war.planLive': 'Command myself',
  'war.planAuto': 'Computer commands',
  'war.adjustTimes': 'Adjust times',
  'war.noCommonTime': 'No shared appointment — adjust your times.',
  'war.enemyStillChoosing': 'Waiting for {realm}',
  'war.prepHelpTooltip': 'Explanation',
  'war.prepHelpBody':
      '• Command: "Command myself" — you give the orders every war round. '
      '"Computer commands" — your army fights along the troop stances.\n\n'
      '• Stance: tap a troop, then "Hold" (defends its position) or '
      '"Attack" (marches on the enemy seat). It applies when the computer '
      'commands or your time runs out.\n\n'
      '• Start: online both sides propose times; the earliest shared hour '
      'becomes the start of the war. If there is none, the war starts at '
      'the end of the preparation window.\n\n'
      '• Everything stays changeable until then.',

  // --- War panel: header & banners ---
  'war.headerVs': 'War against {enemy}',
  'war.winterRuleTooltip':
      'After round 20 winter ends the war — then it is decided by who '
      'holds more (and more valuable) enemy territory and who has won '
      'more battles.',
  'war.roundCounter': 'Round {round}/20',
  'war.openMenuTooltip': 'Open war menu',
  'war.collapse': 'Collapse',
  'war.autopilotBanner':
      'The AI is currently commanding your troops in this war against '
      '{enemy} because you missed its start.',
  'war.resumeCommand': 'Take back control',
  'war.capitalHeldSealBanner':
      "You hold the enemy's royal seat! \"End round\" now seals the "
      'victory — hold the field until then.',
  'war.capitalHeldBanner':
      "You hold the enemy's royal seat! If your army survives the next "
      'round there, the war is won.',
  'war.capitalLostBanner':
      'The enemy holds your royal seat! Retake the field — or the war '
      'is lost.',
  'war.enemyWantsPeaceBanner':
      'The enemy wishes for peace! "Peace" and "End round" ends the war '
      'without territorial changes.',
  'war.peaceWishSentBanner':
      'Peace wish declared — the enemy must consent.',
  'war.objectiveBanner':
      'Objective: Conquer the enemy royal seat (flag) and hold it for a '
      'full round — from round 20 winter ends the war.',

  // --- War panel: unit selection & troop sheet ---
  'war.selectUnitHint':
      'Tap a troop on the map or under "Troops", then a target on the map.',
  'war.selectedUnitMoves': '{name} · Moves {moves}',
  'war.clearSelection': 'Clear selection',
  'war.detailsTitle': 'Troops & enemy host',
  'war.yourTroopsHint': 'Your troops — tap to select',
  'war.autoWarStance': 'On auto-war: ',
  'war.stanceHold': 'Hold',
  'war.stanceAttack': 'Attack',
  'war.stanceHoldPosition': 'Hold position',
  'war.enemyArmyDestroyed': 'The enemy host is destroyed!',
  'war.troopOne': 'troop',
  'war.troopMany': 'troops',
  'war.classCount': '{count}× {class}',
  'war.enemyArmyIntel':
      'Enemy host: {units} {unitWord} ({classes}) · spies report ~{men} '
      'men (as of Anno {year})',
  'war.enemyArmyUnknown':
      'Enemy host: {units} {unitWord} ({classes}) — its strength in men '
      'stays hidden without espionage.',
  'war.movesLeftTooltip': 'Moves remaining: {moves}',
  'war.occupiesEnemySuffix': ' — occupies enemy territory',
  'war.occupiesEnemy': 'Occupies enemy territory',
  'war.stanceTooltip': 'Stance: {stance}',
  'war.unitChipLabel': '{name} · {men} men · ⚔ {strength}',

  // --- War panel: action tiles ---
  'war.plunderNeedUnit': 'Select a troop first',
  'war.plunderAlreadyDone': 'This army has already plundered this round',
  'war.plunderNotEnemyLand': 'The troop must stand on enemy territory',
  'war.plunderNothingHere': 'There is nothing here to plunder',
  'war.plunderHint': 'Plunder a built-up enemy field',
  'war.troopsAction': 'Troops',
  'war.troopsTooltip': 'Your troops & the enemy host',
  'war.plunderAction': 'Plunder',
  'war.plunderReportTitle': 'Plunder',
  'war.withdrawPeace': 'Withdraw',
  'war.peaceAction': 'Peace',
  'war.withdrawPeaceTooltip': 'Withdraw the peace wish',
  'war.peaceTooltip':
      'Wish for peace — if both sides agree, the war ends without '
      'territorial changes',
  'war.handOver': 'Hand over',
  'war.endRound': 'End round',
  'war.roundReportTitle': 'Round report',

  // --- War panel: claim settlement ---
  'war.victoryClaim': 'Victory! Claim: {claim}',
  'war.defeatClaim': "Defeat — the victor's claim: {claim}",
  'war.showExplanation': 'Show explanation',
  'war.done': 'Done',
  'war.settlementWinnerHelp':
      "Choose your spoils: Tap the loser's fields bordering your land to "
      'take them over. Each field costs its value (market {market}, town '
      '{town}, bare land {bare}). "Auto-annex" automatically takes '
      'affordable fields from your border. The unused remainder is paid '
      'out in Taler.',
  'war.settlementLoserHelp': 'The victor now chooses fields of your land.',
  'war.takeWholeLand': 'Take the whole land',
  'war.autoAnnex': 'Auto-annex',
  'war.doneRemainderTaler': 'Done — remainder in Taler',
  // Box-select annexation (long-press an enemy tile, then drag the frame).
  'war.annexDragHint':
      'Long-press an enemy tile and drag the frame across the tiles '
      'you want to take.',
  'war.annexSelectionStatus': '{selected} selected · {plan} annexable',
  'war.annexSelected': 'Annex: {count} · {value} T',
  'war.peaceTreatyTitle': 'Peace treaty',

  // --- War report popup ---
  'war.reportTitle': 'War report',
  'war.continueLabel': 'Continue',
  'war.totalLossesTitle': 'Total losses',
  'war.totalLossesBody':
      'You: −{own} men · Enemy: −{enemy} men ({battles} battles).',
  'war.conquestTitle': 'Conquest',
  'war.conquestOne': '{realm} takes over 1 field.',
  'war.conquestMany': '{realm} takes over {count} fields.',
  'war.summaryTitle': 'War tally',
  'war.summaryRounds': '{rounds} rounds, {battles} battles.',
  'war.sideYou': '{realm} (you)',
  'war.tallyLine': '{side}: {parts}.',
  'war.tallyMenLost': '−{n} men',
  'war.tallyBattleWonOne': '{n} battle won',
  'war.tallyBattlesWon': '{n} battles won',
  'war.tallyLoot': '{n} T looted',
  'war.tallyTileOne': '{n} field conquered',
  'war.tallyTilesMany': '{n} fields conquered',
  'war.theEnemy': 'the enemy',
  'war.battleLoss': '{realm}: "{unit}" loses {losses} men.',
  'war.battleLossDestroyed':
      '{realm}: "{unit}" loses {losses} men — destroyed!',
  'war.attackRepelled': 'The attack was repelled.',
  'war.attackSucceeded': 'The attack succeeded.',
  'war.attackPrevailed': 'The attackers gain the upper hand.',
  'war.defenderPrevailed': 'The defenders drive the attack back.',
  'war.battleAt': 'Battle at ({x}, {y})',
  'war.bareTile': 'Bare field',
  'war.plunderEntryTitle': 'Plunder: {building} of {victim}',
  'war.plunderDevastated':
      'The field is devastated and lies fallow for {years} years.',
  'war.plunderLoot': '{loot} Taler looted.',
  'war.plunderKilled': '{count} inhabitants killed.',
  'war.plunderAt': '{realm} plunders at ({x}, {y}).',
  'war.rulerCapturedTitle': 'Ruler captured!',
  'war.theRuler': 'the ruler',
  'war.rulerCapturedBody':
      '{realm} takes {ruler} of {loser} prisoner — the war is decided.',
  'war.capitalSeizedTitle': 'Royal seat occupied!',
  'war.capitalLostTitle': 'Your royal seat is occupied!',
  'war.capitalSeizedBody':
      'Your army holds the royal seat of {besieged} — if it survives the '
      'next round there, the war is won. If your armies also occupy ALL '
      "of the enemy's strongholds (every town, castle and palace), his "
      'entire land is absorbed into your realm — otherwise you stake '
      'claims by points.',
  'war.capitalLostBody':
      '{realm} holds your royal seat! Retake the field in the next round '
      '— or the war is lost. If ALL your towns, castles and palaces are '
      'occupied as well, your whole land is absorbed by the enemy!',
  'war.warEndTitle': 'End of the war',
  'war.warWonConquered':
      '{realm} wins the war and takes over the entire realm of {loser}!',
  'war.warWonClaim':
      '{realm} wins the war against {loser} (claim: {claim} points).',
  'war.peaceTitle': 'Peace',
  'war.warDrawBody': 'The war ends in a draw — all troops return home.',
  'war.peaceAgreedTitle': 'Peace concluded',
  'war.peaceAgreedBody':
      'Both sides end the war. All troops return home — the land remains '
      'unchanged.',
  'war.winterTitle': 'Winter',
  'war.winterBody':
      'The war had to be ended because of the oncoming winter.',
  'war.claimPaidTitle': 'War indemnity',
  'war.claimPaidBody': '{realm} receives {amount} Taler from {from}.',
  'war.allLostTitle': 'All is lost!',
  'war.totalConquestTitle': 'Total conquest!',
  'war.allLostBody':
      'You have lost your entire land — not a single field remains to you.',
  'war.realmOverrunBody':
      '{realm} has lost its entire land — the realm is wiped from the map.',
  'war.peaceWishTitle': 'Peace wish',
  'war.peaceWishBody': '{realm} wishes for peace.',
  'war.enemyMovedTitle': 'Enemy movement',
  'war.enemyMovedBody':
      '"{unit}" advances from ({fromX}, {fromY}) to ({x}, {y}).',
  'war.enemyHoldsTitle': 'Enemy positions',
  'war.enemyHoldsBody': '{realm} holds its positions — no movement.',
  'war.forcedMarriageTitle': 'Forced marriage',
  'war.forcedMarriageBody': '{victor} marries {spouse}.',
  'war.abdicationTitle': 'Abdication',
  'war.abdicationBody': "{name} must lay down the Kaiser's crown.",
  'war.conversionTitle': 'Conversion',
  'war.conversionBody': 'The dynasty of {realm} changes its faith.',
  'war.executionTitle': 'Execution',
  'war.executionBody': '{name} is executed.',
  'war.electorStrippedTitle': 'Electoral dignity lost',
  'war.electorStrippedBody': '{name} loses the electoral dignity.',
};
