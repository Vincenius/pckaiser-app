# Decision & Fix History

Dated log of decisions, review rounds and fixes — kept for lookups.
Older entries refer to a per-game "ruleset version" (v1–v7); that concept
was removed on 2026-06-23 (see that day's entry) — every game now always
plays the latest rules. The deviations table lives in
`PROJECT_REQUIREMENTS.md`; entries here only summarize.

## 2026-07-06 — User feedback round 3: manual crown pot, marriage-consent fix, settlement batching — appVersion 0.1.13 (still unreleased)

Third batch, folded into the SAME unreleased 0.1.13 (version bumps only on
Vincent's call). Regression tests in `bugfix_v28_test.dart` /
`turn_pipeline_test.dart`:

1. **Manual "Staatskasse plündern" (overrides round 2's decision)**: per
   Vincent's request the crown pot is no longer auto-collected in the
   economy upkeep — new `CollectTribute` action (free, office holder
   only), a "Staatskasse plündern" entry in the Dynastie sheet, a
   turn-report reminder line while the pot waits, and a public
   `tributeCollected` event. AI office holders collect at turn start
   (§20.3 step 3), so pots never rot on an AI throne.
2. **Online marriage consent "accepted but rejected"**: the §14.3 annual
   loop also auto-proposed/married HUMAN dynasty members, so between a
   proposal and the target's answer either side could marry elsewhere —
   the acceptance then failed the re-check and read as a rejection. New
   `awaitingMarriageConsent` guard: persons on either side of a pending
   consent are off the market (annual loop, candidate pool, new
   proposals, commoner marriage — engine + menu filters). An accepted
   consent that still decayed (e.g. religion change) now reports
   `reason: invalid` ("nicht mehr möglich") instead of "abgelehnt".
3. **Settlement without per-tile loading (online)**: new atomic
   `SettlementAnnexMany` engine action; `OnlineGameSession` applies each
   settlement tap optimistically to the local state (same pure-engine
   validation the server runs), buffers the picks and flushes them as ONE
   batch with the settlement finish / next submission. Poll refreshes are
   skipped while taps are unflushed; a rejected batch resyncs before
   rethrowing.
4. **Sponsor popup for successful assassinations**: new owner-visible
   `assassinationSucceeded` event (the public `assassination` stays
   anonymous) with a drama popup "Attentat erfolgreich !".
5. **"(Beta)" dropped** from the online menu entry (DE + EN).
6. **War-start PREPARATION window (supersedes round 2's defender-only
   reaction window — Vincent's design)**: human-vs-human wars begin in
   `WarPhase.preparation`; BOTH sides answer a `warPlan` decision (live
   control vs stance autopilot, optional bulk stance). Start rules in
   `resolveWarPreparation`: both auto → immediate fast-forward
   (`_fastForwardAiWar`, now `warSideIsHuman`-aware); exactly one live →
   start once both answered; both live → hot-seat starts immediately,
   online waits for the deadline (HALF the turn timer, armed in `_commit`
   even when nobody is awaited, forced by `_sweepMatch`) so nobody misses
   the duel start. Unanswered sides default to the autopilot. Client: the
   attacker answers right after declaring (menus), a "Kriegsvorbereitung"
   card replaces the war panel, map taps stay normal during preparation.
   The old `warDefense` handlers remain as no-op legacy for dev saves.

## 2026-07-06 — User feedback round 2: war weariness, war reports, war-start reaction window, options — appVersion 0.1.13

Second batch of player feedback, regression-tested in `bugfix_v28_test.dart`:

1. **Escalating war-declaration penalty** (`[DESIGNED]`, deviations table):
   the traced original has NO direct war popularity cost (§8.4 — wars hurt
   only via food), and our flat −5 with the 25 floor meant war could never
   cause revolt (floor above the §19.1 line) and cost LESS at low
   popularity. Now: −5 × (recentWars + 1) per declaration, new
   `Realm.recentWars` counter (additive JSON) decaying one step per
   war-free year, floored at the new `warPopularityFloor` (10, below the
   strife line). Levies/conversions keep the 25 floor
   (`militarismPopularityCost` gained a `floor` param). The AI war guard
   scales with the same weariness (`popularity >= 50 + 5·recentWars`) so
   serial-warring AIs don't talk themselves into strife; the 200-year
   30-AI smoke test stays green.
2. **War loss overview**: `ActiveWar` carries a cumulative tally (men lost
   / battles / plunder loot / tiles taken per side, additive JSON) fed by
   `resolveCombat`/`transferTile`/`plunderTile`; war-ending events
   (`warWon`, `warDraw`, `peaceAgreed`) embed it as `summary` before the
   war state is cleared, rendered as a "Kriegsbilanz" block in the war
   report. Reports with >1 battle additionally lead with a "Verluste
   gesamt" line (own vs enemy men, client-side sum).
3. **War-start reaction window (online) + delegation**: a human attacked
   by a HUMAN gets a `warDefense` decision — fight themself or hand this
   one war to the stance autopilot (`ActiveWar.autoSlots`, new
   `warSideIsHuman` used by all war-input plumbing). While the choice is
   open the server keeps the FULL turn clock; the 10-min war clock starts
   only after they opt in. Defaults (timeout/empty) keep human control.
   Hot-seat: delegating hands the seat back to the attacker (handoff
   blocker raised in `GameController.resolveDecision`).
4. **Setup option "Namensvorschläge für Kinder"**: new
   `GameState.suggestChildNames` (additive, default true) threaded like
   `genderEqualSuccession` (setup screen, online host settings
   `suggest_child_names`, backend `MatchSettings`); consumed only by the
   naming dialog's prefill.
5. **Discord link** on the About screen (button next to GitHub).

Checked against the original and initially NOT changed: the Kaiser/Sultan
tribute pot auto-collect (§7.2/§17.5). SUPERSEDED in round 3 (same day):
Vincent remembers a manual plunder button in the original and wants the
strategic choice — see the round-3 entry above (`CollectTribute`).

320 core + 32 client + 37 backend tests green.

## 2026-07-06 — User bug reports: inheritance/marriage, decision routing, UI — appVersion 0.1.13

Five fixes from player reports, regression-tested in `bugfix_v27_test.dart`:

1. **Marriage after cross-dynasty inheritance (§14.1/§15.4)**: the marriage
   validations (`_proposeMarriage`, `_marryCommoner`) required
   `proposer.dynasty == realm.slot`, so a ruler who inherited a realm via
   the spouse path (e.g. a widow after a successful assassination) could
   never marry from that slot — "Diese Person gehört nicht zu deiner
   Dynastie !". New `memberOfRulingHouse` (rules/dynasty.dart) accepts the
   slot's own dynasty AND the ruler's home dynasty; the client marriage
   pickers and the misc-menu "Dynastie" sheet follow the ruler's house too.
2. **Title re-gendering on ruler change (§16.1)**: `titleClass` was never
   recalculated when a realm changed hands, so an inherited realm kept the
   predecessor's gendered form. New `regenderTitle` (rules/titles.dart)
   keeps the realm's rank but aligns the ±12 female form with the new
   ruler's gender; called on succession, windfall/replacement inheritance,
   the heir-choice re-crown and internal strife.
3. **Pending decisions follow the player across slots**: decisions
   (heir choice, baby naming, marriage consent, …) surfaced only when the
   deciding slot's own turn came around; a player controlling several
   slots (turns run in slot order) ruled inherited realms for whole turns
   before hearing their ruler died — or met the newborn in the dynasty
   sheet before any notice. `promptDecisionsFor` now also prompts
   decisions of other slots with the same `humanPlayer`, and
   `visibleStateFor` retains them (the server already accepted
   out-of-turn `ResolveDecision` for any controlled slot). The heir-choice
   dialog title now doubles as the death notice ("X ist gestorben !").
4. **Marriage-consent dialog names the proposer's land + age** (deviations
   table): marriage is the main peaceful inheritance path, so the target
   must know which realm they are tying their line to before accepting.
5. **Stuck "So viel steht dir nicht zu !" snackbar**: every error snackbar
   (game screen `_toast`, menus, tile sheet, war panel) queued with the
   4s default, so repeated taps in the war-settlement phase stacked
   minutes of snackbars that read as a stuck banner. All sites now
   `hideCurrentSnackBar()` first (replace, not queue).

313 core + 32 client + 37 backend tests green.

## 2026-07-02 — Full-codebase review: engine/online/UI fixes — appVersion 0.1.11

Four-subsystem code review (rules engine, client UI incl. small screens,
online stack, state/persistence); all confirmed findings fixed in the same
(unreleased) 0.1.11. Also resolved the `fixes`→`dev` merge (both sides'
PROJECT_REQUIREMENTS rows and HISTORY entries kept) and its one semantic
conflict: `bugfix_v24_defeat_reason_test` exercises the §15.4 male-priority
fallthrough, so it now opts out of the new default-on gender-equal option.

Engine (`game_core`):
- **AI double-act guard.** New additive `GameState.aiTurnActed`: a save
  written between an AI's action phase and its turn completing (the
  war-interrupt window) no longer re-runs that phase on resume — no second
  assassination roll / double spend. Set in `advanceUntilHuman`, cleared by
  `completeTurn`; old saves default false.
- **Mutual peace beats winter.** A peace both sides agreed to on the 20th
  round is the negotiated white peace, not winter score arbitration
  (`endWarRound` order swapped).
- **Claim floor no longer inflates marginal wins.** The
  cheapest-bordering-tile floor applies only when the anti-swallow cap cut
  an EARNED claim below it — a score-50 winter win can no longer claim (or
  cash in) a 5,000 T lone border Stadt.
- **`gameWon` deduped structurally** (`events.any` instead of
  `events.last`) — a build event between settlement victory and end of turn
  no longer produces a second victory popup.
- **Plunder tolerates a building/town desync** (no `firstWhere` crash;
  mirrors the earthquake path). — **`clampName` never splits a surrogate
  pair** at the 30-unit cap. — **Founder gender clamped to {0,1}** in
  `newGame`. — **§14.3 marriage loop fires at age > 14** (was ≥ 14; the
  ≥ 14 gate belongs to §14.1 candidates). — Drill doc corrected (repeatable
  per turn like the original); stale "Phase 5" AI-war-movement comments
  replaced with a real driver warning (`endWarRoundFor` is the entry point).

Online (backend + client services):
- **Seat renumbering on lobby leave.** A mid-list leave from a waiting match
  renumbers `turnOrder` contiguously — previously the seat behind the gap
  could NEVER take a turn after start (`playerByTurnOrder` mismatch), and a
  later join could duplicate a number. Regression test added.
- **Match seed no longer sent to clients** (view + public list omit it;
  create-request seeds are ignored). The seed made the map and every early
  random roll precomputable — `visibleStateFor` zeroes `rngSeed` for exactly
  this reason. Persistence still stores it.
- **Off-turn realm submissions rejected.** A seat holding several realms
  (inheritance/conquest) could act for realm B during realm A's turn and
  double B's once-per-turn actions; `_submit` now requires
  `action.slot == _awaitedSlot(state)`.
- One corrupt match document no longer 500s the whole lobby list; the 20 s
  lobby poll got an overlap guard.

Client (state/persistence + UI):
- **"Neues Spiel" no longer silently overwrites a same-named save** (the
  field is pre-filled "Partie 1"!) — confirm dialog via `SaveService.exists`.
- **Undo cancels an armed tile pick** (stale unit index could move the wrong
  troop); **decision resolutions clear the undo stack** (randomized outcomes
  must not stay undoable).
- Small screens: the tile action sheet and the Handel/Spionage/Sonstiges
  menus are scrollable `ListView`s (bottom entries were unreachable on
  ~640 dp phones); war-briefing dialog scrolls; status-row year+realm is one
  ellipsizing text; online "Sichtbarkeit" row scales down; tutorial header
  ellipsizes; defeat/victory screen padded + scrollable.
- Lifecycle: war-panel settlement round-ends catch `ActionException` like
  the header button; `_toast` and the session-load path guard `mounted` (+
  error fallback instead of an eternal spinner); setup-screen controllers
  disposed; the map's previous `ui.Picture` disposed on rebuild; online
  handoff uses `tr('onlineYourTurn')`.
- Removed the stale Flutter-template `widget_test.dart` (broke
  `flutter test`); `build/**` excluded from analysis.

Known, deliberately not fixed: save-slot names that differ only by case
collide on macOS's case-insensitive FS (debug target only); raw
`applyAction(WarEndRound)` still skips AI war movement (documented — tests
encode it; real drivers use `endWarRoundFor`).

## 2026-07-02 — Small-screen dialogs + longer names — appVersion 0.1.11

Follow-up UI report (same release). Client + one engine constant; no schema
change, no gameplay-outcome change.

- **Bribery dialog broke on small screens.** Each elector was a fixed
  `Row(name | 160px slider | 56px amount)` — a long name plus a six-digit gift
  overflowed narrow phones, and the confirm button disabled itself once the
  running total passed the treasury (a dead-end feeling). Redesigned: name +
  live amount on one row, a full-width slider beneath, a running
  "Ausgegeben / Verbleibend" budget line, and each slider capped at the unspent
  remainder so the total can never exceed the treasury — the confirm button is
  always enabled. `decisions.dart`.
- **Other small-screen overflows.** The recruit sheet's class picker
  (`Infanterie +0 / Kavallerie +500 / Artillerie +1000`) overflowed as a fixed
  three-segment control — labels shortened to the class names (the surcharge is
  already in the live cost line) and wrapped in a `FittedBox`; the sheet is now
  scrollable so the keyboard can't push it off-screen. The war panel's
  auto-war stance toggle row is likewise wrapped in a scale-down `FittedBox`.
  `menus.dart`, `war_panel.dart`.
- **Longer names, and no reset when the limit is hit.** Introduced a single
  shared cap `maxNameLength = 30` (was a hard-coded 20 in a couple of spots)
  with `clampName()` in `game_core`; the engine now clamps every stored name
  (towns, troops, children, founders) to it, and all client name fields set
  `maxLength: maxNameLength` so input simply stops at the cap instead of ever
  resetting to a default. `constants.dart`, `apply_military.dart`,
  `apply_action.dart`, `new_game.dart`, `menus.dart`, `tile_sheet.dart`,
  `decisions.dart`, `setup_screen.dart`.

## 2026-07-02 — Famine death-spiral made fair & legible — appVersion 0.1.11

Offline bug report: a large, steadily-growing realm suddenly starved "out of
nowhere", lost ~30 % of its population and thousands of troops per turn to
desertion, then was conquered by an AI **without a fought battle** and finally
overrun. Root cause was one cascade — food production scales only with fields
(≈ 50/field, capped at efficiency 2.0) while population auto-grows up to
+10 %/turn, so once `population > ~50 × fields` the surplus fell off a cliff to
the −30 clamp and famine (§8.2, faithfully ported) erased a third of the realm
in a single turn. The desertion then emptied the army, and an AI attacker
walked onto the undefended capital (`endWarRound`'s troopless-loser instant
capture), forcing a `reseatLostCapitals` "Sitz verloren". The AI dodges all
this because it aggressively over-builds fields (`Kornfeld ≈ pop/9`); a human
got no such help and almost no warning. Balance/UX fix (rules change → new
appVersion, client `0.1.11+7`), no schema change. The guaranteed home guard is
the sole defence against the no-fight conquest — no war-side special-casing:
a starving realm now always keeps troops, so the AI has to fight to reach the
capital.

- **Growth coupled to the food ceiling (the root fix).** Population grew up to
  +10 %/turn (thousands of people at scale) while the player can build only a
  handful of fields per turn (each feeding ~50), so a large realm's population
  inevitably OUTGREW what even a fully-fielded territory could feed — a lingering
  harvest stock kept the surplus positive past the real ceiling, so it
  overshot and then crashed "out of nowhere". Positive growth §8.2 is now capped
  so the population never climbs past what THIS turn's harvest can feed
  (`g = 0` once `population ≥ grainYield + livestockYield`): it plateaus at the
  food ceiling instead of overshooting. More fields/land raise the ceiling;
  famine is left to real causes (a plundered/quaked field, or selling the
  harvest your people needed). Famine shrink (`g < 0`) is untouched.
- **Famine floored (`famineGrowthFloor = −10`).** Growth §8.2 is clamped on the
  famine side so a starving realm shrinks gradually (≈ −12 %/turn worst case)
  instead of losing a third at once — several clearly-warned turns to react,
  recovery stays possible. The surplus percent is still clamped to −30 for the
  §8.4 popularity update, so the mood still reflects a full famine.
- **Desertion capped + home-guard floor (`famineDesertionCapPercent = 25`,
  `famineArmyFloor = 100`).** Famine may thin at most a quarter of the army per
  turn and never below a small remnant, so a starving realm is never left
  utterly defenceless — a war is always fought, never a walkover.
- **"Vorräte reichen für X Leute" was useless.** The number was the leftover
  stock *after* everyone ate (≈ 0 for any hand-to-mouth realm) — alarming and
  non-predictive. The turn report now compares THIS turn's harvest to the
  population ("Deine Felder ernähren nur X von Y Leuten !") and adds an explicit
  early warning to build more fields before a famine hits. `turn_report.dart`.
- Files: `population.dart`, `turn_report.dart`, `versioning.dart`.

## 2026-06-29 — Gender-equal succession option, public rooms, online loading hint, idle kick, advanced game settings — appVersion 0.1.11

Several feature requests. Rules-affecting changes (succession + the
configurable war-start year) → appVersion bump to 0.1.11 (client
`0.1.11+7`); the rest is online orchestration + UI. Schema unchanged (all
new state/settings fields are additive with `fromJson` defaults).

- **Gender-equal succession (per-game option, default ON for new games).**
  New `GameState.genderEqualSuccession` (and `GameSetup` / `MatchSettings`).
  When on, `_chooseHeirByPriority` drops the male-priority steps (the eldest
  child inherits regardless of gender) and the §15.5 Islamic succession
  crisis is skipped, so a female heir never costs a player their realm. Old
  saves migrate to `false` (faithful original behaviour); the setup screens
  default the toggle on. Exposed in the local setup screen ("Erweiterte
  Optionen") and the online host dialog.
- **Public vs. private online rooms.** `MatchSettings.is_public`; new
  `GameStore.publicWaitingMatches` + `MatchService.publicMatches` +
  `GET /matches/public`. The lobby lists open public games (settings, host,
  joined count) with a one-tap join; private games stay code-only.
- **Home-screen online loading hint.** The home screen shows a "loading
  online games" row while the first match fetch is in flight instead of
  silently nothing.
- **Kick idle players → AI.** `match_players.idle_turns` counts consecutive
  timed-out turns (reset on any submission); once it reaches 3 the creator
  may `POST /matches/:id/kick` to hand the realm to the AI. A public
  `playerKicked` event (drama popup + recap) tells everyone. The leave/kick
  AI-conversion logic is shared via `MatchService._dropSeatToAi`.
- **Advanced game settings (grouped).** New `GameState.warStartYear` (and
  `GameSetup` / `MatchSettings`) makes the §11.1 war gate configurable
  (default 1010); `applyDeclareWar`, the AI war check and the Militär menu
  now read `state.warStartYear`. The setup screens gained an "Erweiterte
  Optionen" section that holds Reformation year, Ottoman year, war-start
  year and the succession toggle; the online host dialog adds the war-round
  clock (default 10 min) there too. The `firstWarYear` constant stays 1010
  (still the election gate in `offices.dart` + the default).

## 2026-06-29 — Correct defeat reason + hidden enemy strength + war-panel layout — appVersion 0.1.10

Three offline bug reports. An event-label engine fix plus client UI; no
rules/outcome or schema change. Released as appVersion 0.1.10 (client
`0.1.10+6`).

- **Defeat screen named the wrong cause.** `humansDefeated`'s `reason` was
  derived by scanning the whole *shared* event log backwards for the first
  "control-losing" event type — which could match an unrelated AI-vs-AI
  `rulerCaptured` from an earlier turn. A player whose realm passed to a
  foreign spouse by §15.4 inheritance (a female ruler dies and her
  out-married husband outranks her daughters in the heir priority, so the
  seat flips to his AI house) thus saw "Dein Herrscher wurde im Krieg
  gefangen genommen" with the *inheriting* realm (e.g. Hessen) behind it —
  though no war happened and she still had heirs. The inheritance itself is
  intended (§14.2/§15.4: marriage is the peaceful path to inheriting realms);
  only the message was wrong. Now the cause is recorded at the exact moment
  each human seat falls — `GameState.humanLossReason`, set by
  `noteHumanSeatLost` at every flip site (strife, bankruptcy, islamic
  succession crisis, cross-dynasty inheritance, war overrun, extinction) — so
  the message reflects the player's OWN loss. New `realmInherited` reason with
  its own wording; the buggy log-scan (`_defeatReason`) is gone. Additive
  nullable JSON field (`humanLossReason`), no schema bump. `game_state.dart`,
  `dynasty.dart`, `events.dart`, `war.dart`, `ai_turn.dart`, `game_screen.dart`.
- **Enemy army strength hidden without espionage.** The war panel printed the
  live enemy men count and ⚔-strength to both combatants. Now it shows only
  what the viewer's own (fuzzed, dated) intel reveals — `~N Mann (Stand Anno
  Y)` — or "ihre Stärke bleibt ohne Spionage verborgen". Whether the enemy
  host still stands stays visible (observable on the field), and enemy unit
  positions still render on the map as before. `war_panel.dart`.
- **"Runde beenden" reachable on small screens.** The three war actions sat in
  a `Row(mainAxisSize.min)` that overflowed narrow phones and clipped the
  rightmost button. Now a centered `Wrap`; the unit-chip list is also
  height-capped + scrollable so a large army can't push the actions below the
  map's bottom edge. `war_panel.dart`.

## 2026-06-27 — Online lobby turn-order + off-turn map view (client UI only)

User feedback on the online match screen. No rules/state/server change, so no
`appVersion` bump (the 426 gate only guards rules).

- **Turn-order list sorted correctly, one row per realm.** The lobby listed
  seats in join order and labelled each with its join index ("Zugreihenfolge N").
  But within a game year seats play in **slot order** (realm 1 → 30), not join
  order, so the shown order was wrong. Now: before the start it is just a
  "Spieler" list with no order numbers; after the start there is **one row per
  controlled realm** (a seat holding several after a conquest/inheritance appears
  at each realm's own position), sorted by slot and numbered "Zug 1…N" in that
  play order. The ▶ marker is on the exact awaited realm (`awaited_slot`).
  Eliminated seats get a single trailing "ausgeschieden" row. `online_match_screen.dart`.
- **Off-turn "Karte ansehen".** While another seat is at the turn, a read-only
  `OutlinedButton` opens the new `MapViewerScreen` — the Flame map with pan/zoom,
  no HUD/actions — using the server's already-filtered per-seat state (foreign
  realms stay fuzzed). `MapGame` gained an optional `focusSlot` so the viewer
  centers on the watching seat's own realm. New file: `map_viewer_screen.dart`.

## 2026-06-26 — Outdated-app Play Store link + About scroll fix — appVersion 0.1.8

- **Play Store update link.** The online match's "App-Update erforderlich"
  banner (shown via the server's `update_required` flag) is now a reusable
  `UpdateRequiredBanner` (`client/lib/widgets/update_banner.dart`) that, on
  Android, offers a one-tap link to the Play Store listing
  (`com.pckaiser.app`). iOS hides the link (no published build yet). Covered
  by `client/test/update_banner_test.dart`.
- **About screen overflow fix.** `AboutScreen`'s body was a non-scrollable
  `Column` that overflowed (and failed `app_version_test`) on a short test
  surface / with large font scaling. Wrapped in
  `LayoutBuilder` → `SingleChildScrollView` → `ConstrainedBox`: scrolls when
  tall, stays centered when there is room.

## 2026-06-26 — War-end round (user feedback, rules v15) — appVersion 0.1.8

Four items from a user playtest:

- **Auto-war stance is online-only.** The per-unit "Verhalten im automatischen
  Krieg" stance steers a side fought on autopilot when the online war clock runs
  out. Offline the player moves every unit by hand, so the toggle is now hidden
  in local games (`war_panel.dart`, `menus.dart`, gated on
  `GameController.isOnline`). Engine behavior unchanged — the stance was always
  ignored during live play.
- **Lost-capital re-seating already covers AI** (war conquest, earthquake,
  bankruptcy seizure): `reseatLostCapitals` auto-moves an AI seat onto its
  highest-value Stadt/Burg/Palast at the next round rollover; humans get a
  `relocateCapital` decision. Verified, no change (covered by `bugfix_v15_test`).
- **War claim floor + small realms.** The settlement claim is capped at 50–80 %
  of the loser's remaining territory value (so one war never swallows a realm
  whole). Two fixes: (a) a realm worth **less than a single Burg (5,000)** all
  told is now taken WHOLE — the cap only shields sizeable realms, so a tiny rump
  state can always be finished off; (b) above that, `_cappedClaim` floors to the
  single cheapest loser tile bordering the winner, so a victory can always claim
  at least the remaining part (e.g. a lone Hafen after the Burg was lost) instead
  of the cap falling below the cheapest tile. Generalizes the v13 capital floor.
- **Sole-ruler victory fires immediately + landless-zombie sweep.**
  `checkWinCondition` (moved to `rules/victory.dart`) is now consulted the
  instant a war's settlement overruns the last rival, so a HUMAN winner sees the
  victory popup right after the war instead of only at their next "Zug beenden".
  AI-vs-AI conquests still resolve at the normal end-of-turn check. Separately, a
  user reported owning everything but seeing no popup: a realm stripped of its
  last tile by a NON-war cause (earthquake levelling a town-less rump) was never
  vacated, so its landless ruler counted as a living rival and blocked the win
  forever. `vacateLandlessRealms` now sweeps every round rollover (after world
  events) and vacates any 0-tile realm — war losses are still handled inline.
  Tests in `bugfix_v23_test.dart`.
- Credits: added a link to the original "PCKaiser++" on
  `goodolddays.net` on the About screen.

## 2026-06-25 — AI commoner-marriage fallback so the royal partner pool survives (§14.3) — appVersion 0.1.5

A user reported his heirs could find no one to marry late in the game and asked
whether births were too rare. Investigation (headless dynasty sims under
`packages/game_core/tool/`, 16 seeds × 200 years, all-Catholic best case):

- The marriage logic is correct — engine `findMarriageCandidate` and the client
  candidate list both apply §14.1 exactly (unmarried, opposite gender, age ≥ 14,
  gap < 10, **different dynasty**, same religion). Not a bug.
- Global population GROWS; births are not too rare. The real cause is **dynasty
  consolidation**: female-founded lines merge into their husband's dynasty
  (§15.4 spouse inheritance), and — unlike the original — an AI member who finds
  no royal partner had NO fallback (the 50% phantom birth was removed for
  plausibility, see deviations table), so AI lines that can't marry simply stop
  reproducing and die out. Across a game the 30 dynasties collapse to ~3, and
  since a royal match must be from a *different* dynasty, the late-game pool
  evaporates. Sim: by year 1200 only ~2.8 dynasties survive and a dominant
  dynasty's single 14+ members find a partner only ~39% of the time.
- The human is never truly stuck — "Bürgerlich heiraten" (`MarryCommoner`) is
  always available and always accepted (deviations table). The complaint was the
  empty *royal* list, which is the expected consequence of the AI collapse.

**Fix (chosen with the user over restoring the phantom birth or a flat
birth-rate bump):** give AI dynasties the same commoner-marriage fallback the
player already has. In the §14.3 annual loop, an **AI** member who rolls the
~25% marriage attempt but finds no royal candidate now weds a freshly created
commoner (joins the dynasty, rejoins the birth loop) instead of doing nothing;
the wedding is silent (hidden AI internal state, avoids feed clutter). Human
dynasties are untouched — the player still chooses via the menu so a royal match
can be planned for. Sim with the fix: ~6.8 dynasties survive to 1200 and the
partner-availability rate rises to ~96%, with far more controlled population
growth than a birth-rate increase (which left dynasties dying while the
population exploded to ~786). `marry` gained an `announce` flag and the shared
`createCommonerSpouse` helper now backs both `MarryCommoner` and the AI fallback
(RNG-identical, so the player path is unchanged). Tests in `dynasty_test.dart`.

## 2026-06-25 — Merge needs a shared border IS faithful (original-binary check; §6.2)

A user reported he could not "Reiche zusammenlegen" two of his own realms that
lie next to each other across water (adjacent only through a Hafen). First read
of the traced spec suggested the merge adjacency gate added in `c85b2b1` was a
regression — §6.2 of `ORIGINAL_GAME.md` lists the *only* merge gate as "source
owns ≥ 1 tile". **Disassembly of the original `PCKAISER.OVR` overturned that.**
The merge menu handler (`proc_00F462`) builds its candidate list from the SAME
neighbour helper (`0x75e:0x4a4`) as war declaration (`proc_00A5F1`); both reject
an empty list with a "Nachbarn" message ("Sie haben keine Nachbarn !" /
"…nur unmittelbare Nachbarn angreifen !"). That helper is a pure orthogonal
owner-byte tile scan: a realm is a neighbour iff one of its owned tiles
orthogonally touches one of yours. So the original DID require adjacency to
merge; the §6.2 note only described the merge *implementation* (`proc_00F200`,
which alone gates on ≥ 1 tile), missing the candidate-selection gate. The
adjacency gate in `mergeableSlots` is therefore CORRECT — left in place.

Harbour nuance (the user's actual case): an owned Hafen sits on a water tile the
realm owns, so it counts in the adjacency scan like any owned tile and CAN
bridge a one-tile strait (Hafen tile touching the other realm → neighbours →
mergeable). But a harbour does NOT reach across an open-water gap — the original
has no sea/ship adjacency for merge or war (crossing water is the separate ship
mechanic). So two realms only "near" each other across open sea were
un-mergeable in the original too; the clone matches. If we ever want cross-sea
merging it must be a documented DEVIATION (`PROJECT_REQUIREMENTS.md`), not a
"fix". Net code change: clarified the `mergeableSlots` doc comment only;
behaviour unchanged. Regression test `bugfix_v22_harbor_merge_test.dart` pins
both halves (Hafen-bridge mergeable; open-water gap not). (Original RE evidence:
`~/Downloads/pckaiser/ovr_analysis/` — `proc_00F462`/`proc_00A5F1`, helper
`0x75e:0x4a4`.)

## 2026-06-24 — Merge realms held by your own dynasty across different heirs (§6.2)

`mergeableSlots` gated the Handel "Reiche zusammenlegen" on the **same ruler
person** (plain aliasing, §19). But control follows the *dynasty*, not the one
ruler: when a different heir/branch of your house inherits a neighbouring realm
(peaceful inheritance, §15.4), `alignSlotControl` already hands you control of
it (its `humanPlayer` becomes yours) — yet the realm stayed locked out of the
merge menu because its `rulerId` differed. Fix: for a **human** seat the merge
candidacy is now keyed on the controlling **player** (`dynasty.status == human
&& humanPlayer` match), so any adjacent realm your dynasty holds is mergeable
regardless of which heir rules it; AI/free seats keep plain ruler aliasing
(§20.7 — "one ruler, many slots" — unchanged, so AI balance is untouched). A
different *human* player's realm is still rejected (humanPlayer must match).
Control of an heir-ruled realm was already correct (verified) — only the merge
gate was too strict. (`realm_merge.dart`; `bugfix_v21_heir_merge_test.dart`:
control + merge + cross-player rejection. Ships in the same uncommitted 0.1.4
batch as the war-stance change — no separate bump; no save-format or wire
change, only a wider legal-action set.)

## 2026-06-24 — Online wars vs the AI are fought interactively + per-unit war stance (appVersion 0.1.4)

Online, an AI that attacked a human ran the war on the short **war clock**
(`war_round_timeout`, default 10 min): in async play the timeout sweep played
the defender's side with the AI war logic and the war was over before the
player ever opened the app. Three changes, gated behind the new appVersion:

- **Human-vs-AI wars use the full turn timer.** The match service now picks the
  clock by `_warIsHumanVsHuman`: the short war clock only governs a live
  human-vs-human duel; a human fighting an AI gets the normal turn timer
  ("time like a normal turn") so they can fight every round in the war panel at
  their leisure. `null` turn timer ⇒ no deadline. Server-only change; the
  interactive war UI already existed. (`match_service.dart`; two timeout tests.)
- **Per-unit war stance (`TroopStance`).** New additive `Troop.stance`
  (default `holdPosition`; no schema bump — old units default in) and a
  `SetTroopStance` action (allowed mid-war; it touches neither the troop list
  nor `movesLeft`). It steers only an UNATTENDED (autopiloted) war round: when
  the war clock runs out on an idle human (or they left the match),
  `runAiWarMovement` moves that human's units by stance — *hold position*
  defends the base and marches on the enemy capital only once the enemy has no
  troops left; *attack* advances immediately. A player fighting live still
  moves every unit by hand. Client: a "Verhalten im Krieg" toggle per unit in
  the troop sheet, plus a stance chip/toggle in the war panel.
  (`troop.dart`, `military_actions.dart`, `apply_military.dart`, `ai_turn.dart`,
  `menus.dart`, `war_panel.dart`; tests in `bugfix_v21_test.dart`.)
- **AI keeps a home guard.** `runAiWarMovement` reserves the AI side's unit
  nearest the capital and never marches it out (when it has ≥2 units), and
  peacetime repositioning always leaves one unit on the capital — so an AI base
  is never left wholly undefended. (`ai_turn.dart`.)

## 2026-06-23 — Codebase review: bug fixes, hardening & simplification (appVersion 0.1.3)

A full review pass (parallel subsystem audits + adversarial diff review).
All three suites stayed green throughout; new regression tests added.

Bug fixes:
- **Merge carries trade ships at sea.** `mergeRealms` now also moves the
  source realm's `pendingShipReturns` to the target. The vacated source never
  takes another turn, so its outstanding voyages were never credited — the
  staked Taler were silently lost. (`realm_merge.dart`; test in
  `bugfix_v20_test.dart`.)
- **Conquest can't drive a harvest negative.** `transferTile` now clamps the
  grain/cattle harvest shares with `math.min` (like the treasury share); a
  doubled high-value-capital share could exceed the whole stock. (`war.dart`.)
- **Earthquake tolerates a town/building desync.** The town lookup uses a
  null-tolerant loop instead of `firstWhere`, so a desync no longer throws
  mid-event-phase and leaves the world half-mutated. (`events.dart`.)
- **Backend write serialization.** A per-key async lock (`_locked`) serializes
  every read-modify-write of a match document and the shared players file, so
  a turn submission racing the once-a-minute timeout sweep (or concurrent
  player/token writes) can no longer lose an update. `sweepExpired` re-reads
  and re-validates each match under the lock. (`match_service.dart`; test.)
- **Submission events scoped to all controlled realms.** The turn response
  filters emitted events against every realm the seat controls, not just its
  home slot, so a player on a conquered/inherited realm still receives that
  realm's own battle reports and spy reveals. (`match_service.dart`.)
- **API never bare-500s.** `_guard` now wraps non-`ApiException` errors in the
  standard `{data,error}` envelope, so one corrupt match can't take down the
  whole lobby request. (`api.dart`.)
- **Client double-submit guard.** `applyUndoable`/`applyIrreversible`/
  `applyWarAction`/`resolveDecision` now honour the `_busy` re-entry flag, so a
  rapid double-tap online can't fire two concurrent submissions. (Test.)
- **War-panel crash guards.** "Runde beenden" and `_finishSettlement` now catch
  `ActionException` (like their sibling buttons) — an online rejection / double
  tap shows the message instead of crashing. (`war_panel.dart`.)
- **Online poll re-entrancy.** `_refresh` guards against overlapping fetches so
  a stale view can't clobber a newer one. (`online_match_screen.dart`.)

Simplification / dead code:
- Collapsed the two byte-identical troop-marker rebuilds into
  `GameState.rebuildTroopMarkers()`; inlined the `_requireNotAtWarPeacetime`
  pass-through; deduped the backend `turnOrder→player` lookup into
  `MatchRecord.playerByTurnOrder`; sourced the tile-sheet build prices from
  `Building.cost` instead of hardcoded literals.
- Removed dead code: `townAt`, `WorldMap.shipReachable`, the unused
  `warForCurrentPlayer`/`decisionsForCurrent` getters, the unreachable
  "simultaneous annihilation" combat branch, and the unused `resume`/
  `warDeclared` l10n keys.

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
