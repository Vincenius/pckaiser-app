/// String-table part for the "menus" UI area — merged into the app-wide
/// table in `l10n/strings.dart`. Keys are prefixed `menus.`; `{name}`-style
/// placeholders are filled by `tr(key, params)`.
const Map<String, String> menusDe = {
  // --- Commerce ---
  'menus.surplusMarketPrice': 'Überschuß: {surplus} — Marktpreis {price} T',
  'menus.taxesTitle': 'Steuern: {rate} %',
  'menus.percentSuffix': ' %',
  'menus.taxesSubtitle':
      'Mehr Steuern bringen mehr Geld, senken aber die Beliebtheit',
  'menus.investMax': 'Maximal: {max} T (Häfen: {harbors})',
  'menus.sendMoney': 'Geld schicken',
  'menus.sendMoneySubtitle': 'Taler an ein anderes Land überweisen',
  'menus.taler': 'Taler',
  'menus.mergeWith': 'Reiche zusammenlegen: {realm}',
  'menus.transferRealm': 'Reich übertragen',
  'menus.transferRealmSubtitle':
      'Das gesamte Reich einem fremden Herrscher übergeben',
  'menus.transferConfirm': 'Reich an {realm} übertragen ?',
  'menus.transferConfirmBody':
      'Land, Städte, Truppen, Schiffe, Schatz und Dynastie gehen an den '
      'fremden Herrscher über. Das kann nicht rückgängig gemacht werden !',
  'menus.transferTiles': 'Felder übertragen',
  'menus.transferTilesSubtitle':
      'Einzelne Felder an ein fremdes Reich abgeben',
  'menus.transferTilePickHint':
      'Felder antippen oder gedrückt halten und ziehen, um sie auszuwählen',
  'menus.transferTileHintCount': '{hint} — {n} ausgewählt',
  'menus.transferTileOwnOnly':
      'Nur eigene Felder können übertragen werden',
  'menus.notMidWar': 'Nicht mitten im Krieg !',
  'menus.yields': 'bringt {amount} T',
  'menus.investDetail':
      'Einsatz {amount} T — der Ertrag kehrt nächste Runde zurück',
  // --- Military ---
  'menus.recruitSubtitle':
      '{cost} T pro Mann — freie Kapazität: {capacity} — '
      'Aushebung dieses Jahr: {levy}',
  'menus.soeldnerSubtitle': '{cost} T pro Mann (plus Sold)',
  'menus.costs': 'kostet {cost} T',
  'menus.costPerMan': '{cost} T pro Mann',
  'menus.troopList': 'Truppenliste ({n})',
  'menus.armyMen': 'Armee: {n} Mann',
  'menus.warOncePerYear': 'Einmal pro Jahr — nur Nachbarn',
  'menus.stationWhere': 'Wo soll die Truppe stationiert werden?',
  'menus.capital': 'Hauptsitz',
  'menus.tileAt': 'Feld ({x}, {y})',
  'menus.pickTile': 'Feld auswählen',
  'menus.pickTileSubtitle': 'Ein eigenes Feld auf der Karte antippen',
  'menus.pickTileHint': 'Feld für die neue Truppe antippen',
  'menus.stationOwnTerritory':
      'Du musst deine Truppen auf deinem Territorium stationieren !',
  'menus.recruitsName': 'Rekruten',
  'menus.troopNameLabel': 'Name der Truppe',
  'menus.levyExhausted':
      'Deine Bevölkerung gibt dieses Jahr keine weiteren Rekruten her !',
  'menus.notEnoughTaler': 'Du hast nicht genügend Taler !',
  'menus.recruitCostDetail': 'kostet {cost} T — Stärke {strength}',
  'menus.troopListTitle': 'Truppenliste — Armee: {n} Mann',
  'menus.troopTitle': '{name} — {men} Mann',
  'menus.soeldnerTag': ' (Söldner)',
  'menus.troopSubtitle': '{cls}{tag} — Stärke {strength} — Feld ({x}, {y})',
  'menus.autoWarStance': 'Verhalten im automatischen Krieg',
  'menus.stanceHold': 'Halten',
  'menus.stanceAttack': 'Angreifen',
  'menus.stanceHoldDesc':
      'Verteidigt die Basis; greift erst an, wenn der Gegner '
      'keine Truppen mehr hat.',
  'menus.stanceAttackDesc':
      'Marschiert sofort auf das gewählte Marschziel — '
      'ohne eigenes Ziel auf den gegnerischen Königssitz.',
  'menus.moveTroop': 'Truppe verlegen',
  'menus.moveTroopSubtitle': 'Kostenlos — Zielfeld auf der Karte antippen',
  'menus.moveTroopHint': 'Zielfeld für „{name}" antippen',
  'menus.transferTroop': 'Truppe übertragen',
  'menus.transferTroopSubtitle': 'An ein anderes Reich übergeben',
  'menus.transferTroopConfirm': 'Truppe an {realm} übertragen?',
  'menus.transferTroopConfirmBody':
      '„{name}" ({men} Mann) wird an {realm} übergeben.',
  'menus.reinforceTroop': 'Truppe verstärken',
  'menus.drillTroop': 'Truppe ausbilden',
  'menus.soeldnerNoDrill': 'Söldner können nicht ausgebildet werden',
  'menus.fullyDrilled': 'Bereits voll ausgebildet (Qualität {quality})',
  'menus.drillDetail': '{cost} T — Qualität {from} → {to}',
  'menus.retrainTroop': 'Truppe umrüsten',
  'menus.soeldnerNoRetrain': 'Söldner können nicht umgerüstet werden',
  'menus.retrainSubtitle': 'Gattung wechseln — {cost} T pro Mann plus Aufpreis',
  'menus.mergeWithTroop': 'Vereinigen mit „{name}" ({men} Mann)',
  'menus.renameTroop': 'Truppe umbenennen',
  'menus.disbandTroop': 'Truppe auflösen',
  'menus.disbandTroopQuestion': 'Truppe auflösen?',
  'menus.disbandTroopConfirm': '„{name}" ({men} Mann) wird aufgelöst.',
  'menus.disband': 'Auflösen',
  'menus.retrainTitle': '„{name}" umrüsten — aktuelle Stärke {strength}',
  'menus.retrainTo': 'Zu {cls} umrüsten',
  'menus.retrainDetail': 'kostet {cost} T — neue Stärke {strength}',
  'menus.noSharedBorder':
      'Du hast keine gemeinsame Grenze mit einem anderen Reich !',
  'menus.unknown': 'unbekannt',
  'menus.declareWarOn': 'Krieg erklären: {realm}?',
  // --- Espionage ---
  'menus.spyEconomy': 'Daten ausspionieren',
  'menus.spyMilitary': 'Truppen ausspionieren',
  'menus.assassinate': 'Anschlag verüben',
  'menus.costPerAgent': '{cost} T pro Agent',
  'menus.guardsLevel': 'Spionageabwehr: {level} / {cap}',
  'menus.dismissFree': 'Entlassen ist kostenlos',
  'menus.agents': 'Agenten',
  'menus.agentsDetail': 'kostet {cost} T — mehr Agenten, bessere Chancen',
  'menus.spyTitle': 'Spionage — {realm}',
  'menus.spiesUnderway': 'Die Spione sind unterwegs …',
  'menus.spyCaughtOne':
      'Die Mission ist gescheitert ! Einer deiner Spione wurde '
      'gefangengenommen — er gesteht unter Folter, aus {realm} '
      'geschickt worden zu sein !!!',
  'menus.spyCaughtMany':
      'Die Mission ist gescheitert ! {caught} deiner Spione wurden '
      'gefangengenommen — einer gesteht unter Folter, aus {realm} '
      'geschickt worden zu sein !!!',
  'menus.spyNothing': 'Deine Spione konnten nichts in Erfahrung bringen !',
  'menus.spySuccess':
      'Mission erfolgreich ! Den Bericht findest du unter Info → Dynastien.',
  'menus.assassinConfirm': 'Anschlag auf {realm} — wirklich?',
  'menus.assassinOrdered': 'Anschlag in Auftrag gegeben',
  'menus.assassinUnderway':
      'Die Attentäter sind auf dem Weg !!!\n\n'
      'Ob der Anschlag gelingt, erfährst du in einem der nächsten Züge.',
  'menus.assassinAlready': 'Diesen Zug schon Attentäter entsandt',
  'menus.assassinRisk':
      'Ein Anschlag bleibt ein Wagnis — je mehr Attentäter, desto besser '
      'die Aussichten, doch die Leibwache des Ziels fängt viele ab. Wird '
      'einer gefasst, nennt er dich unter Folter vor aller Welt.',
  // --- Dynasty & misc ---
  'menus.nobodyMarriageable': 'Niemand in deiner Dynastie kann heiraten !',
  'menus.allProposed': 'Alle haben diesen Zug schon einen Antrag gestellt !',
  'menus.dynastySubtitle':
      '{n} Mitglieder — fremde Dynastien über Info → Dynastien',
  'menus.marryCommoner': 'Bürgerlich heiraten',
  'menus.marryCommonerSubtitle': 'Eine Person aus dem Volk heiraten',
  'menus.plunderTreasury': 'Staatskasse plündern',
  'menus.kaiserPot': '{amount} T im Kronschatz',
  'menus.sultanPot': '{amount} T im Sultansschatz',
  'menus.relocateSeat': 'Sitz verlegen',
  'menus.relocateSeatLost':
      'Sitz verloren — neue Stadt, Burg oder Palast wählen (gratis)',
  'menus.relocateSeatSubtitle':
      '{cost} T — eigene Stadt, Burg oder Palast wählen',
  'menus.relocateSeatMapHint':
      'Tippe eine Stadt, Burg oder einen Palast auf der Karte ({cost} T)',
  'menus.relocateSeatMapHintLost':
      'Tippe eine Stadt, Burg oder einen Palast auf der Karte (gratis)',
  'menus.religionCatholic': 'katholisch',
  'menus.religionProtestant': 'evangelisch',
  'menus.religionMuslim': 'moslemisch',
  'menus.religionOption': 'Religion: {religion}',
  'menus.religionCost': '{cost} T, −{pop} Beliebtheit',
  'menus.changeReligionQuestion': 'Religion wechseln?',
  // German declines the faith adjective in place: {faith}en → "katholischen".
  'menus.religionConfirmBody':
      'Deine Dynastie tritt zum {faith}en Glauben über.\n\n'
      'Das kostet {cost} T und {pop} Beliebtheit, löst religiös '
      'unpassende Ehen und kann den Kurfürstensitz kosten. '
      'Wirklich wechseln?',
  'menus.change': 'Wechseln',
  'menus.electors': 'Kurfürsten',
  'menus.free': 'gratis',
  'menus.needSeatBuilding':
      'Du brauchst eine eigene Stadt, Burg oder einen Palast !',
  'menus.dynastyOf': 'Dynastie von {realm}',
  'menus.childCount': '{n} Kind',
  'menus.childrenCount': '{n} Kinder',
  'menus.single': 'ledig',
  'menus.married': 'verheiratet',
  'menus.marriedToCommoner': 'verheiratet mit {name} (bürgerlich)',
  'menus.marriedTo': 'verheiratet mit {name} von {realm}',
  // --- Marriage ---
  'menus.noPartner': 'Es gibt zur Zeit keinen passenden Partner !',
  'menus.whoShallMarry': 'Wer aus deiner Dynastie soll heiraten?',
  'menus.partnerFor': 'Partner für {name} ({age})',
  'menus.marriageProposal': 'Heiratsantrag',
  'menus.proposalPending':
      'Der Antrag wird überbracht — die Antwort folgt im nächsten Zug.',
  'menus.proposalUnderway': 'Der Antrag wird überbracht …',
  'menus.accepted': 'Angenommen !',
  'menus.rejected': 'Abgelehnt !',
  // --- Info ---
  'menus.myRealm': 'Mein Reich — {realm}',
  'menus.armyStat': 'Armee: {n}',
  'menus.moraleStat':
      'Kampfmoral: +{attack} % Angriff / +{defence} % Verteidigung',
  'menus.settlements': 'Siedlungen ({n})',
  'menus.dynasties': 'Dynastien',
  'menus.dynastiesSubtitle': 'Alle Reiche und ihre Herrscherhäuser',
  'menus.chronicleSubtitle': 'Alle bisherigen Kaiser und Sultane',
  'menus.version': 'Version {version}',
  'menus.saveFormat': 'Spielstand-Format v{version}',
  'menus.settlementsOf': 'Siedlungen von {realm}',
  'menus.noSettlements': 'Du hast keine Siedlungen !',
  'menus.settlementSubtitle':
      '{pop} Einwohner — Garnison {garrison}/{cap} — Feld ({x}, {y})',
  'menus.ofRealm': ' von {realm}',
  'menus.noKaiserYet': 'Noch wurde kein Kaiser gekrönt.',
  'menus.kaiser': 'Kaiser',
  'menus.sultans': 'Sultane',
  'menus.dynastiesTitle': 'Dynastien — Reiche nach Größe',
  'menus.youTag': ' (du)',
  'menus.realmSizeLine': '{tiles} Felder — {towns} Siedlungen',
  'menus.ownRealmInfo': '{title} — {pop} Einwohner, {treasury} T, Armee {army}',
  'menus.noIntel': '{title} — keine Informationen (Spione aussenden!)',
  'menus.intelNoTroops': 'keine Truppen',
  'menus.intelTroop': '{n} Truppe (auf der Karte sichtbar)',
  'menus.intelTroops': '{n} Truppen (auf der Karte sichtbar)',
  'menus.intelTreasury': 'Schatzkammer ~{n} T',
  'menus.intelGrain': 'Korn ~{n}',
  'menus.intelCattle': 'Vieh ~{n}',
  'menus.intelPopulation': '~{n} Einwohner',
  'menus.intelArmy': 'Armee ~{n} Mann',
  'menus.intelGuards': 'Spionageabwehr ~{n}',
  'menus.intelLine': 'Spionage Anno {year}: {parts}',
  // --- Stammbaum (family tree modal) ---
  'menus.familyTree': 'Stammbaum',
  'menus.familyTreeSubtitle': 'Dein Herrscherhaus als Baum',
  'menus.familyTreeOf': 'Stammbaum — {realm}',
  'menus.familyTreeStats': '{n} Personen — {g} Generationen',
  'menus.familyTreeEmpty': 'Diese Dynastie ist erloschen.',
  'menus.familyTreeFit': 'Ganzen Baum zeigen',
  'menus.familyTreeHint': 'Ziehen und zoomen zum Erkunden',
  'menus.legendRuler': 'Herrscher',
  'menus.legendHeir': 'Thronfolger',
  'menus.legendSpouse': 'Verheiratet',
  'menus.legendElector': 'Kurfürst',
  'menus.commonerTag': 'bürgerlich',
  'menus.ageYears': '{n} Jahre',
  // --- Shared controls ---
  'menus.ok': 'OK',
  'menus.back': 'Zurück',
};

const Map<String, String> menusEn = {
  // --- Commerce ---
  'menus.surplusMarketPrice': 'Surplus: {surplus} — market price {price} T',
  'menus.taxesTitle': 'Taxes: {rate}%',
  'menus.percentSuffix': '%',
  'menus.taxesSubtitle':
      'Higher taxes bring more money but lower popularity',
  'menus.investMax': 'Maximum: {max} T (harbors: {harbors})',
  'menus.sendMoney': 'Send money',
  'menus.sendMoneySubtitle': 'Transfer Taler to another realm',
  'menus.taler': 'Taler',
  'menus.mergeWith': 'Merge realms: {realm}',
  'menus.transferRealm': 'Transfer realm',
  'menus.transferRealmSubtitle': 'Hand the entire realm to a foreign ruler',
  'menus.transferConfirm': 'Transfer the realm to {realm}?',
  'menus.transferConfirmBody':
      'Land, towns, troops, ships, treasury and dynasty pass to the foreign '
      'ruler. This cannot be undone!',
  'menus.transferTiles': 'Transfer tiles',
  'menus.transferTilesSubtitle':
      'Hand individual tiles to a foreign realm',
  'menus.transferTilePickHint':
      'Tap tiles, or long-press and drag to select them',
  'menus.transferTileHintCount': '{hint} — {n} selected',
  'menus.transferTileOwnOnly':
      'Only your own tiles can be transferred',
  'menus.notMidWar': 'Not in the midst of war!',
  'menus.yields': 'yields {amount} T',
  'menus.investDetail': 'Stake {amount} T — the returns arrive next turn',
  // --- Military ---
  'menus.recruitSubtitle':
      '{cost} T per man — free capacity: {capacity} — levy this year: {levy}',
  'menus.soeldnerSubtitle': '{cost} T per man (plus wages)',
  'menus.costs': 'costs {cost} T',
  'menus.costPerMan': '{cost} T per man',
  'menus.troopList': 'Troop roster ({n})',
  'menus.armyMen': 'Army: {n} men',
  'menus.warOncePerYear': 'Once per year — neighbors only',
  'menus.stationWhere': 'Where shall the troops be stationed?',
  'menus.capital': 'Capital',
  'menus.tileAt': 'Tile ({x}, {y})',
  'menus.pickTile': 'Choose a tile',
  'menus.pickTileSubtitle': 'Tap one of your own tiles on the map',
  'menus.pickTileHint': 'Tap a tile for the new troops',
  'menus.stationOwnTerritory':
      'You must station your troops on your own territory!',
  'menus.recruitsName': 'Recruits',
  'menus.troopNameLabel': 'Troop name',
  'menus.levyExhausted': 'Your people can spare no more recruits this year!',
  'menus.notEnoughTaler': 'You do not have enough Taler!',
  'menus.recruitCostDetail': 'costs {cost} T — strength {strength}',
  'menus.troopListTitle': 'Troop roster — army: {n} men',
  'menus.troopTitle': '{name} — {men} men',
  'menus.soeldnerTag': ' (Söldner)',
  'menus.troopSubtitle': '{cls}{tag} — strength {strength} — tile ({x}, {y})',
  'menus.autoWarStance': 'Conduct in automatic war',
  'menus.stanceHold': 'Hold',
  'menus.stanceAttack': 'Attack',
  'menus.stanceHoldDesc':
      'Defends the base; attacks only once the enemy has no troops left.',
  'menus.stanceAttackDesc':
      'Marches at once upon the chosen march target — '
      'without one, upon the enemy royal seat.',
  'menus.moveTroop': 'Relocate troops',
  'menus.moveTroopSubtitle': 'Free — tap the destination tile on the map',
  'menus.moveTroopHint': 'Tap the destination tile for "{name}"',
  'menus.transferTroop': 'Transfer troop',
  'menus.transferTroopSubtitle': 'Hand over to another realm',
  'menus.transferTroopConfirm': 'Transfer troop to {realm}?',
  'menus.transferTroopConfirmBody':
      '"{name}" ({men} men) will be handed over to {realm}.',
  'menus.reinforceTroop': 'Reinforce troops',
  'menus.drillTroop': 'Drill troops',
  'menus.soeldnerNoDrill': 'Söldner cannot be drilled',
  'menus.fullyDrilled': 'Already fully drilled (quality {quality})',
  'menus.drillDetail': '{cost} T — quality {from} → {to}',
  'menus.retrainTroop': 'Retrain troops',
  'menus.soeldnerNoRetrain': 'Söldner cannot be retrained',
  'menus.retrainSubtitle': 'Change class — {cost} T per man plus surcharge',
  'menus.mergeWithTroop': 'Merge with "{name}" ({men} men)',
  'menus.renameTroop': 'Rename troops',
  'menus.disbandTroop': 'Disband troops',
  'menus.disbandTroopQuestion': 'Disband troops?',
  'menus.disbandTroopConfirm': '"{name}" ({men} men) will be disbanded.',
  'menus.disband': 'Disband',
  'menus.retrainTitle': 'Retrain "{name}" — current strength {strength}',
  'menus.retrainTo': 'Retrain to {cls}',
  'menus.retrainDetail': 'costs {cost} T — new strength {strength}',
  'menus.noSharedBorder': 'You share no border with another realm!',
  'menus.unknown': 'unknown',
  'menus.declareWarOn': 'Declare war: {realm}?',
  // --- Espionage ---
  'menus.spyEconomy': 'Spy on records',
  'menus.spyMilitary': 'Spy on troops',
  'menus.assassinate': 'Stage an assassination',
  'menus.costPerAgent': '{cost} T per agent',
  'menus.guardsLevel': 'Guards: {level} / {cap}',
  'menus.dismissFree': 'Dismissal is free',
  'menus.agents': 'Agents',
  'menus.agentsDetail': 'costs {cost} T — more agents, better odds',
  'menus.spyTitle': 'Espionage — {realm}',
  'menus.spiesUnderway': 'The spies are on their way …',
  'menus.spyCaughtOne':
      'The mission has failed! One of your spies was captured — under '
      'torture he confesses to having been sent from {realm}!!!',
  'menus.spyCaughtMany':
      'The mission has failed! {caught} of your spies were captured — one '
      'confesses under torture to having been sent from {realm}!!!',
  'menus.spyNothing': 'Your spies could learn nothing!',
  'menus.spySuccess':
      'Mission successful! Find the report under Info → Dynasties.',
  'menus.assassinConfirm': 'Assassination attempt on {realm} — really?',
  'menus.assassinOrdered': 'Assassination ordered',
  'menus.assassinUnderway':
      'The assassins are on their way!!!\n\n'
      'Whether the deed succeeds you will learn in one of the coming turns.',
  'menus.assassinAlready': 'Assassins already sent this turn',
  'menus.assassinRisk':
      'An attempt stays a gamble — more assassins improve the odds, but '
      'the target\'s bodyguard catches many of them. If one is caught, he '
      'names you under torture for all the world to hear.',
  // --- Dynasty & misc ---
  'menus.nobodyMarriageable': 'No one in your dynasty can marry!',
  'menus.allProposed': 'Everyone has already proposed this turn!',
  'menus.dynastySubtitle':
      '{n} members — foreign dynasties under Info → Dynasties',
  'menus.marryCommoner': 'Marry a commoner',
  'menus.marryCommonerSubtitle': 'Wed someone of the common folk',
  'menus.plunderTreasury': 'Plunder the state coffers',
  'menus.kaiserPot': '{amount} T in the crown treasure',
  'menus.sultanPot': "{amount} T in the Sultan's treasure",
  'menus.relocateSeat': 'Relocate seat',
  'menus.relocateSeatLost':
      'Seat lost — choose a new town, castle or palace (free)',
  'menus.relocateSeatSubtitle':
      '{cost} T — choose one of your towns, castles or palaces',
  'menus.relocateSeatMapHint':
      'Tap a town, castle or palace on the map ({cost} T)',
  'menus.relocateSeatMapHintLost':
      'Tap a town, castle or palace on the map (free)',
  'menus.religionCatholic': 'Catholic',
  'menus.religionProtestant': 'Protestant',
  'menus.religionMuslim': 'Muslim',
  'menus.religionOption': 'Religion: {religion}',
  'menus.religionCost': '{cost} T, −{pop} popularity',
  'menus.changeReligionQuestion': 'Change religion?',
  // English needs no adjective declension — the {faith}en trick is
  // German-only; here {faith} stands alone.
  'menus.religionConfirmBody':
      'Your dynasty converts to the {faith} faith.\n\n'
      'This costs {cost} T and {pop} popularity, dissolves religiously '
      'mismatched marriages and can cost the Elector seat. Really convert?',
  'menus.change': 'Convert',
  'menus.electors': 'Electors',
  'menus.free': 'free',
  'menus.needSeatBuilding': 'You need a town, castle or palace of your own!',
  'menus.dynastyOf': 'Dynasty of {realm}',
  'menus.childCount': '{n} child',
  'menus.childrenCount': '{n} children',
  'menus.single': 'unwed',
  'menus.married': 'married',
  'menus.marriedToCommoner': 'married to {name} (commoner)',
  'menus.marriedTo': 'married to {name} of {realm}',
  // --- Marriage ---
  'menus.noPartner': 'There is no suitable match at present!',
  'menus.whoShallMarry': 'Who of your dynasty shall marry?',
  'menus.partnerFor': 'A match for {name} ({age})',
  'menus.marriageProposal': 'Marriage proposal',
  'menus.proposalPending':
      'The proposal is being delivered — the answer follows next turn.',
  'menus.proposalUnderway': 'The proposal is being delivered …',
  'menus.accepted': 'Accepted!',
  'menus.rejected': 'Rejected!',
  // --- Info ---
  'menus.myRealm': 'My realm — {realm}',
  'menus.armyStat': 'Army: {n}',
  'menus.moraleStat': 'Morale: +{attack}% attack / +{defence}% defence',
  'menus.settlements': 'Settlements ({n})',
  'menus.dynasties': 'Dynasties',
  'menus.dynastiesSubtitle': 'All realms and their ruling houses',
  'menus.chronicleSubtitle': 'All Kaisers and Sultans to date',
  'menus.version': 'Version {version}',
  'menus.saveFormat': 'Save format v{version}',
  'menus.settlementsOf': 'Settlements of {realm}',
  'menus.noSettlements': 'You have no settlements!',
  'menus.settlementSubtitle':
      '{pop} inhabitants — garrison {garrison}/{cap} — tile ({x}, {y})',
  'menus.ofRealm': ' of {realm}',
  'menus.noKaiserYet': 'No Kaiser has been crowned yet.',
  'menus.kaiser': 'Kaiser',
  'menus.sultans': 'Sultans',
  'menus.dynastiesTitle': 'Dynasties — realms by size',
  'menus.youTag': ' (you)',
  'menus.realmSizeLine': '{tiles} tiles — {towns} settlements',
  'menus.ownRealmInfo':
      '{title} — {pop} inhabitants, {treasury} T, army {army}',
  'menus.noIntel': '{title} — no intelligence (send out spies!)',
  'menus.intelNoTroops': 'no troops',
  'menus.intelTroop': '{n} troop (visible on the map)',
  'menus.intelTroops': '{n} troops (visible on the map)',
  'menus.intelTreasury': 'treasury ~{n} T',
  'menus.intelGrain': 'grain ~{n}',
  'menus.intelCattle': 'cattle ~{n}',
  'menus.intelPopulation': '~{n} inhabitants',
  'menus.intelArmy': 'army ~{n} men',
  'menus.intelGuards': 'guards ~{n}',
  'menus.intelLine': 'Espionage Anno {year}: {parts}',
  // --- Stammbaum (family tree modal) ---
  'menus.familyTree': 'Family tree',
  'menus.familyTreeSubtitle': 'Your ruling house as a tree',
  'menus.familyTreeOf': 'Family tree — {realm}',
  'menus.familyTreeStats': '{n} people — {g} generations',
  'menus.familyTreeEmpty': 'This dynasty has died out.',
  'menus.familyTreeFit': 'Show the whole tree',
  'menus.familyTreeHint': 'Drag and pinch to explore',
  'menus.legendRuler': 'Ruler',
  'menus.legendHeir': 'Heir',
  'menus.legendSpouse': 'Married',
  'menus.legendElector': 'Elector',
  'menus.commonerTag': 'commoner',
  'menus.ageYears': '{n} years',
  // --- Shared controls ---
  'menus.ok': 'OK',
  'menus.back': 'Back',
};
