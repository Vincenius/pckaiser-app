/// String-table part for the "tutorial" UI area — merged into the app-wide
/// table in `l10n/strings.dart`. Keys are prefixed `tut.`; `{name}`-style
/// placeholders are filled by `tr(key, params)`. Steps that name a menu
/// entry receive it as a param (`tr('commerce')`, `tr('recruit')`, …) so
/// the tutorial can never drift from the live menu wording.
const Map<String, String> tutorialDe = {
  'tut.welcomeTitle': 'Willkommen, Ritter!',
  // {realm} = realmName(1), the tutorial's fixed starting realm.
  'tut.welcomeBody':
      'Du herrschst über {realm}, eines von 30 Reichen. Ziel des '
      'Spiels: Erhebe deine Dynastie vom Ritter zum Kaiser und '
      'werde alleiniger Herrscher des ganzen Landes.\n\n'
      'Die Karte: Ziehe mit dem Finger, zoome mit zwei '
      'Fingern. Die Fahne markiert deinen Königssitz (deine Burg).',
  'tut.statsTitle': 'Deine Werte',
  'tut.statsBody':
      'Oben links steht, welches Reich gerade am Zug ist, oben rechts '
      'das aktuelle Jahr (Kalender), deine Taler (Münze), deine '
      'verbleibenden Züge (Hammer) und deine Beliebtheit (Herz) — '
      'tippe eines von beidem an für alle Werte deines Reichs '
      '("Mein Reich"). '
      'Bauen und Erweitern auf der Karte kostet einen Zug, Truppen '
      'verlegen ist kostenlos. Die Züge werden jede Runde neu '
      'gewürfelt: je beliebter du beim Volk bist, desto mehr. '
      'Der Pfeil unten rechts macht Aktionen innerhalb des Zuges '
      'rückgängig.',
  'tut.buildTitle': 'Bauen & Erweitern',
  'tut.buildBody':
      'Dein Reich wächst, indem du auf freien Feldern neben deinem '
      'Gebiet baust: Kornfelder (100 T) und Weiden (150 T) ernähren '
      'das Volk, Dörfer (1000 T) bringen Einwohner und Steuern, '
      'Häfen (700 T) erlauben Handelsschiffe. In einem Hafen kannst '
      'du außerdem ein Schiff kaufen (700 T) und über See steuern '
      '(1 Zug pro Feld) — steuerst du ein freies Landfeld an, '
      'gründet das Schiff dort ein Dorf: so kolonisierst du '
      'z. B. Inseln.',
  'tut.buildTask':
      'Tippe ein freies Feld neben deinem Gebiet an und baue '
      'ein Kornfeld oder eine Weide.',
  'tut.tradeBody':
      'Überschüssiges Korn und Vieh verkaufst du auf dem Markt — '
      'die Preise schwanken von Jahr zu Jahr. Mit einem Hafen kannst '
      'du außerdem Handelsschiffe aussenden — ihr Ertrag kehrt zu '
      'Beginn der nächsten Runde zurück.',
  // {menu} = tr('commerce').
  'tut.tradeTask': 'Öffne unten „{menu}" und verkaufe Korn oder Rinder.',
  'tut.militaryBody':
      'Truppen schützen dein Reich und führen Kriege: Rekruten kosten '
      '5 T pro Mann (Söldner 50 T), die Kapazität kommt aus deinen '
      'Siedlungen. Pro Jahr hebt dein Volk höchstens 10 % der '
      'Bevölkerung aus (mind. 100 Mann) — nur Söldner sind unbegrenzt. '
      'Bestehende Truppen kannst du ausbilden (Kosten '
      'steigen pro Level: 5 T/Mann × Stufe) oder zu Kavallerie/Artillerie '
      'umrüsten — die angezeigte Stärke entscheidet den Kampf. Dazu '
      'kommen Boni: Burgen (+15 %) und Paläste (+25 %) schützen ihre '
      'Besatzung, Artillerie schwächt diese Boni und belagert am besten; '
      'Infanterie schlägt Kavallerie, Kavallerie schlägt Artillerie, '
      'Artillerie schlägt Infanterie. Aber Vorsicht: Das Volk verübelt '
      'dir Aushebungen und Kriege (Beliebtheit sinkt) — wer Jahr für Jahr '
      'Krieg führt, dessen Volk erholt sich nicht mehr und erhebt sich '
      'irgendwann. Krieg erklären kannst du ab dem Jahr 1010 — nur '
      'Nachbarn, einmal pro Jahr, und nach jedem Krieg gilt ein Jahr '
      'Waffenruhe zwischen den beiden Reichen.',
  // {military} = tr('military'), {recruit} = tr('recruit').
  'tut.militaryTask':
      'Öffne „{military}" → „{recruit}" und stationiere '
      'Rekruten am Hauptsitz.',
  'tut.espionageBody':
      'Andere Reiche sind verdeckt: Schatzkammer, Truppen und Vorräte '
      'siehst du nur durch Spione (200 T pro Agent, ungefähre Werte — '
      'je mehr Agenten, desto bessere Chancen). Ausspionierte Armeen '
      'erscheinen blass auf der Karte (Stand des Spionagejahres). '
      'Attentäter (250 T pro Agent) können fremde Herrscher beseitigen. '
      'Die Spionageabwehr (100 T pro Mann) schützt dich vor beidem.',
  // {menu} = tr('misc') — the "Dynastie"/"Dynasty" bottom menu.
  'tut.dynastyBody':
      'Unter „{menu}" verwaltest du dein Herrscherhaus: Heirate in '
      'fremde Häuser ein oder bürgerlich — ohne Erben stirbt deine '
      'Dynastie aus und das Spiel ist für dich verloren. Der „Stammbaum" '
      'zeigt dein Haus mit Krone und Thronfolger. Die Kurfürsten wählen '
      'den Kaiser; Titel steigen mit der Größe deines Reichs.',
  // {endTurn} = tr('endTurn').
  'tut.endTurnBody':
      'Mit „{endTurn}" unten rechts schließt du deinen Zug ab: die '
      'anderen Reiche spielen, ein Jahr vergeht, und Ernte, Steuern und '
      'Ereignisse werden abgerechnet. Sind noch Bauzüge offen, fragt das '
      'Spiel vorher nach — ungenutzte Züge verfallen. Jeder abgeschlossene '
      'Zug wird automatisch gespeichert, und zu Beginn des nächsten Zuges fasst '
      'eine Übersicht zusammen, was seither geschah.',
  'tut.readyTitle': 'Bereit zur Herrschaft',
  // {info} = tr('info'), {finish} = tr('tut.finish').
  'tut.readyBody':
      'Das waren die Grundlagen! Alles Weitere findest du unter '
      '„{info}": Ereignisse, Siedlungen, Dynastien und die Kaiserchronik. '
      'Verlassen kannst du das Spiel jederzeit über das rote Symbol '
      'links in der Leiste unten.\n\n'
      'Diese Übungspartie wird nicht gespeichert — mit „{finish}" '
      'kehrst du zum Hauptmenü zurück und kannst dein '
      'erstes richtiges Spiel starten.',
  // Overlay chrome.
  'tut.chip': 'Tutorial {step}/{total}',
  'tut.header': 'Tutorial — Schritt {step} von {total}',
  'tut.minimize': 'Minimieren',
  'tut.skip': 'Überspringen',
  'tut.next': 'Weiter',
  'tut.finish': 'Tutorial abschließen',
  'tut.quitTooltip': 'Tutorial beenden',
  'tut.quitTitle': 'Tutorial beenden?',
  'tut.quitBody':
      'Du kehrst zum Hauptmenü zurück. Die '
      'Übungspartie wird nicht gespeichert.',
  'tut.quitConfirm': 'Beenden',
};

const Map<String, String> tutorialEn = {
  'tut.welcomeTitle': 'Welcome, knight!',
  'tut.welcomeBody':
      'You rule {realm}, one of 30 realms. The goal of the game: raise '
      'your dynasty from knight to Kaiser and become sole ruler of the '
      'whole land.\n\n'
      'The map: drag with one finger, zoom with two. The flag marks '
      'your royal seat (your castle).',
  'tut.statsTitle': 'Your stats',
  'tut.statsBody':
      'At the top left you see whose realm is on turn, at the top right '
      'the current year (calendar), your Taler (coin), your remaining '
      'moves (hammer) and your popularity (heart) — tap either for all '
      'of your realm\'s stats ("My realm"). Building and expanding on the map '
      'costs one move, moving troops is free. Your moves are re-rolled '
      'every round: the more your people love you, the more you get. '
      'The arrow at the bottom right undoes actions within the current '
      'turn.',
  'tut.buildTitle': 'Build & expand',
  'tut.buildBody':
      'Your realm grows by building on free fields next to your '
      'territory: grain fields (100 T) and pastures (150 T) feed the '
      'people, villages (1000 T) bring inhabitants and taxes, harbors '
      '(700 T) allow trade ships. In a harbor you can also buy a ship '
      '(700 T) and steer it across the sea (1 move per field) — steer '
      'it onto a free land field and the ship founds a village there: '
      'that is how you colonize islands, for example.',
  'tut.buildTask':
      'Tap a free field next to your territory and build '
      'a grain field or a pasture.',
  'tut.tradeBody':
      'Sell surplus grain and cattle at the market — prices fluctuate '
      'from year to year. With a harbor you can also send trade ships '
      '— their profit returns at the start of the next round.',
  'tut.tradeTask': 'Open "{menu}" at the bottom and sell grain or cattle.',
  'tut.militaryBody':
      'Troops protect your realm and fight your wars: recruits cost '
      '5 T per man (Söldner 50 T), capacity comes from your '
      'settlements. Each year your people muster at most 10 % of the '
      'population (at least 100 men) — only Söldner are unlimited. '
      'Existing troops can be drilled (costs rise per level: '
      '5 T/man × level) or converted to cavalry/artillery — the '
      'displayed strength decides the battle. On top come bonuses: '
      'castles (+15 %) and palaces (+25 %) protect their garrison, '
      'artillery weakens these bonuses and is best at sieges; '
      'infantry beats cavalry, cavalry beats artillery, artillery '
      'beats infantry. But beware: the people resent levies and wars '
      '(popularity drops) — war year after year and their mood never '
      'recovers, until they rise up. You can declare war from the year '
      '1010 — only on neighbors, once per year, and every war is followed '
      'by a year of truce between the two realms.',
  'tut.militaryTask':
      'Open "{military}" → "{recruit}" and station '
      'recruits at your capital.',
  'tut.espionageBody':
      'Other realms are hidden: you only see their treasury, troops '
      'and stores through spies (200 T per agent, approximate figures '
      '— the more agents, the better your chances). Spied-out armies '
      'appear faded on the map (as of the espionage year). Assassins '
      '(250 T per agent) can remove foreign rulers. Guards (100 T per '
      'man) protect you from both.',
  'tut.dynastyBody':
      'Under "{menu}" you manage your ruling house: marry into foreign '
      'houses or marry a commoner — without an heir your dynasty dies '
      'out and the game is lost for you. The "Family tree" shows your '
      'house with its crown and heir. The Electors choose the Kaiser; '
      'titles rise with the size of your realm.',
  'tut.endTurnBody':
      'With "{endTurn}" at the bottom right you complete your turn: '
      'the other realms play, a year passes, and harvest, taxes and '
      'events are settled. With build moves still unspent the game asks '
      'first — unused moves expire. Every completed turn is saved '
      'automatically, and at the start of your next turn a summary '
      'recaps what has happened since.',
  'tut.readyTitle': 'Ready to rule',
  'tut.readyBody':
      'Those were the basics! Everything else is under "{info}": '
      'events, settlements, dynasties and the Kaiser chronicle. You '
      'can leave the game at any time via the red icon on the left of '
      'the bottom bar.\n\n'
      'This practice game is not saved — "{finish}" returns you to '
      'the main menu, where you can start your first real game.',
  // Overlay chrome.
  'tut.chip': 'Tutorial {step}/{total}',
  'tut.header': 'Tutorial — step {step} of {total}',
  'tut.minimize': 'Minimize',
  'tut.skip': 'Skip',
  'tut.next': 'Next',
  'tut.finish': 'Finish tutorial',
  'tut.quitTooltip': 'Quit tutorial',
  'tut.quitTitle': 'Quit the tutorial?',
  'tut.quitBody':
      'You will return to the main menu. The practice game is not '
      'saved.',
  'tut.quitConfirm': 'Quit',
};
