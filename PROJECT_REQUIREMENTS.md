# PC Kaiser Mobile — Project Requirements

Mobile-first clone of PC Kaiser (1999, Martin Gelter). Setting: Holy Roman Empire ~1000 AD.
The world always has **30 realms** (as in the original); up to **16** of them are human players, the rest are AI. Goal: be the last dynasty standing.

---

## Platform & Tech

- Android + iOS
- Flutter + Flame (client)
- Dart (shelf) + PostgreSQL (backend, online mode only) — game logic is a single shared Dart package used by client and server
- Firebase Cloud Messaging (push notifications, online mode only)
- Self-hosted via Docker + Nginx

---

## Game Modes

### Local (V1 — primary focus)
- 1–16 human players on one device, passing the device between turns ("hot seat"); AI plays the remaining realms (30 total)
- **Multiple named game slots**: several games can exist side by side; each slot is auto-saved after every completed turn (no manual save button)
- Full game state stored locally on device (SQLite or JSON file)

### Online (V2 — design for it now, implement later)
- Async multiplayer, up to 16 human players per match; the server simulates the AI realms and world events between human turns
- Push notifications when it's your turn
- **Turn timer, configurable by the match host** at creation (off / 12h / 24h / 48h / 7d): when a player's turn or pending decision expires, the server auto-resolves it (turn → end turn after upkeep with no actions; decision → its AI/default fallback) and play continues. A reminder push goes out at ~80% of the timeout.
- Game state lives in server JSONB; client is read-only until your turn
- Same domain model and game logic as local mode (single Dart implementation — see ARCHITECTURE.md)
- Player identity: device-generated UUID, no auth in V1 of online

---

## Input & UX

- Touch-only input (no hardware keyboard; text fields — founder/child/town names, setup years — use the on-screen keyboard)
- Pinch-to-zoom and pan the map
- Tap tile → action sheet (available builds/actions with costs shown inline)
- Sliders for numeric inputs: espionage agents, market sell amounts, trade ship investment
- Slim status row (treasury + movement points, tap for full "Mein Reich" stats; popularity warning when < 30) + persistent labeled bottom action bar (Handel/Militär/Spionage/Sonstiges/Info — no hamburger). Population/food/popularity live in the Info sheet.
- **Event feed**: a scrolling chronicle of game events (filters: my realm / wars / dynasty news / world events) plus a "since your last turn" recap card at turn start — replaces the original's modal text walls. Built on the `GameEvent` stream from game_core.
- **Undo within turn**: deterministic actions (cursor moves, tile claims, builds, demolish before confirmation) can be undone while the turn is open; the undo stack clears on any randomized or irreversible action (battle, ship investment, espionage, market sale, end turn)
- Confirmation dialog before irreversible actions (demolish, assassination, declare war)
- Popularity warning indicator when popularity < 30 (before the 20-threshold crisis)
- Smart defaults in game setup: pre-fill Reformation year 1020 and Ottoman year 1040 (both editable, minimum 1011 per the original's validation)
- Language: German UI by default (v1); English as optional setting

### Accessibility

- Color-blind-safe realm palette **plus pattern/symbol overlays** on tile ownership (color is never the only channel)
- Scalable UI text (respect system font scale), minimum touch target 48×48 dp
- Event feed and HUD readable by screen readers (semantic labels on Flame overlays where feasible)

### Hidden information & espionage

Deviation from the original (which exposed most numbers in info screens): other realms' **treasury, food stocks, army composition and guard level are hidden** by default. They are revealed only through espionage missions (§13 of ORIGINAL_GAME.md), shown as fuzzed values (±10%) with an in-game timestamp ("as of year X"). Public information: map ownership, dynasty names/titles/religion, town names and sizes (tier), Kurfürsten list, Kaiser/Sultan, chronicle. This makes the espionage system genuinely useful. Intel reports appear in the event feed and stay accessible per realm.

---

## Core Game Mechanics (faithful to original unless noted)

See `ORIGINAL_GAME.md` (§1–27) for exact formulas — all constants there are traced from the original binaries unless marked `[APPROX]`. Summary of key systems:

- **Map**: 80×44 tile grid, procedurally generated every game (§3); 9 building types, per-tile ownership (§4)
- **Turn order**: round = every slot takes a turn; per-turn pipeline (§6): upkeep (food → population → popularity → taxes → tribute → harbors → wages → movement roll) → action phase → dynasty events → elimination → win check
- **Economy**: taxes `[pop, 2×pop)`, feudal tribute (10% into Kaiser/Sultan pot), harbor income, army wages (§7)
- **Food & population**: grain/meat yields; surplus % clamped to [−30, +15]; growth capped at +10%/turn (divisor 82); famine kills soldiers; popularity and "weight" are ONE stat — multiplicative food update capped ×1.05/turn plus ±[1,3] balance nudge (§8)
- **Market**: annual global price roll; one sell per good per turn (§9.1)
- **Trade ship**: 50/50 invest mechanic, once per turn, cap 600 T × harbors (§9.2)
- **Espionage**: counter-espionage rolls, reveal checks, deferred assassination with public sponsor reveal on failure; guard level capped at 50 (§13)
- **War**: year ≥ 1010 gate; once per year per player; war-round loop ends by ruler capture (capital occupied → realm takeover + coercion), mutual peace, or winter after ~20 rounds. End-of-war: leading side's score = "claim"; claim ≥ 0.4 × loser territory value → occupied tiles convert; smaller claim → **claim settlement** (winner annexes adjacent enemy tiles at building-value cost, unspent claim paid out 1:1 in Taler from the loser's treasury) (§11); post-war coercion only on ruler capture (§12)
- **Military**: 5 T/soldier base; Infantry (+0), Cavalry (+500), Artillery (+1000) fixed cost. Söldner = 50 T/man + wages. Garrison capacity from towns; troops stationed on own territory (§10)
- **Realms & dynasties**: 30 fixed slots (index 1–30, 0 = "Niemand"), never compacted; dynasty status byte dispatches human/AI; religion is a dynasty property (§2, §19)
- **Marriage**: eligibility = unmarried, opposite gender, age ≥ 14, age gap < 10, different dynasty, same religion; AI acceptance 25% (§14)
- **Dynasty events**: aging/death roll `2/(90−age)`, births, divorce on religion mismatch, Islamic succession crisis (§15)
- **Succession**: fixed heir-priority list (first male child → first male member → spouse → any child → any member → random); human dynasties pick from a menu (§15.4)
- **Elimination**: popularity crisis (popularity < 20 AND dynasty > 3 members); bankruptcy (debt beyond per-title threshold) (§19)
- **Win condition**: sole distinct non-null ruler pointer across all 30 slots (§19.3)
- **Epithets**: four pools of 20; awarded only when a Kaiser/Sultan dies in office, 50% chance of none, pool picked by reign length (>10 y) × weight (>60) (§17.5)
- **Noble titles**: 12 male + 12 female classes (Ritter → König, Scheich → Kalif); promotion by prestige score, never demote (§16)
- **Offices**: 7 Kurfürst seats, Kaiser/Sultan elections with bribery phase (§17)
- **Events**: earthquake (10%/round), disease (>150 persons), Reformation and Ottoman invasion at player-chosen years, merchant founders, revolts (§18)
- **AI behavior**: rule-based script using the same action primitives as humans (§20)

### Intentional deviations from original

| Original behavior | Change | Reason |
|---|---|---|
| Newborn age left uninitialized (heap garbage) | Newborns start at age 0 | Confirmed original bug (§15.3) |
| Shareware cutoff at year 1019/1020 | Removed | Copy protection artifact |
| German-only UI | German default, English option (in-app toggle) | Preserve original feel; broader audience via toggle |
| Keyboard number input | Sliders / steppers | Touch UX |
| Separate claim step before building | Building on adjacent unowned land claims the tile implicitly; claim-only action removed from the UI (AI still uses it) | Touch UX, fewer taps |
| Weide only on Berg | Weide also buildable on Ebene | Gameplay request |
| Starting position: any spot with > 2 land neighbors (islands possible) | Starting landmass must span ≥ 50 connected tiles | No boxed-in starts |
| Unlimited marriage proposals per turn | One proposal per turn | Pacing/balance |
| Wars against any realm | Wars only against realms with a shared border | Plausibility, map gameplay |
| Earthquakes from year 1000 | Earthquakes only from year 1005 | Build-up grace period |
| 50% "phantom birth" for unmarried members without candidates (§15.3) | Removed — children require married parents | Plausibility |
| Post-war coercion: convert or die | Retain mechanic, modernize wording | Core game design |
| Other realms' stats visible in info screens | Hidden by default; espionage reveals (fuzzed) | Makes espionage meaningful |
| Modal text walls for events | Event feed + turn recap | Mobile UX, async play |
| Single implicit save | Multiple named game slots (each auto-saved) | Mobile expectations |
| No action revert | Undo for deterministic actions within turn | Touch mistaps |
| Combat (§11.3): tile defense MULTIPLIED the occupant's own losses; def 0 = never any casualties | `losses = round(P_opponent × R / (2 × (1 + def)))` — defense now reduces losses, open ground bleeds | Wars were walking races to the capital; combat now matters |
| Disease kills 50% of ALL persons (§18.2) | Mercy rule: the last living member of a dynasty is spared | No zero-counterplay dynasty wipes |
| AI election bribes: random(treasury) repeated until a 0-roll (≈ whole treasury spent) | Campaign budget capped at half the treasury | Healthy AI economies |
| War declarable on any non-vacant realm | Not against a slot your own ruler already holds (aliasing, §19) | Merging is the intended path; self-war is nonsense |
| Troop merge/disband any time | Forbidden while at war (the war state is keyed to the troop list) | Consistent war bookkeeping |
| Unbounded event history in memory | In-state event log capped at 1,000 entries (`prunedEventCount` keeps absolute positions stable) | Bounded saves and state copies |

Two undo/movement clarifications that follow from the table: founding a **Dorf** rolls its starting population, so it counts as a randomized action and clears the undo stack like battles and investments do. And peacetime troop **repositioning** (any own tile for 1 movement point) intentionally differs from war movement (strictly 1 tile per move): war marches are the tactical game, peacetime stationing is logistics.

---

## Protect-New-Players Rule

In the **first 10 in-game years** (years 1000–1009):
- **Random** deaths are suppressed: no natural aging death rolls, no disease event
- **Assassinations are NOT suppressed** — they are deliberate player actions and resolve normally in this window
- Elimination via popularity crisis or bankruptcy is suppressed
- AI players also cannot be eliminated during this window
- Wars are already impossible in this window (original year-1010 gate)
- Purpose: prevent the game from ending abruptly through bad luck before players understand the systems

---

## Architecture Constraints

- Game logic must be **pure and testable** — no side effects in domain functions
- Local and online share the **same game state model** (same JSON schema)
- Persistence is the only difference: local writes to device, online submits to server
- Server always validates turns; client never mutates state directly (online mode)
- Modules must be small and isolated: economy, population, war, espionage, events, succession each in their own unit
- Auto-save triggers after every turn completion, before handing off to next player

---

## V1 Scope (Local Game)

**In scope:**
- Full local hot-seat multiplayer (1–16 human players, 30-realm world)
- All game mechanics from ORIGINAL_GAME.md
- AI players (behavior TBD — see open questions)
- Touch map interaction (pan, zoom, tile selection)
- All build types, espionage, marriage, dynasty events
- Auto-save / resume

**Out of scope for V1:**
- Online multiplayer
- Push notifications
- Server backend
- Authentication
- Leaderboard / stats

---

## Open Questions / Missing Data

All unknowns are resolved — `ORIGINAL_GAME.md` (§1–27) is traced from the original binaries and is the single source of truth:

- Initial map layout → procedural generator (§3.2)
- Starting conditions → §5; setup-year validation (≥ 1011) traced 2026-06-10
- Military combat & casualty formulas → §10, §11.3
- War-round termination (ruler capture / mutual peace / winter, ~20-round cap) → §11.2 (traced 2026-06-10 from `proc_00E097`)
- Weight/popularity → ONE stat with exact formula (§8.4, traced 2026-06-10)
- Earthquake town damage → exact (§18.1, traced 2026-06-10)
- AI behavior → §20
- Epithet assignment → §17.5 (on Kaiser/Sultan death in office)

Remaining deliberate stand-ins are listed in §27 (intel fuzz ±10% by design, AI scan-order simplifications, war-round movement allowance `[DESIGNED]` = normal movement roll) — all are final design decisions, none block V1.

---

## Non-Functional Requirements

- Cold start to playable state: < 3 seconds on mid-range devices
- Map pan/zoom: 60 fps
- Turn auto-save must complete before control passes to next player
- Game state JSON must be forward-compatible (add fields, never remove)
- Offline-first: local game must work with no network
