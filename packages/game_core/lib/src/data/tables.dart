/// Data tables, verbatim from the original game data (ORIGINAL_GAME.md §22).
library;

/// European male first names — 50 entries (§22.1).
const List<String> europeanMaleNames = [
  'Siegfried', 'Johann', 'Richard', 'Nepomuk', 'Gerald', 'Gernot',
  'Emmerich', 'Phillip', 'Engelbert', 'Martin', 'Klemens', 'Bernhard',
  'Christoph', 'Willibald', 'Lorenz', 'Leopold', 'Friedrich', 'Heinrich',
  'Ludwig', 'Hagen', 'Günther', 'Franz', 'Josef', 'Karl', 'Rudolf',
  'Maximilian', 'Tobias', 'Horst', 'Lukas', 'Ignaz', 'Georg', 'Alois',
  'Kurt', 'Robert', 'Roland', 'Christian', 'Paul', 'Florian', 'Alexander',
  'Napoleon', 'Christoph', 'Andreas', 'Stefan', 'Iwan', 'Thomas', 'Arthur',
  'Mathias', 'Xaver', 'Walter', 'Viktor',
];

/// European female first names — 50 entries (§22.1).
const List<String> europeanFemaleNames = [
  'Isolde', 'Sieglinde', 'Gudrun', 'Brunhild', 'Maria', 'Kriemhild',
  'Andrea', 'Minna', 'Emilia', 'Constanze', 'Ludmilla', 'Simone',
  'Dorothea', 'Theresa', 'Margarete', 'Anna', 'Isabella', 'Irmgard',
  'Lisa', 'Elisabeth', 'Helga', 'Gabriele', 'Helena', 'Agnes', 'Lea',
  'Katharina', 'Clara', 'Claudia', 'Barbara', 'Monika', 'Susanne',
  'Astrid', 'Tina', 'Martina', 'Klementine', 'Lorentia', 'Alexandra',
  'Sigrid', 'Ulrike', 'Florentina', 'Daniela', 'Doris', 'Josefine',
  'Maria Theresia', 'Annette', 'Roswitha', 'Hertha', 'Christine', 'Ruth',
  'Marilies',
];

/// Ottoman male names — 10 entries, for Muslim dynasties (§22.2).
/// "Saddam" and "Hussein" are separate entries in the original data.
const List<String> ottomanMaleNames = [
  'Mohammed', 'Ali', 'Saddam', 'Hussein', 'Suleiman', 'Aziz', 'Hassan',
  'Tarek', 'Kemal', 'Anwar',
];

/// Ottoman female names — 10 entries; "Fatima" appears twice in the
/// original data (§22.2).
const List<String> ottomanFemaleNames = [
  'Fatima', 'Benazir', 'Asi', 'Sherezade', 'Suha', 'Selina', 'Farida',
  'Myriam', 'Fatima', 'Sara',
];

/// Country names, index 0–31 (§22.3). Index = realm slot; [0] is the
/// "Niemand" sentinel, [31] the Islamic-coded placeholder.
const List<String> countryNames = [
  'Niemand', 'Brandenburg', 'Hessen', 'Bayern', 'Böhmen', 'Sachsen',
  'Mähren', 'Tirol', 'Kurpfalz', 'Flandern', 'Österreich', 'Steiermark',
  'Kärnten', 'Krain', 'Görz', 'Oberpfalz', 'Pommern', 'Mecklenburg',
  'Schlesien', 'Holstein', 'Schwaben', 'Lothringen', 'Isenburg', 'Holland',
  'Friesland', 'Luxemburg', 'Liechtenstein', 'Lüneburg', 'Zweibrücken',
  'Oldenburg', 'Brabant', 'Ben Mohammed',
];

/// City names — 30 entries, the suggested first-Dorf name per country
/// (index = realm slot − 1; Berlin ↔ Brandenburg, …) (§22.4).
const List<String> cityNames = [
  'Berlin', 'Kassel', 'München', 'Prag', 'Dresden', 'Brünn', 'Innsbruck',
  'Heidelberg', 'Brügge', 'Wien', 'Graz', 'Klagenfurt', 'Laibach', 'Görz',
  'Trausnitz', 'Stettin', 'Schwerin', 'Breslau', 'Kiel', 'Augsburg',
  'Münster', 'Isenburg', 'Amsterdam', 'Emden', 'Luxemburg', 'Vaduz',
  'Lüneburg', 'Zweibrücken', 'Oldenburg', 'Brüssel',
];

/// Place names — 101 entries used for generated towns (§22.9). Several
/// entries are deliberate jokes in the original data — kept verbatim.
const List<String> placeNames = [
  'St.Jakob', 'Mühlwald', 'Waldzell', 'Tiefenbrunn', 'Zelling', 'Inzendorf',
  'St.Martin am Wald', 'Lunz am See', 'Obergurgel', 'Unterwalden', 'Schwyz',
  'Kleinwals', 'Unterbach', 'Grossklein', 'Vorderbrunn', 'Hinterwald',
  'Ochsenboden', 'Waldgrund', 'Ofenberg', 'Schlitters', 'Moosling',
  'Mehlgrube', 'Zell', 'Bruck', 'Hamburg', 'Bärlin', 'Bonn', 'Krumpendorf',
  'Neusiedl', 'Seewalchen', 'Holzbach', 'Pforzheim', 'Schweinfurt',
  'Frankfurt', 'Freiburg', 'Dusseldorf', 'Bayreuth', 'Miesmuschel',
  'Venedig', 'Nuremburge', 'Kölln', 'Mühlbach', 'St. Lorenz',
  'Franzensburg', 'Deutsch Wagram', 'Piefkina', 'Witzelsbrunn',
  'Witgenstein', 'Wasselsbrunn', 'Brunn', 'Bern', 'Rhinomarien',
  'Schweinebacke', 'Buchwurmingen', 'Tarantelstich', 'Saupaß',
  'Dreikirchen', 'Grinz', 'Wurzelbach', 'Mahlbeck', 'Abrahamsburg',
  'Johannesburg', 'Schiftdruck', 'Petersburg', 'Schönburg', 'Schöndorf',
  'Posingen', 'Burgen', 'Branzheim', 'Kukshafen', 'Kopenhafen',
  'Wattenstein', 'Großwald', 'Wartburg', 'Grünwald', 'Lemmingshafen',
  'Glasmost', 'Neuenscheid', 'Neu-Jerusalem', 'Weißenbach', 'Burgdorf',
  'Baldwurz', 'Nasenloch', 'Flügelschlag', 'Holzschlag', 'Burggarten',
  'Volksgarten', 'Schlagham', 'Mitterreith', 'Nasserreith', 'Gutenrutsch',
  'Halming', 'Tiefenwies', 'Wiedenn', 'Seebruck', 'Turmenquark',
  'Waltersee', 'Frauentürk', 'Heißenwald', 'Kaltenbruck', 'Wien-Hütteldorf',
];

/// Title ladders (§16.1): `titleClass` 1–8 Christian, 9–12 Muslim;
/// +12 for the female form. Index 0 unused.
const List<String> maleTitles = [
  '', 'Ritter', 'Baron', 'Graf', 'Fürst', 'Großfürst', 'Herzog',
  'Erzherzog', 'König', 'Scheich', 'Pascha', 'Emir', 'Kalif',
];

const List<String> femaleTitles = [
  '', 'Burgherrin', 'Baronin', 'Gräfin', 'Fürstin', 'Großfürstin',
  'Herzogin', 'Erzherzogin', 'Königin', 'Scheichin', 'Paschin', 'Emirin',
  'Kalifin',
];

/// Display title for a title class (female classes are stored as
/// `class + 12`).
String titleName(int titleClass) => titleClass > 12
    ? femaleTitles[titleClass - 12]
    : maleTitles[titleClass];
