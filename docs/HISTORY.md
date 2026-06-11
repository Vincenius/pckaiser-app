# Decision & Fix History

Dated log of decisions, review rounds and fixes — kept for lookups.
Rules-version changes (v2–v10) are documented in detail in
`packages/game_core/lib/src/state/versioning.dart` (changelog) and the
deviations table in `PROJECT_REQUIREMENTS.md`; entries here only summarize.

## 2026-06-10

- **World size**: 30 realms (original layout), max 16 humans.
- **Single game-logic implementation** in pure Dart (`game_core`), shared by
  client and server; backend is Dart shelf (not Node).
- **War termination traced** from `proc_00E097`: ruler capture / mutual
  peace / winter after ~20 rounds; coercion only on ruler capture (§11/§12).
- **Protect-new-players** scoped to *random* deaths only; assassinations
  resolve normally in years 1000–1009.
- **Micro-gaps traced** from the disassembly: setup years ≥ 1011 (§5); exact
  earthquake town damage (§18.1); weight ≡ popularity, one stat,
  `round(stat × (100+S)/82)` capped ×1.05 + ±[1,3] nudge (§8.4); surplus
  clamp [−30, +15], growth divisor 82 (§8.2); religion change −70 popularity
  (§4); guard cap 50 (§13); per-round town normalization (§8.3). War-round
  movement allowance `[DESIGNED]` = normal movement roll. Intel fuzz ±10%
  adopted as final design.
- **Modern features adopted**: hidden info + intel reports, event feed, undo
  within turn, accessibility baseline, named save slots, host-configurable
  online turn timers.
- **Control follows the ruler**: when a slot's ruler pointer is overwritten
  cross-dynasty (conquest §11.2, inheritance §15.4), the slot adopts the new
  ruler's home-dynasty controller (`alignSlotControl`).
- **Post-review fixes**: Hafen build = unowned coastal water adjacent to own
  land (was impossible); plunder guards ownerless tiles; war-resume no longer
  duplicates events or re-runs the interrupted AI's action phase; bribery
  dialog charges the deciding finalist's treasury.
- **Menu parity vs. original** verified; gaps closed: `MarryCommoner`
  ("Bürgerlich heiraten"), Dynastien-Info, Siedlungs-Info, Statistiken.
  Jenkinsfile removed — Jenkins reserved for the V2 backend.
- **Military/UX round**: troop markers encode owner slot (sword vs. shield
  icons); capital pennant; station picker for new units (`RecruitTroops`/
  `HireSoeldner` x/y); Truppenliste; religion options hidden until available;
  dynasty info shows spouse country.
- **War UX rework**: tap-to-select army, tap target to march; war panel with
  Königssitz, live scores, Plündern; recap shows war *results* only.
  `resume` heals saves parked on an AI slot via `advanceUntilHuman`;
  `runAiTurn` got a human-dynasty guard.
- **Online human-vs-human wars (V2 design)**: wars stay blocking/sequential
  (one global `activeWar`) but war-round inputs run on a short war clock
  (default 10 min); expiry falls back to AI war logic per round; explicit
  delegate-to-AI; WAR_STARTED push. Rejected: parallel war track, WEGO
  plans, plain blocking. Details in ARCHITECTURE.md.
- **Full-codebase review round 1** — fixes: war `movesLeft` drops dead
  units' entries; merge/disband forbidden at war; election-bribe validation
  counts only applied gifts; stale decisions resolve as no-ops; `armySize`
  clamped in town death; event log capped (1,000 + `prunedEventCount`);
  chronicle matches by `personId`; earthquake epicenter covers the map;
  election tie-break uses an explicit shuffle tiebreaker; popularity writes
  clamped 0–100. Design: combat formula reworked (defense reduces losses),
  disease mercy rule, AI bribes capped at half treasury, no war against a
  same-ruler slot, Dorf founding counts as randomized for undo.
- **Home screen redesigned + interactive tutorial** (`client/lib/tutorial/`):
  real fixed-seed game (Brandenburg) with a step overlay; standing rule:
  keep `tutorial_steps.dart` in sync with gameplay/UI changes. Credits page;
  original release year corrected to 1992.
- **Claim settlement traced** (`proc_00CC0B`): winner's war score = claim;
  ≥ 0.4 × loser territory → occupied tiles convert; smaller → winner annexes
  adjacent loser tiles at building value, `F` pays the rest 1:1 in Taler.
- **Update-safe versioning introduced**: `schemaVersion` + migration chain in
  `GameState.fromJson`; `rulesVersion` gates (originally pinned per game —
  superseded 2026-06-11 by the latest-rules policy). Newer saves are listed
  as "App aktualisieren".
- **UX feedback round**: troop-creation sheet-context bug fixed; station
  picker reworked; recruit slider caps at affordability; `MarryCommoner`
  always accepted; Info → "Dynastien" hosts the realm list; map tint
  softened, borders + name captions; leaving via Info → "Spiel verlassen".
- **Full-codebase review round 2**: client *seat* concept
  (`GameController.currentSlot` returns the human war side during a war
  pause; menus locked); human-vs-human wars blocked in V1 (engine + UI);
  **rules v2** (see versioning.dart); unconditional fixes: bankruptcy
  garrison double-cut, Ottoman title ladder, `SellGood` amount 0, vacant spy
  targets, marriage age ≥ 14, total extinction → `gameDraw`, stale
  assassination orders pruned, deep-copied decision payloads; visibility
  clears election bribes/votes and war internals for non-participants.

## 2026-06-11

- **Full-codebase review round 3** — **rules v4** (see versioning.dart) plus
  integrity fixes: `foundReplacementDynasty` fully cleans up vanished
  dynasties (children refs, offices via `closeChronicleIfOfficeHolder`,
  aliased slots pass on per §15.4); unknown decision types resolve as no-op;
  `marriageConsent` re-checks eligibility at resolution; stale decisions for
  AI/vacant slots purged; merged-away dynasties set to AI; war snapshots
  matched consume-based by name (`matchedSnapshots`); troop markers refreshed
  on disband/merge; `recapBaselines` persisted in the state. 15 regression
  tests in `bugfix_v4_test.dart`. Deliberate non-fixes: election self-bribes
  (no-op), sole-surviving-realm win semantics, town plunder minting Taler.
- **Rules v5 war overhaul**: decided encounters (winner/loser casualties),
  white peace, claim settlement on every scored victory, `TrainTroop`
  retrain, `MarryCommoner` decoupled from the proposal gate.
- **Rules v6 colony ship** (`SendShip`): traced from manual + `proc_005D2B`
  (flat 700 T, ship consumed); tap-target UX; `WorldMap.shipReachable` BFS.
- **Rules v7**: AI war defender fights back (intercept + counter-march, BFS
  pathing); war panel rework; `DrillTroop` (traced `proc_00A316`: 5 T/man,
  +1 quality, cap 10).
- **About page & latest-rules policy**: every game plays the LATEST ruleset —
  `adoptLatestRules` upgrades `rulesVersion` at the save-load boundary
  (`SaveService.load`); `GameState.fromJson` stays a faithful decoder; gates
  remain for documentation/testability/re-pinning.
- **Colony-ship discoverability**: "Schiff aussenden" also on the own Hafen
  tile sheet with a tile pick; invalid picks toast the engine reason.
- **UX feedback round**: war-goal crosshair removed (capital flag suffices);
  **rules v8** (no per-turn drill limit); peacetime troop relocation removed
  from the tile sheet (Militär → Truppenliste only).
- **Rules v9 (user decisions)**: manually steered colony ships
  (`BuyShip`/`MoveShip`/`ColonizeShip`, 1 Zug per water tile, colonization
  founds a named Dorf; `SendShip` retired); ruler capture resolves at war
  ROUND END (hold the capital) and opens the claim settlement instead of
  swallowing the realm (claim = war score incl. +3,000 capital bonus).
- **Rules v10 original-fidelity round**: every applicable §12 coercion
  option fires; coerced conversion switches the home realm's title ladder
  and divorces incompatible couples (Reformation/Ottoman divorce too); all
  conversions to Islam strip the whole dynasty's Kurfürst seats;
  earthquake/disease garrison losses cut from units. Unversioned fixes:
  realm merge moves ships + intel; stale abdication can't depose a successor
  Kaiser; AI no longer declares war on its own ruler's aliased slot (was an
  uncaught `ActionException` that killed the AI turn); AI harbor picks honor
  own-LAND adjacency; `Rng.nextInt` no longer overflows into negative
  results for bounds ≥ 2³¹ (late-game treasuries). Regression tests in
  `bugfix_v10_test.dart` / `rng_test.dart`.
- **Docs compacted**: decision log moved here from CHECKLIST.md; the
  PROJECT_REQUIREMENTS deviations table now points to the versioning.dart
  changelog for rules-versioned changes.
- **V2-readiness round (rules v11)**: (1) ruler capture must be held
  through the enemy's FULL response round — occupying the capital at a
  round end only *arms* it (`ActiveWar.heldCapitalSlot`, `capitalHeld`
  event); holding at the next round end resolves it; troopless opponents
  resolve immediately. Fixes the v9 asymmetry where an AI seizing a human
  defender's capital won in the same "Runde beenden" tap. (2) War
  round-end orchestration moved into the engine: `endWarRoundWithAi`
  (ai_turn.dart) is the one "AI sides respond, then the round ends" entry
  point for client AND V2 server; `GameController.endWarRound` lost its
  hand-rolled mutation. (3) `completeTurn` throws on an open war (engine
  backstop for server-side validation; the client already disables the
  button). (4) `tool/sim_report.dart` restored (deleted by the previous
  commit but still referenced by README/CHECKLIST); 200-year sim healthy
  (gameWon ~1095, 47 wars, 23 captures). War panel shows armed/besieged
  states for both sides; tests pin the v9–v10 instant capture and cover
  the v11 arm/confirm/disarm/troopless cases.
