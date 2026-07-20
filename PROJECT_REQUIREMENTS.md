# PCKaiser Mobile — Project Requirements

Mobile-first clone of PCKaiser++ (1992, Martin Gelter & Lorenz Giefing); Holy Roman Empire ~1000 AD.
Always **30 realms**, up to **16** human players, rest AI. Goal: last dynasty standing.

## Platform & Tech

- Android + iOS; Flutter + Flame (client)
- Dart (shelf) + PostgreSQL backend (online only) — game logic is one shared Dart package (`game_core`)
- FCM push (online only); self-hosted Docker + Nginx

## Game Modes

**Local (V1, primary):** 1–16 humans hot-seat on one device, AI plays the rest.
Multiple named game slots, each auto-saved after every completed turn (no manual save). State stored locally as JSON.

**Online (V2, designed now, built later):** async multiplayer; the server simulates AI realms and world events between human turns. Push on your turn. Host-configurable turn timer (off/12h/24h/48h/7d) — expired turns/decisions auto-resolve (turn → end with no actions; decision → its AI/default fallback), reminder push at ~80%. State in server JSONB; client read-only outside its turn — the waiting view offers "Reich & Karte ansehen": map plus Info menu (Mein Reich, Ereignisse, Siedlungen, Dynastien, Kaiserchronik) over all realms the player holds (realm switcher), actions disabled. Same domain model + logic as local. Identity: device UUID, no auth.

## Input & UX

- Touch-only; pinch-zoom/pan map; tap tile → action sheet with inline costs
- Sliders for numeric inputs; every cost slider live-shows the Taler cost and never exceeds treasury/caps
- Slim status row (treasury + Züge; popularity warning < 30; tap → "Mein Reich") + labeled bottom bar (Handel/Militär/Spionage/Sonstiges/Info). Leave game = red logout button (confirm; auto-save makes it safe)
- Actions without visible results confirm in a modal (spy suspense beat, "Attentäter unterwegs", marriage answer)
- **Event feed** (filters: my realm / wars / dynasty / world) + "since your last turn" recap card; per-seat baseline lives in the state (`recapBaselines`) so it survives restarts and travels online
- **Undo within turn** for deterministic actions; stack clears on randomized/irreversible ones (battle, investment, espionage, market sale, Dorf founding — it rolls population, end turn)
- Confirmation before irreversible actions (demolish, assassination, declare war)
- **War UI**: armies on realm-colored badges (sword = attacker/peacetime, shield = defender); selected unit pulses; war goal = enemy Königssitz (flag, no crosshair). Tap own army to select, tap a target: march (greedy 1-tile steps) or attack; holding the enemy capital through a full round wins (the first round end *arms* the capture — panel + report announce both states, the enemy gets one round to retake). Battle/plunder/war-end results as **report popups** (incl. synthetic enemy-movement lines after "Runde beenden"); defender gets a "Krieg !" orientation popup. Panel shows unit strength (⚔) and AI peace readiness ("friedensbereit"); units namable/renamable/retrainable in the Truppenliste
- **Drama popups & headline recap**: assassination outcomes and coronations as own popups at turn start; recap renders big news as styled headline rows, the rest as one-liners
- Setup defaults: Reformation 1020, Ottoman 1040 (editable, min 1011)
- Language: German default, English optional
- Peacetime troop relocation (free) only via Militär → Truppenliste; war marches stay strictly 1 tile per move

### Accessibility

- Color-blind-safe palette **plus** country border strokes and name captions (color never the only channel)
- Respect system font scale; min 48×48 dp touch targets; semantic labels on HUD/feed

### Hidden information & espionage

Deviation from the original (which exposed most numbers): other realms' treasury, food stocks, army composition, colony ships and guard level are **hidden**; espionage (§13) reveals them fuzzed ±10% with an in-game timestamp. Military intel additionally records each spied unit's map position — the client renders the spied army as faded map badges ("Stand Anno X"); mission success scales with the agents sent. Public: map ownership, dynasty names/titles/religion, town names/tiers, Kurfürsten, Kaiser/Sultan, chronicle. `visibleStateFor` enforces this in the domain model (local hot-seat AND server).

## Core Game Mechanics

`ORIGINAL_GAME.md` (§1–27) holds the exact, traced formulas — the single source of truth. Headlines: 80×44 procedural map (§3); turn pipeline upkeep → actions → dynasty events → elimination → win check (§6); economy (§7); food/population/popularity (§8); market + trade-ship invest (§9.1/§9.2); colony ships: buy at own Hafen (700 T + 1 Zug), steer manually (1 Zug per water tile), colonize adjacent free land into a named Dorf; ships are hidden info (§9.3); military 5 T/man + class surcharges, Söldner 50 T/man, drilling +1 quality for 5 T/man cap 10 (§10); war — year ≥ 1010, once/year, rounds end by capital held through a full round (armed at one round end, resolved at the next; ruler coerced — the captor occupying ALL of the loser's strongholds (every Stadt/Burg/Palast tile, seat included; Dörfer/Märkte/Häfen do NOT count) annexes the loser's ENTIRE territory into the captor's own realm and the landless loser slot is vacated — never §19 slot aliasing; a lone capital capture wins on points via the claim settlement), mutual peace (white peace), or winter > 20 rounds → score arbitration + claim settlement; the claim is capped at a rolled 50–80% of the loser's territory value (a capture claim covers at least the capital tile), conquest never transfers debt, "Ganzes Land übernehmen"/"Auto-Annexion" takes affordable land automatically in a wave from the winner's border (always available, also for partial claims — 2026-07-19); plunder once per ARMY per war round (§11.5); militarism costs popularity — war declaration −5 × (Kriege in Folge), escalating per war and decaying one step per war-free year, floored at 10 (BELOW the §19.1 strife line: a serial warmonger can face revolt); levies −(1 + men/200), floored at 25 (§11); coercion on capture (§12); espionage/assassination, guard cap 50, success scales with agents (§13); marriage rules (§14); dynasty events (§15); titles (§16); Kurfürsten + elections (§17); world events (§18); elimination + win (§19); AI script (§20).

### Intentional deviations from the original

**Every game plays the latest rules** — rules are not versioned per game; a balance or rule change ships as a new app version and existing saves adopt it on load. The pre-release rule iterations (combat rework, white peace, manually steered colony ships, AI war defender, drilling, round-end ruler capture held through a full response round + claim settlement (since 2026-07-13: occupying ALL of the loser's strongholds — Stadt/Burg/Palast only — instead annexes the whole territory into the winner's realm and vacates the loser slot; the earlier §19-aliasing takeover of 2026-07-10 is gone, §11.2), coercion/conversion fidelity, the rolled 50–80% claim cap with capital-tile floor, militarism popularity costs, debt-free conquest, take-all settlement, agent-scaled espionage, war-bookkeeping gates) are baked into the baseline; their dated history lives in `docs/HISTORY.md`. In an online match every seat must run the same app version to take its turn (the server rejects a stale build with HTTP 426).

Unversioned design deviations:

| Original behavior | Change | Reason |
|---|---|---|
| Newborn age uninitialized (heap garbage) | Age 0 | Original bug (§15.3) |
| Shareware year-1019 cutoff | Removed | Copy protection |
| German-only UI | Fully bilingual: every UI string, event line, engine message and realm name exists in German and English (`client/lib/l10n/`, `game_core` message catalog). Language set in the main menu's Options sub-menu; default follows the device language (German devices → German, all others → English), stored in `settings.json` | Broader audience |
| Keyboard number input | Sliders/steppers | Touch UX |
| Separate claim step before building | Building on adjacent unowned land claims implicitly (AI still uses ClaimTile) | Fewer taps |
| Weide only on Berg | Also on Ebene | Gameplay request |
| Island starts possible | Starting landmass ≥ 50 connected tiles | No boxed-in starts |
| Unlimited proposals/turn | One royal proposal per PERSON per turn (2026-07-10, was one per realm); commoner marriage always available and always accepted | Pacing per suitor; reliable fallback |
| Wars against any realm | Only shared-border realms; never against a slot your ruler already holds; human-vs-human wars run sequentially (attacker's half, then the defender's — hot-seat handoff locally, war clock online) | Plausibility; self-war nonsense; one global war needs ordered two-sided input |
| 50% phantom birth (§15.3) | Removed (children require married parents); the §14.3 no-partner case instead falls back to a commoner marriage — manual for humans, automatic for AI so AI lines don't die out and the late-game royal-partner pool stays alive | Plausibility; keep dynasties alive without single-parent births |
| Other realms' stats visible | Hidden + espionage reveals | Makes espionage matter |
| Marriage-consent prompt shows only the names (§14.1) | Dialog names the proposer's land and age | Informed consent — marriage is the main peaceful inheritance path |
| Dynasty prompts appear on the deciding slot's turn | Pending decisions (heir choice, baby naming, consent, …) surface at the player's FIRST handoff, whichever of their slots it is | A multi-slot player must not rule inherited realms before hearing of the death behind them |
| No direct war popularity cost (§8.4: wars hurt only via food) | War declaration costs −5 × (wars in a row), decays one step per war-free year, floored at 10 — below the §19.1 strife line | Serial warmongering must be punishable by revolt (user feedback); AI war guard scales with the same weariness |
| War end shows only winner + claim (§11.2) | Per-battle numbers as before, plus a running loss total per report and a "Kriegsbilanz" (rounds, battles, men lost, loot, tiles per side) on the war-ending popup | Players asked for a picture of the whole war |
| Plunder once per SIDE per war round (§11.5) | Once per ARMY per war round (`Troop.plunderedThisRound`) | User report 2026-07-10 — several armies mean several raids |
| War rounds start immediately on declaration | Human-vs-human wars open a PREPARATION window (`WarPhase.preparation`, user-designed): both combatants answer a `warPlan` decision — command their side live or hand it to the stance autopilot. Throughout the window each combatant sets every troop's stance INDIVIDUALLY (Halten/Angreifen, `SetTroopStance`) over the visible map — in the war panel (attacker / hot-seat) or the off-turn map viewer (online defender; the server accepts these orders out of turn, like decisions). The old all-troops bulk choice in the `warPlan` dialog is gone (2026-07-13). Start rules: both auto → the war fast-forwards at once; exactly one live → starts as soon as both answered; both live → online waits for the AGREED start or the deadline (half the turn timer), hot-seat starts immediately. Unanswered sides default to the autopilot at the deadline | Async players need a fair reaction window before a live duel — and per-unit orders over their own land instead of one blanket stance (user request 2026-07-13) |
| — (no scheduling in the original) | Online duel scheduling (user-designed, 2026-07-08): a live `warPlan` answer proposes start times ("sofort" + hourly slots over the turn-timer window, max 24, shown in local time). Earliest common slot wins — both "sofort" starts at once, an agreed hour becomes the exact deadline (may lie later than the fallback; also works without a turn timer); no overlap or no answer → half the turn timer, as before. Both sides get a "Termin steht" push, an agreed start also one reminder ~15 min ahead. No-show rule: a duelist who never acted and lets their round clock expire is autopiloted for the rest of the war | Two live players in different timezones need a start time both can actually attend |
| Newborn naming always prefilled | Per-game setup option "Namensvorschläge für Kinder" (host-set online) | Player preference |
| Single fixed AI script (§20) | Per-game setup option **"Stärke der KI-Gegner"** (Leicht/Mittel/Schwer, host-set online; default Mittel = the faithful §20 script, old saves too). Levels change only the script's behaviour (`ai_tuning.dart`), never rules and never the AI's resources — no gold/growth boni. (Like the original, the AI script plays on the unfiltered state — its war movement always has; Schwer merely uses it for target picks too.) Leicht sells at any price, halves levies, ignores Burg/Palast mostly, never assassinates; Schwer keeps a food buffer, holds out for top prices, fills the army to ~80 % capacity split over ≥ 3 units with a war chest, raises Kavallerie when rich, drills regulars (the original AI never drilled), assassinates the strongest bordering rival more often (budgeted before the turn's spending), and only declares war on the weakest neighbour with a ≥ 1.3× strength edge (boxed-in realms still war to break out, §20.4) | Player request — selectable AI difficulty |
| Crown pot auto-collected on the holder's turn (§7.2/§17.5) | "Staatskasse plündern": explicit `CollectTribute` action (Dynastie sheet; AI collects at turn start; turn report reminds while the pot waits) | User request — deliberate collection has strategic value |
| §14.3 annual loop can re-match anyone | Persons on either side of a pending marriage consent are off the market (annual loop, proposals, commoner marriage) until the answer lands; an accepted-but-decayed consent reads "nicht mehr möglich", not "abgelehnt" | An interim auto-match invalidated accepted proposals online |
| Losing a realm just flips it to the AI, silently | Every involuntary loss of a human-controlled realm announces itself: `internalStrife`/`bankruptcy`/`islamicSuccessionCrisis` carry a `human` payload flag, an inheritance away emits the public `seatLost` event — the client shows a prominent "Reich verloren" popup (turn start, and online immediately on the waiting screen) naming the cause | User report 2026-07-13 — a realm vanished from a player's control "and I never got told why" |
| Modal text walls | Event feed + recap | Mobile UX |
| Single implicit save | Named slots, auto-saved | Mobile expectations |
| No action revert | In-turn undo (deterministic actions) | Touch mistaps |
| Disease kills 50% of ALL persons | Mercy rule: last dynasty member spared | No zero-counterplay wipes |
| AI election bribes ≈ whole treasury | Budget capped at half treasury | Healthy AI economies |
| Earthquakes from year 1000 | From 1005 | Build-up grace |
| Unbounded event history | Log capped at 1,000 (`prunedEventCount` keeps positions stable) | Bounded saves |
| Hafen next to any own tile | Needs an adjacent own LAND tile | Stops coast-chaining exploit |
| Troop merge/disband/rename any time | Forbidden at war (war state is keyed to the troop list) | Consistent bookkeeping |
| Male-priority heirs; a Muslim realm under a female heir is lost (§15.4/§15.5) | Per-game **"Frauen können überall herrschen"** option (default on for new games, off for old saves): the eldest child inherits regardless of gender and the Islamic succession crisis never eliminates a player | Player request; equal succession |
| Population grows on surplus, unbounded vs. fields (§8.2) | Positive growth capped at 90 % of the EXPECTED yield (mean rolls × efficiency; 2026-07-14, was: this turn's rolled yield) and never past the on-hand stock — the ~10 % margin accumulates as a harvest stock that buffers bad rolls | +10 %/turn growth outran field-building; capping at the ±25 %-noisy per-turn roll pinned population to the ceiling → chronic famine trickle that more fields never cured (user report) |
| Labour efficiency rounded to e ∈ {1, 2} (§8.1) | Continuous multiplier (still clamped 0.5–2.0) | Crossing the rounding boundary — by building MORE fields or by recruiting — halved every field's output in one step |
| Harvest stock accumulates unbounded | Spoilage: stores cap at 2 × population after consumption (2026-07-14) | The growth margin's stock buffer must not become an infinite grain-gold printer |
| No per-turn recruit cap (§10.2: only `armySize ≤ troopCapacity`) | Per-turn levy limit: at most 10 % of the population (min. 100) regular recruits per year, `RecruitTroops` + `ReinforceTroop`; Söldner exempt; AI plans within the same cap (2026-07-14) | A gold-rich late-game realm — especially the Schwer AI refilling to 80 % capacity — raised thousands of men in one turn, which read as cheating (user report) |
| Combat: tile-defense multiplies own losses, casualties are shares of a unit's own size | The DISPLAYED strength (men × per-man power) is the one combat factor (2026-07-19, user-designed; replaces the 2026-07-14 √(men)-damped superiority): who wins AND casualties follow effective strength — loser 35–65% of the winner's reach, winner 10–25% of the loser's, converted via the casualty side's per-man power | The shown number must be what actually decides battles; the damping formula was opaque and mass-vs-quality no longer needs a special case |
| Tile defense from Berg/Dorf/Markt/Stadt/Burg/Palast/Hafen (§11.3) | Only fortifications defend (2026-07-19): +15% strength on a Burg tile, +25% on a Palast; all other tiles are neutral ground | Simpler, readable rule — walls protect, open ground doesn't |
| Troop classes differ only in raw power (§10.1) | Schere-Stein-Papier ×1.15 (2026-07-19): Infanterie > Kavallerie > Artillerie > Infanterie; Artillerie additionally besieges — a fortified enemy keeps only half its bonus and takes ×1.1 fire (replaces the 2026-07-14 wall/charge/siege roles) | Each class counters one other (~64% win rate at equal strength — noticeable, not overwhelming); artillery is the siege weapon |
| Troops embark only via an OWN Hafen | At war, the ENEMY's harbors serve the invader too (2026-07-19): embark step, naval transport and the client's sea-routing accept both war sides' ports | Captured/contested ports should be usable in an invasion instead of dead ends |
| War score = Σ avgStrength × unitStrength × tile value (§11.2) | Occupation-based score (2026-07-19): Σ tile value of DISTINCT occupied enemy tiles + 250/won battle + 3,000 capital bonus — no strength factor | The old formula was quadratic in army strength: a big army was rewarded twice (wins battles AND outscores per tile), a doomstack on one Kornfeld outscored real conquest |
| Attacker moves first in every war round (§11.2) | Initiative alternates (2026-07-19): attacker opens even rounds, defender odd ones (`warRoundOrder`) — drives the HvH handover, the AI move order and the both-occupy-capitals tie-break | Attacker-first in all 20 rounds summed to a real edge in human-vs-human wars |
| Any unit plunders a full haul (§11.5) | Plunder scales with the acting unit's strength (2026-07-19): min. strength 1, loot ≤ 10 ×, kills/razed quarters ≤ 5 × strength; the strongest unspent unit on the tile carries the raid | A 1-man splinter looted like a full army — chaff spam out-plundered real conquest |
| Plundered fields are erased to no-man's-land (§11.5) | Fields are DEVASTATED (2026-07-19): owner and building stay, the tile yields nothing for 3 years (`WorldMap.devastatedUntil`), then recovers; map darkens the tile, Feldinfo shows the recovery year | Wars permanently shrank the world even after a white peace; a realm could no longer lose its last tile to plunder |
| Enemy army fully hidden without espionage (§13) | At war the enemy units' GATTUNG is battlefield-observable (2026-07-19): class letters (I/K/A) on the map badges, class breakdown in the Kriegsdetails; men and quality stay espionage-only | The Schere-Stein-Papier counters need visible classes to play against — blind counters are dice rolls |
| Famine growth to −30 % (≈ −37 %/turn, §8.2) | Floored at −10 growth (≈ −12 %/turn); surplus still clamped −30 for popularity | One harvest could erase a third of a realm — an unrecoverable cliff |
| Famine deserts ¼ of the population loss, up to the whole army (§8.2) | Capped at 25 %/turn and never below a 100-man home guard | A famine left the realm defenceless → conquered without a battle |
| Names capped at 20 (troops) / uncapped (towns, children) | Single shared cap `maxNameLength = 30`, engine-clamped everywhere; inputs stop at the cap | Longer names; input never resets to a default |

## Protect-New-Players Rule

Years 1000–1009: no random deaths (aging rolls, disease) and no eliminations (popularity crisis, bankruptcy) — for AI too. Deliberate assassinations still resolve. Wars are gated to ≥ 1010 anyway.

## Architecture Constraints

- Game logic pure and testable; local and online share the same JSON state model; persistence is the only difference
- Server validates all turns (online); modules small and isolated (economy, population, war, espionage, events, succession)
- Auto-save after every turn completion, before handoff

## V1 Scope

In: full local hot-seat (1–16 humans, 30 realms), all mechanics, AI, touch map, auto-save/resume.
Out: online, push, backend, auth, leaderboards.

## Open Questions

None — all unknowns traced into `ORIGINAL_GAME.md` (§1–27). Remaining deliberate stand-ins are listed in §27 (final design decisions).

## Non-Functional Requirements

- Cold start < 3 s on mid-range devices; map pan/zoom 60 fps
- Auto-save completes before handoff; state JSON forward-compatible (add-only); offline-first
