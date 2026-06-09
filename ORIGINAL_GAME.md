# PC Kaiser — Complete Clone Implementation Guide

Self-contained spec for building a faithful clone of **PC Kaiser** ("PCKAISER++"),
a 1999 German medieval strategy/dynasty-simulation game by Martin Gelter.
Setting: Holy Roman Empire circa 1010 AD. Up to ~16 human+AI players each rule one
realm; the goal is to be the last dynasty standing by conquest or rivals' bankruptcy.

**Confidence labels:** `[CONFIRMED]` = exact constants traced from x86 disassembly.
`[ESTIMATE]` = reasoned approximation; clearly flagged for playtesting/tuning.

---

## 1. Game Overview

- Turn-based strategy, 1–~16 players (human or AI), single-screen map
- Each player controls one realm: a ruler, a dynasty, and a territory of provinces
- **Win condition**: be the only dynasty remaining (pure elimination — no score)
- **Time span**: starts in year 1010 AD
- **Languages**: German UI throughout (translations provided in this guide)

---

## 2. Map Structure `[CONFIRMED]`

| Property | Value |
|---|---|
| Storage grid | 44 columns × 80 rows = 3,520 tiles |
| Playable area | 43 × 79 (right column and bottom row are border/padding) |

**Per-tile data (4 fields):**

| Field | Notes |
|---|---|
| occupied flag | 0 = vacant/water, 1 = occupied land |
| **terrain/field type** | 0–8 enum (see §3) |
| **owning player index** | 0-based |

---

## 3. Field / Building Types `[CONFIRMED]`

Nine types, indexed 0–8:

| Index | German name | English name | War score multiplier | Food yield/turn | Build cost |
|---|---|---|---|---|---|
| 0 | keine / Wasser | none / water | 0 | 0 | — |
| 1 | Kornfeld | grain field | 100 | 5 | 100 T |
| 2 | Weide | pasture | 150 | 5 | 150 T |
| 3 | Dorf | village | 1,000 | 5 | 1,000 T |
| 4 | Markt | market town | 2,500 | 4 | — |
| 5 | Stadt | city | 5,000 | 10 | — |
| 6 | Burg | castle | 5,000 | 10 | 5,000 T |
| 7 | Palast | palace | 10,000 | 10 | 10,000 T |
| 8 | Hafen | harbor/port | 700 | 0 | 700 T |

**Additional build actions:**

| German | English | Cost |
|---|---|---|
| (S)chiff | ship (trade vessel) | 700 T |
| (A)breißen | demolish a field | 100 T |

**Settlement-class display names** (fixed-width, note trailing spaces):
`Dorf  `, `Markt `, `Stadt `

**Military unit-type abbreviations:** `Inf`, `Kav`, `Art`, `Söld.`, `Rek.`
(Infanterie / Kavallerie / Artillerie / Söldner / Rekruten)

---

## 4. Player Record `[CONFIRMED]`

One record per player (up to 30). Each record holds:

| Field | Type | Notes |
|---|---|---|
| **class byte** | byte | Social rank; 0 = lowest. Gates movement, tribute, marriage |
| **population** | uint32 | People to feed per turn |
| **army size** | uint32 | Subtracted from pop in food formula; also = counter-espionage strength |
| **grain field count** | uint16 | # Kornfeld tiles owned |
| **livestock field count** | uint16 | # Weide tiles owned |
| **harbor count** | uint16 | # Hafen tiles; > 0 shows harbor-income line in status screen |
| **grain stock** | uint32 | "Getreidevorräte" — current grain, in person-feeding units |
| **meat stock** | uint32 | "Viehzuchtvorräte" — current livestock, in person-feeding units |
| **treasury** | int32 | Taler; can go negative (debt) |
| **popularity** | uint16 | Updated [0, 100]; displayed [0, 150] |
| **last target coords** | (x, y) | Grid position of last colony/conquest action |
| **taxes this turn** | uint32 | Tax income generated this turn |
| **harbor income this turn** | uint32 | Harbor income this turn |
| **tribute this turn** | uint32 | 10% of treasury paid upward this turn |
| **wages this turn** | uint32 | Mercenaries + army upkeep paid this turn |
| **movement points** | uint16 | Remaining moves this turn |
| **ruler pointer** | ref | Points to this dynasty's Person record; null = slot vacant |
| **mercenary roster** | ref | List of mercenary units |
| **invested this turn** | bool | Trade-ship investment flag; reset end-of-turn |
| **sold grain this turn** | bool | Market sell flag; reset end-of-turn |
| **sold cattle this turn** | bool | Market sell flag; reset end-of-turn |

---

## 5. Person (Dynasty Member) Record `[CONFIRMED]`

One record per living dynasty member:

| Field | Type | Notes |
|---|---|---|
| **name** | string[20] | Up to 20 characters |
| **age** | byte | Incremented once per turn; death certain by ~88 |
| **class byte** | byte | Social rank; indexes into class table; 0 = commoner, 31 = sentinel |
| **gender** | byte | 0 = male, 1 = female |
| **spouse** | ref | Points to spouse's Person record; null = unmarried |
| **home province X** | uint16 | Column in province grid |
| **home province Y** | uint16 | Row in province grid |

---

## 6. Global State `[CONFIRMED]`

| Field | Notes |
|---|---|
| **current year** | Starts 1010; incremented each full round |
| **reformation year** | Player-chosen at game setup |
| **grain price** | Float; rolled once per year; shared by all players |
| **cattle price** | Float; rolled once per year; shared by all players |
| **war started flag** | Prevents re-triggering the war-start event |
| **reformation started flag** | Prevents re-triggering the Reformation event |
| **current active player index** | 0-based |
| **pending event queue** | Elimination/narrative events batched for display |
| **dynasty member list** | For the annual aging loop |

---

## 7. Per-Turn Order of Operations

One full round = each player takes their turn in sequence. When control returns to
player 0, the year increments. Each player's turn runs in this exact order:

1. **Gate**: if `population == 0`, zero population and reset popularity to 50
2. **Food production** (grain/meat yields added to stock)
3. **Population growth** (delta from food surplus/deficit)
4. **Popularity update** (food balance test, ±1–3)
5. **Tax income** generated and added to treasury
6. **Feudal tribute** (10% of treasury) deducted
7. **Harbor income** added to treasury
8. **Wages** deducted (mercenaries + regular army)
9. **Movement points** rolled (class-tiered)
10. **End-of-turn flags reset** (grain/cattle sold, ship invested)
11. **Narrative events**: aging, death rolls, births, succession crises
12. **Elimination checks** (Mode 0: popularity crisis; Mode 1: bankruptcy)
13. **Win check** (sole dynasty remaining?)

**Year increment** (once per full round, when player index == 0):
- Increment year counter
- Roll new global grain and cattle market prices

---

## 8. Economy — Per-Turn Treasury Pipeline `[CONFIRMED]`

### 8.1 Tax Income

```
taxesCollected = random(population) + population     # uniform in [population, 2×population)
treasury += taxesCollected
```

### 8.2 Feudal Tribute

```
# Gated on: player has a liege AND treasury > 0
tribute = treasury / 10
treasury -= tribute
```

Two structurally-identical 10% transfers can fire per turn (to your designated liege,
and to the Emperor), but only the second is displayed. Practical clone simplification:
one flat 10% per turn while any feudal superior exists.

The tribute gate also checks the **religion byte** of the dynasty's class-table entry:
`religion == 2` (Muslim/Ottoman) pays tribute to a different faction, not the Holy
Roman Emperor.

### 8.3 Harbor Income

```
harborIncome = 0
for i in 1..harborCount:
    harborIncome += random(70)     # uniform [0, 69] per harbor
treasury += harborIncome
```

Mean: ~34.5 Taler per harbor per turn.

### 8.4 Wages

```
wages = 0
for each mercenary unit:
    wages += unit.count × unit.wageRate
wages += armySize × 0.5            # regular soldiers: 0.5 T each
treasury -= wages
```

### 8.5 Net Ledger Summary

```
treasury += random(pop) + pop      # tax: [pop, 2×pop)
treasury -= treasury / 10          # tribute: ~10%
treasury += Σ random(70)           # harbors: [0,69) each
treasury -= armySize×0.5 + Σ mercs # wages
```

---

## 9. Food & Population System `[CONFIRMED structure, ESTIMATED base_factor]`

### 9.1 Food Production

```
grain_yield = (random(15) + 20) × grainFieldCount / 128
meat_yield  = (random(10) + 20) × livestockFieldCount / 128

grainStock += grain_yield
meatStock  += meat_yield
```

Grain yield multiplier: random in [20, 34]. Meat yield multiplier: random in [20, 29].
`base_factor = 128` is a confirmed approximation (exact value is clamped in [128, 130]).

### 9.2 Population Growth

```
netSurplus = grain_yield + meat_yield – population
delta = clamp(netSurplus / 100, –30, +15)
population = population × (100 + delta) / 100
```

Delta range [–30%, +15%] per turn. Asymmetric: famine collapses dynasties faster
than food surplus grows them.

### 9.3 Popularity Update (Food Balance)

```
balanced = (grainStock ≤ 2×meatStock) AND (meatStock ≤ 2×grainStock)

if balanced:
    popularity += random(3) + 1      # gain [1, 3]
else:
    popularity -= random(3) + 1      # loss [1, 3]

popularity = clamp(popularity, 0, 100)
```

This is a **ratio check** — a tiny realm with 1 grain and 1 meat is just as "balanced"
as one with 10,000 grain and 6,000 meat.

### 9.4 Disease Events

Four disease types (Pest, Cholera, Typhus, Ruhr) reduce population directly when
food reserves fall below consumption. Exact mortality formula not yet decoded.

---

## 10. Market — Grain & Cattle Trade `[CONFIRMED]`

### 10.1 Annual Price Roll

Fires once per round (when the year increments):

```
grainPrice  = (random(11) + 10) / 10    # uniform [1.0, 2.0] Taler
cattlePrice = (random(11) + 15) / 10    # uniform [1.5, 2.5] Taler
```

Prices are **global** — every player trades at the same price all year.

### 10.2 Sell Transaction

Menu keys: `(K)orn verkaufen` (grain) and `(R)inder verkaufen` (cattle):

```
if stock ≤ 0:               # menu entry silently absent
    return

if alreadySoldThisTurn:
    show "Sie haben diese Runde schon verkauft !!!"
    return

show "Überschuß: <stock>"
show "Marktpreis pro <goodsName>: <price>"
amount = readPlayerInput()

if amount < 0 or amount > stock:
    show "Das geht nicht !!!"
    return

stock    -= amount
treasury += amount × price
alreadySoldThisTurn = true
```

One sale per good per turn. No haggling. Pure `amount × globalPrice`.

| Good | Goods name string |
|---|---|
| Grain ("Korn") | "Sack Korn" |
| Cattle ("Rinder") | "Tier" |

---

## 11. Trade Ship Investment `[CONFIRMED]`

```
maxInvestment = harborCount × 600

# Validation:
if chosenAmount > treasury:       error "not enough money"
if chosenAmount > maxInvestment:  error "can't invest that much"
if chosenAmount == 0:             abort

treasury -= chosenAmount
investedThisTurn = true

# 50/50 outcome:
if random(2) == 0:                    # PROFIT
    delta  = random(chosenAmount) + 1
    result = chosenAmount + delta     # [chosenAmount+1, 2×chosenAmount]
else:                                 # LOSS
    delta  = random(chosenAmount) + 1
    result = chosenAmount - delta     # [0, chosenAmount-1]

treasury += result
```

Best case: exactly double your investment. Worst case: lose everything.
One investment per turn.

---

## 12. War Scoring `[CONFIRMED]`

Runs at war's end (or each war turn):

```
occupiedTotal = countOccupied(side1) + countOccupied(side2)
if occupiedTotal == 0:
    return draw

average = Σ troopSize(allOccupiedProvinces) / occupiedTotal

for side in {1, 2}:
    score[side] = 0
    for each province p occupied by side:
        ratio  = troopSize(p) / average
        ratio  = clamp(ratio, 129, 16384)
        score[side] += fieldTypeMultiplier[fieldType(p)] × ratio

    if side holds the other side's capital province:
        score[side] += 3000

winner = side with higher score (tie = draw)
```

All arithmetic is 32-bit. The clamp [129, 16384] prevents any single garrison
from dominating. Field type multipliers: see §3.

---

## 13. Espionage `[CONFIRMED costs and odds]`

All missions: player picks `count ∈ [1, 30]` agents (above 30: "too conspicuous").
Cost deducted upfront.

| Mission | Cost per agent |
|---|---|
| `(D)aten ausspionieren` (spy on economy) | 200 T |
| `(T)ruppen ausspionieren` (spy on army) | 200 T |
| `(A)nschlag verüben` (assassination) | 250 T |
| `(v)erstärken` (reinforce counter-espionage) | 100 T `[ESTIMATE]` |

### 13.1 Counter-Espionage Roll

```
# For economic espionage:
caught    = min(defense, random(2×defense + 2))
survivors = min(count − caught, 99)

# For military espionage:
caught    = min(defense, random(2×defense + 5))
survivors = min(count − caught, 49)
```

`defense` = target's army/counter-espionage strength.

If `survivors ≤ 0`: show "konnten nichts in Erfahrung bringen", abort.

### 13.2 Reveal Rolls — Economic Espionage

Five independent checks (`random(N − survivors) ≤ threshold` = success):

| # | N | Threshold | Reveals |
|---|---|---|---|
| 1 | 55 | 50 | Target's treasury (fuzzed — see §13.3) |
| 2 | 55 | 30 | Target's grain stock |
| 3 | 55 | 30 | Target's meat stock |
| 4 | 60 | 20 | Target's army/dynasty summary |
| 5 | 60 | 5 | Target's counter-espionage strength |

More surviving agents → smaller pool → higher reveal probability → becomes
guaranteed once `N − survivors ≤ threshold + 1`.

### 13.3 Intelligence Fuzzing `[ESTIMATE magnitude]`

Spied numeric values (at minimum, treasury) are jittered before display.
A clone **must not** show exact numbers for spied intel.

**Estimated model:** `displayedValue = trueValue × (1 + (random(21) − 10) / 100)`
— uniform ±10% jitter.

### 13.4 Military Espionage Reveal

Single check: `random(50 − survivors) < 15` → reveals troop-list information.

### 13.5 Assassination `[CONFIRMED narrative; ESTIMATE odds]`

Outcome is **deferred** — resolved during narrative events, not immediately.
When queued: show "Die Attentäter sind auf dem Weg !!!"

**Four outcome branches:**
1. No-op: "Sie scheinen keine Ahnung von Anschlägen zu haben !!!" (target has no guard structure)
2. Queued: "Die Attentäter sind auf dem Weg !!!"
3. SUCCESS: "`<Victim>` wird hinterhätig ermordet !!!"
4. FAILURE: "Ein Mordanschlag auf `<Victim>` scheitert !!!! `<N>` mutmaßliche Attentäter wurden gefangengenommen. Einer von ihnen gesteht unter Folter, aus `<Sponsor Land>` geschickt worden zu sein !!!"

**Critical:** a failed assassination **names the sponsoring player** — must trigger
a diplomatic consequence.

**Estimated odds** `[ESTIMATE]`:
```
caught    = min(sentCount, random(2 × targetDefense + 3))
survivors = sentCount − caught
if survivors ≤ 0 or targetClass == 0:  → NO-OP
P(success) ≈ min(0.75, survivors / (survivors + targetDefense))
capturedCount = caught
```

### 13.6 Counter-Espionage Reinforcement `[ESTIMATE]`

Each unit adds `+10` to the defender's counter-espionage strength.

---

## 14. Movement `[CONFIRMED]`

Movement points assigned once per turn, class-tiered:

| Class | Range | Formula |
|---|---|---|
| 9 | [1, 6] | `random(6) + 1` |
| 10 | [3, 8] | `random(6) + 3` |
| 11 | [6, 11] | `random(6) + 6` |
| 12 | [8, 13] | `random(6) + 8` |
| > 12 | [class, class+5] | `class + random(6)` |

---

## 15. Marriage `[CONFIRMED]`

### 15.1 Menu Entries

- `H(e)irat vorschlagen` — formal proposal (hotkey **E**)
- `(B)ürgerlich heiraten` — commoner marriage, always possible (hotkey **B**)

### 15.2 Social Rank

Each person has a **class byte** (0–31 stored in their record) which maps into a
**class table** (one entry per class) with two key fields per entry:
- **eligible flag** (byte 0): gates which marriage/dynasty-growth paths apply
- **religion** (byte 1): 0 = Catholic, 1 = Protestant, 2 = Muslim/Ottoman

The *rank* of a person (`classTable[classByte].religion`) determines marriage
compatibility (same rank = commoner path, different rank = formal proposal path).

### 15.3 Class-Compatibility Gate

```
rank(p) = classTable[p.classByte].religion
flag(p) = classTable[p.classByte].eligibleFlag

if flag(person1)==0 AND rank(person1) != rank(person2):
    → formal proposal path

elif rank(person1) == rank(person2):
    # Commoner marriage:
    reject if: same gender
            or either already married
            or person1.gender != male
            or either under age 14
            or |person1.age − person2.age| >= 10
    → perform union (no negotiation)

else:
    if compatibility_check():
        → formal proposal path
```

### 15.4 Formal Proposal Outcome

```
if flag(person1) != 0 OR person2.classByte == 31:
    skip coin flip → secondary check
else:
    accepted = (random(2) == 1)     # flat 50/50
    if accepted: → ACCEPTED

# Secondary check:
if flag(person2) == 0:
    → REJECTED
accepted = compatibility_check()
```

**ACCEPTED:** show "Angenommen !"; person2's rank inherits person1's rank (class assimilation).
**REJECTED:** show "Abgelehnt !"

`classByte == 31` is an "unclassed" sentinel that bypasses the coin flip.

---

## 16. Dynasty Events `[CONFIRMED]`

### 16.1 Annual Aging & Death Roll

For every living dynasty member, each turn:

```
person.age += 1
if random(90 - age) < 2:
    DIES this turn
```

Death probability = `2 / (90 − age)`:

| Age | Death chance per turn |
|---|---|
| 20 | ~2.9% |
| 40 | 4.0% |
| 60 | ~6.7% |
| 70 | 10.0% |
| 80 | 20.0% |
| 88+ | 100% (certain) |

**On death:** show "`<name>` ist im Alter von `<age>` Jahren verstorben." then "R.I.P."
Succession handled by council (see §17).

### 16.2 Dynasty Growth (New Members)

For each unmarried dynasty member, fires at most once every ~4 turns:

```
if person.spouse != null:                          SKIP
if classTable[person.classByte].eligibleFlag != 0: SKIP
if random(4) != 0:                                 SKIP   # 25% throttle
if person.age ≤ 14:                                SKIP
if person.classByte == 0:                          SKIP   # commoners excluded

candidates = searchForNPCPartner()
if candidates:
    → NPC auto-marriage; show "<A> heiratet <B>"
else:
    if random(2) == 0:                                     # 50% phantom birth
        newMember.gender = 1 − person.gender
        newMember.name = pickName(nameTable, gender, religion)
        newMember.classByte = 0                            # starts as commoner
        newMember.spouse = null
        newMember.age = person.age    # NOTE: copies parent's age (original bug)
        show "<A> und <B> feiern die Geburt eines Sohnes / einer Tochter."
```

**Name selection:** if `person.religion == 2` (Muslim) → Ottoman name table (10/gender);
otherwise → European name table (50/gender).

**Note on age copy:** The game copies the parent's age to the newborn — this appears to
be an original bug. A clone can reproduce it verbatim or zero the age; the "correct"
behavior is unconfirmed.

### 16.3 Religious-Conversion Divorce

If a religious conversion makes a marriage incompatible:

```
person1.spouse = null
person2.spouse = null
show "<dynasty> tritt zum Islam über!!! <A> und <B> trennen sich wegen religiöser Differenzen."
```

### 16.4 Religion Assignment on New Members

```
if   year ≤ reformationYear:  religion = 0          # Catholic, always
elif year ≤ ottomanYear:      religion = random(2)   # 0=Catholic, 1=Protestant (50/50)
else:                          religion = random(3)   # 0=Catholic, 1=Protestant, 2=Muslim
```

A fresh game has all persons at religion 0 (Catholic).

### 16.5 Islamic Succession Crisis

If a dynasty converts to Islam and the only remaining heir is female:

```
show "Da ein islamisches Land nicht von einer Frau regiert werden kann, machen sich
die Weisen von <Land> auf die Suche für einen Nachfolger von <Herrscher>.
Schließlich finden sie heraus, daß es niemand geeigneten gibt. Sie legen das Schicksal
des Landes in die Hände von <X> ( Das ist der Computer )."
→ land transferred to AI control (automatic player elimination)
```

---

## 17. Succession / Heir Selection `[CONFIRMED narrative; ESTIMATE odds]`

Triggered whenever a dynasty member dies. Framed as a **council deliberation**,
not a deterministic genealogical rule.

**Full narrative text (verbatim):**
1. "Ein neuer Kaiser soll gewählt werden."
2. "Die Kurfürsten ziehen sich zurück. Nach längeren Beratungen einigen sie sich, daß `<X>` niemand für diese Würde geeignet ist."
3. "Die dunkle Zeit des Interregnums bricht an."
4. "...allein `<Name>` ... in Frage kommt." / "`<Names>` ... dafür in Frage kommen."
5. "Kandidat A: `<Name>`" / "Kandidat B: `<Name>`" / ", Sie erhielten folgende Bestechungsgelder: A: `<amount>` Taler, B: `<amount>` Taler"
6. "Sind sie für Kandidat A oder B ?" ← **player choice**
7. "Die Wahl wird ausgewertet." / "Die Kurfürsten können sich nicht einigen." / "`<Name>` geht als Sieger aus der Wahl hervor."
8. "Die Weisen gehen auf die Suche nach in Frage kommenden Nachfolgern, müssen aber feststellen, daß die Dynastie endgültig ausgestorben ist. Nach langem Beraten beschließen sie, die Reichtümer und Länder an eine befreundete Dynastie weiterzugeben..."
9. "Nach weiteren Beratungen stellen die Weisen fest, daß alle alten Adelsgeschlechter ausgestorben sind. Einer nach dem anderen verläßt den Saal und verschwindet in die Berge, hoffend, daß die Zeit der großen Könige wiederkommen wird..."
10. "Ihre Wahl fällt schließlich auf `<Name>`." / "Sie beschließen, daß nur einer dieser Ehre würdig ist: Die Weisen erwählen `<Name>` zum Erben des Toten."

**Estimated branch selection** `[ESTIMATE]`:
```
eligible = [m for m in dynasty if m.gender == male and m.age >= 16]

if eligible is empty and dynasty is empty: → TOTAL EXTINCTION (narrative #9)
if eligible is empty:                       → DYNASTY EXTINCT, realm to ally (#8)
if len(eligible) == 1:                      → PLAIN HEIR (#10), no roll
else:
    top 2 by seniority → IMPERIAL ELECTION (#1-7)
    each offers bribe: random(500) × (classByte + 1)
    P(A wins | player backed A) ≈ 0.6 + 0.3 × (bribeA − bribeB)/(bribeA + bribeB)
    P(Interregnum / no agreement) ≈ 0.15
```

---

## 18. Elimination Mechanics `[CONFIRMED]`

### 18.1 The 30-Slot Land Array

Exactly **30 fixed land slots** (never compacted). Conquest = overwrite the loser's
ruler-pointer with the winner's (aliasing merge). The win check is pointer-identity:
exactly one distinct non-null pointer across all 30 slots = that dynasty wins.

### 18.2 Mode 0 — Succession Crisis / Internal Strife

Triggers when **both** hold:
- `popularity < 20`
- `dynasty.memberCount > 3`

**Consequence:**
1. Transfer all of the loser's territory to the winner
2. Overwrite loser's slot ruler-pointer with winner's
3. Reset loser's popularity to 50

### 18.3 Mode 1 — Bankruptcy

Triggers when: `treasury < −bankruptcyThreshold[classIndex]`

**Bankruptcy thresholds by class index:**

| Class index | Debt threshold |
|---|---|
| 0 | −10,000 T |
| 1 | −15,000 T |
| 2 | −20,000 T |
| 3 | −30,000 T |
| 4 | −40,000 T |
| 5 | −50,000 T |
| 6 | −75,000 T |
| 7 | −100,000 T |

**Consequence:**
1. Scan loser's map for high-value tiles (Stadt/Burg/Palast, types 5/6/7)
2. Transfer each such tile to winner; deduct 5,000 T from outstanding debt per tile
3. Allocate new ruler record for absorbed territory; assign name from appropriate name table
4. Reset loser's treasury to `debt ÷ 2`; reset cooldowns (winner → 60, loser → 50)
5. Overwrite loser's slot pointer with winner's

---

## 19. Win Condition `[CONFIRMED]`

```
scan all 30 land slots:
    if exactly one distinct non-null ruler-pointer exists across all slots:
        → WINNER: that dynasty
    if two distinct non-null pointers found:
        → no winner yet, game continues
```

Victory screen: "Sie haben es geschafft!!! `<Name>` ist der alleinige Herrscher des ganzen Landes..."
and "Das ist Ihr Land!!!"

No end-game score. Pure last-dynasty-standing.

---

## 20. Date-Gated Events `[CONFIRMED]`

```
if not warStarted and year >= 1010 and <some condition> > 0:
    trigger war event;  warStarted = true

if not reformationStarted and year >= reformationYear:
    trigger Reformation event;  reformationStarted = true

if year == 1019:
    show shareware-end warning dialog

# year 1020: actual shareware cutoff
```

Post-Reformation: new dynasty members get random(2) Catholic/Protestant instead of
certain Catholic. Post-Ottoman invasion: random(3) including Muslim.

---

## 21. Turn-Start Status Screen `[CONFIRMED]`

```
"Wir schreiben das Jahr <Jahr>. Spieler <N>, Sie sind am Zug!
<Der Herrscher / Die Herrscherin> von der <Dynastiename> von <Ländername> ist <Titel>.

Die Getreidevorräte reichen für <N> Leute.
[Die Vorräte aus der Viehzucht reichen für <N> Leute.]
Ihre Bevölkerung besteht nun aus <N> Einwohnern.

Beliebtheit: <Wert> — <Popularitätsbeschreibung>

Sie haben <N> Taler an Steuern eingenommen.
[Ihre Häfen haben <N> Taler erwirtschaftet.]
Sie mußten <N> Taler Steuern zahlen.
Sie mußten <N> Taler an Sold zahlen.
Sie haben <N> Taler.
Sie können <N> Feld(er) ziehen."
```

**Translations:**
- "Wir schreiben das Jahr X" = "The year is X"
- "Sie sind am Zug!" = "It's your turn!"
- "Der Herrscher / Die Herrscherin" = "The ruler (m/f)"
- "Die Getreidevorräte reichen für N Leute" = "The grain stores will last for N people"
- "Die Vorräte aus der Viehzucht" = "The livestock reserves"
- "Ihre Bevölkerung besteht nun aus N Einwohnern" = "Your population now consists of N inhabitants"
- "Beliebtheit" = "Popularity"
- "Sie haben N Taler an Steuern eingenommen" = "You collected N Taler in taxes"
- "Ihre Häfen haben N Taler erwirtschaftet" = "Your harbors generated N Taler"
- "Sie mußten N Taler Steuern zahlen" = "You had to pay N Taler in taxes"
- "Sie mußten N Taler an Sold zahlen" = "You had to pay N Taler in wages"
- "Sie haben N Taler" = "You have N Taler"
- "Sie können N Feld(er) ziehen" = "You can move N field(s)"

---

## 22. Popularity Tiers `[CONFIRMED]`

Seven bands (popularity updated in [0, 100]; displayed in [0, 150]):

| Range | German text | English |
|---|---|---|
| 0 – 10 | "Ihr Land steht am Rande einer Revolution !!!" | Your land is on the verge of a revolution!!! |
| 11 – 25 | "In ihrem Land gibt es kleinere Aufstände !!!" | There are minor uprisings in your land!!! |
| 26 – 40 | "Sie sind nicht gerade sehr beliebt." | You're not exactly very popular. |
| 41 – 60 | "durchschnittlich" | average |
| 61 – 75 | "Nicht gerade niedrig" | Not exactly low |
| 76 – 90 | "Sehr hoch" | Very high |
| 91 – 150 | "Unglaublich Hoch" | Incredibly high |

Popularity < 20 **and** dynasty size > 3 triggers a succession crisis (§18.2).

---

## 23. Cost Reference `[CONFIRMED]`

### Build Costs

| Action | Cost |
|---|---|
| `(K)orn` — grain field | 100 T |
| `(W)eide` — pasture | 150 T |
| `(D)orf` — village | 1,000 T |
| `(B)urg` — castle | 5,000 T |
| `(P)alast` — palace | 10,000 T |
| `Ha(f)en` — port | 700 T |
| `(S)chiff` — trade ship | 700 T |
| `(A)breißen` — demolish | 100 T |

### Espionage & Other

| Action | Cost |
|---|---|
| Counter-espionage per agent | 100 T |
| Economic spy per agent | 200 T |
| Military spy per agent | 200 T |
| Assassination per agent | 250 T |
| Mercenaries `(S)öldner` | 50 T per man |
| Train troops | 5 T per soldier |
| Religion change — Catholic | free |
| Religion change — Evangelical | 500 T |
| Religion change — Muslim | 1,000 T |

---

## 24. Name Tables `[CONFIRMED — verbatim from game data]`

### 24.1 European Names (50+50)

**Male:** Siegfried, Johann, Richard, Nepomuk, Gerald, Gernot, Emmerich, Phillip,
Engelbert, Martin, Klemens, Bernhard, Christoph, Willibald, Lorenz, Leopold,
Friedrich, Heinrich, Ludwig, Hagen, Günther, Franz, Josef, Karl, Rudolf, Maximilian,
Tobias, Horst, Lukas, Ignaz, Georg, Alois, Kurt, Robert, Roland, Christian, Paul,
Florian, Alexander, Napoleon, Christoph, Andreas, Stefan, Iwan, Thomas, Arthur,
Mathias, Xaver, Walter, Viktor

**Female:** Isolde, Sieglinde, Gudrun, Brunhild, Maria, Kriemhild, Andrea, Minna,
Emilia, Constanze, Ludmilla, Simone, Dorothea, Theresa, Margarete, Anna, Isabella,
Irmgard, Lisa, Elisabeth, Helga, Gabriele, Helena, Agnes, Lea, Katharina, Clara,
Claudia, Barbara, Monika, Susanne, Astrid, Tina, Martina, Klementine, Lorentia,
Alexandra, Sigrid, Ulrike, Florentina, Daniela, Doris, Josefine, Maria Theresia,
Annette, Roswitha, Hertha, Christine, Ruth, Marilies

### 24.2 Ottoman/Exotic Names (10+10)

Used when the dynasty's religion is Muslim.

**Male:** Mohammed, Ali, Saddam, Hussein, Suleiman, Aziz, Hassan, Tarek, Kemal, Anwar

**Female:** Fatima, Benazir, Asi, Sherezade, Suha, Selina, Farida, Myriam, Fatima, Sara

*(Note: "Saddam" and "Hussein" are separate entries. "Fatima" appears twice.)*

### 24.3 Country Names (32 entries, index 0–31)

`[0] Niemand` (vacant sentinel), `[1] Brandenburg`, `[2] Hessen`, `[3] Bayern`,
`[4] Böhmen`, `[5] Sachsen`, `[6] Mähren`, `[7] Tirol`, `[8] Kurpfalz`,
`[9] Flandern`, `[10] Österreich`, `[11] Steiermark`, `[12] Kärnten`, `[13] Krain`,
`[14] Görz`, `[15] Oberpfalz`, `[16] Pommern`, `[17] Mecklenburg`, `[18] Schlesien`,
`[19] Holstein`, `[20] Schwaben`, `[21] Lothringen`, `[22] Isenburg`, `[23] Holland`,
`[24] Friesland`, `[25] Luxemburg`, `[26] Liechtenstein`, `[27] Lüneburg`,
`[28] Zweibrücken`, `[29] Oldenburg`, `[30] Brabant`, `[31] Ben Mohammed`

Index 0 = "nobody" / vacant. Index 31 = Islamic-coded placeholder dynasty.

### 24.4 City Names (30 entries)

Berlin, Kassel, München, Prag, Dresden, Brünn, Innsbruck, Heidelberg, Brügge, Wien,
Graz, Klagenfurt, Laibach, Görz, Trausnitz, Stettin, Schwerin, Breslau, Kiel,
Augsburg, Münster, Isenburg, Amsterdam, Emden, Luxemburg, Vaduz, Lüneburg,
Zweibrücken, Oldenburg, Brüssel

*(Note: entry [24] "Luxemburg" has a corrupted byte in the original data — it
renders as "Luxembu‌σg". This is the game's own data-entry mistake.)*

### 24.5 Noble Titles (12 male + 12 female)

**Male:** Ritter, Baron, Graf, Fürst, Großfürst, Herzog, Erzherzog, König, Scheich, Pascha, Emir, Kalif

**Female:** Burgherrin, Baronin, Gräfin, Fürstin, Großfürstin, Herzogin, Erzherzogin, Königin, Scheichin, Paschin, Emirin, Kalifin

*(Note: "Burgherrin" — "lady of the castle" — substitutes for "Ritterin" as the
lowest female rank; a deliberate authorial choice.)*

### 24.6 Epithets / Bynames (24 entries)

Rulers can receive descriptive bynames. When/how they're awarded is not yet traced:

Der Große, Der Gute, Der Schöne, Der Lange, Der Gutmütige, Der Tapfere, Der Mutige,
Der Reiche, Der Stifter, Der Tugendhafte, Der Eroberer, Der Keusche, Der Heilige,
Der Fromme, Der Prächtige, Der Löwe, Der Weise, Der Fleißige, Der Ritterliche,
Der letzte Ritter, Der Lange, Der Sonnenkönig, Der Böse, Der Schreckliche

*(Note: "Der Lange" appears twice. "Der letzte Ritter" and "Der Schreckliche"
overflow the 9-char display slot into adjacent zero-padding.)*

### 24.7 Religions (3 entries)

`katholisch`, `evangelisch`, `moslemisch`

### 24.8 Disease Names (4 entries)

`Pest`, `Cholera`, `Typhus`, `Ruhr`

---

## 25. Additional German UI Strings `[CONFIRMED]`

### Market & Trade

| German | English |
|---|---|
| "Überschuß : " | "Surplus: " |
| "Marktpreis pro " | "Market price per " |
| "Wieviel wollen Sie verkaufen ?" | "How many do you want to sell?" |
| "Das geht nicht !!!" | "That's not possible!!!" |
| "Sie haben diese Runde schon verkauft !!!" | "You have already sold this round!!!" |
| "Das haben Sie diese Runde schon getan !!!" | "You have already done that this round!!!" |
| "An welches Land wollen Sie Geld schicken ?" | "To which country do you want to send money?" |

### Espionage

| German | English |
|---|---|
| "Wieviele Attentäter schicken ( 250T/Mann ) :" | "How many assassins to send (250T/man):" |
| "Sie scheinen keine Ahnung von Anschlägen zu haben !!!" | "They don't seem to know anything about assassinations!!!" |
| "Die Attentäter sind auf dem Weg !!!" | "The assassins are on their way!!!" |
| "`<Victim>` wird hinterhätig ermordet !!!" | "`<Victim>` is treacherously murdered!!!" |
| "Ein Mordanschlag auf `<Victim>` scheitert !!!! `<N>` mutmaßliche Attentäter wurden gefangengenommen. Einer von ihnen gesteht unter Folter, aus `<Sponsor Land>` geschickt worden zu sein !!!" | "An assassination attempt on `<Victim>` fails!!!! `<N>` suspected assassins were captured. One confesses under torture to having been sent from `<Sponsor Land>`!!!" |
| "konnten nichts in Erfahrung bringen" | "could not learn anything" |

### Marriage

| German | English |
|---|---|
| "H(e)irat vorschlagen" | "Propose marriage" (hotkey E) |
| "(B)ürgerlich heiraten" | "Commoner marriage" (hotkey B) |
| "Angenommen !" | "Accepted!" |
| "Abgelehnt !" | "Rejected!" |
| "... heiraten ?" | "...marry?" |
| "Es gibt zur Zeit keinen passenden Partner !" | "There is currently no suitable partner!" |

### Coercion Menu (post-war victory)

Shown to the winning player after a war victory — allows forcing the defeated ruler to:

| German | English |
|---|---|
| "... zur Heirat zwingen ?" | "Force ... into marriage?" |
| "... zur Abdankung als Kaiser zwingen ?" | "Force ... to abdicate as Emperor?" |
| "... zur Abdankung als Kurfürst zwingen ?" | "Force ... to abdicate as Elector?" |
| "... muß als Kurfürst abdanken." | "... must abdicate as Elector." |

### Dynasty Events

| German | English |
|---|---|
| "`<name>` ist im Alter von `<age>` Jahren verstorben." | "`<name>` died at the age of `<age>` years." |
| "R.I.P." | "R.I.P." |
| "`<A>` heiratet `<B>`" | "`<A>` marries `<B>`" |
| "`<A>` und `<B>` feiern die Geburt eines Sohnes / einer Tochter." | "`<A>` and `<B>` celebrate the birth of a son / a daughter." |
| "Name des Kindes: `<name>`" | "Name of the child: `<name>`" |
| "`<dynasty>` tritt zum Islam über!!!" | "`<dynasty>` converts to Islam!!!" |
| "`<A>` und `<B>` trennen sich wegen religiöser Differenzen." | "`<A>` and `<B>` separate due to religious differences." |

### Succession / Election

| German | English |
|---|---|
| "Ein neuer Kaiser soll gewählt werden." | "A new Emperor is to be elected." |
| "Die dunkle Zeit des Interregnums bricht an." | "The dark age of the Interregnum begins." |
| "Sind sie für Kandidat A oder B ?" | "Are you in favor of Candidate A or B?" |
| "Die Kurfürsten können sich nicht einigen." | "The Electors cannot agree." |
| "`<Name>` geht als Sieger aus der Wahl hervor." | "`<Name>` emerges victorious from the election." |
| "Die Weisen erwählen `<Name>` zum Erben des Toten." | "The wise men elect `<Name>` as heir of the deceased." |

### Win / End

| German | English |
|---|---|
| "Sie haben es geschafft!!!" | "You did it!!!" |
| "`<Name>` ist der alleinige Herrscher des ganzen Landes..." | "`<Name>` is the sole ruler of the entire land..." |
| "Das ist Ihr Land!!!" | "This is your land!!!" |
| "Sie haben zu wenig Geld !!!" | "You don't have enough money!!!" |
| "So viele Spione würden zu sehr auffallen" | "That many spies would attract too much attention" |

---

## 26. Random Number Function `[CONFIRMED]`

`random(N)` returns a uniform integer in `[0, N-1]`.
All probability/range formulas in this guide use this definition.

---

## 27. Image Asset Reference

Images in `imgs/`. Two sizes: `large_NN.png` (map tile) and `small_NN.png` (minimap/UI).
38 indices (00–37):

| Index | Description | Likely use |
|---|---|---|
| 00 | Green speckled terrain | Base grass/land |
| 01 | Gray mountain with snow lines | Mountain tile |
| 02 | Solid blue water | Open water |
| 03–13 | Water-land border transitions | Coastal tiles (various corners/edges) |
| 14 | Green with trees on both sides | Forest / river edge |
| 15 | Green land with path | Open land |
| 16 | Green with rocks | Rocky terrain |
| 17 | Purple-blue landmass | Highland/mountain variant |
| 18 | Green with brown speckles | Open farmland |
| 19 | Yellow-green crop rows | **Kornfeld** (grain field) |
| 20 | Green with red animal shapes | **Weide** (pasture) |
| 21 | Green with small red buildings | **Dorf** (village) |
| 22 | Red brick buildings | **Markt** (market town) |
| 23 | Dark brick buildings with border | **Stadt** (city) |
| 24 | Stone castle with soldier figures | **Burg** (castle) |
| 25 | Castle with multiple soldiers | **Palast** (palace) or Burg variant |
| 26 | Single person/ruler figure | Ruler icon |
| 27 | Water with boat | **Hafen** (harbor) |
| 28 | Blue water with shapes | Sea activity |
| 29 | House with tree | Settlement variant |
| 30 | Knight/cavalry figure | Military unit |
| 31 | Ship/boat | Trade ship |
| 32 | Water with fish | Sea icon |
| 33 | Field with bushes/trees | Forest/Weide variant |
| 34 | Ruins / destroyed building | Demolished province |
| 35 | Red and white sword | Sword / war icon |
| 36 | Black and white heraldic shield | Player crest / dynasty |
| 37 | Ship | Conquest / war event |

---

## 28. Architecture Notes

### Core Systems

1. **Map renderer**: 43×79 tile grid, 9 terrain types, per-tile ownership coloring
2. **Player/dynasty data model**: 30 land slots, player records (§4), person records (§5)
3. **Turn manager**: ordered per-turn pipeline (§7)
4. **Economy**: tax/tribute/harbor/wages (§8)
5. **Food/population**: production + growth + popularity (§9)
6. **Market**: annual price roll + sell transactions (§10)
7. **Trade ship**: 50/50 invest mechanic (§11)
8. **War**: score formula (§12)
9. **Espionage**: counter-espionage rolls + reveal checks + deferred assassination (§13)
10. **Marriage**: class-compatibility gate + 50/50 formal proposal (§15)
11. **Dynasty events**: aging/death + births + divorce + Islamic crisis (§16–§17)
12. **Elimination**: Mode 0 (popularity crisis) + Mode 1 (bankruptcy) + pointer-aliasing win-check (§18–§19)
13. **Date events**: war start (1010+), Reformation (player-set), Ottoman invasion (§20)
14. **UI**: German text strings (§25), popularity tier text (§22), build menu

### Key Design Rules

- 30 land slots are **fixed-index**, never compacted. Conquest = copy winner's ruler-pointer to loser's slot (aliasing), don't null it.
- Win check = exactly one distinct non-null ruler-pointer across all 30 slots.
- The **class table** (one entry per class byte value) has two critical fields: `eligibleFlag` (gates marriage/dynasty-growth paths) and `religion` (0=Catholic, 1=Protestant, 2=Muslim). Getting this table right unlocks both the marriage system and the tribute system.
- Market prices are **global and annual** — one price roll per year, shared by all players.
- Intelligence values shown to the player are **fuzzed** (~±10%) — never show exact spied numbers.

### Mechanics Not in the Manual

- Religion-change costs: Catholic=free, Evangelical=500T, Muslim=1000T
- Assassination count cap: max 30 agents
- Failed assassination outs the sponsor by name (requires diplomatic consequence)
- Coercion menu after war victory (force marriage / abdication of defeated ruler)
- Ruler epithets (24 bynames — trigger condition not yet traced)
- Islamic succession crisis (female heir + Muslim religion = automatic elimination)
- New dynasty members may inherit parent's age (possible original bug)

---

## 29. All Confirmed Random Formulas

| Mechanic | Formula | Range |
|---|---|---|
| Death roll | `random(90 − age) < 2` | P = 2/(90-age) |
| Grain market price | `(random(11) + 10) / 10` | [1.0, 2.0] T |
| Cattle market price | `(random(11) + 15) / 10` | [1.5, 2.5] T |
| Tax income | `random(pop) + pop` | [pop, 2×pop) T |
| Harbor income | `Σ random(70)` per harbor | [0, 69] each |
| Movement (class 9) | `random(6) + 1` | [1, 6] |
| Movement (class 10) | `random(6) + 3` | [3, 8] |
| Movement (class 11) | `random(6) + 6` | [6, 11] |
| Movement (class 12) | `random(6) + 8` | [8, 13] |
| Movement (class >12) | `class + random(6)` | [class, class+5] |
| Counter-espionage (econ) | `min(def, random(2×def+2))` | [0, def] caught |
| Counter-espionage (mil) | `min(def, random(2×def+5))` | [0, def] caught |
| Espionage reveal | `random(N−survivors) ≤/< threshold` | see §13.2 |
| Dynasty growth throttle | `random(4) == 0` | 25%/turn |
| Phantom birth roll | `random(2) == 0` | 50% |
| Trade ship profit/loss | `random(2)` + `random(stake)+1` | [0, 2×stake] |
| Grain yield | `(random(15)+20) × fields / 128` | ~[0.15, 0.27] per field |
| Meat yield | `(random(10)+20) × fields / 128` | ~[0.15, 0.23] per field |
| Popularity change | `random(3) + 1` (±direction) | ±[1,3]/turn |
| War score ratio clamp | `clamp(troopSize/avg, 129, 16384)` | [129, 16384] |
