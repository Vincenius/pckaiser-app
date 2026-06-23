# Decision & Fix History

Dated log of decisions, review rounds and fixes — kept for lookups.
Older entries refer to a per-game "ruleset version" (v1–v7); that concept
was removed on 2026-06-23 (see that day's entry) — every game now always
plays the latest rules. The deviations table lives in
`PROJECT_REQUIREMENTS.md`; entries here only summarize.

## 2026-06-23 — Online war playtest fixes (appVersion 0.1.2)

Reported from a human-vs-human online war: the attacked player saw the
normal status (popularity) popup AND a fresh "Krieg!" popup every single
round; a lost war left a huge NEGATIVE treasury and soft-locked the player
(stuck "loading", then trapped in the Kaiser-election bribe popup with no
confirmable button); and a defenceless seat could stall the war.

- **War turns show a round report, not the status popup.** `showRecapAndDecisions`
  now branches when the seated player is a combatant in an active war: it
  replaces the §21.1 status report + recap card with a single
  `showWarReport` of the opponent's actions since this side last acted
  (battles/plunders/outcome), then prompts any decisions. The routine
  stats popup is suppressed mid-war.
- **War report scoped to the latest round.** The recap baseline now advances
  on every `WarEndRound` (server `match_service.submit`, mirrored locally in
  `GameController.endWarRound` for hot-seat), so the per-round report holds
  only the opponent's response — not every battle of the war, re-shown each
  round.
- **"Krieg!" briefing shows once.** `_maybeShowWarAlert` keyed off a fresh
  `warDeclared` in the defender's recap instead of an instance flag (which
  reset every turn online, since the GameScreen is rebuilt per turn) — so it
  appears once and never repeats.
- **War never drives a treasury negative.** `finishSettlement` caps the claim
  cash to what the loser owns, and `transferTile` clamps a conquered tile's
  treasury share (a doubled capital share could exceed the whole purse).
  "Through war you never lose more money than you have."
- **Bribe prompt is answerable when broke.** Backend `electionBribe` validation
  accepts the empty submission with a non-positive treasury (only over-spend
  is rejected); the dialog enables its confirm button (labelled "Ohne
  Bestechung") and clamps sliders to the affordable amount. This was the
  post-war soft-lock.
- **Defenceless war sides are auto-skipped.** `endWarRoundFor` now auto-resolves
  the round of a troopless awaited human (`_skipTrooplessWarSides`) — an
  attacker hands over, anyone else advances — so an empty army never stalls
  the match waiting on a player who can do nothing.
- Tests: new `bugfix_v19_online_war_test.dart` (treasury clamps + broke bribe),
  updated `war_test.dart` for the auto-skip; full game_core + backend suites
  green.

## 2026-06-23

Playtest feedback batch (single change set).

- **Ruleset versioning removed — the app version replaces it.** Games are no
  longer tagged with a `rulesVersion`; every game always plays the latest
  rules. Dropped `currentRulesVersion`, `adoptLatestRules` and the three
  `state.rulesVersion >= n` gates (human-vs-human wars, the 50–80 % claim-cap
  roll, the round-19 winter war end — all now unconditional). A single
  `appVersion` (in `versioning.dart`, mirrored in each `pubspec.yaml`) is the
  shared build identifier: the client sends it with every online turn, the
  server rejects a mismatched build with HTTP **426**, and the match view
  flags `update_required` so the client blocks the turn before it starts.
  `GET /version` now reports `app_version`. `schemaVersion` (JSON shape) is
  untouched. Old saves carrying a `rulesVersion` field still load (the
  decoder ignores it).
- **Kaiser windfall fixed.** Feudal tribute no longer accrues while the
  throne is VACANT (`economy.dart`): with no Kaiser/Sultan to collect it, the
  5 % skim used to pile up through the kaiserless first decade (and any later
  interregnum) and dump a huge hoard on whoever was crowned next — the boost
  that made a freshly crowned Kaiser instantly, unbeatably rich. Tribute now
  only flows once the office is filled. Regression in `turn_pipeline_test`.
- **Action buttons grey out instead of vanishing.** "Truppe ausbilden" and
  "Truppe umrüsten" (and the war "Ganzes Land übernehmen") stay visible and
  disabled when unavailable rather than disappearing — a vanishing button
  shifted the others under the finger and caused mis-taps. The drill button
  is pinned high in the troop sheet (above the come-and-go merge options) so
  spamming it never moves it, and **disbanding a troop now asks for
  confirmation** — a stray tap can no longer destroy a unit.
- **Multi-realm online play works, and the turn order shows it.** A player can
  come to hold several realms (control follows the ruler). The match view now
  lists every realm a seat plays (`controlled_slots`) and the exact realm
  awaited (`awaited_slot`); the turn-order UI lists all of a player's realms
  and names the right one in "… ist am Zug". Found in the audit and fixed:
  the server filtered the state and validated actions against the seat's HOME
  slot only, so a conquered/inherited realm was redacted and unplayable —
  `view()` now filters for the realm actually being played (`your_slot` /
  `_viewSlot`) and `submit()` accepts an action for ANY realm the seat
  controls; a human-vs-human war round drove the home slot instead of the
  awaited war realm (skipping the defender's half) — now the awaited war slot;
  the recap baseline is keyed on the realm actually played; and an out-of-turn
  decision (e.g. an election vote) on a non-home realm is surfaced off-turn
  instead of stalling until that realm's own turn.

## 2026-06-22

Batch of gameplay/UX fixes from playtest feedback (single change set).

- **Rules v7** (universal/ungated, see versioning.dart changelog):
  - **Earthquakes gated to year ≥ 1010** (was 1005) — the protected first
    decade is now fully disaster-free (`firstEarthquakeYear`).
  - **Religion change popularity** is a smaller, FLOORED hit
    (`religionChangePopularityCost` = 25, never below `militarismPopularityFloor`
    = 25) instead of the opaque flat −70 that could crater a realm in one
    (often accidental) tap. The `religionChanged` event now reports the exact
    loss, and the menu asks for confirmation first.
  - **Food satisfaction (§8.4) reworked** — popularity nudges toward a
    food-driven target with a small, bounded, symmetric step
    (`foodSatisfactionStepCap` = 8) instead of the multiplicative crawl, so a
    slumping realm recovers fairly and the mood never swings >~11/turn.
  - **Control follows the ruler** (`alignSlotControl`): a realm whose ruler
    already plays another slot as a human is played by that human even after
    the home dynasty was couped to AI — you regain a retaken realm when your
    own heir is back on its throne. Regression: `bugfix_v17_heir_control_test`.
  - **Human births announce only after naming** — the public `birth` event is
    deferred to the `childName` decision, so rivals see the CHOSEN name a round
    later (online players were seeing the provisional table name, same round).
    Regression: `bugfix_v18_mp_fixes_test`.
  - **`realmOverrun` / `rulerCaptured`** carry whether a HUMAN player was the
    loser, so the client pops a strong "a player has fallen" event to everyone.
  - **AI scripting** (ungated): the AI redeploys troops in peacetime
    (`_repositionTroops`), occasionally sends assassins at a bordering rival
    (`_maybeAssassinate`), and declares war a little more often (~2× chance).
- **Online enemy troops in war** — `visibleStateFor` now keeps the OPPONENT's
  troop list + army size for a war the viewer fights (it only rebuilt map
  markers before, so the online war panel showed no enemy army). Regression:
  `visibility_test` ("reveals the opponent troop list … during war").
- **Online notification spam fixed** — `MatchService._commit` re-pushed a
  `yourDecision` nudge on EVERY commit while a decision sat open (an election
  vote drew one per AI turn). Now only NEW decisions are pushed, at most one
  per player per commit.
- **Online popups reach parity** — strong events (a coronation of THIS player,
  a player losing their realm/ruler) now pop the moment they happen on the
  waiting screen (`OnlineMatchScreen._maybeShowDrama`, deduped by event
  position), not only at the next own turn; "Du bist Kaiser !" is one of them.
- **Event feed/recap** highlights events of OTHER human players (border + bold
  + person badge) so real rivals' moves stand out from AI bookkeeping.
- **In-game Info menu** shows the running game's app + ruleset + save-format
  version (handy online, where the round may have started on another build).
- **Pre-existing cleanups found in the audit**: removed an unused import in
  `economy.dart`; fixed a raw-type lint in `serialization_test`; synced
  `client/pubspec.yaml` `version:` to the displayed `appVersion` (0.1.1) so the
  `app_version_test` sync guard passes.

## 2026-06-19

- **Rules v6** (universal/ungated, see versioning.dart changelog) —
  **trade ships return next turn**. "Handelsschiffe aussenden" (§9.2) was an
  instant 50/50 gamble that credited the treasury in the same action. Now the
  stake leaves the treasury on departure, the outcome is rolled then (so saves
  stay replayable) but is hidden, and the haul lands at the START of the
  realm's next turn — the new `Realm.pendingShipReturns` voyages resolve in
  `_resolveShipReturns` (turn pipeline begin-turn). Departure fires a
  `shipsSent` event; the return fires `shipsReturned` (now the turn-start
  notice of what the ships brought back, shown in the recap card). Hidden info
  like colony ships (`_redactRealm` omits it). Additive JSON field — no schema
  bump. UI: `_investSheet` detail + tutorial "Handel" step updated. Regression
  test: `turn_pipeline_test.dart` ("trade ships return at the start of the
  next round").
- **`fromJson` list-aliasing fix** (no rules/schema change). `WorldMap.fromJson`
  and `Realm.fromJson` built their index-mutated lists with `cast<int>()`, which
  returns a write-through *view* over the decoded JSON rather than a copy — so a
  loaded map's in-place writes (`map.building[i] = …`, `tileCount[b]++`) could
  leak back into the source document (and vice versa), contradicting `copy()`
  and the "cheap to copy" contract. Latent today (every engine entry point
  copies state first) but a real footgun. Now `.toList()` detaches both.
  Regression test: `serialization_test.dart` ("fromJson detaches index-mutated
  lists"). A full audit of the rest of `game_core` (economy, military/war,
  dynasty/offices/espionage, turn pipeline/events/AI, visibility) surfaced no
  other live logic bugs.
- **Rules v5** (universal/ungated, see versioning.dart changelog) —
  **drilled regular ≠ Söldner**: a regular drilled to quality 3 (common
  after the v4 drill-to-99 change) was misidentified as a mercenary because
  several sites keyed off `quality == 3` instead of `garrisonCounted`. Effects
  fixed: the client hid its **drill/retrain buttons** at quality 3 (the
  reported "can only train to level 3" bug — `menus.dart`), reinforcing it
  cost 50 T/man and skipped the quarters check (`applyReinforceTroop`), §7.4
  wages double-counted its men (`runEconomy`), and the troop list mislabelled
  it "(Söldner)". Regression test: `bugfix_v16_drilled_regular_not_soeldner_test.dart`.
- **Server `/version` endpoint** (`backend/lib/src/api.dart`): reports the
  deployed `game_core` `rules_version`/`schema_version` so a stale online
  deployment (server not rebuilt with `--build` / checkout not pulled) can be
  spotted with one `curl`. README "Run the online server" documents it.
- **War sea movement → usable two ways** (folded into rules v5). The
  `[DESIGNED]` sea transport (not in the original — colony ships only
  colonised, ORIGINAL_GAME.md §9.3) was effectively unusable: own-territory
  only, no combat, and the client only tried it as a march fallback that
  rarely left the unit beside a harbour. Now:
  - **Manual steering** (`applyWarMove`): a unit embarks by stepping onto an
    own Hafen, sails open water tile by tile (1 Zug each, like the colony
    ship) and disembarks on any reachable coast. Only a third realm's tiles
    block. Tapping water/coast tiles steers it.
  - **One-shot transport** (`applyWarNavalTransport`): ships a
    harbour-adjacent unit straight to a sea-connected coast; the client
    auto-routes to the connecting harbour (`WorldMap.navalEmbarkTile`) when a
    sea-separated tile is tapped (`_marchToward`).
  Both target own/enemy/neutral coast and **resolve combat on a contested
  landing** (repelled landing stays at the embark coast). Tests:
  `naval_transport_test.dart`. **TODO:** the AI defends a landing but never
  launches its own (its war pathing still treats water as impassable).

## 2026-06-18

- **Rules v4** (universal/ungated, see versioning.dart changelog):
  - **War march over neutral land**: armies may cross unowned (`niemand`)
    land in war, not only own/enemy territory — `applyWarMove` and the AI
    war pathing (`runAiWarMovement` allowed-owners). Third realms still block.
  - **Lost-capital re-seating** (`reseatLostCapitals`, run each round in
    `_startRound`): a realm whose capital tile is lost (war claim,
    earthquake, bankruptcy seizure) takes a new seat — AI auto-picks the
    highest-value own Stadt/Burg/Palast (random among ties); humans get a
    `relocateCapital` decision (free, prompted at turn start).
  - **"Sitz verlegen" any time**: voluntary relocation costs 5,000 T; a
    forced re-seat after a loss is free. (Was: only allowed when lost.)
  - **`humansDefeated` carries `reason`**: the defeat screen now explains the
    cause (internal strife / bankruptcy / succession crisis / conquest /
    extinction) instead of just "no human dynasty". Mechanics unchanged — the
    player can still be eliminated; only the messaging is clearer.
  - **Bankruptcy grace period**: §19.2 no longer forecloses the moment the
    treasury crosses the debt limit. A realm gets `bankruptcyGraceTurns` (3)
    end-of-turns below the limit — warned each turn (`debtWarning`) — to
    recover before tiles are seized. `Realm.debtTurns` tracks the streak,
    resets on recovery.
- **Drill display bug** (client-only): "Truppe ausbilden" showed/gated the
  cost as `5 × men` while the engine charges `5 × men × quality`, so at
  higher quality the enabled button threw "nicht genügend Taler" — it looked
  like a level-3 cap. Fixed the menu to use the real cost. Engine cap was
  already 99.

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
- **War-balance & defeat round (rules v12, user feedback)**: (1) the
  settlement claim is capped at HALF the loser's territory settlement
  value — the §11.2 war score grows ~quadratically with army strength, so
  any sizeable army's claim used to dwarf the loser's realm (winner
  annexed everything reachable, the cash remainder bankrupted the loser);
  the last tile is now never affordable, so one war can't erase a realm.
  (2) `realmOverrun` event when a settlement leaves the loser with zero
  tiles — both sides get an explicit "everything won/lost" popup
  (war report + recap headline). (3) `advanceUntilHuman` ends the game
  with a `humansDefeated` event the moment no human seat remains (root
  cause of "lost a war, returned ~200 years later as a rich sole ruler":
  after the last human dynasty fell to strife/extinction, the loop
  silently simulated up to 2,000 AI turns and re-seated the player in
  the surviving AI realm); client shows a defeat screen ("Niederlage!").
  (4) UX: steering a colony ship onto a FREE land tile now colonizes it
  in one flow (sail to the nearest adjacent water tile + found the Dorf,
  voyage + 1 Zug) — engine actions unchanged, pure client chaining; the
  human winner's settlement finish shows a war-report popup
  (claim payout / total loss). Tests in `bugfix_v12_test.dart`.

## 2026-06-12

- **UX & balance round (user feedback, rules v13)**: (1) militarism costs
  popularity `[DESIGNED]` — war declaration −5 (attacker), levies
  (recruit/Söldner) −(1 + men/200), both floored at 25 so the §19.1
  strife revolution (< 20) stays food-driven; the traced original (§8.4)
  only knows food satisfaction + balance nudge + religion −70, armies
  hurt the stat merely indirectly, but players expect levies/wars to
  matter. Tuned on multi-seed 200-year sims: war at −10 (or no floor)
  collapsed AI realms into strife 5–9× as often; −5 + floor + a
  popularity-aware AI (§20.8 only wars at ≥ 50) lands at ~3× with a
  healthy world (102 wars, 67 captures, 7 realms alive in 1200). (2) A
  capture victory's claim is at least the loser's CAPITAL tile settlement
  value (overrides the v12 cap): a quick war against a troopless enemy
  yielded a claim below the Burg's 5,000, so the winner couldn't take the
  seat they conquered. Client: turn-start §21.1 status report popup
  (income, Beliebtheit + tier text, buildable fields — shown before
  decisions/recap); event feed redesigned (year groups newest-first,
  chronological top-down within a year, "Wichtig" default filter, icons);
  recap card now chronological (was newest-first, reading "A gewinnt →
  A erklärt Krieg" backwards); top-right vitals stacked vertically with
  Beliebtheit; status-row year never truncates ("Anno 1…"); the troop
  sheet stays open while drilling (rebuilds via ListenableBuilder); the
  war settlement panel is collapsible so it no longer blocks tapping
  northern map tiles.

- **War/espionage round 2 (user feedback, rules v14)**: (1) conquest never
  transfers DEBT — the §11.4 tile treasury share is skipped while the
  loser's treasury is ≤ 0 (annexing an indebted realm's capital used to
  hand the winner a doubled debt share: "won the war, ended −5,000 T").
  (2) `SettlementTakeAll` ("Ganzes Land übernehmen"): one action runs the
  AI's greedy annex loop for a human winner and finishes the settlement;
  the client offers the button when the claim covers the loser's whole
  territory value. (3) Espionage rebalance `[DESIGNED]`: the defense
  catches at most `min(defenseRoll, random(agents+1))` agents (a high
  guard level could wipe whole missions outright — vs a rich AI's 50
  guards ~70% failed before any roll), and success scales with the
  survivors (military `random(50) < min(45, 15+2s)`, assassination
  `random(50) < min(40, 10+s)`); slider hint "mehr Agenten, bessere
  Chancen". (4) Military intel stores spied unit positions; the client
  draws the spied army as faded ghost badges (snapshot of the spy year,
  hidden where live troops are visible) and the tile sheet shows
  "~N Mann <Klasse> — Stand Anno X". (5) Map-bug fix: realm name labels
  now anchor to OWNED land (capital while owned, else the tile nearest
  the territory centroid; no label without land) — a conquered seat no
  longer shows the dead realm's name on the winner's land. (6) War panel
  slimmed: Kriegspunkte scoreboard and the instruction paragraph removed
  (winter rule lives in the round-counter tooltip). Verified existing
  behavior: assassinating a sole-member royal house passes ALL its slots
  to a random living ruler (`dynastyExtinct`, control follows the
  inheritor); with relatives the §15.4 heir priority applies — pinned in
  `bugfix_v14_test.dart`. Sim healthy (67 wars, 6 strife, 2 realms at
  1200).

- **Polish round (user feedback, same day)**: (1) intel reports written
  out as German text (menus `_intelText`: "Spionage Anno X: Schatzkammer
  ~N T, Korn ~N, …"; Dynastien info shows the newest economy AND military
  report instead of raw `unitCount`/`armySize` key dumps). (2) Movement
  scaling vs original VERIFIED — already faithful: §6.3 roll is
  `titleClassEquivalent + random(6)` and titles rise with the §16.2
  prestige score (population, treasury, Häfen/Burgen/Paläste), so bigger
  realms do get more Züge; tutorial + turn report now say so. (3) Failed
  espionage uses the original §13.3 torture wording ("… gesteht unter
  Folter, aus X geschickt worden zu sein !!!"); with caught agents the
  `missionFailed` event is now participants-visible `[DESIGNED]` — the
  TARGET realm learns the sponsor (recap headline), like failed
  assassinations always did; a wiped mission without catches reads
  "konnten nichts in Erfahrung bringen" (§13.1). (4) Human heir choice on
  a ruler's death VERIFIED — already implemented (provisional §15.4 heir
  + `heirChoice` menu for human dynasties with >1 member, re-crowning on
  resolve); positive end-to-end path now pinned in dynasty_test.

- **Inheritance & coercion-timing round (user feedback, same day)**:
  (1) new public `realmInherited` event, emitted from the GAINING house's
  side on both §15.4 cross-dynasty paths (spouse inheritance; extinction →
  random living ruler) with the inherited slot list — the client shows an
  "Erbschaft !" drama popup at the inheritor's turn start, a recap
  headline and a feed line ("Durch Erbfolge fällt X an …"); previously a
  quiet `succession`/`dynastyExtinct` line from the DEAD realm's side was
  all there was, and players only noticed when seated at the new realm.
  (2) Pending decisions born from a war resolution (coercion: Abdanken /
  Kurfürstensitz aberkennen / Bekehrung, convert-or-die for a losing
  human) are prompted IMMEDIATELY after the war report — new shared
  `promptDecisionsFor` in decisions.dart, called after "Runde beenden"
  (capture resolution), settlement finish, take-all and the mid-march
  capture path; they used to wait for the next turn's start (engine
  `ResolveDecision` never required the active turn, so this is
  client-flow only).

- **Release-1 cut + V2 server (user request)**: (1) GitHub link on the
  About page (url_launcher). (2) Versioning consolidated for the first
  release: ALL `rulesVersion` gates removed from engine and client (the
  latest behavior is the only behavior), `currentRulesVersion` reset to
  **1** as the release-1 baseline (pre-release history stays in this
  file), the retired `SendShip` action and the vestigial
  `Troop.drilledThisTurn` flag deleted, old-version-pinned tests removed
  (226 engine tests remain green; sim byte-identical before/after).
  (3) Final review: 5-seed 200-year sims with periodic JSON round-trips —
  no crashes, no drift; stale version markers stripped from comments.
  (4) **V2 online server implemented** (`backend/`): shelf REST API per
  ARCHITECTURE (players, create/join with founder setup + slot
  assignment, per-requester visibleStateFor filtering, turn submission
  incl. out-of-turn ResolveDecision and the endWarRoundWithAi war-round
  entry point, post-war AI resume, win/finish + winner mapping, turn
  deadlines + timeout sweep with AI/default fallbacks, push hooks as a
  logged stub) on a GameStore interface (in-memory + atomic JSON file
  store; PostgreSQL later), Dockerfile; 13 server tests. Client: device
  UUID identity + ApiClient + online lobby (configure server/name,
  create match with timer + share ID, join by ID, list with "Du bist am
  Zug", 20 s polling). Remaining V2 milestone: the in-match play screen —
  async action round-trips (client cannot roll dice; rngSeed never
  leaves the server).

- **V2 online play complete (user request)**: (1) `GameSession` interface
  splits local/online: `LocalGameSession` unchanged in behavior;
  `OnlineGameSession` round-trips every action to the server and maps
  400/403 responses back to `ActionException`, so menus/war/decisions UI
  run unchanged; `GameController`'s action path is async for both modes
  (undo disabled online — the client never rolls dice, `rngSeed` never
  leaves the server). (2) Server submissions return the action's
  visibility-filtered events (client result popups) and move the recap
  baseline at end_turn. (3) Client: `OnlineMatchScreen` (poll while
  waiting, share match ID, prompt out-of-turn decisions, open the game
  screen on your turn; screen pops itself when the turn passes on);
  lobby opens matches. (4) Server URL via
  `--dart-define=PCKAISER_SERVER_URL` (baked-in URL hides the address
  field; manual entry = dev fallback). (5) FCM HTTP-v1 push
  (`FIREBASE_SERVICE_ACCOUNT` base64 env, googleapis_auth) with logged
  fallback; docker-compose + Nginx example + backup cron note in
  backend/deploy/. Still open: human-vs-human war clock (engine rejects
  human-vs-human wars — needs two-sided war-round input) and a
  two-device system test. 226 core + 14 backend + 26 client tests green.

- **Human-vs-human wars + lobby rework (user request, ruleset v2)**:
  (1) Engine: `DeclareWar` against human realms is allowed (gate
  `rulesVersion >= 2`); new additive `ActiveWar.actingSlot` names the
  war side whose input is awaited — attacker first each round (original
  order), the attacker's round end HANDS OVER to a human defender
  (`handWarRoundOver`), the defender's ends the round; war actions from
  the non-acting human side are rejected ("Dein Gegner ist gerade am
  Zug !"); `warActingSlot(state)` resolves the awaited side everywhere
  (settlement → the human winner); entry point `endWarRoundFor(state,
  slot, …)` (used by client session and server submit). (2) Local
  hot-seat: `GameController.currentSlot` keys off `warActingSlot`; every
  acting-side change (incl. war end → back to the paused attacker turn)
  raises the handoff blocker (`_maybeRequestSeatHandoff`); the "Krieg !"
  defender briefing shows once per war; the war panel labels the
  attacker's button "Züge übergeben" and surfaces a human opponent's
  peace wish. (3) Online: the awaited player during a war is the acting
  combatant (war clock `war_round_timeout` unchanged); the timeout sweep
  now runs the AI war logic for the idle side (per the 2026-06-10
  decision) and auto-settles an idle winner's claim; `WAR_STARTED` push
  goes to both human combatants. (4) Lobby rework: match ids are now
  5-letter uppercase room codes (lowercase accepted on lookup; legacy
  UUIDs still valid), `human_count` dropped from creation — players join
  via code (≤ 16) until the creator starts via new
  `POST /matches/:id/start` (403 for non-creators; legacy fixed-size
  matches still auto-start when full); client: room-code join dialog
  (auto-uppercase), waiting room shows the code big + creator's "Spiel
  starten" button (solo start allowed). 230 core + 17 backend + 27
  client tests green.

- **Leave/delete online matches + dev QoL (user request)**: (1) New
  `POST /matches/:id/leave`: waiting + creator → match deleted for
  everyone, otherwise the seat is freed; in a RUNNING game every dynasty
  the player holds falls to the AI (`playerLeft` public event,
  irreversible) — the leaver's open decisions resolve with defaults, a
  war whose awaited side left runs out like a pure AI war
  (`endWarRoundWithAi`/`autoSettleClaim` loop), and an abandoned open
  turn completes via `_resumeAfterWarIfOver` (last human gone →
  `humansDefeated` ends the match); a match with no seats left is
  deleted (`GameStore.deleteMatch`). Lobby list now carries
  `is_creator`; client: leave/delete icon per lobby tile + match-screen
  app-bar action, with status-specific confirmation texts. (2)
  Multiplayer testing on one desktop: `--dart-define=PCKAISER_INSTANCE=2`
  switches the online profile file (`pckaiser_online_2.json`) so a second
  instance registers as its own player (README). (3) Status row: compact
  visual density for logout/undo icons and the end-turn button — the row
  overflowed by 19 px on narrow phones (debug banner over "Anno …";
  release would clip). (4) Action-bar menu "Sonstiges" renamed
  "Dynastie" (EN "Dynasty"), tutorial step text updated. 230 core +
  22 backend + 27 client tests green.
- **Client push notifications + home-screen online list (user request)**:
  server-side FCM existed since the V2 backend; this adds the client
  half. New `client/lib/services/push_service.dart` wrapping
  firebase_core/firebase_messaging: `PushService.init()` in `main()`
  yields null on desktop or without the platform Firebase config, so
  push stays optional end to end (Linux dev builds keep working —
  verified). Permission is asked via the system dialog when online play
  is used: on the home screen with a configured profile and right after
  "Online einrichten"; the token then goes up via the new
  `ApiClient.updatePlayer` (`PATCH /players/:id`,
  `OnlineService.syncPushToken`) and re-uploads on rotation
  (`onTokenRefresh`). Notification taps (cold start + background) carry
  `data.match_id` and open `OnlineMatchScreen` directly. Android wiring:
  google-services Gradle plugin applied **only when
  `client/android/app/google-services.json` exists** (builds never break
  without Firebase), `POST_NOTIFICATIONS` in the manifest; iOS needs
  plist + APNs key (README "Push notifications" documents the full
  Firebase setup incl. server `FIREBASE_SERVICE_ACCOUNT`). Home screen:
  new "Online-Partien" section between the action buttons and the saved
  games — non-finished matches, "Du bist am Zug !" entries first with a
  highlighted icon, 20 s foreground poll like the lobby, tap opens the
  match; errors are silent there (the online screen reports them). 27
  client tests + analyze green.
- **Polish round (user feedback, ruleset v3)**: (1) Hot-seat/turn
  blockers ("Spieler X ist am Zug", victory, busy) moved OUTSIDE the
  game screen's `SafeArea` — inside it the system-inset strips (status
  bar / gesture nav) stayed uncovered and the map shone through on
  devices with edge-to-edge UI. (2) AI build variability `[DEVIATION]`:
  `_pickBuildAction` picked the FIRST matching tile of a row-major map
  scan, so AI realms always built/expanded toward the top-left ("nach
  oben"); now every candidate set (fields, Dorf/Burg/Palast spots,
  Hafen coast tiles, claimable frontier) is collected and a uniformly
  random one is taken — same priorities, unpredictable shape. Ungated
  (AI scripting, not a state rule). (3) Winter war end now reports with
  the original's sentence "Der Krieg musste wegen des hereinbrechenden
  Winters beendet werden" (war report popup + event feed; was a terse
  "Der Winter beendet den Krieg"). (4) **Ruleset v3**: the settlement
  claim cap is rolled per war end at 50–80% of the loser's territory
  value (was a flat 50%, which made every victory against a
  similar-sized realm pay out the same 5000–6000) — old half cap kept
  under `rulesVersion < 3` and covered by a pinned-v2 test in
  `bugfix_v12_test.dart`. (5) Kaiserchronik shows the office holder's
  home country: `ChronicleRecord.slot` (additive JSON field, no schema
  bump) stamped at coronation/record creation; the chronicle sheet
  renders "Name von Land (Jahre)" with a person-dynasty fallback for
  pre-slot saves. 231 core + 27 client + 22 backend tests green.
- **Balance: Kaiser income, drill scaling, merge direction (2026-06-16)**:
  Three balance/UX fixes. (1) Kaiser/Sultan tribute reduced from 10% to
  5% (`economy.dart` `~/ 20`): the accumulated pot gave the Kaiser an
  overwhelming compounding advantage that was near-impossible to overcome.
  (2) Drill cap raised from 10 to 99; drill cost now scales with current
  quality (`5 × men × quality`) so early levels are cheap and high levels
  are expensive; reinforcing regular troops dilutes quality back toward 1
  via a population-weighted average — this means elite units require
  dedicated upkeep and cannot be mass-reinforced without re-training.
  (3) "Reiche zusammenlegen" direction fixed: the acting slot is now the
  SOURCE (it gets vacated) and the selected other slot is the TARGET that
  absorbs everything — previously it was the other way around. 235 tests
  green.
- **Winter off-by-one (test-play follow-up, ruleset v3)**: the winter
  check fired at `war.round >= 20`, but the counter is 0-based and the
  war UI counts "Runde X/20" — wars ran 21 rounds, the panel showed
  "Runde 21/20", and the player never saw the winter message where the
  UI promised it. v3 fires winter when the 20th round ends
  (`round >= 19`); pre-v3 behavior kept under the gate. Natural-flow
  regression test in `war_test.dart` (the old winter test forces
  `round = 21` and would not have caught this). Launcher icons:
  regenerated via `dart run flutter_launcher_icons` after the new
  `client/assets/icon/` images landed — the generated platform mipmaps
  are checked in, so they must be regenerated whenever the source
  images change.
