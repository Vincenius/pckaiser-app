# PC Kaiser — Complete Clone Implementation Guide

Self-contained specification for building a faithful clone of **PC Kaiser**
("PCKAISER++"), a German shareware medieval strategy/dynasty-simulation game
by Martin Gelter (with Lorenz Giefing), originally released 1992 (the
disassembled final build is from 1999). Setting: the Holy
Roman Empire from the year 1000. Players rule dynasties; the goal is to be
the **last dynasty standing**.

Everything in this guide was recovered from the original x86 binaries
(`PCKAISER.EXE` + `PCKAISER.OVR`) by full static disassembly. Unless a rule
is explicitly marked `[APPROX]`, the constants and formulas are exact, traced
from code. You should be able to implement the entire game from this document
alone. (§27 lists the handful of approximations and known original bugs.)

Throughout, `random(N)` = uniform integer in `[0, N−1]`, and `RandomReal` =
uniform real in `[0, 1)` (§25).

---

## Table of Contents

1. Game Overview
2. Data Model
3. Map, Terrain & Map Generation
4. Buildings, Tile Values & Build Actions
5. New-Game Setup & Starting Conditions
6. Turn Structure, Menus & Movement
7. Economy: Taxes, Tribute, Harbors, Wages
8. Food, Towns & Population
9. Market & Trade Ships
10. Military: Troops, Recruitment, Garrisons
11. War: Declaration, Battles, Conquest, Plunder
12. Post-War Coercion
13. Espionage & Assassination
14. Marriage
15. Dynasty Life Cycle: Aging, Death, Births, Succession
16. Titles & the Prestige Score
17. Kurfürsten, Kaiser & Sultan
18. Random & Scripted Events
19. Elimination, Bankruptcy & Win Condition
20. AI Player Behavior
21. UI Screens & Status Texts
22. Data Tables (names, titles, epithets, places…)
23. German UI Strings (verbatim, with translations)
24. Assets & Rendering
25. RNG & Numeric Conventions
26. Original-Engine Reference (record layouts)
27. Fidelity Notes, Approximations & Original Bugs

---

## 1. Game Overview

- Turn-based strategy on a single-screen tile map; German-language UI.
- Up to **30 realms** (player slots); any mix of human and computer players
  (humans are created at setup; every remaining dynasty is AI).
- Each realm = one **dynasty** (a family of persons, one of whom is the
  **ruler**) + a **territory** of map tiles + towns, troops and a treasury.
- **Win condition:** be the only dynasty left ruling land. Pure elimination —
  there is no score.
- **Timeline:** the year counter starts at 999 and increments at the top of
  every round, so the first playable year is **1000**. Wars are forbidden
  before **1010** ("Kriege sind erst ab dem Jahr 1010 erlaubt !") — the first
  ten rounds are a guaranteed peaceful build-up. The **Reformation year** and
  the **Ottoman-invasion year** are typed in by the player at setup (§5).
  The original shareware warned at year 1019 and ended at 1020; a clone can
  ignore this cutoff.
- Three religions: katholisch (0), evangelisch (1), moslemisch (2). Religion
  drives titles, elections, marriage eligibility and one invasion event.

---

## 2. Data Model

Implement these entities (original memory layouts for reference in §26):

**Game (globals)**
- `year` (starts 999), `reformationYear`, `ottomanYear` (player-chosen)
- `grainPrice`, `cattlePrice` (floats, rolled once per year, global)
- `kaiser`, `sultan` — person references (null = vacant / Interregnum)
- `kaiserPot`, `sultanPot` — accumulated tribute money for the office holders
- `kurfuersten` — list of persons, **capacity exactly 7, never grows**
- `kaiserChronicle`, `sultanChronicle` — lists of chronicle records
  `{name, accessionYear, deathYear, epithet}`
- `persons` — master list of every living dynasty member
- `assassinationOrders` — list of pending orders `{sponsor, targetPlayer, count}`
- `currentPlayer` — index of the active player slot

**Map** — 80×44 tiles, each `{terrain, owner, building, troopMarker}` (§3).

**Player slot / realm** (30 fixed slots, indices 1–30; 0 = "Niemand"):
- `titleClass` (1–12 male, 13–24 female; §16), `capitalX/Y`, `cursorX/Y`
- `population` = Σ of its towns' populations (kept in sync)
- `troopCapacity` = Σ of its towns' capacities
- `armySize` = Σ of its towns' garrisons (= Σ of garrison-counted troops' men)
- `tileCount[1..8]` — owned-tile counters per building type
- `grainHarvest`, `livestockHarvest` — this turn's yields (sellable food)
- `treasury` (can go negative — debt), `guardLevel` ("Verstärken" stat)
- `popularity` (a.k.a. "weight") — **one field** (init 50, clamped 0–100,
  displayed up to 150): food-satisfaction tracker AND Beliebtheit; drives
  strife, epithets and ×10 in the prestige score (§8.4)
- `movementPoints` (re-rolled per turn), per-turn action flags
  (soldThisTurn, investedThisTurn, warThisYear, …)
- `ruler` — person reference (null = slot vacant)
- `troops` — list of troop units; `towns` — list of town objects

**Dynasty** (table parallel to player slots; index = person.dynasty):
- `status`: `FREE`, `AI`, or human player number — this byte is the
  human/AI turn dispatch
- `religion` (0/1/2)
- `members` — list of persons

**Person**
- `name` (≤20 chars), `age`, `dynasty` index, `gender` (0=male, 1=female)
- `spouse` (person ref or null), `children` (list, created lazily),
  `siblingList` (back-pointer to the parent's children list)

**Town** — `{name ≤20, population, troopCapacity, garrison, buildingType
(3/4/5), x, y}`

**Troop unit** — `{name ≤20, men, class (0=Infanterie, 1=Kavallerie,
2=Artillerie), quality (1=regular, 3=Söldner, 50=Janitscharen),
garrisonCounted (bool — false for Söldner), x, y}`

---

## 3. Map, Terrain & Map Generation

### 3.1 Grid & tiles

- **80 columns (X: 0–79) × 44 rows (Y: 0–43) = 3,520 tiles.**
- Tile fields:
  - **terrain**: `0` = Ebene (plain), `1` = Berg (mountain),
    **`2`–`17` = Wasser** — water value = `2 + neighborMask`, where the
    4-bit mask encodes which orthogonal neighbors are land
    (bit3 = +X, bit2 = −X, bit1 = −Y, bit0 = +Y). The 16 values select
    shoreline sprites; *all* game logic tests "water" as `terrain ≥ 2`.
  - **owner**: player slot index, `0` = unowned.
  - **building**: 0–8 (§4).
  - **troopMarker**: 0/1 — set while a troop unit stands on the tile
    (used for blocking, "no enemy troop here" checks, and rendering;
    during war rounds it is stamped with the war-participant index).
- Only Ebene and Berg can be claimed or built on. Water is impassable
  (exception: a starting-position water neighbor becomes a Hafen, §5).

### 3.2 Map generation (procedural, every new game)

```
1. Fill all 80×44 tiles with water (terrain = 2), no owner, no building.
2. Repeat 100 times (land patches):
       x0 = random(70);  y0 = random(34)
       for y in y0 .. y0+7:                       # 8 rows
           for x in (x0 + random(2)) .. (x0 + 5 + random(2)):   # ~6–8 cols
               terrain[x][y] = random(7) div 6    # 0 = Ebene (p=6/7), 1 = Berg (p=1/7)
3. Repeat 25 times (lakes):
       x0 = random(70);  y0 = random(34)
       rows y0 .. y0 + 2 + random(3);  cols (x0+random(2)) .. (x0+2+random(3))
       → set to water again
4. Shoreline pass: for every water tile, terrain = 2 + landNeighborMask
   (bounds-checked; see §3.1 for the bit layout).
```

There is **no fixed scenario map** — every game world is random.

---

## 4. Buildings, Tile Values & Build Actions

Nine building types (tile field `building`):

| Idx | German | English | Value (war score & worth) | Build cost |
|---|---|---|---|---|
| 0 | keine / Wasser | none | 0 | — |
| 1 | Kornfeld | grain field | 100 | 100 T |
| 2 | Weide | pasture | 150 | 150 T |
| 3 | Dorf | village | 1,000 | 1,000 T |
| 4 | Markt | market town | 2,500 | — (grows from Dorf, §8.3) |
| 5 | Stadt | city | 5,000 | — (grows from Markt, §8.3) |
| 6 | Burg | castle | 5,000 | 5,000 T |
| 7 | Palast | palace | 10,000 | 10,000 T |
| 8 | Hafen | harbor | 700 | 700 T |

The "value" column is one table in the engine, used by the war score (§11)
and quoted by the in-game help: "Alles zählt soviel, wie es kostet. Ein Markt
zählt 2500 Punkte, eine Stadt 5000."

**Build rules** (build menu, on an owned tile; each action costs 1 movement
point and the listed Taler):

- Kornfeld only on Ebene; Weide only on Berg.
- Dorf can be founded on either land terrain → creates a **town object**
  (§8.3) with population `75 + random(50)`, capacity 25, garrison 0; the
  player names it (first Dorf named at setup).
- Burg / Palast / Hafen built explicitly (Hafen on the coast).
- `(S)chiff` (colony ship) 700 T — sent out from a Hafen to colonize a
  free land tile across the sea (§9.3); distinct from the *trade-ship
  investment* of §9.2, which is keyed off the Hafen count, not ships.
- `(A)breißen` (demolish a field) 100 T — clears the building.
- Markt and Stadt can never be built — they only grow from towns (§8.3).
- Claiming an adjacent unowned land tile costs 1 movement point and makes it
  yours (empty; build separately). Update `tileCount[]` on every change.

**Religion change** (menu action): katholisch = free, evangelisch = 500 T,
moslemisch = 1,000 T. Converting to Islam costs any Kurfürst seat (§17) and
switches the dynasty's title ladder (§16). Any conversion also costs
**−70 popularity** (clamped ≥ 0) on every slot the ruler holds (§8.4).

---

## 5. New-Game Setup & Starting Conditions

Setup flow (after the title/intro):

1. Optional savegame load ("Spielstand Laden ? ( j/n )").
2. For each human player: founder **name**, **gender** ("(M)ännlich oder
   (W)eiblich ?"), **country** ("Welches dieser Länder soll Ihnen gehören ?" —
   pick from the country table §22.3), and the **name of the first Dorf**
   ("Wie soll Ihr erstes Dorf heißen ( z.B. <city> ) ?").
3. Press RETURN to let the computer play all remaining dynasties
   (their `dynasty.status = AI`).
4. The player types the **Reformation year** and the **Türken (Ottoman)
   invasion year**. Each is validated independently: values **< 1011** are
   rejected ("Das ist zu früh !!!") and re-asked until ≥ 1011. (There is no
   check that the Ottoman year follows the Reformation year.)
5. Year counter set to 999 (becomes 1000 at the first round).

**Starting position & territory** (per dynasty): re-roll
`x = random(78)+1, y = random(42)+1` until the tile is **land**, all four
orthogonal neighbors are **unowned**, **more than two** of them are land, and
no neighbor is one of the forbidden shoreline variants
{7, 8, 9, 11, 12, 13, 15, 16}. Then claim a **5-tile cross**:

- center: **Burg** (this is the **capital**; counts in the prestige score)
- the first land neighbor (scan order −X, +X, +Y, −Y): the named **Dorf**
  (the founder's town)
- other land neighbors: Kornfeld (on Ebene) / Weide (on Berg)
- water neighbors: **Hafen**

**Founding values:** treasury **1,000 T**; titleClass Ritter (1) — Scheich
(9) for a Muslim founder; weight 50; no army; founder person created with age
`17 + random(5)`; the dynasty's members list, towns list and troops list
start with just these.

(A *replacement* dynasty created mid-game by bankruptcy/elimination instead
gets treasury `(territoryValue × 1.2) / 2` clamped to [500, 25,000] T — §19.)

---

## 6. Turn Structure, Menus & Movement

### 6.1 Round & turn order

One **round** = every living player slot takes a turn, in slot order. When
control wraps back to the first slot: `year += 1`, and the **global market
prices re-roll** (§9.1). Between turns, the engine also runs the world-event
phase (§18) and per-slot upkeep.

Per player turn, in order:

1. **Upkeep / status report** (§21): food production (§8.1), town growth &
   transitions (§8.2–8.3), popularity update (§8.4), tax income, tribute,
   harbor income, wages (§7), movement-point roll (§6.3), per-turn flags
   reset.
2. **Action phase**: the human menu loop (§6.2) or the AI script (§20),
   spending movement points and money.
3. **End-of-turn**: dynasty events for this slot (aging, deaths, marriages,
   births — §15), pending assassinations (§13.3), elimination checks (§19),
   win check.

### 6.2 The human main menu

Single-key dispatch (also mouse: clicking the map = tile action):

| Key | Menu text | Action |
|---|---|---|
| Z | `(Z)iehen und Bebauen` | move cursor / claim & build on tiles |
| H | `(H)andel` | commerce menu: sell grain/cattle, ship investment, send money, **merge realms** |
| M | `(M)ilitär` | military menu (§10) |
| S | `(S)onstiges` | misc: marriage, religion change, Kurfürsten list, relocate capital, "Wer regiert wen?" |
| P | `S(p)ionage` | espionage menu (§13) |
| I | `(I)nfo anzeigen` | info/status screens |
| D | `(D)etailkarte` | detail map / tile inspection |
| B | `Zu(g) (b)eenden` | end turn |
| E | `Sp(e)ichern` | save game |
| Q | `(Q)uit` | quit (with confirmation) |

Commerce-menu extras:
- **Send money**: "An welches Land wollen Sie Geld schicken ?" — transfer
  Taler to another player (diplomacy, election bribes).
- **Merge realms** (`Z` inside Handel, "Reiche zusammenlegen"): if you rule
  more than one slot (inheritance/conquest), merge slot B into slot A — free;
  A's popularity becomes the population-weighted average of both (plain 50 if
  A had no population; B's slot is left at 60); population, harvests, all map
  tiles and the dynasty members move to A; A gets a one-off movement bonus
  `B.titleClass + random(6)`. Only gate: the source realm must own ≥ 1 tile.
- **Relocate capital** ("Sitz verlegen"): costs **5,000 T**; valid target =
  own tile with Stadt/Burg/Palast (building 5/6/7); only when the capital is
  unset/lost.

### 6.3 Movement points

Rolled each turn from the ruler's title class: **`points = classEquivalent +
random(6)`**, where Muslim classes map to Christian equivalents:

| Class | Title | Range |
|---|---|---|
| 1 / 9 | Ritter / Scheich | [1, 6] |
| 2 | Baron | [2, 7] |
| 3 / 10 | Graf / Pascha | [3, 8] |
| 4 | Fürst | [4, 9] |
| 5 | Großfürst | [5, 10] |
| 6 / 11 | Herzog / Emir | [6, 11] |
| 7 | Erzherzog | [7, 12] |
| 8 / 12 | König / Kalif | [8, 13] |

Every map action — cursor move, tile claim, build — costs **exactly 1
point**, terrain-independent. Ship movement onto a Hafen also costs 1.
UI shows "Sie können N Feld(er) ziehen." / tile panel "Ziehen: N" =
remaining points.

---

## 7. Economy: Taxes, Tribute, Harbors, Wages

All run during turn upkeep; all amounts are whole Taler.

```
# 7.1 Tax income
tax = random(population) + population        # uniform [pop, 2×pop)
treasury += tax                              # "Sie haben <tax> Taler an Steuern eingenommen."

# 7.2 Feudal tribute — 10% skims toward the crowns
tribute = treasury / 10                      # only if treasury > 0
treasury -= tribute
# Christian dynasties pay into the KAISER POT, Muslim dynasties into the
# SULTAN POT (global accumulators). The office holder collects the whole pot
# on their own turn (§17.5). Two structurally identical 10% transfers can
# fire (liege + crown); a clone may simplify to one 10% while any superior
# exists.

# 7.3 Harbor income
for i in 1..tileCount[Hafen]: treasury += random(70)    # mean ~34.5/harbor

# 7.4 Wages
wages = Σ söldner men × per-man rate        # mercenary upkeep (§10.2)
      + armySize × 0.5                      # regulars: 0.5 T per man
treasury -= wages                           # "Sie mußten <N> Taler an Sold zahlen."
```

Treasury may go negative — debt is allowed until the bankruptcy threshold
(§19.2).

---

## 8. Food, Towns & Population

Population lives **in towns**. The player-level numbers are sums over the
realm's towns (population, capacity, garrison); keep them consistent (the
original literally asserts these invariants every turn).

### 8.1 Food production (per turn)

```
fields = tileCount[Kornfeld] + tileCount[Weide]
if fields > 0 and population ≥ 2:
    E = round(clamp((population − armySize) / fields / 10, 0.5, 2.0))   # ∈ {1, 2}
    grainHarvest     += E × (random(15) + 20) × tileCount[Kornfeld]
    livestockHarvest += E × (random(10) + 20) × tileCount[Weide]
```

- `E` is labor efficiency: roughly ≥ 15 free workers per field doubles the
  yield (the army doesn't farm).
- Each inhabitant eats **1 food per turn**; harvests double as sellable
  stock (§9.1) — what you sell, your people don't eat.

### 8.2 Population growth & starvation

```
S = (grainHarvest + livestockHarvest − population) × 100 / population   # surplus %
S = clamp(S, −30, +15)                   # surplus percent is clamped FIRST
                                         # (also feeds the weight update, §8.4)
G = sign(S) × (random(|S|) + 1)          # growth percent (negative on famine)
G = min(G, +10)                          # global growth cap: +10%/turn (DS:[2])
for each town:
    delta = round(town.population × G / 82)   # NB: divisor is 82, not 100
    town.population    += delta
    town.troopCapacity += delta / 4      # capacity follows pop at ¼ rate
                                         # (capacity loss capped at −capacity)
if Σ delta < 0:                          # famine: soldiers desert/die
    loss = min((−Σ delta) / 4, armySize)
    remove `loss` men from troops & garrisons
```

If population ≤ 1 the whole food/growth/popularity block is skipped,
population is zeroed and the §8.4 stat resets to 50.

### 8.3 Town transitions (per town, per turn)

- population ≥ **500** and building < Markt → becomes **Markt**
  ("Dem Dorf <name> in <player> wurde das Marktrecht verliehen.")
- population ≥ **1000** and building < Stadt → becomes **Stadt**
  ("Dem Markt <name> … wurde das Stadtrecht verliehen.")
- population < **5** → the town **dies**: garrison soldiers are removed from
  the army, the town object is deleted, the tile reverts to Kornfeld (Ebene)
  or Weide (Berg).

Update the tile's building byte and `tileCount[]` on every transition.

**Normalization pass** (every round, in the world phase, after the events
of §18): for every player, every town is clamped to the invariants
`capacity ≤ population` and `garrison ≤ capacity` — excess capacity is
dropped (player capacity sum updated), excess garrison soldiers are
**removed from the army**.

### 8.4 Popularity / weight (Beliebtheit) — ONE stat

"Popularity" and "weight" are the **same field** (player record +0x35,
init 50). It receives **two updates per turn**, in this order within
upkeep (traced exactly — no longer `[APPROX]`):

```
# 1. Food-satisfaction update (right after S is computed, §8.2):
stat = round(stat × (100 + S) / 82)          # S ∈ [−30, +15]
stat = min(stat, round(oldStat × 1.05))      # upward growth capped at +5%/turn
                                             # (downward is uncapped: ×0.85 at S=−30)

# 2. Balance nudge (after town growth & famine):
balanced = (grainHarvest ≤ 2×livestockHarvest) AND (livestockHarvest ≤ 2×grainHarvest)
stat += (balanced ? +1 : −1) × (random(3) + 1)     # ±[1,3]
stat = clamp(stat, 0, 100)
```

- The equilibrium of update 1 sits at S = −18; with any decent surplus the
  stat climbs +5%/turn toward 100, and famine drags it down fast.
- The balance check is a **ratio** test — 1 grain + 1 meat is as "balanced"
  as 10,000 + 6,000. Display tiers in §21.2 (merging realms can push the
  displayed value above 100 between clamps, §6.2).
- This one stat drives everything previously attributed to either name:
  internal strife when < 20 with a big dynasty (§19.1), ×10 in the prestige
  score (§16.2), and epithet quality > 60 at a Kaiser's death (§17.5).
- On a realm merge (§6.2) the surviving slot gets the **population-weighted
  average** of the two stats (target with 0 population: plain 50); the
  merged-away slot's stat is set to 60.
- **Religion change** (§4) subtracts **70** from this stat (clamped ≥ 0) on
  every slot ruled by the converting dynasty's ruler.

---

## 9. Market & Trade Ships

### 9.1 Market (grain & cattle)

Once per year (global — all players trade at the same prices):

```
grainPrice  = (random(11) + 10) / 10     # [1.0, 2.0] T per Sack Korn
cattlePrice = (random(11) + 15) / 10     # [1.5, 2.5] T per Tier
```

Sell (`(K)orn verkaufen` / `(R)inder verkaufen`, once per good per turn):

```
show "Überschuß : <stock>"  and  "Marktpreis pro <Sack Korn|Tier> : <price>"
amount = input;  reject if amount < 0 or amount > stock ("Das geht nicht !!!")
stock −= amount;  treasury += amount × price
# second attempt same turn: "Sie haben diese Runde schon verkauft !!!"
```

### 9.2 Trade-ship investment (once per turn)

```
maxInvestment = tileCount[Hafen] × 600
validate: amount ≤ treasury, amount ≤ maxInvestment, amount > 0
treasury −= amount
if random(2) == 0:  treasury += amount + random(amount) + 1   # profit, ≤ 2×
else:               treasury += amount − (random(amount) + 1) # loss, ≥ 0
```

`[DESIGNED]` (rules v6) — the clone keeps the original outcome roll above
but **delays the return**: the stake leaves the treasury on departure, the
profit/loss is rolled then (replayable) but hidden, and the haul is
credited at the START of the realm's next turn with a `shipsReturned`
notice. Modelled by `Realm.pendingShipReturns` / `_resolveShipReturns`.

### 9.3 Colony ships (`(S)chiff`, build menu)

Manual: "Häfen bringen Geld, man kann von ihnen aus aber auch Schiffe
ausschicken, um z.B. unbewohnte Inseln zu kolonisieren. Um dies zu tun,
muß man sein Schiff einfach gegen ein freies Landfeld steuern." — a ship
is launched from a Hafen and steered tile-by-tile over water (1 movement
point per tile, also onto a Hafen, §6.3); steering it against a **free
land tile** colonizes that tile for the player.

Colonization itself (`proc_005D2B`, fully decoded):

```
tile(shipX, shipY).owner = currentPlayer     # the free land tile hit
treasury −= 700                              # the ship is consumed at its build cost
```

The claimed tile is empty — founding a Dorf there is a normal build
action afterwards. UI strings: "(S)chiff: 700 T", "(S)chiff steuern",
"Hier kommt das Schiff unmöglich hin ! Sie können nicht weiter ziehen !"
(invalid ship move / out of movement points).

---

## 10. Military: Troops, Recruitment, Garrisons

### 10.1 Troop units

Armies are **troop units** placed on map tiles (setting the tile's
troopMarker). Each has men, a class, a quality and a name. Per-man combat
power = `(3 × class + quality) / 10`:

| Type | class | quality | power/man | cost |
|---|---|---|---|---|
| Infanterie (regular) | 0 | 1 | 0.1 | 5 T/man |
| Kavallerie (regular) | 1 | 1 | 0.4 | 5 T/man + 500 T |
| Artillerie (regular) | 2 | 1 | 0.7 | 5 T/man + 1,000 T |
| Söldner (mercenary inf.) | 0 | 3 | 0.3 | 50 T/man (plus ongoing wages) |
| "Die Janitscharen" (event) | — | 50 | ~5 | spawned by the Ottoman invasion (§18.4) |

### 10.2 Recruitment & garrison bookkeeping

- **Regulars** ("Rekruten", 5 T/man + class surcharge): prompt
  "Welche Truppe ausbilden ( 5 Taler pro Soldat ) ?", keys 1/2/3 for
  Inf/Kav/Art. Recruits are **quartered in towns**: distribute the men
  across the realm's towns proportionally to free capacity
  (capacity − garrison), leftovers one-by-one to random towns. `armySize`
  may never exceed `troopCapacity` (Σ town capacities).
- **Söldner** (50 T/man): not garrison-counted (they live outside the towns)
  but cost upkeep every turn (§7.4).
- Military menu: `(K)rieg erklären`, `Truppe (b)ilden` (create unit),
  `Truppe ver(s)tärken` (add men), `Truppe (a)uflösen` (disband),
  `Truppen ver(e)inigen` (merge units), `Truppe ausb(i)lden` (drill —
  traced `proc_00A316`: cost = men × 5 T, increments the unit's
  **quality** counter (`+0x1a`) by 1, class unchanged),
  `Truppens(t)andort` (position), `Truppen(l)iste`, `(H)auptmenü`.
- Troops must be stationed on own territory ("müssen Ihre Truppen auf Ihrem
  Territorium stationieren!").
- Combat losses are distributed across **engaged** units proportionally to
  size; emptied units are deleted; garrisons shrink to match.

---

## 11. War: Declaration, Battles, Conquest, Plunder

### 11.1 Declaration

- Only from year **1010** ("Kriege sind erst ab dem Jahr 1010 erlaubt !").
- **One war per player per year** ("Sie haben dieses Jahr schon einmal Krieg
  geführt !"); needs troops ("Sie haben nicht genug Truppen !").
- War start: switch to the war screen (`KRIEG.IMG`), prune empty troop
  units, and **snapshot every unit's position** (used by the AI peace test
  and the post-war return below).

### 11.2 War rounds & termination

A war is a loop of **war rounds** (round counter starts at 0). Each round:

1. **Movement**: both sides move their troops — a human side
   interactively, an AI side by script. The attacker's units march onto
   enemy territory; meeting an enemy unit triggers per-tile combat
   (§11.3). AI-vs-AI wars run in silent "fast mode".
   `[DESIGNED: the per-round movement allowance was not traced — the
   clone gives each unit moves equal to the owner's normal movement roll
   (§6.3) per war round, 1 tile per move.]`
2. **Score**: the attacker war score (below) is recomputed.
3. **Termination checks** — the war ends when any of these fires:
   - **Ruler capture**: a unit stands on the *enemy capital tile* →
     "<X> beendet den Krieg durch die Gefangennahme des Herrschers von
     <Y>." The capturer immediately takes over the loser's **entire
     realm** (slot pointer overwritten, §19), and **post-war coercion
     (§12) fires — this is the only path that triggers §12**.
   - **Mutual peace**: each round both sides decide whether they want
     peace; the war ends only when **both** do (a one-sided wish is
     announced: "<X> will ein Ende des Krieges."). A human side is asked
     "Will <Land> ein Ende des Krieges ?" (j/n) every round. An AI
     **attacker** wants peace when all of its surviving units stand on
     their snapshotted pre-war positions; an AI **defender** wants peace
     when its units are all on their pre-war positions AND the war is
     decided (attacker war score ≥ 1,000, or the defender fields more
     than 2× the attacker's unit count, or the attacker has no units
     left).
   - **Winter**: when the round counter exceeds **20**, the war is
     forcibly ended: "Der Krieg mußte wegen des hereinbrechenden Winters
     beendet werden."

**End-of-war resolution** — unless the war ended by ruler capture, the
winner and their **claim** are determined **once, at the end**:

```
score(side) = Σ (avgTroopStrength × thisTroopStrength × value[occupiedTile])
              over every troop of that side standing on ENEMY tiles
              (+3000 if it occupies the enemy's CAPITAL tile)
winner = the side with the higher score; its score is the CLAIM
         ("Der Sieger ist : <name> hat einen Anspruch von <N> Punkten.")
         no leader → "Der Krieg endete unentschieden.", nothing more happens
loserValue = Σ value[tile.building]  over ALL loser-owned tiles

if claim ≥ round(loserValue × 0.4):    # decisive victory
    occupied tiles convert to the winner (§11.4)
else:                                  # limited victory → claim settlement
    the winner spends the claim on enemy land (below)
```

**Claim settlement** (limited victory). The help line "Alles zählt soviel,
wie es kostet. Ein Markt zählt 2500 Punkte, eine Stadt 5000." refers to
this screen. A **human** winner gets an interactive annexation screen
(cursor starts at the loser's capital): annex enemy tiles one by one, each
costing its **building value** (§4 table) from the remaining claim, with
three checks — the tile must belong to the loser ("Das gehört nicht Ihrem
Feind !"), its value must fit the remaining claim ("So viel steht Ihnen
nicht zu !"), and it must **border the winner's territory** ("Sie können
sich nur Felder aneignen, die direkt an Ihr Land grenzen !"). Annexed
tiles convert with full §11.4 bookkeeping. Pressing `F` (fertig) ends the
settlement: the **unspent claim converts 1:1 into Taler**, transferred
straight from the loser's treasury (which may go negative) to the winner.
An **AI** winner settles automatically (`proc_00CC0B`)
`[APPROX: same economy — greedy adjacent-tile annexation, remainder in cash]`.

Afterwards every surviving unit **returns to its snapshotted pre-war
position** and emptied units are deleted.

### 11.3 Per-tile combat (casualties)

For each pair of opposing troop units that meet:

```
# tile defense bonus per side (0–4), from the tile the unit stands on:
def = 0
+1 if terrain == Berg
+1 if building ∈ {Dorf, Palast, Hafen}
+2 if building ∈ {Markt, Stadt}
+3 if building == Burg

P_side = men × (3×class + quality) / 10           # integer combat power
R      = RandomReal / 2 × 0.2                     # ONE roll per encounter, ∈ [0, 0.1)
losses_side = round(P_side × def_side × 0.2 × R)  # capped at the unit's men
```

- **def = 0 → zero casualties for that side**: combat on flat, building-less
  tiles is decided purely by the round-level score, not attrition.
- If both units would be annihilated simultaneously, `random(2)` picks one
  side to keep 1 man.
- Display: "Es kam zu einer Schlacht : Verluste : <X> aus <Name> : <Y>
  Mann"; "Die Angreifer/Verteidiger wurden vernichtet." on a wipe. AI-vs-AI
  battles run silently ("fast mode").

### 11.4 Conquest transfer

When a tile changes owner, the winner also receives a share of the loser's
**treasury** and current **harvests**:

```
treasuryShare = T1[building] / Σ T1 over all loser's tiles
harvestShare  = T2[building] / Σ T2 over all loser's tiles
T1[0..7] = [0, 0, 1, 2, 3, 5, 6, 3]      # by building type 0..7
T2[0..8] = [0, 0, 1, 2, 3, 0, 0, 2, 6]   # by building type 0..8
both shares are DOUBLED if the tile is the loser's capital
```

Town tiles (3/4/5) move their **town object** between the two realms' town
lists; tile counters and population/capacity/army sums update accordingly.

### 11.5 Plunder ("Plündern") — per-tile action during war rounds

(Distinct from the post-war claim settlement in §11.2 — plunder happens
*during* the war, on tiles your troops reach.) Preconditions, in order:
tile has a building ("Hier steht doch gar nichts !"), not already plundered
this round ("Sie haben diese Runde schon geplündert !"), not your own tile
("Wollen sie wirklich ihr eigenes Land plündern !").

| Target building | Effect |
|---|---|
| Kornfeld / Weide | destroyed: building = 0, owner = 0, loser's tile counter −1 |
| Dorf / Markt / Stadt | town plunder (below) |
| Burg / Palast / Hafen | steal `random(victim.treasury)` Taler straight from the victim's treasury (nothing destroyed) |

Town plunder:

```
R1 = random(town.population / 2)      # population KILLED
R2 = random(town.population)          # Taler LOOTED → "Sie erbeuteten <R2> Taler"
R3 = random(town.capacity − town.garrison)

attacker.treasury += R2               # the victim's treasury is NOT touched
town.population −= R1                 # (and the victim's population sum)
if R3 > 0: town.capacity −= R3
```

---

## 12. Post-War Coercion

When a war ends by **ruler capture** (a unit on the enemy capital tile,
§11.2 — wars ended by mutual peace or winter skip this), the victor
confronts the captured ruler. Human victors get a "wollen Sie <X> …
zwingen ?" prompt per applicable option; AI victors auto-execute. Checked
in order:

1. **Religions differ → conversion-or-death**: "<V> verlangt von <L>, zu
   sterben oder sich zur <adj>en Religion zu bekehren !!!" An AI loser
   decides by **coin flip** (`random(2)`); a human loser answers j/n.
   - Accept → the whole dynasty converts ("Die Dynastie <X> nimmt die <adj>e
     Religion an."); conversion to Islam forfeits any Kurfürst seat.
   - Refuse → "<L> weigert sich, sich zu bekehren, und wird hingerichtet !!!"
     → execution → succession (§15.4).
2. **Same religion & marriage-compatible** (opposite genders, both
   unmarried, victor male, both age ≥ 14, age difference < 10) → **forced
   marriage**: "<V> zwingt <L> zur Heirat." (dynasties merge through the
   marriage).
3. **Loser is the Kaiser** → forced abdication ("… muß als Kaiser
   abdanken.") → office cleared, new election (§17.3).
4. **Loser is a Kurfürst** → seat stripped ("… muß als Kurfürst abdanken.")
   → vacancy refilled next turn.

---

## 13. Espionage & Assassination

All missions from the Spionage menu; pick `count ∈ [1, 30]` agents (more:
"So viele Spione würden zu sehr auffallen"); cost deducted up front.

| Mission | Cost per agent |
|---|---|
| `(D)aten ausspionieren` — economy intel | 200 T |
| `(T)ruppen ausspionieren` — military intel | 200 T |
| `(A)nschlag verüben` — assassination | 250 T |
| `(v)erstärken` — raise guard level | **100 T per guard unit** |

`guardLevel` (the Verstärken stat) is the defender-side stat for everything
below. It is hard-capped at **50** units ("Das ist keine Spionageabwehr,
sondern eine Armee !!!"); guards can also be dismissed
("Wieviele Spione entlassen :").

### 13.1 Counter-espionage roll (intel missions)

```
caught    = min(defense, random(2×defense + 2))     # economy missions
caught    = min(defense, random(2×defense + 5))     # military missions
survivors = count − caught   (cap 99 econ / 49 mil)
if survivors ≤ 0: "konnten nichts in Erfahrung bringen", abort
```

### 13.2 Intel reveals

Economy — five independent checks, `random(N − survivors) ≤ threshold` ⇒
revealed:

| Reveals | N | threshold |
|---|---|---|
| treasury (fuzzed) | 55 | 50 |
| grain stock | 55 | 30 |
| livestock stock | 55 | 30 |
| army/dynasty summary | 60 | 20 |
| guard level | 60 | 5 |

Military: single check `random(50 − survivors) < 15` reveals the troop list.
**Spied numbers are fuzzed before display** — never show exact values
`[APPROX: ±10% uniform jitter]`.

### 13.3 Assassination

The order is queued ("Die Attentäter sind auf dem Weg !!!") and resolved in
the event phase:

```
g         = 2 × target.guardLevel
caught    = min(random(g + 15), count)     # "<caught> mutmaßliche Attentäter wurden gefangengenommen."
survivors = min(count − caught, 49)
success   = random(50 − survivors) < 15    # 30% at 0 survivors → 100% at ≥ 35
```

- Success: "<Victim> wird hinterhätig ermordet !!!" → full succession (§15.4).
- Failure: failure text + captured count + "Einer von ihnen gesteht unter
  Folter, aus <Sponsor> geschickt worden zu sein !!!" — **the sponsor is
  publicly named.**

---

## 14. Marriage

### 14.1 Voluntary marriage (menu: `H(e)irat vorschlagen` / `(B)ürgerlich heiraten`)

Candidate eligibility (both for the player's proposal list and the AI's
annual partner search): **unmarried, opposite gender, age ≥ 14, age
difference < 10, different dynasty, same religion**. If none exists:
"Es gibt zur Zeit keinen passenden Partner !"

Acceptance, once a candidate is approached:

- target belongs to an **AI or no dynasty** → accepts iff `random(4) == 0`
  (**25%**) → "Angenommen !" / "Abgelehnt !"
- target is **human-controlled** → that player answers
  "Ist die/der Angesprochene einverstanden ? ( j/n )".

### 14.2 The wedding

```
A.spouse = B;  B.spouse = A
children: create a fresh shared list, merge both partners' existing children
into it, attach it to the HUSBAND (wife's children pointer cleared)
portraits + fanfare if a player dynasty is involved; "<A> heiratet <B>"
```

A marriage between dynasties is the main peaceful path to inheriting realms
(the spouse is in the heir priority, §15.4).

### 14.3 Annual marriage upkeep (all dynasties)

In the per-person event loop, every unmarried member with age > 14 (not a
plain commoner) tries at ~25% per turn (`random(4) == 0`) to find a partner
via §14.1; if no candidate exists, a 50% "phantom birth" may fire instead
(§15.3).

Forced marriage exists as a coercion outcome (§12).

### 14.4 Religious-conversion divorce

If a conversion makes a marriage religiously incompatible: both spouse
pointers cleared; "<A> und <B> trennen sich wegen religiöser Differenzen."

---

## 15. Dynasty Life Cycle

### 15.1 Aging & natural death (every person, every turn)

```
person.age += 1
if random(90 − age) < 2: person dies      # P = 2/(90−age); certain at 88+
```

"<name> ist im Alter von <age> Jahren verstorben." + "R.I.P." → §15.4.

### 15.2 Religion availability

```
year ≤ reformationYear: new dynasties/conversions are Catholic
else if year ≤ ottomanYear: random(2) → Catholic / Protestant
else: random(3) → Catholic / Protestant / Muslim
```

(Religion is a *dynasty* property; persons follow their dynasty.)

### 15.3 Births

For each **married** couple (and the 50% "phantom birth" fallback when a
partner search found nobody, §14.3), gated by the `random(4)` annual
throttle:

```
child = new Person:
    gender  = random(2)
    name    = random(50) from the European name table (gender-matched);
              Muslim dynasties: random(10) from the Ottoman table;
              human players type the name ("Name des Kindes:", re-asked
              until non-empty)
    dynasty = parent's dynasty
    age     = 0     # ORIGINAL BUG: the game leaves age uninitialized
                    # (heap garbage, often the previous occupant's bytes).
                    # Set 0 in a clone.
append to the parents' children list (created lazily on first child)
"<A> und <B> feiern die Geburt eines Sohnes / einer Tochter."
```

(All *other* person creations — founders, replacement rulers, merchant
founders — use age `17 + random(5)`.)

### 15.4 Death of a ruler — succession

When a ruler dies (naturally, by execution, assassination or disease):

```
remove the person from the master list and dynasty
if the dynasty still has members — heir priority (AI dynasties; lists are in
insertion order ≈ eldest first; human dynasties pick from a menu):
    1. first MALE among the deceased's children
    2. first MALE among the dynasty's members
    3. the spouse (if still dynasty-affiliated)
    4. first child of any gender
    5. first member of any gender
    6. a random member
    → "Die Weisen erwählen <Name> zum Erben des Toten." — the heir becomes
      ruler of all the deceased's slots
if NO members remain:
    AI dynasty    → a RANDOM other living ruler inherits everything
                    ("…die Reichtümer und Länder an eine befreundete
                    Dynastie weiterzugeben…")
    human dynasty → chooser menu
    nobody left anywhere → total-extinction ending text (§23)
offices: a Kurfürst seat is refilled (§17.2); Kaiser/Sultan → chronicle
entry + epithet (§17.5), office cleared, new election immediately (§17.3)
```

### 15.5 Islamic succession crisis

A Muslim dynasty may not be ruled by a woman. If succession would crown a
female heir: "Da ein islamisches Land nicht von einer Frau regiert werden
kann, machen sich die Weisen von <Land> auf die Suche für einen Nachfolger
von <Herrscher>. Schließlich finden sie heraus, daß es niemand geeigneten
gibt. Sie legen das Schicksal des Landes in die Hände von <X> ( Das ist der
Computer )." → the realm becomes computer-controlled (player eliminated).

---

## 16. Titles & the Prestige Score

### 16.1 Title ladders

`titleClass` 1–8 Christian, 9–12 Muslim; +12 for the female form:

| Class | Male | Female | | Class | Male | Female |
|---|---|---|---|---|---|---|
| 1 | Ritter | Burgherrin | | 9 | Scheich | Scheichin |
| 2 | Baron | Baronin | | 10 | Pascha | Paschin |
| 3 | Graf | Gräfin | | 11 | Emir | Emirin |
| 4 | Fürst | Fürstin | | 12 | Kalif | Kalifin |
| 5 | Großfürst | Großfürstin | | | | |
| 6 | Herzog | Herzogin | | | | |
| 7 | Erzherzog | Erzherzogin | | | | |
| 8 | König | Königin | | | | |

### 16.2 Prestige score & advancement (checked every turn, every player)

```
score = population + treasury + 10 × weight
      + 1,000  × tileCount[Hafen]
      + 10,000 × tileCount[Burg]
      + 20,000 × tileCount[Palast]
```

Promotion when score reaches (and the current class is lower):

| Christian | score ≥ | | Muslim | score ≥ |
|---|---|---|---|---|
| Baron | 15,000 | | Scheich | (floor) |
| Graf | 20,000 | | Pascha | 20,000 |
| Fürst | 30,000 | | Emir | 50,000 |
| Großfürst | 40,000 | | Kalif | 80,000 |
| Herzog | 50,000 | | | |
| Erzherzog | 75,000 | | | |
| König | 100,000 | | | |

The starting Burg alone contributes 10,000. Titles never demote.

---

## 17. Kurfürsten, Kaiser & Sultan

### 17.1 The electoral college

**Exactly 7 Kurfürst seats** (fixed-capacity list).

### 17.2 Filling vacancies (every round, while seats < 7)

Eligibility: a living dynasty's **ruler**, **male**, **age ≥ 14**, dynasty
religion **≠ Muslim**, not already an elector. Among the eligible, the
**highest titleClass wins** (the current Kaiser counts +2); ties break by
random draw order. "Neuer Kurfürst wird <X>." / no candidate: "Der Posten
als Kurfürst bleibt vakant."

Seats are lost by: losing all land, converting to Islam, post-war coercion
(§12), or death (refilled immediately).

### 17.3 Kaiser election

Runs whenever there is **no Kaiser**, the year ≥ 1010 and ≥ 1 elector
exists. "Ein neuer Kaiser soll gewählt werden." Candidates = §17.2
eligibility (current electors included).

- 0 candidates → "…niemand für diese Würde geeignet ist." + "Die dunkle
  Zeit des Interregnums bricht an." (no Kaiser; retried next round)
- 1 candidate → acclaimed ("…allein <X> in Frage kommt.")
- ≥ 2 → eliminate pairwise by the same title score down to **2 finalists**,
  then:
  - **Bribery phase** (each finalist): an AI finalist repeatedly gifts
    `random(own treasury)` Taler to a random elector — the money transfers
    immediately — **until one of the rolls is 0**; a human finalist picks
    electors and amounts in a dialog. Bribes are tracked per elector
    (from A / from B) and shown to human electors.
  - **Vote**: a finalist-elector votes for themself; an AI elector votes for
    whichever finalist bribed them more (equal → coin flip); human electors
    answer "Sind sie für Kandidat A oder B ?".
  - Strict majority → "<X> geht als Sieger aus der Wahl hervor." → Kaiser.
    **Tie** → "Die Kurfürsten können sich nicht einigen." → Interregnum.

### 17.4 Sultan

The Muslim mirror office: same pattern among Muslim rulers ("Der neue Sultan
ist …"), with its own chronicle and tribute pot.

### 17.5 Office perks, chronicle & epithets

- The Kaiser/Sultan collects the global 10%-tribute **pot** on their turn
  (§7.2). The Kaiser gets **+2** in Kurfürst-selection scores.
- Every Kaiser/Sultan gets a **chronicle record** (the "Urkunde" screen):
  name, accession year, death year, epithet.
- **Epithets** (§22.6) are awarded only when a Kaiser/Sultan **dies in
  office**: 50% chance of none; otherwise `random(20)` from one of four
  pools by a 2×2 matrix — reign > 10 years? × weight > 60?:

| | weight > 60 | weight ≤ 60 |
|---|---|---|
| **reign > 10 y** | pool 1 ("Der Große", …) | pool 2 |
| **reign ≤ 10 y** | pool 3 | pool 4 ("Der Stinkende", …) |

---

## 18. Random & Scripted Events

Run in the between-turns world phase.

### 18.1 Earthquake — 10% per round

```
if random(10) == 0:
    epicenter = (random(79), random(43))
    for every tile with Manhattan distance ≤ 10 from the epicenter:
        if random(2) == 1:                       # 50% per tile
            building ∈ {Kornfeld, Weide, Burg, Palast, Hafen} →
                destroyed (building = 0, owner = 0, counters updated)
            building ∈ {Dorf, Markt, Stadt} → town damage (exact):
                T = random(town.population)
                town.capacity   −= round(T × capacity / population)
                town.garrison   −= round(T × garrison / population)
                                   # the garrison loss is removed from the army
                town.population −= T
                (player population/capacity sums updated)
    list the affected realms (up to 30):
    "Ein verherendes Erdbeben verwüstet das Reich … Betroffen sind folgende Länder:"
```

(The same per-town damage shape as disease, §18.2, with one `T` roll per
town instead of a realm-wide budget.)

### 18.2 Disease ("Seuche") — population control

Trigger: total person count > **150** → fires with p = 1/20 per round;
count > **250** → fires unconditionally. Disease name = `random(4)` of
Pest / Cholera / Typhus / Ruhr (cosmetic — mortality is identical).

```
for each player with population > 10 and a living ruler:
    D = random(min(population, 65000))
    while D > 0 and the realm has towns:
        t = random town;  T = min(random(t.population), D)
        t.capacity −= round(T × t.capacity / t.population)
        t.garrison −= round(T × t.garrison / t.population)   # kills army too
        t.population −= T;  D −= T
then EVERY person in the game dies with probability 1/2
    ("<name> starb an <Seuche>", age shown; dead rulers → succession §15.4)
```

### 18.3 Reformation — at the player-chosen year

"…tritt zum evangelischen Glauben über !!!" — Protestantism appears; from
now on religion rolls include Protestant (§15.2) and dynasties may convert
(500 T).

### 18.4 Ottoman invasion ("Türken") — at the player-chosen year

"Eine riesige Reiterhorde moslemischer Türken dringt in das Reich ein !!!"
One realm is taken over by the Moslems ("Die Moslems übernehmen die Macht in
<X>"): its capital town is renamed "<ruler>sburg" and gains **+1000
population (and capacity/garrison)**, and a special army **"Die
Janitscharen"** spawns — **1000 men, quality 50** (~5 power/man). "Die
Janitscharen fordert alle auf, sich zu bekehren !!!" From now on Muslim
dynasties/conversions are possible (§15.2) and the Sultan office matters.

### 18.5 Merchant founder (dynasty refill)

When dynasties die out, a rich merchant can found a new one: "Der Reiche
Kaufmann <X> wird in den Adelsstand erhoben und begründet die Dynastie …" —
standard dynasty founding (§5 values, age 17+random(5), Ritter/Scheich).

### 18.6 Bankruptcy seizure & revolts (see §19.2)

Narrative strings: "Da das Land <X> bankrott ist, wird es vom Gläubiger
gepfändet !!", "Es kommt zu Unruhen in <X> im Gebiet von <Y>. Die
Bevölkerung wählt einen aus ihrer Mitte zu ihrem neuen Führer : <Name>. Das
Gebiet heißt nun <Z>, und sein Herrscher ist <Name>."

---

## 19. Elimination, Bankruptcy & Win Condition

The 30 slots are **fixed-index and never compacted**. "Conquering" a whole
realm = overwrite the loser slot's ruler pointer with the winner's ruler
(aliasing — one ruler can hold many slots; the Handel menu's *merge realms*
consolidates them, §6.2).

### 19.1 Internal strife (popularity crisis)

Trigger: `popularity < 20` **and** dynasty members > 3. The realm collapses:
territory passes to the rival/heir branch (slot pointer overwritten),
popularity resets to 50.

### 19.2 Bankruptcy

Trigger: `treasury < −threshold[titleClassIndex]`:

| Class idx | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| Debt limit (T) | 10k | 15k | 20k | 30k | 40k | 50k | 75k | 100k |

Consequences: the creditor seizes high-value tiles (Stadt/Burg/Palast at
5,000 T of debt each), a replacement ruler is allocated (named from the name
tables; treasury reset to `debt ÷ 2`; replacement-founding values §5), and
the slot pointer is overwritten. Narrative in §18.6.

### 19.3 Win check (after every turn)

If exactly **one distinct non-null ruler pointer** exists across all 30
slots → that dynasty wins: "Sie haben es geschafft!!! <Name> ist der
alleinige Herrscher des ganzen Landes…" + "Das ist Ihr Land!!!"

---

## 20. AI Player Behavior

Dispatch: `dynasty.status` (FREE → skip, AI → script below, else human
menu). The AI uses **the same action primitives and rules as a human**.
Turn script ("Die <name> zieht."):

1. Shared turn upkeep (identical to humans).
2. **Sell harvests**: all grain if `grainPrice > 1.6`; all livestock if
   `cattlePrice > ~2.2` (the upper ~40% of each price range). Never
   stockpiles.
3. Collect the Kaiser/Sultan **tribute pot** if its ruler holds the office.
4. **Build loop** (repeats while movement points remain and a target tile is
   found; targets = first matching tile in a map scan):
   - keep food up: target `tileCount[Kornfeld] × 9 ≳ population`
     (plant Kornfeld/Weide by terrain, claim adjacent land)
   - found a **Dorf** if treasury ≥ 1,000 T (named from the place-name table)
   - build a **Hafen** if treasury ≥ ~700 T and a coastal tile qualifies
   - build a **Burg** if treasury ≥ 5,000 T (≈ 1/20 chance per turn)
   - build a **Palast** if treasury ≥ 10,000 T (≈ 1/20 chance per turn)
   - if a build/claim scan finds **no target** (boxed in) → set the **war
     flag** and leave the loop
5. **Reinforce troops**: each engaged unit gets `random(freeCapacity) + 1`
   recruits; keep the guard level near a `random(treasury/200)` target
   (100 T per guard unit); buy ships up to 600 T × #Häfen.
6. Marriage/heir upkeep (§14.3 runs for its dynasty members).
7. **Merge** one randomly-chosen other slot ruled by the same ruler, if any
   ("<X> vereinigt … und …").
8. **War**: if (warFlag or `random(20) == 0`) and `random(7) == 0` and year
   > 1009 and it has ≥ 1 troop unit → declare war on a random **adjacent**
   realm of a **different religion**, falling back to any adjacent realm
   ("<X> erklärt <Y> den Krieg."). Adjacency = any tile of A orthogonally
   touching a tile of B. Net baseline ≈ 0.7%/turn, but near-certain
   escalation once expansion is blocked (the war flag).
9. Slight extra build-up in years 1006 and 1009 (pre-war preparation).

AI battles and events render without prompts ("fast mode").

---

## 21. UI Screens & Status Texts

### 21.1 Turn-start status report

```
"Wir schreiben das Jahr <Jahr>. Spieler <N>, Sie sind am Zug!
<Der Herrscher / Die Herrscherin> von der <Dynastie> von <Land> ist <Titel>.

Die Getreidevorräte reichen für <N> Leute.
[Die Vorräte aus der Viehzucht reichen für <N> Leute.]
Ihre Bevölkerung besteht nun aus <N> Einwohnern.

Beliebtheit: <Wert> — <Tier-Text §21.2>

Sie haben <N> Taler an Steuern eingenommen.
[Ihre Häfen haben <N> Taler erwirtschaftet.]
Sie mußten <N> Taler Steuern zahlen.        ← tribute
Sie mußten <N> Taler an Sold zahlen.
Sie haben <N> Taler.
Sie können <N> Feld(er) ziehen."
```

### 21.2 Popularity tiers

| Range | Text |
|---|---|
| 0–10 | "Ihr Land steht am Rande einer Revolution !!!" |
| 11–25 | "In ihrem Land gibt es kleinere Aufstände !!!" |
| 26–40 | "Sie sind nicht gerade sehr beliebt." |
| 41–60 | "durchschnittlich" |
| 61–75 | "Nicht gerade niedrig" |
| 76–90 | "Sehr hoch" |
| 91–150 | "Unglaublich Hoch" |

### 21.3 Other screens

- **Tile info panel**: terrain, owner ("Niemand" if none), building, and the
  player's remaining movement points ("Ziehen: N").
- **Kurfürsten list**; **"Wer regiert wen?"** (who-rules-whom overview);
  **Urkunde/chronicle** (Kaiser & Sultan history with reigns and epithets);
  troop list; detail map.
- Intro/registration nag: "Vergessen Sie nicht, sich registrieren zu
  lassen !!!"; quit prompt "Wollen Sie wirklich das Spiel beenden
  ( J / N ) ?"; outro "Thanks for Playing PCKAISER++".

---

## 22. Data Tables (verbatim from the game data)

### 22.1 European first names (50 male + 50 female)

**Male:** Siegfried, Johann, Richard, Nepomuk, Gerald, Gernot, Emmerich,
Phillip, Engelbert, Martin, Klemens, Bernhard, Christoph, Willibald, Lorenz,
Leopold, Friedrich, Heinrich, Ludwig, Hagen, Günther, Franz, Josef, Karl,
Rudolf, Maximilian, Tobias, Horst, Lukas, Ignaz, Georg, Alois, Kurt, Robert,
Roland, Christian, Paul, Florian, Alexander, Napoleon, Christoph, Andreas,
Stefan, Iwan, Thomas, Arthur, Mathias, Xaver, Walter, Viktor

**Female:** Isolde, Sieglinde, Gudrun, Brunhild, Maria, Kriemhild, Andrea,
Minna, Emilia, Constanze, Ludmilla, Simone, Dorothea, Theresa, Margarete,
Anna, Isabella, Irmgard, Lisa, Elisabeth, Helga, Gabriele, Helena, Agnes,
Lea, Katharina, Clara, Claudia, Barbara, Monika, Susanne, Astrid, Tina,
Martina, Klementine, Lorentia, Alexandra, Sigrid, Ulrike, Florentina,
Daniela, Doris, Josefine, Maria Theresia, Annette, Roswitha, Hertha,
Christine, Ruth, Marilies

### 22.2 Ottoman names (10 + 10, for Muslim dynasties)

**Male:** Mohammed, Ali, Saddam, Hussein, Suleiman, Aziz, Hassan, Tarek,
Kemal, Anwar
**Female:** Fatima, Benazir, Asi, Sherezade, Suha, Selina, Farida, Myriam,
Fatima, Sara
*("Saddam" and "Hussein" are separate entries; "Fatima" appears twice.)*

### 22.3 Country names (32, index 0–31)

`[0] Niemand` (vacant sentinel), `[1] Brandenburg`, `[2] Hessen`,
`[3] Bayern`, `[4] Böhmen`, `[5] Sachsen`, `[6] Mähren`, `[7] Tirol`,
`[8] Kurpfalz`, `[9] Flandern`, `[10] Österreich`, `[11] Steiermark`,
`[12] Kärnten`, `[13] Krain`, `[14] Görz`, `[15] Oberpfalz`, `[16] Pommern`,
`[17] Mecklenburg`, `[18] Schlesien`, `[19] Holstein`, `[20] Schwaben`,
`[21] Lothringen`, `[22] Isenburg`, `[23] Holland`, `[24] Friesland`,
`[25] Luxemburg`, `[26] Liechtenstein`, `[27] Lüneburg`, `[28] Zweibrücken`,
`[29] Oldenburg`, `[30] Brabant`, `[31] Ben Mohammed` (Islamic-coded
placeholder; also the "unaffiliated" sentinel dynasty slot).

### 22.4 City names (30 — suggested Dorf names at setup)

Berlin, Kassel, München, Prag, Dresden, Brünn, Innsbruck, Heidelberg,
Brügge, Wien, Graz, Klagenfurt, Laibach, Görz, Trausnitz, Stettin, Schwerin,
Breslau, Kiel, Augsburg, Münster, Isenburg, Amsterdam, Emden, Luxemburg,
Vaduz, Lüneburg, Zweibrücken, Oldenburg, Brüssel
*(Entry "Luxemburg" has a corrupted byte in the original data — the game's
own data-entry mistake.)*

### 22.5 Titles — see §16.1.

### 22.6 Epithets — four pools of 20 (§17.5)

**Pool 1** (long reign + good weight): Der Große, Der Gute, Der Schöne,
Der Lange, Der Gutmütige, Der Tapfere, Der Mutige, Der Reiche, Der Stifter,
Der Tugendhafte, Der Eroberer, Der Keusche, Der Heilige, Der Fromme,
Der Prächtige, Der Löwe, Der Weise, Der Fleißige, Der Ritterliche,
Der letzte Ritter¹

**Pool 2** (long reign + poor weight): Der Lange, Der Sonnenkönig, Der Böse,
Der Schreckliche¹, Der Kühne, Der Eroberer, Der Alte, Der Hammer,
Der Gottlose, Die Geisel Gottes¹, Der Dumme, Der Schwachsinnige¹,
Der Kämpfer, Der Kahle, Der Riese, Der Schlimme, Der Schlaue, Der Fälscher,
Der Wütende, Des Reiches Schande¹

**Pool 3** (short reign + good weight): Der Kurze, Der Kleine, Der Kühne,
Der Tapfere, Der Kahle, Der Keusche, Der Kluge, Der Gutmütige, Der Brave,
Der Gottfrömmige¹, Der Adler, Der Fröhliche, Der Heilige, Der Gute,
Der Magere, Der Schlaue, Der Händler, Der Fremde, Der Redliche,
Der Hinterlistige

**Pool 4** (short reign + poor weight): Der Böse, Der Schreckliche,
Der Stinkende, Der Zwerg, Der Schlaue, Der Fähige, Der Durchtriebene,
Der Räuber, Der Magere, Der Übermütige, Der Schnelle, Der Dumme,
Der Reisende, Der Rohe, Der Starke, Der Verrückte, Der Schläfrige,
Der Unfromme, Der Streitbare *(19 entries — the 20th slot overlaps the
adjacent place-name data; treat as 19 + pad or reuse entry 0)*

¹ stored truncated (last letter cut off) in the original's fixed-width
slots. Duplicates across pools are in the original data.

### 22.7 Religions & adjectives

`katholisch`, `evangelisch`, `moslemisch` (adjective forms used in the
conversion texts: "katholische/evangelische/moslemische Religion").

### 22.8 Disease names

`Pest`, `Cholera`, `Typhus`, `Ruhr`.

### 22.9 Place names (101, for generated towns)

St.Jakob, Mühlwald, Waldzell, Tiefenbrunn, Zelling, Inzendorf,
St.Martin am Wald, Lunz am See, Obergurgel, Unterwalden, Schwyz, Kleinwals,
Unterbach, Grossklein, Vorderbrunn, Hinterwald, Ochsenboden, Waldgrund,
Ofenberg, Schlitters, Moosling, Mehlgrube, Zell, Bruck, Hamburg, Bärlin,
Bonn, Krumpendorf, Neusiedl, Seewalchen, Holzbach, Pforzheim, Schweinfurt,
Frankfurt, Freiburg, Dusseldorf, Bayreuth, Miesmuschel, Venedig, Nuremburge,
Kölln, Mühlbach, St. Lorenz, Franzensburg, Deutsch Wagram, Piefkina,
Witzelsbrunn, Witgenstein, Wasselsbrunn, Brunn, Bern, Rhinomarien,
Schweinebacke, Buchwurmingen, Tarantelstich, Saupaß, Dreikirchen, Grinz,
Wurzelbach, Mahlbeck, Abrahamsburg, Johannesburg, Schiftdruck, Petersburg,
Schönburg, Schöndorf, Posingen, Burgen, Branzheim, Kukshafen, Kopenhafen,
Wattenstein, Großwald, Wartburg, Grünwald, Lemmingshafen, Glasmost,
Neuenscheid, Neu-Jerusalem, Weißenbach, Burgdorf, Baldwurz, Nasenloch,
Flügelschlag, Holzschlag, Burggarten, Volksgarten, Schlagham, Mitterreith,
Nasserreith, Gutenrutsch, Halming, Tiefenwies, Wiedenn, Seebruck,
Turmenquark, Waltersee, Frauentürk, Heißenwald, Kaltenbruck, Wien-Hütteldorf
*(+1 empty sentinel. Several entries are deliberate jokes — keep them.)*

### 22.10 Settlement display names & unit abbreviations

`Dorf  `, `Markt `, `Stadt ` (fixed width); `Inf`, `Kav`, `Art`, `Söld.`,
`Rek.`

---

## 23. German UI Strings (verbatim, with translations)

### Market & commerce
| German | English |
|---|---|
| "Überschuß : " | "Surplus: " |
| "Marktpreis pro <Sack Korn / Tier>" | "Market price per <sack of grain / animal>" |
| "Wieviel wollen Sie verkaufen ?" | "How many do you want to sell?" |
| "Das geht nicht !!!" | "That's not possible!!!" |
| "Sie haben diese Runde schon verkauft !!!" | "You already sold this round!!!" |
| "Das haben Sie diese Runde schon getan !!!" | "You already did that this round!!!" |
| "An welches Land wollen Sie Geld schicken ?" | "Which country do you want to send money to?" |
| "Sie haben zu wenig Geld !!!" | "You don't have enough money!!!" |

### Military & war
| German | English |
|---|---|
| "Kriege sind erst ab dem Jahr 1010 erlaubt !" | "Wars are only allowed from year 1010!" |
| "Sie haben dieses Jahr schon einmal Krieg geführt !" | "You already waged war this year!" |
| "Sie haben nicht genug Truppen !" | "You don't have enough troops!" |
| "Welche Truppe ausbilden ( 5 Taler pro Soldat ) ?" | "Which troop type to train (5 T/soldier)?" |
| "(1) Infantrie, keine zusätzlichen Kosten" | "(1) Infantry, no extra cost" |
| "(2) Kavallerie, 500 T…" / "(3) Artillerie, 1000 T…" | cavalry +500 T / artillery +1000 T |
| "Wieviele Söldner wollen Sie (50T pro Mann):" | "How many mercenaries (50T per man):" |
| "Wieviele Soldaten rekrutieren:" | "How many soldiers to recruit:" |
| "müssen Ihre Truppen auf Ihrem Territorium stationieren!" | "must station your troops on your own territory!" |
| "<Dynasty> zieht mit seinen Truppen." | "<Dynasty> moves its troops." |
| "Es steht keine feindliche Truppe !!!" | "There is no enemy troop!!!" |
| "Es kam zu einer Schlacht : Verluste : <X> aus <Name> : <Y> Mann" | "A battle took place: losses: <X> from <Name>: <Y> men" |
| "Die Angreifer/Verteidiger wurden vernichtet." | "The attackers/defenders were annihilated." |
| "Der Krieg endete unentschieden." | "The war ended in a draw." |
| "Will <Land> ein Ende des Krieges ?" | "Does <country> want an end to the war?" |
| "<X> will ein Ende des Krieges." | "<X> wants an end to the war." |
| "Der Krieg mußte wegen des hereinbrechenden Winters beendet werden." | "The war had to be ended because of the oncoming winter." |
| "<X> beendet den Krieg durch die Gefangennahme des Herrschers von <Y>" | "<X> ends the war by capturing the ruler of <Y>" |
| "Das gehört nicht Ihrem Feind !" | "That doesn't belong to your enemy!" |
| "So viel steht Ihnen nicht zu !" | "You are not entitled to that much!" |
| "Sie können sich nur Felder aneignen, die direkt an Ihr Land grenzen !" | "You can only annex tiles directly bordering your land!" |
| "Der Sieger ist : <name> hat einen Anspruch von <N> Punkten." | "The winner is: <name> has a claim of <N> points." |
| "Alles zählt soviel, wie es kostet. Ein Markt zählt 2500 Punkte, eine Stadt 5000." | "Everything counts what it costs. A market = 2500 points, a city = 5000." |

### Plunder
| German | English |
|---|---|
| "Hier steht doch gar nichts !" | "There's nothing here!" |
| "Sie haben diese Runde schon geplündert !" | "You already plundered this round!" |
| "Wollen sie wirklich ihr eigenes Land plündern !" | "Do you really want to plunder your own land!" |
| "Sie erbeuteten <N> Taler" | "You looted <N> Taler" |

### Espionage & assassination
| German | English |
|---|---|
| "Wieviele Attentäter schicken ( 250T/Mann ) :" | "How many assassins to send (250T/man):" |
| "So viele Spione würden zu sehr auffallen" | "That many spies would be too conspicuous" |
| "Sie scheinen keine Ahnung von Anschlägen zu haben !!!" | "They seem to know nothing about assassinations!!!" |
| "Die Attentäter sind auf dem Weg !!!" | "The assassins are on their way!!!" |
| "<Victim> wird hinterhätig ermordet !!!" *(sic — original typo)* | "<Victim> is treacherously murdered!!!" |
| "Ein Mordanschlag auf <Victim> scheitert !!!!" | "An assassination attempt on <Victim> fails!!!!" |
| "<N> mutmaßliche Attentäter wurden gefangengenommen." | "<N> suspected assassins were captured." |
| "Einer von ihnen gesteht unter Folter, aus <Land> geschickt worden zu sein !!!" | "One confesses under torture to having been sent from <Land>!!!" |
| "konnten nichts in Erfahrung bringen" | "could not learn anything" |

### Marriage & coercion
| German | English |
|---|---|
| "H(e)irat vorschlagen" / "(B)ürgerlich heiraten" | "Propose marriage" (hotkey E) / "Commoner marriage" (B) |
| "Ist die/der Angesprochene einverstanden ? ( j/n )" | "Does the person addressed agree? (y/n)" |
| "Angenommen !" / "Abgelehnt !" | "Accepted!" / "Rejected!" |
| "Es gibt zur Zeit keinen passenden Partner !" | "There is currently no suitable partner!" |
| "<A> heiratet <B>" | "<A> marries <B>" |
| "wollen Sie <X> unter Androhung des Todes zwingen, ihre Religion anzunehmen ?" | "force <X> on pain of death to adopt your religion?" |
| "wollen Sie <X> zur Heirat zwingen ?" | "force <X> into marriage?" |
| "… zur Abdankung als Kaiser/Kurfürst zwingen ?" | "force … to abdicate as Emperor/Elector?" |
| "<V> verlangt von <L>, zu sterben oder sich zur <adj>en Religion zu bekehren !!!" | "<V> demands <L> die or convert to the <adj> religion!!!" |
| "Die Dynastie <X> nimmt die <adj>e Religion an." | "Dynasty <X> adopts the <adj> religion." |
| "<L> weigert sich, sich zu bekehren, und wird hingerichtet !!!" | "<L> refuses to convert and is executed!!!" |
| "<V> zwingt <L> zur Heirat." | "<V> forces <L> into marriage." |
| "… muß als Kaiser/Kurfürst abdanken." | "… must abdicate as Emperor/Elector." |

### Dynasty & succession
| German | English |
|---|---|
| "<name> ist im Alter von <age> Jahren verstorben." / "R.I.P." | "<name> died at the age of <age>." |
| "<A> und <B> feiern die Geburt eines Sohnes / einer Tochter." | "<A> and <B> celebrate the birth of a son / daughter." |
| "Name des Kindes: " | "Name of the child: " |
| "<dynasty> tritt zum Islam über!!!" | "<dynasty> converts to Islam!!!" |
| "<A> und <B> trennen sich wegen religiöser Differenzen." | "<A> and <B> separate over religious differences." |
| "Die Weisen erwählen <Name> zum Erben des Toten." | "The wise men choose <Name> as the deceased's heir." |
| "Die Weisen gehen auf die Suche … die Dynastie endgültig ausgestorben ist … die Reichtümer und Länder an eine befreundete Dynastie weiterzugeben…" | dynasty extinct: realm passes to another dynasty |
| "Nach weiteren Beratungen … alle alten Adelsgeschlechter ausgestorben sind…" | total-extinction ending |
| "Der Reiche Kaufmann <X> wird in den Adelsstand erhoben und begründet die Dynastie …" | a merchant founds a new dynasty |
| "Da ein islamisches Land nicht von einer Frau regiert werden kann, …" | "Since an Islamic land cannot be ruled by a woman, …" (§15.5) |

### Elections & offices
| German | English |
|---|---|
| "Ein neuer Kaiser soll gewählt werden." | "A new Emperor shall be elected." |
| "Die Kurfürsten ziehen sich zurück. Nach längeren Beratungen einigen sie sich, daß …" | "The Electors withdraw. After long deliberation they agree that …" |
| "… niemand für diese Würde geeignet ist." | "… nobody is suited for this dignity." |
| "… allein <X> in Frage kommt." | "… only <X> comes into question." |
| "Die dunkle Zeit des Interregnums bricht an." | "The dark age of the Interregnum begins." |
| "Kandidat A/B: <Name>", "Sie erhielten folgende Bestechungsgelder: …" | candidates + bribes received |
| "Sind sie für Kandidat A oder B ?" | "Are you for candidate A or B?" |
| "Die Wahl wird ausgewertet." | "The election is being evaluated." |
| "Die Kurfürsten können sich nicht einigen." | "The Electors cannot agree." |
| "<Name> geht als Sieger aus der Wahl hervor." | "<Name> emerges as the winner." |
| "Neuer Kurfürst wird <X>." | "<X> becomes the new Elector." |
| "Der Posten als Kurfürst bleibt vakant." | "The Elector's seat remains vacant." |
| "Der neue Sultan ist <X>." | "The new Sultan is <X>." |

### Events
| German | English |
|---|---|
| "Ein verherendes Erdbeben verwüstet das Reich … Betroffen sind folgende Länder:" | "A devastating earthquake ravages the empire… Affected are:" |
| "<name> starb an <Seuche>" | "<name> died of <disease>" |
| "Eine riesige Reiterhorde moslemischer Türken dringt in das Reich ein !!!" | "A huge horde of Muslim Turkish horsemen invades the empire!!!" |
| "Die Moslems übernehmen die Macht in <X>" | "The Muslims seize power in <X>" |
| "Die Janitscharen fordert alle auf, sich zu bekehren !!!" | "The Janissaries call on everyone to convert!!!" |
| "Da das Land <X> bankrott ist, wird es vom Gläubiger gepfändet !!" | "Since <X> is bankrupt, it is seized by the creditor!!" |
| "Es kommt zu Unruhen in <X> …" | "Unrest breaks out in <X> …" |
| "Dem Dorf/Markt <name> in <player> wurde das Markt-/Stadtrecht verliehen." | "<name> was granted market/city rights." |

### Win / misc
| German | English |
|---|---|
| "Sie haben es geschafft!!!" | "You did it!!!" |
| "<Name> ist der alleinige Herrscher des ganzen Landes…" | "<Name> is the sole ruler of the whole land…" |
| "Das ist Ihr Land!!!" | "This is your land!!!" |
| "Wollen Sie wirklich das Spiel beenden ( J / N ) ?" | "Do you really want to quit (Y/N)?" |
| "Wir schreiben das Jahr <N>." | "The year is <N>." |
| "Niemand" | "Nobody" (unowned) |

---

## 24. Assets & Rendering

VGA 320×200-era tile graphics; extracted images in `imgs/` (two sizes:
`large_NN` map tile, `small_NN` minimap/UI), 38 indices:

| Idx | Content | Use |
|---|---|---|
| 00 | green speckled | Ebene |
| 01 | gray mountain | Berg |
| 02 | solid blue | open water (terrain 2) |
| 03–17 | water-land transitions | shoreline variants, 1:1 with terrain 3–17 (sprite index = terrain value; verified: 03 land below, 04 land above, 06 land left, 10 land right) |
| 18 | crop rows + path | Kornfeld |
| 19 | farmstead + animals | Weide |
| 20 | small red buildings | Dorf |
| 21 | red brick buildings | Markt |
| 22 | dark brick + wall | Stadt |
| 23 | gray stone fortress | Burg |
| 24 | castle + tower + banner | Palast |
| 25 | ship at dock | Hafen |
| 26–34 | harbor/ship/water scenes | decorations |
| 35 | sword | troop marker |
| 36 | shield emblem | capital marker |
| 37 | red ship close-up | UI icon |

(The table above reflects the *verified extraction* in `imgs/` /
`client/assets/tiles/large/`; an earlier draft listed the 19–27 block one
index too high and a ruler-figure tile that does not exist in the set.)

Owned tiles are tinted/marked per player; the troopMarker draws a unit icon.
The original used a 4:3 VGA mode with a map viewport, a side panel (tile
info, movement points) and a message line.

---

## 25. RNG & Numeric Conventions

- `random(N)` → uniform integer `[0, N−1]` (Borland Pascal `Random(N)`);
  `random(0)` = 0. `RandomReal` → uniform `[0, 1)`.
- The original re-seeds from the system timer at game start (and before each
  battle encounter — irrelevant for a clone; any decent PRNG is fine).
- Money and population are 32-bit signed integers; several rolls cap their
  inputs at 65,000 (a clone with 64-bit ints can ignore these caps or keep
  them for fidelity).
- Percentages are computed in integer math with explicit rounding where
  marked `round(...)` (the original uses 6-byte Borland Reals there).

---

## 26. Original-Engine Reference (record layouts)

Memory layout of the original (DS-relative) for anyone cross-checking
against `PCKAISER.EXE`/`PCKAISER.OVR` with the toolchain in
`../ovr_analysis/`:

- Map: `DS:0x7104 + X×0xB0 + Y×4`, bytes {terrain, owner, building, marker}.
- Player record: `DS:0x64e2 + slot×0x5E`: `+0` titleClass, `+1/+3` capital
  X/Y, `+5/+7` cursor, `+9` population, `+0xd` troopCapacity, `+0x11`
  armySize, `+0x13+2t` tileCount[t], `+0x25`/`+0x29` harvests, `+0x2d`
  treasury, `+0x31` guardLevel (32-bit), `+0x35` popularity/weight (ONE
  field, §8.4), `+0x3b` last tax amount, `+0x43` last tribute paid,
  `+0x4b` movementPoints, `+0x4d` ruler ptr, `+0x51` troops list,
  `+0x55` towns list, `+0x59..+0x5d` turn flags.
- Dynasty table: `DS:0x7044 + dyn×6`: status / religion / members ptr.
- Person: `+2` name[20], `+0x17` age, `+0x18` dynasty, `+0x19` gender,
  `+0x1a` spouse, `+0x1e` children, `+0x22` sibling-list back-ptr.
- Town: `+2` name[20], `+0x17` pop, `+0x19` capacity, `+0x1b` garrison,
  `+0x1d` building, `+0x1e/+0x20` X/Y.
- Troop: `+2` name[20], `+0x17` men, `+0x19` class, `+0x1a` quality,
  `+0x1b` garrison-counted, `+0x1c/+0x1e` X/Y.
- Key globals: `[0xa804]` year, `[0xa81e]` Kurfürst list, `[0xa822]` Kaiser,
  `[0xa826]` Sultan, `[0xa82a]/[0xa82e]` chronicles, `[0xa834]`
  assassination orders, `[0xa838]` persons, `[0xa812]/[0xa818]` prices,
  `[0xa80a]/[0xa80e]` tribute pots, `DS:[2]` growth cap (10).
- Data tables: titles `DS:0x233e` (16-byte entries), European names
  `DS:0x24ce` (16-byte, gender blocks of 50), Ottoman names `DS:0x2b0e`,
  epithet pools `DS:0x2c4e/0x2d8e/0x2ece/0x300e`, place names `DS:0x31b2`
  (21-byte), player/dynasty names `DS:0x1e38` (21-byte), religion adjectives
  `DS:0x1df8` (21-byte), building values `DS:0x1dd6`, disease names
  `DS:0x1c` (8-byte), bankruptcy thresholds `DS:0x3c`.

Full procedure-level cross-reference: `../ovr_analysis/RE_FINDINGS.md`.

---

## 27. Fidelity Notes, Approximations & Original Bugs

**The `[APPROX]`/`[DESIGNED]` items** (everything else in this guide is exact):
1. **Intel fuzz magnitude** (§13.2): jitter exists; ±10% uniform is the
   adopted design value (the exact original jitter was never located).
2. The AI's coastal-site test and some scan orderings (§20) are simplified
   descriptions of its "first matching tile" map scans.
3. **War-round movement allowance** (§11.2): `[DESIGNED]` — normal
   movement roll per unit per war round.
4. **AI claim settlement** (§11.2, `proc_00CC0B`): the human path is exact;
   the AI's automatic settlement is `[APPROX]` — same economy, greedy
   adjacent-tile annexation, remainder in cash.

(The weight smoothing, formerly `[APPROX]`, is now exact — §8.4:
`round(stat × (100+S)/82)`, capped at ×1.05/turn.)

**Original bugs/quirks a clone may reproduce or fix:**
- **Newborn age is uninitialized memory** (§15.3) — fix: age 0.
- "Luxemburg" city-name corruption (§22.4); several truncated epithets
  (§22.6); the "hinterhätig" typo (§23); duplicate names in the tables.
- A **vote tie** in the Kaiser election leaves the throne vacant even with
  willing candidates (§17.3) — original behavior.
- Disease mortality is independent of the disease name, and one outbreak
  kills 50% of *all persons in the world* — brutal but original (§18.2).
- Plundered town loot is **not** deducted from the victim's treasury
  (§11.5).
- The AI **attacker's** peace decision (§11.2) contains a dead war-score
  check (a local flag is set unconditionally before it is tested), so an AI
  attacker effectively wants peace as soon as all its units are back on
  their pre-war positions; only the AI defender's "war is decided" test is
  live — original behavior.

**All tuning constants in one place** (for a config file): town thresholds
500 / 1000 / 5; surplus clamp [−30, +15]; growth cap +10%/turn, divisor 82;
popularity factor `(100+S)/82` capped ×1.05, nudge ±[1,3], clamp [0,100];
religion-change popularity −70; food 1 per person; yields `(20+random(15))`
/ `(20+random(10))` per field × efficiency {1,2}; tax `[pop, 2×pop)`;
tribute 10%; harbor `random(70)`; wages 0.5 T/man; prices [1.0–2.0] /
[1.5–2.5]; ship cap 600 × Häfen; setup years ≥ 1011; war year 1010;
war rounds ≤ ~21 (winter > 20); end-of-war threshold 0.4; capital bonus
3000; casualty factor `0.2 × (RandomReal/2 × 0.2) × defense`; plunder rolls
§11.5; espionage tables §13; guard cap 50; assassination `15/(50−survivors)`;
marriage acceptance 25%; death roll `2/(90−age)`; birth throttle 1/4 then
1/2; disease 150/250 + 1/20 + 50%; earthquake 1/10, radius 10, 50%/tile,
town roll `random(pop)`; epithets 1/2 + 4×20 pools; election bribes
`random(treasury)` repeated; AI war (1/20 or blocked) × 1/7; bankruptcy
ladder §19.2; prestige weights 1/1/10/1,000/10,000/20,000 with thresholds
§16.2.
