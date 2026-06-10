# Project Checklist — PC Kaiser Mobile

Step-by-step plan and progress tracker. Check items off as they are completed; add notes inline. Update together with `CLAUDE.md` / `ARCHITECTURE.md` when scope changes.

Spec source of truth: `ORIGINAL_GAME.md` (§ references below point there).

---

## Phase 0 — Project Setup

- [x] Flutter workspace: app (`client/`, Flutter 3.44.1) + `packages/game_core` (pure Dart, no Flutter deps)
- [x] ~~CI via Jenkinsfile~~ removed 2026-06-10: no CI for the app for now; Jenkins will only be used for the backend (V2). Run the test suites locally before pushing (see README)
- [x] Decide save format (single JSON file vs SQLite) and write `save_service` skeleton — **decision: one JSON file per named slot** (same `GameState` schema as server JSONB; atomic temp-file+rename writes); `client/lib/services/save_service.dart`
- [x] Import tile assets from `imgs/` (38 indices, §24) into the Flutter asset bundle (`client/assets/tiles/{large,small}/NN.png`)

## Phase 1 — Game Core: World & State

- [x] State model: GameState, Realm (slots 1–30), Dynasty, Person, Town, Troop, Tile (§2) with JSON (de)serialization — forward-compatible (add-only) (`lib/src/state/`; persons referenced by stable int ids instead of pointers)
- [x] GameEvent model `{year, slot, type, visibility, payload}` — feeds event feed, recap, replay (incl. `visibleTo()` filter)
- [x] Visibility module: `visibleStateFor(state, slot)`, IntelReport storage (ARCHITECTURE.md) — also filters pending decisions, assassination orders, events; zeroes `rngSeed`
- [x] Injectable seeded RNG (`random(N)`, `RandomReal`, §25) — exact Borland Pascal LCG, platform-independent determinism
- [x] Map generation: land patches, lakes, shoreline mask (§3) — invariant tests in `test/map_generator_test.dart`
- [x] New-game setup: starting cross, founder, starting values (§5) — `src/setup/new_game.dart`; all starting dynasties Catholic per §15.2; **replacement-dynasty values (§19) still pending** (Phase 4 elimination work)
- [x] Buildings, tile values, build/claim/demolish actions, religion change (§4) — `src/actions/`; sealed `PlayerAction` with JSON wire format + `applyAction` dispatcher. Hafen build = owned water tile adjacent to own land (matches starting-cross convention). Title-ladder reset on conversion is an approximation until §16.2 promotions exist (Phase 3)
- [x] Golden tests: map statistics, setup invariants (population/capacity/garrison sums) — `test/new_game_test.dart` cross-checks tileCount vs map, aggregate sums, 150 owned tiles

## Phase 2 — Game Core: Turn Pipeline

- [x] Round/turn driver: year increment, price re-roll, world-event phase, per-slot upkeep (§6.1) — `src/turn/turn_pipeline.dart` (`startGame` / `completeTurn` / `checkWinCondition`); world-event phase is a stub until Phase 4
- [x] Economy: taxes, tribute pots, harbor income, wages (§7) — single 10% tribute into the religion's pot, office holder collects on own turn and pays none; wages 0.5 T/man for regulars AND Söldner (§27 constants list gives one rate)
- [x] Food, growth (+10% cap), famine desertion, town transitions, popularity & weight (§8) — exact formulas incl. ×1.05 cap, divisor 82, balance nudge; **[INTERPRETATION]** food consumption: stock −= population after S (grain first), since the spec implies but never states the write-back
- [x] Market sales + trade-ship investment (§9) — `SellGood`/`InvestShips` actions + annual `rollMarketPrices`
- [x] Movement points by title class (§6.3) — incl. Muslim→Christian class equivalents
- [x] Protect-new-players rule — `newPlayerProtectionActive()` helper (years ≤ 1009); consumed by Phase 3 death rolls & Phase 4 eliminations
- [x] Auto-save hook after each completed turn — `client/lib/services/local_game_session.dart` (`endTurn()` saves before handoff; tested)

## Phase 3 — Game Core: Dynasty & Society

- [x] Aging & death roll, succession priority, ruler aliasing across slots (§15, §19) — `rules/dynasty.dart`; death rolls suppressed in the protection window; heir takes ALL the deceased's slots; spouse-inheritance across dynasties
- [x] Births (age 0 fix), marriages, divorce, Islamic succession crisis (§14, §15) — incl. phantom births, conversion divorce hooked into ChangeReligion; crisis crowns the female heir but flips the dynasty to AI
- [x] Titles & prestige score, promotions (§16) — `rules/titles.dart`, checked in every upkeep, never demotes
- [x] Kurfürsten, Kaiser/Sultan elections incl. bribery, chronicle & epithets (§17) — `rules/offices.dart` + `ActiveElection` state (JSON-persistable, survives async waits); AI bribery `random(treasury)`-until-0; vote tie keeps throne vacant (original behavior); epithet 2×2 matrix. Sultan electorate = Muslim rulers (interpretation of "same pattern")
- [x] Pending-decisions queue — `marriageConsent`, `heirChoice` (provisional priority heir applied immediately, re-crowned on resolution), `childName` (non-blocking rename), `electionBribe`, `electorVote`; all resolved via the `ResolveDecision` action; AI deciders resolve inline

## Phase 4 — Game Core: Conflict & Events

- [x] Troops: recruitment, garrisons, merge/disband/reinforce (§10) — `rules/troops.dart` + actions; merge requires same class+quality (simplification)
- [x] War: declaration gates, war-round loop, termination (ruler capture / mutual peace / winter >20 rounds), per-tile combat, end-of-war 0.4-threshold resolution, conquest transfer, troop return (§11) — `rules/war.dart` + `ActiveWar` state; war actions (`WarMove`/`WarPlunder`/`WarPeaceWish`/`WarEndRound`/`SettlementAnnex`/`SettlementFinish`); AI sides hold position until Phase 5 (their traced peace rules incl. the dead-check quirk are in)
- [x] Post-war coercion — only on ruler capture (§12) — first applicable option; human victor/loser via `coercion`/`convertOrDie` pending decisions, AI via coin flip
- [x] Plunder (§11.5) — exact rolls; town loot does NOT touch the victim's treasury (original quirk kept)
- [x] Espionage & assassination (§13) — counter-espionage rolls, 5-check economy reveals, ±10% fuzz into IntelReports; deferred assassination resolved at the target's end-of-turn with public sponsor reveal on failure
- [x] Events: earthquake, disease, Reformation, Ottoman invasion, merchant founders, bankruptcy & revolts (§18, §19) — `rules/events.dart`. Interpretations: Reformation converts one random AI dynasty; Ottoman target prefers AI realms; merchant-founder rate `[DESIGNED]` 1/10 per vacant slot per round. Disease suppressed in protection window
- [x] Elimination & win check (§19) — strife + bankruptcy (title-class debt ladder, tile seizures, replacement dynasty via §5 formula); win check was done in Phase 2

## Phase 5 — Game Core: AI

- [x] AI turn script: sell, build loop, recruit, guard, ships, merge, war flag (§20) — `src/ai/ai_turn.dart`, uses the same action primitives via `applyActionInPlace`; realm merge (§6.2) implemented as `MergeRealms` action usable by humans too. Omitted: §20.9 "slight extra build-up in 1006/1009" (untraced cosmetic). AI without units recruits one first [INTERPRETATION]
- [x] AI war-round movement & peace decision (§11.2) — attacker marches on the enemy capital, defender walks home; AI-vs-AI wars fast-forward in silent mode; `advanceUntilHuman` driver for local loop & server (stops when a human's action phase or a human-defended war is reached)
- [x] Full-AI smoke test: 30 AI realms, run 200 years headless without invariant violations — `test/ai_test.dart`; `tool/sim_report.dart` prints event statistics (seed 777: 13 wars / 591 battles / 19 coronations / 6 realms left by 1200)

## Phase 6 — Flutter Client (V1, local)

- [x] Flame map rendering: tiles, ownership tint **+ color-blind-safe pattern overlays**, troop markers, pinch-zoom + pan — `game/map_game.dart` (whole map rasterized to one Picture per state change → 1 draw call/frame); `[APPROX]` shoreline mask→sprite mapping needs a visual pass on device
- [x] Tap-tile action sheet with costs; confirmation for irreversible actions — `widgets/tile_sheet.dart`
- [x] Bottom HUD (treasury, population, food, popularity, movement points) — incl. popularity-<30 warning indicator
- [x] Event feed (filters: my realm / wars / dynasty / world) + "since your last turn" recap card — `widgets/event_feed.dart`
- [x] Undo stack: deterministic actions undoable within turn; cleared on randomized/irreversible actions — `state/game_controller.dart` (snapshot stack)
- [x] Hidden-info views: own realm full, others filtered via `visibleStateFor`; intel shown per realm in the Info screen (a dedicated intel-history screen can come in polish)
- [x] Menus: commerce, military, espionage, misc, info screens, chronicle — `widgets/menus.dart` (sliders for amounts per PROJECT_REQUIREMENTS); war panel + claim-settlement UI in `widgets/war_panel.dart`
- [x] Setup flow: players, names, country, first Dorf, Reformation/Ottoman years (defaults 1020/1040, min 1011) — `screens/setup_screen.dart`
- [x] Hot-seat handoff screen (blocks predecessor's intel) + pending-decision prompts — full-screen blocker → recap card → decision dialogs (marriage consent, heir choice, child name, elector vote, bribery, coercion, convert-or-die)
- [x] Multiple named game slots; auto-save after every turn; resume — home screen + SaveService
- [x] Accessibility: 48dp touch targets (padded tap targets), semantic labels on HUD stats; system font scale respected by default — needs an on-device audit in Phase 7
- [ ] Localization: English default, German optional (string table from §23) — basic en/de table + in-app toggle in `l10n/strings.dart`; full §23 coverage still to import

> Note: not yet run on a device/emulator — no Android toolchain on this machine. All logic is covered by tests (controller turn flow, undo, handoff, auto-save); rendering and gestures need a visual pass when a device is available.

## Phase 7 — Polish & Release (V1)

- [ ] Performance: 60 fps pan/zoom, <3 s cold start on mid-range device — structurally addressed (map rasterized to one cached Picture, single draw call per frame); **measurement requires a device** (`flutter run --profile`)
- [x] App icons (generated from the original Burg tile via `flutter_launcher_icons`, Android adaptive + iOS) and store metadata (`store/metadata.md`, EN/DE; screenshots pending device). **Sound/music: skipped by decision (2026-06-10).**
- [ ] Beta round (TestFlight / Play internal testing) — prepared: release-signing scaffold (`key.properties` pattern in `build.gradle.kts`), build & upload steps documented in README.md; needs device + store accounts
- [x] README.md with run/test/build/deploy instructions — **standing rule: keep it up to date with every setup/build/deploy change** (also in CLAUDE.md)

## Phase 8 — Online Mode (V2)

- [ ] Dart shelf backend: players/matches routes, JSONB state, turn endpoint (ARCHITECTURE.md)
- [ ] Server-side simulation advance (AI realms + world events between human turns)
- [ ] Server-side `visibleStateFor` filtering on all state responses
- [ ] Host match settings (turn timer off/12h/24h/48h/7d); `turn_deadline` bookkeeping
- [ ] Timeout job: auto-resolve expired turns/decisions; reminder push at ~80% of timeout
- [ ] Human-vs-human war clock: war-round inputs as pending decisions with `war_round_timeout` deadline (default 10 min, host-configurable); expiry falls back to AI war logic for that round; explicit delegate-war-to-AI action; WAR_STARTED push (ARCHITECTURE.md "Human-vs-human wars online")
- [ ] FCM push (YOUR_TURN / YOUR_DECISION / TURN_REMINDER / WAR_STARTED), token refresh
- [ ] Match lifecycle: create/join/list, eliminated-player skipping
- [ ] Docker + Nginx deployment, pg_dump backups

---

## Resolved questions log

- 2026-06-10: World size = 30 realms (original), max 16 humans.
- 2026-06-10: Single game-logic implementation in Dart (`game_core`), shared by client and server; backend is Dart shelf, not Node.
- 2026-06-10: War termination traced from `proc_00E097` (ruler capture / mutual peace / winter after ~20 rounds); coercion only on ruler capture. Spec updated in §11/§12.
- 2026-06-10: Protect-new-players rule scoped to **random** deaths only (aging, disease); assassinations resolve normally in years 1000–1009.
- 2026-06-10: Remaining micro-gaps traced from the disassembly: setup years validated ≥ 1011 (§5); earthquake town damage exact (§18.1: `T = random(pop)`, proportional capacity/garrison loss); weight ≡ popularity, ONE stat with exact formula `round(stat × (100+S)/82)` capped ×1.05/turn + ±[1,3] nudge (§8.4); surplus clamp [−30, +15] and growth divisor 82 (§8.2); religion change −70 popularity (§4); guard cap 50 (§13); per-round town normalization pass (§8.3). War-round movement allowance: `[DESIGNED]` = normal movement roll per unit per round. Intel fuzz ±10% adopted as final design.
- 2026-06-10: Modern features adopted: hidden info + espionage intel reports, event feed, undo within turn, accessibility baseline, multiple named save slots, host-configurable online turn timers (see PROJECT_REQUIREMENTS.md / ARCHITECTURE.md).
- 2026-06-10: **Control follows the ruler** (post-review decision): when a slot's ruler pointer is overwritten cross-dynasty (conquest §11.2, inheritance §15.4), the slot's dispatch entry (status/humanPlayer) adopts the new ruler's home-dynasty controller (`alignSlotControl`). The original's behavior here is untraced; without this a captured human slot would still be dealt to the old player.
- 2026-06-10: Post-review fixes: Hafen build = unowned coastal water adjacent to own land, taking ownership (was impossible — ownership check preceded the water rule); plunder guards against ownerless tiles; war-resume no longer duplicates feed events or re-runs the interrupted AI's action phase; bribery dialog charges the deciding finalist's treasury.
- 2026-06-10: Menu parity vs. original screenshots verified; gaps closed: "(B)ürgerlich heiraten" (`MarryCommoner`, 25% roll, spouse joins the dynasty — replaces the removed phantom births as the no-candidate fallback), Dynastien-Info (tap a realm in Info), Siedlungs-Info, Statistiken (public data only). Jenkinsfile removed — Jenkins reserved for the V2 backend.
- 2026-06-10: Military/UX round: troop markers in the visible state encode the owner slot → map draws sword (attacker/idle own) vs. shield (war defender); capital marked by a realm-colored pennant (no ruler sprite exists); new units ask for their station first (capital or town; `RecruitTroops`/`HireSoeldner` got optional x/y validated against own territory); Truppenliste overview + tap-an-army-on-the-map info/edit sheet; religion options hidden until available (§15.2: evangelisch after Reformation, moslemisch after Ottoman invasion — core gates already enforced this); dynasty info shows the spouse's country or "(bürgerlich)".
- 2026-06-10: War UX rework: tap an own army to select, tap any tile to march toward it (greedy orthogonal steps; combat on contact, capital capture wins — engine already matched §11); war panel shows the enemy Königssitz, live war scores and a Plündern button for the selected unit; war tile-sheet removed. Recap shows only war results (warWon "X gewinnt den Krieg gegen Y"/warDraw/winter/rulerCaptured) — battles/conquests/plunder stay in the full feed. AI-plays-player report: traced to pre-fix saves parked on an AI slot; `resume` now heals such saves via advanceUntilHuman (persisted), and `runAiTurn` got a defensive human-dynasty guard.
- 2026-06-10: Online human-vs-human wars (V2): wars stay blocking/sequential (one global `activeWar`, original semantics preserved), but war-round inputs run on a short **war clock** (`war_round_timeout`, default 10 min) instead of the match turn timer; expired inputs fall back to the existing AI war logic per round; players can delegate the war to the AI; both combatants get a WAR_STARTED push. Rejected: parallel war track (breaks replay + shared-state mutation), WEGO battle plans (kills tactics), plain blocking (days-long match freeze). Full design in ARCHITECTURE.md "Human-vs-human wars online".
- 2026-06-10: Full-codebase review round — bug fixes: war `movesLeft` now drops a dead unit's entry (was index-misaligned after mid-round losses; merge/disband additionally forbidden while at war, greyed out in the UI); election-bribe validation only counts the gifts actually applied (negative amounts could offset an over-spend); stale decisions (electionBribe/electorVote after the election ended, heirChoice with a dead heir) resolve as no-ops instead of throwing — a throw restored the removed decision and re-prompted forever; `armySize` clamped in town death; event log capped at `maxRetainedEvents` (1,000) with `prunedEventCount` keeping recap baselines stable (sim_report tallies incrementally now); chronicle records match by new `personId` (table names repeat); earthquake epicenter covers the full map; election tie-break uses an explicit shuffled-position tiebreaker (Dart sort is unstable); religion-change popularity clamps 0–100 like every other write. Design changes (all in PROJECT_REQUIREMENTS deviations table): combat formula `losses = round(P_opponent × R / (2 × (1 + def)))` — defense reduces losses, open ground bleeds (original: defense multiplied own losses, def 0 = no casualties; wars were walking races — sim: 164 wars/4,936 near-lossless battles → meaningful attrition); disease mercy rule (last dynasty member survives); AI election bribes capped at half treasury; no war against a same-ruler slot; Dorf founding counts as randomized for undo. ARCHITECTURE.md documents the single-global-war constraint as the biggest V2 unwind.
- 2026-06-10: End-of-war "claim settlement" traced (the suspected plunder-budget screen): winner's war score = claim; claim ≥ 0.4 × loser territory → occupied tiles convert; smaller claim → human winner annexes loser tiles adjacent to own land at building-value cost, `F` converts the unspent claim 1:1 into Taler from the loser's treasury; AI winner settles automatically (`proc_00CC0B`, [APPROX]). §11.2/§11.5/§23 updated.
