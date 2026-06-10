# Project Checklist — PC Kaiser Mobile

Step-by-step plan and progress tracker. Check items off as they are completed; add notes inline. Update together with `CLAUDE.md` / `ARCHITECTURE.md` when scope changes.

Spec source of truth: `ORIGINAL_GAME.md` (§ references below point there).

---

## Phase 0 — Project Setup

- [x] Flutter workspace: app (`client/`, Flutter 3.44.1) + `packages/game_core` (pure Dart, no Flutter deps)
- [x] CI: `dart analyze`, `dart test` for game_core; `flutter test` for app (`Jenkinsfile` — Jenkins on VPC, expects Flutter SDK at `$FLUTTER_HOME`, default `/opt/flutter`)
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

- [ ] AI turn script: sell, build loop, recruit, guard, ships, merge, war flag (§20)
- [ ] AI war-round movement & peace decision (§11.2)
- [ ] Full-AI smoke test: 30 AI realms, run 200 years headless without invariant violations

## Phase 6 — Flutter Client (V1, local)

- [ ] Flame map rendering: tiles, ownership tint **+ color-blind-safe pattern overlays**, troop markers, pinch-zoom + pan
- [ ] Tap-tile action sheet with costs; confirmation for irreversible actions
- [ ] Bottom HUD (treasury, population, food, popularity, movement points)
- [ ] Event feed (filters: my realm / wars / dynasty / world) + "since your last turn" recap card
- [ ] Undo stack: deterministic actions undoable within turn; cleared on randomized/irreversible actions
- [ ] Hidden-info views: own realm full, others filtered via `visibleStateFor`; intel report screen per realm
- [ ] Menus: commerce, military, espionage, misc, info screens, chronicle
- [ ] Setup flow: players, names, country, first Dorf, Reformation/Ottoman years (defaults 1020/1040, min 1011)
- [ ] Hot-seat handoff screen (blocks predecessor's intel) + pending-decision prompts
- [ ] Multiple named game slots; auto-save after every turn; resume
- [ ] Accessibility: system font scale, 48dp touch targets, semantic labels on overlays
- [ ] Localization: English default, German optional (string table from §23)

## Phase 7 — Polish & Release (V1)

- [ ] Performance: 60 fps pan/zoom, <3 s cold start on mid-range device
- [ ] Sound/music (optional), app icons, store metadata
- [ ] Beta round (TestFlight / Play internal testing)

## Phase 8 — Online Mode (V2)

- [ ] Dart shelf backend: players/matches routes, JSONB state, turn endpoint (ARCHITECTURE.md)
- [ ] Server-side simulation advance (AI realms + world events between human turns)
- [ ] Server-side `visibleStateFor` filtering on all state responses
- [ ] Host match settings (turn timer off/12h/24h/48h/7d); `turn_deadline` bookkeeping
- [ ] Timeout job: auto-resolve expired turns/decisions; reminder push at ~80% of timeout
- [ ] FCM push (YOUR_TURN / YOUR_DECISION / TURN_REMINDER), token refresh
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
- 2026-06-10: End-of-war "claim settlement" traced (the suspected plunder-budget screen): winner's war score = claim; claim ≥ 0.4 × loser territory → occupied tiles convert; smaller claim → human winner annexes loser tiles adjacent to own land at building-value cost, `F` converts the unspent claim 1:1 into Taler from the loser's treasury; AI winner settles automatically (`proc_00CC0B`, [APPROX]). §11.2/§11.5/§23 updated.
