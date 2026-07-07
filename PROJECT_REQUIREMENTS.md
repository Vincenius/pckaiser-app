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

`ORIGINAL_GAME.md` (§1–27) holds the exact, traced formulas — the single source of truth. Headlines: 80×44 procedural map (§3); turn pipeline upkeep → actions → dynasty events → elimination → win check (§6); economy (§7); food/population/popularity (§8); market + trade-ship invest (§9.1/§9.2); colony ships: buy at own Hafen (700 T + 1 Zug), steer manually (1 Zug per water tile), colonize adjacent free land into a named Dorf; ships are hidden info (§9.3); military 5 T/man + class surcharges, Söldner 50 T/man, drilling +1 quality for 5 T/man cap 10 (§10); war — year ≥ 1010, once/year, rounds end by capital held through a full round (armed at one round end, resolved at the next; ruler coerced + claim settlement), mutual peace (white peace), or winter > 20 rounds → score arbitration + claim settlement; the claim is capped at half the loser's territory value, a capture victory's claim covers at least the loser's capital tile, conquest never transfers debt, "Ganzes Land übernehmen" takes all affordable land at once; militarism costs popularity — war declaration −5 × (Kriege in Folge), escalating per war and decaying one step per war-free year, floored at 10 (BELOW the §19.1 strife line: a serial warmonger can face revolt); levies −(1 + men/200), floored at 25 (§11); coercion on capture (§12); espionage/assassination, guard cap 50, success scales with agents (§13); marriage rules (§14); dynasty events (§15); titles (§16); Kurfürsten + elections (§17); world events (§18); elimination + win (§19); AI script (§20).

### Intentional deviations from the original

**Every game plays the latest rules** — rules are not versioned per game; a balance or rule change ships as a new app version and existing saves adopt it on load. The pre-release rule iterations (combat rework, white peace, manually steered colony ships, AI war defender, drilling, round-end ruler capture + claim settlement held through a full response round, coercion/conversion fidelity, claim cap at half the loser's territory with a capital-tile floor, militarism popularity costs, debt-free conquest, take-all settlement, agent-scaled espionage, war-bookkeeping gates) are baked into the baseline; their dated history lives in `docs/HISTORY.md`. In an online match every seat must run the same app version to take its turn (the server rejects a stale build with HTTP 426).

Unversioned design deviations:

| Original behavior | Change | Reason |
|---|---|---|
| Newborn age uninitialized (heap garbage) | Age 0 | Original bug (§15.3) |
| Shareware year-1019 cutoff | Removed | Copy protection |
| German-only UI | German default, English toggle | Broader audience |
| Keyboard number input | Sliders/steppers | Touch UX |
| Separate claim step before building | Building on adjacent unowned land claims implicitly (AI still uses ClaimTile) | Fewer taps |
| Weide only on Berg | Also on Ebene | Gameplay request |
| Island starts possible | Starting landmass ≥ 50 connected tiles | No boxed-in starts |
| Unlimited proposals/turn | One royal proposal per turn; commoner marriage always available and always accepted | Pacing; reliable fallback |
| Wars against any realm | Only shared-border realms; never against a slot your ruler already holds; human-vs-human wars run sequentially (attacker's half, then the defender's — hot-seat handoff locally, war clock online) | Plausibility; self-war nonsense; one global war needs ordered two-sided input |
| 50% phantom birth (§15.3) | Removed (children require married parents); the §14.3 no-partner case instead falls back to a commoner marriage — manual for humans, automatic for AI so AI lines don't die out and the late-game royal-partner pool stays alive | Plausibility; keep dynasties alive without single-parent births |
| Other realms' stats visible | Hidden + espionage reveals | Makes espionage matter |
| Marriage-consent prompt shows only the names (§14.1) | Dialog names the proposer's land and age | Informed consent — marriage is the main peaceful inheritance path |
| Dynasty prompts appear on the deciding slot's turn | Pending decisions (heir choice, baby naming, consent, …) surface at the player's FIRST handoff, whichever of their slots it is | A multi-slot player must not rule inherited realms before hearing of the death behind them |
| No direct war popularity cost (§8.4: wars hurt only via food) | War declaration costs −5 × (wars in a row), decays one step per war-free year, floored at 10 — below the §19.1 strife line | Serial warmongering must be punishable by revolt (user feedback); AI war guard scales with the same weariness |
| War end shows only winner + claim (§11.2) | Per-battle numbers as before, plus a running loss total per report and a "Kriegsbilanz" (rounds, battles, men lost, loot, tiles per side) on the war-ending popup | Players asked for a picture of the whole war |
| War rounds start immediately on declaration | Human-vs-human wars open a PREPARATION window (`WarPhase.preparation`, user-designed): both combatants answer a `warPlan` decision — command their side live or hand it to the stance autopilot, optionally bulk-setting all units' stance. Start rules: both auto → the war fast-forwards at once; exactly one live → starts as soon as both answered; both live → online waits for the deadline (half the turn timer) so nobody misses the duel start, hot-seat starts immediately. Unanswered sides default to the autopilot at the deadline | Async players need a fair reaction window before a live duel |
| Newborn naming always prefilled | Per-game setup option "Namensvorschläge für Kinder" (host-set online) | Player preference |
| Crown pot auto-collected on the holder's turn (§7.2/§17.5) | "Staatskasse plündern": explicit `CollectTribute` action (Dynastie sheet; AI collects at turn start; turn report reminds while the pot waits) | User request — deliberate collection has strategic value |
| §14.3 annual loop can re-match anyone | Persons on either side of a pending marriage consent are off the market (annual loop, proposals, commoner marriage) until the answer lands; an accepted-but-decayed consent reads "nicht mehr möglich", not "abgelehnt" | An interim auto-match invalidated accepted proposals online |
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
| Population grows on surplus, unbounded vs. fields (§8.2) | Positive growth capped at the food ceiling (`pop ≤ grain+livestock yield`) — population plateaus at what the fields feed instead of overshooting and crashing | +10 %/turn growth outran the player's field-building; large realms starved "out of nowhere" |
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
