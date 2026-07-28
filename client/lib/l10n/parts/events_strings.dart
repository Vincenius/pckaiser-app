/// String-table part for the "events" UI area — merged into the app-wide
/// table in `l10n/strings.dart`. Keys are prefixed `ev.`; `{name}`-style
/// placeholders are filled by `tr(key, params)`.
const Map<String, String> eventsDe = {
  // ---- Feed UI (filters, headers, buttons) ----
  'ev.filterRelevant': 'Wichtig',
  'ev.filterMine': 'Mein Reich',
  'ev.filterWars': 'Kriege',
  'ev.filterDynasty': 'Dynastie',
  'ev.filterWorld': 'Welt',
  'ev.filterAll': 'Alles',
  'ev.noEvents': 'Keine Ereignisse.',
  'ev.anno': 'Anno {year}',
  'ev.continue': 'Weiter',
  'ev.ok': 'OK',

  // ---- Office nouns (identical in both languages, inserted as {office}) ----
  'ev.officeKaiser': 'Kaiser',
  'ev.officeSultan': 'Sultan',

  // ---- Event lines ----
  'ev.turnUpkeep':
      '{realm}: Steuern {tax} T, Ernte '
      '{grainYield}/{livestockYield}, Sold {wages} T',
  'ev.tileClaimed': '{realm} beansprucht ({x}, {y})',
  'ev.shipBought': '{realm} kauft ein Schiff im Hafen ({x}, {y})',
  'ev.shipColonized': '{realm} kolonisiert ({x}, {y}) per Schiff',
  'ev.buildingBuilt': '{realm} baut auf ({x}, {y})',
  'ev.townFounded': '{realm} gründet {name}',
  'ev.townPromotedMarket': 'Dem Ort {name} wurde das Marktrecht verliehen',
  'ev.townPromotedTown': 'Dem Ort {name} wurde das Stadtrecht verliehen',
  'ev.townDied': '{name} ist verlassen',
  'ev.goodsSold': '{realm} verkauft {amount} für {proceeds} T',
  'ev.shipsSent': '{realm} sendet Handelsschiffe aus — Einsatz {invested} T',
  'ev.shipsReturned':
      '{realm}: Handelsschiffe kehren zurück — Erlös {returned} T '
      '(Einsatz {invested} T)',
  'ev.moneySent': '{realm} schickt {amount} T an {target}',
  'ev.capitalRelocated': '{realm} verlegt den Sitz nach ({x}, {y})',
  'ev.capitalReseated':
      '{realm} bestimmt nach dem Verlust einen neuen Sitz bei ({x}, {y})',
  'ev.capitalLost':
      '{realm} hat seinen Sitz verloren — ein neuer muss bestimmt werden !',
  'ev.wedding': '{a} von {realm} heiratet {b}',
  'ev.marriageRejectedInvalid':
      '{realm}: die Heirat ist nicht mehr möglich '
      '(einer der Partner ist inzwischen gebunden) !',
  'ev.marriageRejected': '{realm}: der Heiratsantrag wurde abgelehnt !',
  'ev.divorce': 'Die Ehe von {a} und {b} wird geschieden (Religion)',
  'ev.birth': '{parent} von {realm} feiert die Geburt von {child}',
  'ev.personDied':
      '{name} von {realm} ist im Alter von {age} Jahren verstorben ({cause})',
  'ev.succession': '{realm}: Die Weisen erwählen {heir} zum Erben',
  'ev.titlePromoted': '{realm}: neuer Titel {title}',
  'ev.troopsRecruited': '{realm} bildet {men} Rekruten aus',
  'ev.soeldnerHired': '{realm} wirbt {men} Söldner an',
  'ev.warDeclared': '{realm} erklärt {target} den Krieg!',
  'ev.battle':
      'Schlacht: {attackerUnit} (−{attackerLosses}) '
      'vs {defenderUnit} (−{defenderLosses})',
  'ev.rulerCaptured': '{realm} nimmt den Herrscher von {loser} gefangen!',
  'ev.capitalHeld': '{realm} besetzt den Königssitz von {loser} !',
  'ev.warWonConquered':
      '{realm} gewinnt den Krieg und übernimmt das gesamte Reich von '
      '{loser} !',
  'ev.warWon': '{realm} gewinnt den Krieg gegen {loser}',
  'ev.warDraw': 'Der Krieg endet unentschieden',
  'ev.peaceAgreed': 'Friedensschluss — der Krieg endet ohne Gebietsänderungen',
  'ev.winterEndsWar':
      'Der Krieg musste wegen des hereinbrechenden Winters beendet werden',
  'ev.peaceWish': '{realm} wünscht ein Ende des Krieges',
  'ev.tileConquered': '{realm} erobert ({x}, {y}) von {from}',
  'ev.plunder': '{realm} plündert ({x}, {y}) — Opfer: {victim}',
  'ev.claimPaidOut':
      '{realm} erhält {amount} T Kriegsentschädigung von {from}',
  'ev.realmOverrun': '{realm} hat sein gesamtes Land verloren !',
  'ev.humansDefeated':
      'Keine menschliche Dynastie hält mehr die Macht — das Spiel ist aus',
  'ev.playerLeft':
      '{realm}: der Spieler hat die Partie verlassen — der Computer übernimmt',
  'ev.playerKicked':
      '{realm}: der Spieler wurde wegen Inaktivität ersetzt — '
      'der Computer übernimmt',
  'ev.forcedMarriage': '{victor} erzwingt die Heirat mit {spouse}',
  'ev.forcedAbdication': '{name} muss abdanken !',
  'ev.execution': '{name} wird hingerichtet !!!',
  'ev.realmsMerged': '{realm} übernimmt {source}',
  'ev.realmTransferred': '{source} übergibt sein Reich an {realm}',
  'ev.crowned': '{name} von {realm} wird {office}',
  'ev.electionStartedKaiser': 'Kaiserwahl — die Wahl beginnt',
  'ev.electionStartedSultan': 'Sultanswahl — die Wahl beginnt',
  'ev.electionTie': 'Die Wahl endet unentschieden — Stichwahl !',
  'ev.interregnum': 'Interregnum — der Thron bleibt unbesetzt',
  'ev.tributeCollectedSultan':
      '{realm} plündert den Sultansschatz: +{amount} T',
  'ev.tributeCollectedKaiser': '{realm} plündert den Kronschatz: +{amount} T',
  'ev.newKurfuerst': '{name} wird Kurfürst',
  'ev.kurfuerstStripped': '{name} verliert die Kurfürstenwürde',
  'ev.officeHolderDied': 'Der Amtsinhaber ist verstorben',
  'ev.assassination': '{victim} von {realm} wird hinterhältig ermordet !!!',
  'ev.assassinationSucceeded':
      'Deine Attentäter haben {victim} in {target} ermordet',
  'ev.assassinationFailed':
      'Anschlag auf {victim} vereitelt — Auftraggeber: {sponsor}',
  'ev.assassinsDispatched':
      '{realm} entsendet {agents} Attentäter nach {target}',
  'ev.intelGathered': '{realm}: Spionagebericht über {target} liegt vor',
  'ev.missionFailedCaught':
      'Spione in {target} gefangengenommen — einer gesteht unter Folter, aus '
      '{realm} geschickt worden zu sein !!!',
  'ev.missionFailed': '{realm}: Spionagemission in {target} gescheitert',
  'ev.religionChanged': '{realm} wechselt die Religion',
  'ev.religionChangedPopularity':
      '{realm} wechselt die Religion (−{popularityLost} Beliebtheit)',
  'ev.dynastyConverted': '{realm}: die Dynastie konvertiert',
  'ev.dynastyExtinct': '{realm}: die Dynastie ist erloschen',
  'ev.realmInherited':
      'Durch Erbfolge fällt {realms} an {heir} von {realm}',
  'ev.islamicSuccessionCrisis':
      '{realm}: Erbfolgekrise — {heir} setzt sich durch',
  'ev.islamicSuccessionCrisisHuman':
      '{realm}: Erbfolgekrise — {heir} setzt sich durch; '
      'der Spieler verliert die Kontrolle über das Reich !',
  'ev.internalStrife': '{realm}: Volksaufstand — {newRuler} ergreift die Macht',
  'ev.internalStrifeHuman':
      '{realm}: Volksaufstand — {newRuler} ergreift die Macht; '
      'der Spieler verliert die Kontrolle über das Reich !',
  'ev.seatLost':
      'Durch Erbfolge fällt {realm} an ein fremdes Herrscherhaus — '
      'der Spieler verliert die Kontrolle über das Reich !',
  'ev.seatLostHeir':
      'Durch Erbfolge fällt {realm} an ein fremdes Herrscherhaus ({heir}) — '
      'der Spieler verliert die Kontrolle über das Reich !',
  'ev.bankruptcy': '{realm} ist bankrott ({debt} T Schulden) !',
  'ev.bankruptcyHuman':
      '{realm} ist bankrott ({debt} T Schulden) ! '
      'Der Spieler verliert das Reich an ein neues Herrscherhaus !',
  'ev.debtWarning':
      '{realm} steckt tief in Schulden ({debt} T) — noch {turnsLeft} Züge '
      'bis zum Staatsbankrott !',
  'ev.debtWarningOne':
      '{realm} steckt tief in Schulden ({debt} T) — noch {turnsLeft} Zug '
      'bis zum Staatsbankrott !',
  'ev.merchantFounder': 'Der Kaufmann {name} gründet eine neue Dynastie',
  'ev.totalExtinction': 'Alle Dynastien sind erloschen — das Land verfällt',
  'ev.earthquake': 'Ein verheerendes Erdbeben verwüstet das Reich',
  'ev.disease': 'Die {name} geht um!',
  'ev.reformation': 'Die Reformation! ',
  'ev.ottomanInvasion':
      'Die Osmanen erreichen {realm}: Das Reich tritt zum Islam über, '
          'die Janitscharen ({men} Mann) beziehen die Hauptstadt!',
  'ev.janissariesDisbanded':
      'Die Janitscharen von {realm} lösen sich auf — '
          'einem neuen Herrn dienen sie nicht.',
  'ev.buildingDemolished': '{realm} reißt ({x}, {y}) ab',
  'ev.gameWon': '{realm} ist der alleinige Herrscher des ganzen Landes!',
  'ev.gameDraw': 'Alle Dynastien sind erloschen — das Land bleibt herrenlos',

  // ---- Drama popups ----
  'ev.dramaAssassinationTitle': 'Attentat !!!',
  'ev.dramaAssassinationBody':
      '{victim} wurde von gedungenen Mördern ermordet !',
  'ev.dramaAssassinationSucceededTitle': 'Attentat erfolgreich !',
  'ev.dramaAssassinationSucceededBody':
      'Deine Attentäter haben {victim} in {target} ermordet — '
      'niemand ahnt, wer den Auftrag gab.',
  'ev.dramaAssassinationFoiledTitle': 'Attentat vereitelt !',
  'ev.dramaAssassinationFoiledBody':
      'Ein Anschlag auf {victim} ist fehlgeschlagen !',
  'ev.dramaAssassinationFoiledBodyCaught':
      'Ein Anschlag auf {victim} ist fehlgeschlagen !\n'
      'Die gefassten Attentäter gestehen unter Folter: '
      'der Auftrag kam aus {sponsor} !',
  'ev.dramaAssassinationFailedTitle': 'Anschlag fehlgeschlagen',
  'ev.dramaAssassinationFailedBody':
      'Deine Attentäter haben {victim} nicht erwischt.',
  'ev.dramaAssassinationFailedBodyCaught':
      'Deine Attentäter haben {victim} nicht erwischt — und wurden gefasst ! '
      'Dein Auftrag ist nun bekannt !',
  'ev.dramaCrownedYouTitle': 'Du bist {office} !',
  'ev.dramaCrownedYouBody': '{name} wird zum {office} gekrönt !',
  'ev.dramaCrownedYouBodyAcclaimed':
      '{name} wird ohne Gegenstimme zum {office} gekrönt !',
  'ev.dramaCrownedOtherTitle': 'Ein neuer {office} !',
  'ev.dramaCrownedOtherBody': '{name} von {realm} wird zum {office} gekrönt !',
  'ev.dramaCrownedOtherBodyAcclaimed':
      '{name} von {realm} wird ohne Gegenstimme zum {office} gekrönt !',
  'ev.dramaInheritanceTitle': 'Erbschaft !',
  'ev.dramaInheritanceBody':
      'Nach dem Tod von {deceased} fällt {realms} durch Erbfolge an {heir} — '
      'das Reich gehört nun deinem Haus, du führst es ab sofort mit !',
  'ev.dramaRealmLostTitle': 'Reich verloren !',
  'ev.dramaRealmOverrunYouBody':
      'Dein Reich wurde im Krieg vollständig überrannt — du hast all '
      'dein Land verloren !',
  'ev.dramaRealmFallenTitle': 'Ein Reich ist gefallen !',
  'ev.dramaRealmOverrunOtherBody':
      '{realm} wurde im Krieg vollständig überrannt '
      'und hat sein gesamtes Land verloren !',
  'ev.dramaRulerCapturedTitle': 'Herrscher gefangen !',
  'ev.dramaRulerCapturedBody':
      '{realm} nimmt den Herrscher von {loser} gefangen !',
  'ev.dramaRulerCapturedBodyNamed':
      '{realm} nimmt den Herrscher von {loser} ({ruler}) gefangen !',
  'ev.dramaInternalStrifeYouBody':
      'Volksaufstand in {realm}: die Zustimmung deines Volkes ist unter 20 '
      'gefallen — {newRuler} ergreift die Macht ! Du hast die Kontrolle über '
      'das Reich verloren; der Computer regiert es fortan.',
  'ev.dramaInternalStrifeTitle': 'Volksaufstand !',
  'ev.dramaInternalStrifeOtherBody':
      '{realm}: die Zustimmung fiel unter 20 — '
      '{newRuler} entthront den Spieler und ergreift die Macht !',
  'ev.dramaBankruptcyYouBody':
      'Dein Reich {realm} ist bankrott ({debt} T Schulden) — die Gläubiger '
      'übergeben es einem neuen Herrscherhaus. Du hast die Kontrolle über '
      'das Reich verloren.',
  'ev.dramaBankruptcyTitle': 'Staatsbankrott !',
  'ev.dramaBankruptcyOtherBody':
      '{realm} ist bankrott ({debt} T Schulden) — '
      'der Spieler verliert das Reich an ein neues Herrscherhaus !',
  'ev.dramaIslamicCrisisYouBody':
      'Erbfolgekrise in {realm}: {heir} kann als Frau kein muslimisches '
      'Reich führen — das Reich fällt unter Computer-Kontrolle. '
      'Du hast die Kontrolle verloren.',
  'ev.dramaIslamicCrisisTitle': 'Erbfolgekrise !',
  'ev.dramaIslamicCrisisOtherBody':
      '{realm}: {heir} setzt sich durch — der '
      'Spieler verliert die Kontrolle über das Reich !',
  'ev.dramaSeatLostYouBody':
      'Durch Erbfolge ist {realm} an ein fremdes Herrscherhaus gefallen — '
      'du hast die Kontrolle über das Reich verloren.',
  'ev.dramaSeatLostYouBodyHeir':
      'Durch Erbfolge ist {realm} an ein fremdes Herrscherhaus gefallen '
      '({heir}) — du hast die Kontrolle über das Reich verloren.',
  'ev.dramaSeatLostOtherTitle': 'Reich durch Erbfolge verloren !',
  'ev.dramaSeatLostOtherBody':
      'Durch Erbfolge fällt {realm} an ein fremdes Herrscherhaus — '
      'der Spieler verliert die Kontrolle über das Reich !',
  'ev.dramaSeatLostOtherBodyHeir':
      'Durch Erbfolge fällt {realm} an ein fremdes Herrscherhaus ({heir}) — '
      'der Spieler verliert die Kontrolle über das Reich !',
  'ev.dramaPlayerKickedTitle': 'Spieler ersetzt',
  'ev.dramaPlayerKickedBody':
      'Der Spieler von {realm} wurde wegen Inaktivität aus der Partie '
      'entfernt — der Computer übernimmt das Reich.',
  'ev.dramaDefaultTitle': 'Nachricht',
};

const Map<String, String> eventsEn = {
  // ---- Feed UI (filters, headers, buttons) ----
  'ev.filterRelevant': 'Important',
  'ev.filterMine': 'My realm',
  'ev.filterWars': 'Wars',
  'ev.filterDynasty': 'Dynasty',
  'ev.filterWorld': 'World',
  'ev.filterAll': 'All',
  'ev.noEvents': 'No events.',
  'ev.anno': 'Anno {year}',
  'ev.continue': 'Continue',
  'ev.ok': 'OK',

  // ---- Office nouns (identical in both languages, inserted as {office}) ----
  'ev.officeKaiser': 'Kaiser',
  'ev.officeSultan': 'Sultan',

  // ---- Event lines ----
  'ev.turnUpkeep':
      '{realm}: taxes {tax} T, harvest '
      '{grainYield}/{livestockYield}, wages {wages} T',
  'ev.tileClaimed': '{realm} claims ({x}, {y})',
  'ev.shipBought': '{realm} buys a ship at the harbor ({x}, {y})',
  'ev.shipColonized': '{realm} colonizes ({x}, {y}) by ship',
  'ev.buildingBuilt': '{realm} builds at ({x}, {y})',
  'ev.townFounded': '{realm} founds {name}',
  'ev.townPromotedMarket': '{name} has been granted market rights',
  'ev.townPromotedTown': '{name} has been granted town rights',
  'ev.townDied': '{name} lies abandoned',
  'ev.goodsSold': '{realm} sells {amount} for {proceeds} T',
  'ev.shipsSent': '{realm} sends out trade ships — stake {invested} T',
  'ev.shipsReturned':
      '{realm}: trade ships return — proceeds {returned} T '
      '(stake {invested} T)',
  'ev.moneySent': '{realm} sends {amount} T to {target}',
  'ev.capitalRelocated': '{realm} moves its seat to ({x}, {y})',
  'ev.capitalReseated':
      '{realm} chooses a new seat at ({x}, {y}) after the loss',
  'ev.capitalLost': '{realm} has lost its seat — a new one must be chosen!',
  'ev.wedding': '{a} of {realm} marries {b}',
  'ev.marriageRejectedInvalid':
      '{realm}: the marriage is no longer possible '
      '(one of the partners is now bound)!',
  'ev.marriageRejected': '{realm}: the marriage proposal was rejected!',
  'ev.divorce': 'The marriage of {a} and {b} is dissolved (religion)',
  'ev.birth': '{parent} of {realm} celebrates the birth of {child}',
  'ev.personDied': '{name} of {realm} has died at the age of {age} ({cause})',
  'ev.succession': '{realm}: the elders choose {heir} as heir',
  'ev.titlePromoted': '{realm}: new title {title}',
  'ev.troopsRecruited': '{realm} trains {men} recruits',
  'ev.soeldnerHired': '{realm} hires {men} Söldner',
  'ev.warDeclared': '{realm} declares war on {target}!',
  'ev.battle':
      'Battle: {attackerUnit} (−{attackerLosses}) '
      'vs {defenderUnit} (−{defenderLosses})',
  'ev.rulerCaptured': '{realm} captures the ruler of {loser}!',
  'ev.capitalHeld': '{realm} occupies the royal seat of {loser}!',
  'ev.warWonConquered':
      '{realm} wins the war and takes over the entire realm of {loser}!',
  'ev.warWon': '{realm} wins the war against {loser}',
  'ev.warDraw': 'The war ends in a draw',
  'ev.peaceAgreed': 'Peace is made — the war ends without territorial changes',
  'ev.winterEndsWar': 'The war had to end with the onset of winter',
  'ev.peaceWish': '{realm} wishes for an end to the war',
  'ev.tileConquered': '{realm} conquers ({x}, {y}) from {from}',
  'ev.plunder': '{realm} plunders ({x}, {y}) — victim: {victim}',
  'ev.claimPaidOut':
      '{realm} receives {amount} T in war reparations from {from}',
  'ev.realmOverrun': '{realm} has lost all of its land!',
  'ev.humansDefeated':
      'No human dynasty holds power any longer — the game is over',
  'ev.playerLeft':
      '{realm}: the player has left the game — the computer takes over',
  'ev.playerKicked':
      '{realm}: the player was replaced for inactivity — '
      'the computer takes over',
  'ev.forcedMarriage': '{victor} forces a marriage with {spouse}',
  'ev.forcedAbdication': '{name} must abdicate!',
  'ev.execution': '{name} is executed!!!',
  'ev.realmsMerged': '{realm} takes over {source}',
  'ev.realmTransferred': '{source} hands its realm over to {realm}',
  'ev.crowned': '{name} of {realm} becomes {office}',
  'ev.electionStartedKaiser': 'Kaiser election — the vote begins',
  'ev.electionStartedSultan': 'Sultan election — the vote begins',
  'ev.electionTie': 'The election ends in a tie — runoff!',
  'ev.interregnum': 'Interregnum — the throne remains vacant',
  'ev.tributeCollectedSultan':
      "{realm} plunders the Sultan's treasury: +{amount} T",
  'ev.tributeCollectedKaiser': '{realm} plunders the crown treasury: '
      '+{amount} T',
  'ev.newKurfuerst': '{name} becomes Elector',
  'ev.kurfuerstStripped': '{name} is stripped of the electoral dignity',
  'ev.officeHolderDied': 'The office holder has died',
  'ev.assassination': '{victim} of {realm} is treacherously murdered!!!',
  'ev.assassinationSucceeded':
      'Your assassins have murdered {victim} in {target}',
  'ev.assassinationFailed':
      'Attempt on {victim} foiled — sponsor: {sponsor}',
  'ev.assassinsDispatched': '{realm} dispatches {agents} assassins to {target}',
  'ev.intelGathered': '{realm}: spy report on {target} has arrived',
  'ev.missionFailedCaught':
      'Spies caught in {target} — one confesses under torture '
      'to having been sent from {realm}!!!',
  'ev.missionFailed': '{realm}: spy mission in {target} has failed',
  'ev.religionChanged': '{realm} changes its religion',
  'ev.religionChangedPopularity':
      '{realm} changes its religion (−{popularityLost} popularity)',
  'ev.dynastyConverted': '{realm}: the dynasty converts',
  'ev.dynastyExtinct': '{realm}: the dynasty has died out',
  'ev.realmInherited': 'By succession, {realms} falls to {heir} of {realm}',
  'ev.islamicSuccessionCrisis':
      '{realm}: succession crisis — {heir} prevails',
  'ev.islamicSuccessionCrisisHuman':
      '{realm}: succession crisis — {heir} prevails; '
      'the player loses control of the realm!',
  'ev.internalStrife': '{realm}: popular uprising — {newRuler} seizes power',
  'ev.internalStrifeHuman':
      '{realm}: popular uprising — {newRuler} seizes power; '
      'the player loses control of the realm!',
  'ev.seatLost':
      'By succession, {realm} falls to a foreign ruling house — '
      'the player loses control of the realm!',
  'ev.seatLostHeir':
      'By succession, {realm} falls to a foreign ruling house ({heir}) — '
      'the player loses control of the realm!',
  'ev.bankruptcy': '{realm} is bankrupt ({debt} T of debt)!',
  'ev.bankruptcyHuman':
      '{realm} is bankrupt ({debt} T of debt)! '
      'The player loses the realm to a new ruling house!',
  'ev.debtWarning':
      '{realm} is deep in debt ({debt} T) — {turnsLeft} more turns '
      'until state bankruptcy!',
  'ev.debtWarningOne':
      '{realm} is deep in debt ({debt} T) — {turnsLeft} more turn '
      'until state bankruptcy!',
  'ev.merchantFounder': 'The merchant {name} founds a new dynasty',
  'ev.totalExtinction': 'All dynasties have died out — the land falls to ruin',
  'ev.earthquake': 'A devastating earthquake ravages the realm',
  'ev.disease': 'The {name} is spreading!',
  'ev.reformation': 'The Reformation!',
  'ev.ottomanInvasion':
      'The Ottomans reach {realm}: the realm converts to Islam, '
          'the Janissaries ({men} men) garrison the capital!',
  'ev.janissariesDisbanded':
      'The Janissaries of {realm} disband — they serve no new master.',
  'ev.buildingDemolished': '{realm} demolishes ({x}, {y})',
  'ev.gameWon': '{realm} is the sole ruler of the whole land!',
  'ev.gameDraw':
      'All dynasties have died out — the land remains without a master',

  // ---- Drama popups ----
  'ev.dramaAssassinationTitle': 'Assassination!!!',
  'ev.dramaAssassinationBody':
      '{victim} has been murdered by hired killers!',
  'ev.dramaAssassinationSucceededTitle': 'Assassination successful!',
  'ev.dramaAssassinationSucceededBody':
      'Your assassins have murdered {victim} in {target} — '
      'no one suspects who gave the order.',
  'ev.dramaAssassinationFoiledTitle': 'Assassination foiled!',
  'ev.dramaAssassinationFoiledBody': 'An attempt on {victim} has failed!',
  'ev.dramaAssassinationFoiledBodyCaught':
      'An attempt on {victim} has failed!\n'
      'The captured assassins confess under torture: '
      'the order came from {sponsor}!',
  'ev.dramaAssassinationFailedTitle': 'Attempt failed',
  'ev.dramaAssassinationFailedBody':
      'Your assassins did not get to {victim}.',
  'ev.dramaAssassinationFailedBodyCaught':
      'Your assassins did not get to {victim} — and were caught! '
      'Your order is now known!',
  'ev.dramaCrownedYouTitle': 'You are {office}!',
  'ev.dramaCrownedYouBody': '{name} is crowned {office}!',
  'ev.dramaCrownedYouBodyAcclaimed':
      '{name} is crowned {office} without a dissenting vote!',
  'ev.dramaCrownedOtherTitle': 'A new {office}!',
  'ev.dramaCrownedOtherBody': '{name} of {realm} is crowned {office}!',
  'ev.dramaCrownedOtherBodyAcclaimed':
      '{name} of {realm} is crowned {office} without a dissenting vote!',
  'ev.dramaInheritanceTitle': 'Inheritance!',
  'ev.dramaInheritanceBody':
      'Upon the death of {deceased}, {realms} falls by succession to {heir} — '
      'the realm now belongs to your house, and you rule it from this day on!',
  'ev.dramaRealmLostTitle': 'Realm lost!',
  'ev.dramaRealmOverrunYouBody':
      'Your realm has been completely overrun in the war — you have lost '
      'all your land!',
  'ev.dramaRealmFallenTitle': 'A realm has fallen!',
  'ev.dramaRealmOverrunOtherBody':
      '{realm} has been completely overrun in the war '
      'and has lost all of its land!',
  'ev.dramaRulerCapturedTitle': 'Ruler captured!',
  'ev.dramaRulerCapturedBody': '{realm} captures the ruler of {loser}!',
  'ev.dramaRulerCapturedBodyNamed':
      '{realm} captures the ruler of {loser} ({ruler})!',
  'ev.dramaInternalStrifeYouBody':
      "Popular uprising in {realm}: your people's approval has fallen "
      'below 20 — {newRuler} seizes power! You have lost control of the '
      'realm; the computer rules it from now on.',
  'ev.dramaInternalStrifeTitle': 'Popular uprising!',
  'ev.dramaInternalStrifeOtherBody':
      '{realm}: approval fell below 20 — '
      '{newRuler} dethrones the player and seizes power!',
  'ev.dramaBankruptcyYouBody':
      'Your realm {realm} is bankrupt ({debt} T of debt) — the creditors '
      'hand it over to a new ruling house. You have lost control of '
      'the realm.',
  'ev.dramaBankruptcyTitle': 'State bankruptcy!',
  'ev.dramaBankruptcyOtherBody':
      '{realm} is bankrupt ({debt} T of debt) — '
      'the player loses the realm to a new ruling house!',
  'ev.dramaIslamicCrisisYouBody':
      'Succession crisis in {realm}: as a woman, {heir} cannot rule a '
      'Muslim realm — the realm falls under computer control. '
      'You have lost control.',
  'ev.dramaIslamicCrisisTitle': 'Succession crisis!',
  'ev.dramaIslamicCrisisOtherBody':
      '{realm}: {heir} prevails — the player loses control of the realm!',
  'ev.dramaSeatLostYouBody':
      'By succession, {realm} has fallen to a foreign ruling house — '
      'you have lost control of the realm.',
  'ev.dramaSeatLostYouBodyHeir':
      'By succession, {realm} has fallen to a foreign ruling house '
      '({heir}) — you have lost control of the realm.',
  'ev.dramaSeatLostOtherTitle': 'Realm lost by succession!',
  'ev.dramaSeatLostOtherBody':
      'By succession, {realm} falls to a foreign ruling house — '
      'the player loses control of the realm!',
  'ev.dramaSeatLostOtherBodyHeir':
      'By succession, {realm} falls to a foreign ruling house ({heir}) — '
      'the player loses control of the realm!',
  'ev.dramaPlayerKickedTitle': 'Player replaced',
  'ev.dramaPlayerKickedBody':
      'The player of {realm} was removed from the game for inactivity — '
      'the computer takes over the realm.',
  'ev.dramaDefaultTitle': 'News',
};
