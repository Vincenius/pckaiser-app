/// Localizable, transient player-facing engine messages: [ActionException]
/// texts and validation-reason strings (war-target blockers etc.).
///
/// NOT for strings stored in game state (troop names like 'Söldner',
/// generated person/town names): those are shared state in online games
/// and saved games and must stay identical on every client.
///
/// The German texts are the originals (§23 of ORIGINAL_GAME.md) and must
/// stay EXACTLY as the engine used to throw them.
library;

/// Presentation-only message locale ('de' or 'en'). The client sets it from
/// its UI language; the online server sets it per turn submission to the
/// submitting seat's language (synchronously, right before it applies the
/// action) so a rejection reads in that player's tongue. The engine's
/// deterministic rules never read it except when FORMATTING messages via
/// [coreMessage].
String messageLocale = 'de';

const Map<String, Map<String, String>> _messages = {
  'de': {
    'invalidRealm': 'Ungültiges Reich {slot} !',
    'realmVacant': 'Das Reich ist verwaist !',
    'noMovesLeft': 'Du hast keine Züge mehr !',
    'notEnoughTaler': 'Du hast nicht genügend Taler ! ({cost} benötigt)',
    'tileOffMap': 'Das Feld liegt außerhalb der Karte !',
    'cannotClaimWater': 'Wasser kann nicht beansprucht werden !',
    'tileAlreadyOwned': 'Das Feld hat bereits einen Besitzer !',
    'tileNotAdjacent': 'Das Feld grenzt nicht an dein Territorium !',
    'noSuchShip': 'Dieses Schiff gibt es nicht !',
    'buyShipAtOwnHarbor': 'Schiffe werden in einem eigenen Hafen gekauft !',
    'shipsOnlyOnWater': 'Schiffe fahren nur auf dem Wasser !',
    'notReachableBySea': 'Dieses Feld ist über See nicht erreichbar !',
    'shipAlreadyThere': 'Da liegt das Schiff doch schon !',
    'shipTooFar': 'So weit kommt das Schiff nicht mehr — die Fahrt kostet '
        '{distance} Züge !',
    'shipMustBeAdjacent': 'Das Schiff muß direkt neben dem Feld liegen !',
    'colonizeFreeLandOnly': 'Kolonisiert wird ein freies Landfeld !',
    'villageNeedsName': 'Das Dorf braucht einen Namen !',
    'cannotBuildThat': 'Das kann nicht gebaut werden !',
    'tileNotYours': 'Das Feld gehört dir nicht !',
    'tileAlreadyBuilt': 'Das Feld ist bereits bebaut !',
    'wrongTerrain': 'Falsches Gelände für dieses Bauwerk !',
    'nothingHere': 'Hier steht doch gar nichts !',
    'cannotDemolishTowns': 'Orte können nicht abgerissen werden !',
    'notDuringWar': 'Nicht mitten im Krieg !',
    'cannotMergeRealms': 'Diese Reiche können nicht zusammengelegt werden !',
    'cannotTransferRealm': 'Das Reich kann nicht übertragen werden !',
    'alreadySoldThisTurn': 'Du hast diese Runde schon verkauft !!!',
    'notPossible': 'Das geht nicht !!!',
    'alreadyInvestedThisTurn': 'Du hast diese Runde schon investiert !',
    'invalidTargetRealm': 'Ungültiges Zielreich !',
    'alreadyYourSeat': 'Das ist bereits dein Sitz !',
    'seatOnOwnTerritory': 'Der neue Sitz muss auf deinem Territorium liegen !',
    'seatNeedsSeatBuilding':
        'Der neue Sitz braucht eine Stadt, Burg oder einen Palast !',
    'onlyKaiserOrSultan': 'Nur der Kaiser oder Sultan darf das !',
    'stateTreasuryEmpty': 'Die Staatskasse ist leer !',
    'alreadyProposedThisTurn':
        'Diese Person hat diesen Zug schon einen Antrag gestellt !',
    'personNotFound': 'Person nicht gefunden !',
    'notYourDynasty': 'Diese Person gehört nicht zu deiner Dynastie !',
    'awaitingAnswer': 'Hier wird noch auf eine Antwort gewartet !',
    'noSuitablePartner': 'Es gibt zur Zeit keinen passenden Partner !',
    'decisionNotFound': 'Entscheidung nicht gefunden !',
    'decisionNotYours': 'Diese Entscheidung steht dir nicht zu !',
    'notEnoughTalerBribe':
        'Du hast nicht genügend Taler für diese Bestechung !',
    'voteForCandidate': 'Stimme für einen der Kandidaten !',
    'unknownReligion': 'Unbekannte Religion !',
    'alreadyYourReligion': 'Das ist bereits deine Religion !',
    'reformationNotYet': 'Die Reformation hat noch nicht stattgefunden !',
    'islamNotYet': 'Der Islam ist noch nicht verfügbar !',
    'noSuchTroop': 'Diese Truppe gibt es nicht !',
    'troopCannotTransfer': 'Diese Truppe kann nicht übertragen werden !',
    'noRecruitsThisYear':
        'Deine Bevölkerung gibt dieses Jahr keine weiteren Rekruten her !',
    'fewRecruitsThisYear':
        'Deine Bevölkerung gibt dieses Jahr nur noch {left} Rekruten her !',
    'unknownTroopClass': 'Unbekannte Truppengattung !',
    'notEnoughQuarters': 'Nicht genügend Quartiere in deinen Orten !',
    'stationOnOwnTerritory':
        'Du musst deine Truppen auf deinem Territorium stationieren !',
    'onlyRegularsTrain': 'Nur reguläre Truppen lassen sich ausbilden !',
    'troopFullyDrilled': 'Diese Truppe ist bereits voll ausgebildet !',
    'troopAlreadyTrained': 'Diese Ausbildung hat die Truppe schon !',
    'troopNeedsName': 'Die Truppe braucht einen Namen !',
    'unknownTroopStance': 'Unbekannte Truppenhaltung !',
    'chooseTwoDifferentTroops': 'Wähle zwei verschiedene Truppen !',
    'onlySameKindMerge': 'Nur gleichartige Truppen können vereinigt werden !',
    'warTooEarly': 'Kriege sind erst ab dem Jahr {year} erlaubt !',
    'warAlreadyThisYear': 'Du hast dieses Jahr schon einmal Krieg geführt !',
    'notEnoughTroops': 'Du hast nicht genug Truppen !',
    'anotherWarActive': 'Es tobt bereits ein anderer Krieg !',
    'invalidWarTarget': 'Ungültiges Kriegsziel !',
    'realmAlreadyYourRulers': 'Dieses Reich gehört bereits deinem Herrscher !',
    'noSharedBorder': 'Du hast keine gemeinsame Grenze !',
    'truceActive': 'Waffenruhe bis zum Jahr {year} !',
    'notAtWar': 'Du führst keinen Krieg !',
    'wrongWarPhase': 'Falsche Kriegsphase !',
    'opponentActing': 'Dein Gegner ist gerade am Zug !',
    'impassable': 'Unpassierbar !',
    'embarkViaHarborOnly':
        'Truppen gehen nur über einen eigenen oder feindlichen '
            'Hafen an Bord !',
    'noWarTransitForeignRealms':
        'Durch fremde Reiche darf man im Krieg nicht ziehen !',
    'oneTilePerMove': 'Nur ein Feld pro Zug — gerade, nicht diagonal !',
    'troopCannotMoveThisRound':
        'Diese Truppe kann in dieser Runde nicht weiter ziehen !',
    'troopAlreadyThere': 'Da steht die Truppe doch schon !',
    'noSeaRouteToTarget':
        'Keine Seeverbindung von einem eigenen oder feindlichen Hafen '
            'zu diesem Ziel !',
    'landOnOwnEnemyNeutralCoast':
        'Du kannst nur an eigener, feindlicher oder neutraler Küste landen !',
    'plunderOwnLand': 'Wollen sie wirklich ihr eigenes Land plündern !',
    'notYourWarEnemy': 'Das gehört nicht deinem Kriegsgegner !',
    'noTroopsOnTile': 'Keine Truppen auf diesem Feld !',
    'armyAlreadyPlundered': 'Diese Armee hat diese Runde schon geplündert !',
    'onlyVictorClaims': 'Nur der Sieger stellt Ansprüche !',
    'notYourEnemy': 'Das gehört nicht deinem Feind !',
    'claimTooMuch': 'So viel steht dir nicht zu !',
    'annexOnlyBordering':
        'Du kannst dir nur Felder aneignen, die direkt an dein Land '
            'grenzen !',
    'tooManySpies': 'So viele Spione würden zu sehr auffallen',
    'assassinsAlreadySent':
        'Deine Attentäter sind dieses Jahr schon dorthin unterwegs !',
    'invalidTarget': 'Ungültiges Ziel !',
    'guardsNotArmy': 'Das ist keine Spionageabwehr, sondern eine Armee !!!',
    'notSoManyGuards': 'So viele Wachen hast du nicht !',
    'troopTooWeakToPlunder': 'Diese Truppe ist zum Plündern zu schwach !',
  },
  'en': {
    'invalidRealm': 'Invalid realm {slot}!',
    'realmVacant': 'That realm has no ruler!',
    'noMovesLeft': 'You have no moves left!',
    'notEnoughTaler': 'You do not have enough Taler! ({cost} needed)',
    'tileOffMap': 'That tile lies outside the map!',
    'cannotClaimWater': 'Water cannot be claimed!',
    'tileAlreadyOwned': 'That tile already has an owner!',
    'tileNotAdjacent': 'That tile does not border your territory!',
    'noSuchShip': 'There is no such ship!',
    'buyShipAtOwnHarbor': 'Ships are bought at one of your own harbors!',
    'shipsOnlyOnWater': 'Ships sail only on water!',
    'notReachableBySea': 'That tile cannot be reached by sea!',
    'shipAlreadyThere': 'The ship is already there!',
    'shipTooFar': 'The ship cannot sail that far — the voyage costs '
        '{distance} moves!',
    'shipMustBeAdjacent': 'The ship must lie right next to that tile!',
    'colonizeFreeLandOnly': 'Only a free land tile can be colonized!',
    'villageNeedsName': 'The village needs a name!',
    'cannotBuildThat': 'That cannot be built!',
    'tileNotYours': 'That tile is not yours!',
    'tileAlreadyBuilt': 'That tile is already built on!',
    'wrongTerrain': 'Wrong terrain for this building!',
    'nothingHere': 'There is nothing here!',
    'cannotDemolishTowns': 'Settlements cannot be demolished!',
    'notDuringWar': 'Not in the middle of a war!',
    'cannotMergeRealms': 'These realms cannot be merged!',
    'cannotTransferRealm': 'The realm cannot be transferred!',
    'alreadySoldThisTurn': 'You have already sold this round!!!',
    'notPossible': 'That cannot be done!!!',
    'alreadyInvestedThisTurn': 'You have already invested this round!',
    'invalidTargetRealm': 'Invalid target realm!',
    'alreadyYourSeat': 'That is already your seat!',
    'seatOnOwnTerritory': 'The new seat must lie on your territory!',
    'seatNeedsSeatBuilding': 'The new seat needs a city, castle or palace!',
    'onlyKaiserOrSultan': 'Only the Kaiser or the Sultan may do that!',
    'stateTreasuryEmpty': 'The state treasury is empty!',
    'alreadyProposedThisTurn':
        'This person has already made a proposal this turn!',
    'personNotFound': 'Person not found!',
    'notYourDynasty': 'This person does not belong to your dynasty!',
    'awaitingAnswer': 'An answer is still awaited here!',
    'noSuitablePartner': 'There is no suitable partner at this time!',
    'decisionNotFound': 'Decision not found!',
    'decisionNotYours': 'This decision is not yours to make!',
    'notEnoughTalerBribe': 'You do not have enough Taler for this bribe!',
    'voteForCandidate': 'Vote for one of the candidates!',
    'unknownReligion': 'Unknown religion!',
    'alreadyYourReligion': 'That is already your religion!',
    'reformationNotYet': 'The Reformation has not yet taken place!',
    'islamNotYet': 'Islam is not yet available!',
    'noSuchTroop': 'There is no such troop!',
    'troopCannotTransfer': 'This troop cannot be transferred!',
    'noRecruitsThisYear': 'Your people can spare no more recruits this year!',
    'fewRecruitsThisYear':
        'Your people can spare only {left} more recruits this year!',
    'unknownTroopClass': 'Unknown troop class!',
    'notEnoughQuarters': 'Not enough quarters in your settlements!',
    'stationOnOwnTerritory':
        'You must station your troops on your own territory!',
    'onlyRegularsTrain': 'Only regular troops can be trained!',
    'troopFullyDrilled': 'This troop is already fully trained!',
    'troopAlreadyTrained': 'This troop already has that training!',
    'troopNeedsName': 'The troop needs a name!',
    'unknownTroopStance': 'Unknown troop stance!',
    'chooseTwoDifferentTroops': 'Choose two different troops!',
    'onlySameKindMerge': 'Only troops of the same kind can be united!',
    'warTooEarly': 'Wars are not allowed before the year {year}!',
    'warAlreadyThisYear': 'You have already waged war this year!',
    'notEnoughTroops': 'You do not have enough troops!',
    'anotherWarActive': 'Another war is already raging!',
    'invalidWarTarget': 'Invalid war target!',
    'realmAlreadyYourRulers': 'That realm already belongs to your ruler!',
    'noSharedBorder': 'You share no common border!',
    'truceActive': 'Truce until the year {year}!',
    'notAtWar': 'You are not waging a war!',
    'wrongWarPhase': 'Wrong war phase!',
    'opponentActing': 'Your opponent is making their move!',
    'impassable': 'Impassable!',
    'embarkViaHarborOnly':
        'Troops can only embark through your own or an enemy harbor!',
    'noWarTransitForeignRealms':
        'You may not march through foreign realms in war!',
    'oneTilePerMove': 'Only one tile per move — straight, not diagonal!',
    'troopCannotMoveThisRound':
        'This troop cannot move any further this round!',
    'troopAlreadyThere': 'The troop is already there!',
    'noSeaRouteToTarget':
        'No sea route from your own or an enemy harbor to that '
            'destination!',
    'landOnOwnEnemyNeutralCoast':
        'You can only land on your own, enemy or neutral coast!',
    'plunderOwnLand': 'Do you really wish to plunder your own land!',
    'notYourWarEnemy': 'That does not belong to your war enemy!',
    'noTroopsOnTile': 'No troops on this tile!',
    'armyAlreadyPlundered': 'This army has already plundered this round!',
    'onlyVictorClaims': 'Only the victor makes claims!',
    'notYourEnemy': 'That does not belong to your enemy!',
    'claimTooMuch': 'You are not entitled to that much!',
    'annexOnlyBordering':
        'You can only seize tiles that directly border your own land!',
    'tooManySpies': 'That many spies would draw too much attention',
    'assassinsAlreadySent':
        'Your assassins are already on their way there this year!',
    'invalidTarget': 'Invalid target!',
    'guardsNotArmy': 'That is not counter-espionage, that is an army!!!',
    'notSoManyGuards': 'You do not have that many guards!',
    'troopTooWeakToPlunder': 'This troop is too weak to plunder!',
  },
};

/// Formats the message [key] in the current [messageLocale], substituting
/// `{name}` placeholders from [params]. Falls back to German, then to the
/// key itself, so an unknown key can never crash message formatting.
String coreMessage(String key, [Map<String, Object?>? params]) {
  final catalog = _messages[messageLocale] ?? _messages['de']!;
  final text = catalog[key] ?? _messages['de']![key] ?? key;
  return formatTemplate(text, params);
}

/// Substitutes `{name}` placeholders in [template] from [params]. Shared by
/// the engine's [coreMessage] and the client's `tr()` so both catalogs
/// format identically.
String formatTemplate(String template, [Map<String, Object?>? params]) {
  if (params == null) return template;
  var text = template;
  params.forEach((name, value) {
    text = text.replaceAll('{$name}', '$value');
  });
  return text;
}
