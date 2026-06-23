# PC Kaiser Mobile — Project Requirements

Mobile-first clone of PC Kaiser (1992, Martin Gelter); Holy Roman Empire ~1000 AD.
Always **30 realms**, up to **16** human players, rest AI. Goal: last dynasty standing.

## Platform & Tech

- Android + iOS; Flutter + Flame (client)
- Dart (shelf) + PostgreSQL backend (online only) — game logic is one shared Dart package (`game_core`)
- FCM push (online only); self-hosted Docker + Nginx

## Game Modes

**Local (V1, primary):** 1–16 humans hot-seat on one device, AI plays the rest.
Multiple named game slots, each auto-saved after every completed turn (no manual save). State stored locally as JSON.

**Online (V2, designed now, built later):** async multiplayer; the server simulates AI realms and world events between human turns. Push on your turn. Host-configurable turn timer (off/12h/24h/48h/7d) — expired turns/decisions auto-resolve (turn → end with no actions; decision → its AI/default fallback), reminder push at ~80%. State in server JSONB; client read-only outside its turn. Same domain model + logic as local. Identity: device UUID, no auth.

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

`ORIGINAL_GAME.md` (§1–27) holds the exact, traced formulas — the single source of truth. Headlines: 80×44 procedural map (§3); turn pipeline upkeep → actions → dynasty events → elimination → win check (§6); economy (§7); food/population/popularity (§8); market + trade-ship invest (§9.1/§9.2); colony ships: buy at own Hafen (700 T + 1 Zug), steer manually (1 Zug per water tile), colonize adjacent free land into a named Dorf; ships are hidden info (§9.3); military 5 T/man + class surcharges, Söldner 50 T/man, drilling +1 quality for 5 T/man cap 10 (§10); war — year ≥ 1010, once/year, rounds end by capital held through a full round (armed at one round end, resolved at the next; ruler coerced + claim settlement), mutual peace (white peace), or winter > 20 rounds → score arbitration + claim settlement; the claim is capped at half the loser's territory value, a capture victory's claim covers at least the loser's capital tile, conquest never transfers debt, "Ganzes Land übernehmen" takes all affordable land at once; militarism costs popularity — war declaration −5, levies −(1 + men/200), floored at 25 so strife stays food-driven (§11); coercion on capture (§12); espionage/assassination, guard cap 50, success scales with agents (§13); marriage rules (§14); dynasty events (§15); titles (§16); Kurfürsten + elections (§17); world events (§18); elimination + win (§19); AI script (§20).

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
| 50% phantom birth (§15.3) | Removed — children require married parents | Plausibility |
| Other realms' stats visible | Hidden + espionage reveals | Makes espionage matter |
| Modal text walls | Event feed + recap | Mobile UX |
| Single implicit save | Named slots, auto-saved | Mobile expectations |
| No action revert | In-turn undo (deterministic actions) | Touch mistaps |
| Disease kills 50% of ALL persons | Mercy rule: last dynasty member spared | No zero-counterplay wipes |
| AI election bribes ≈ whole treasury | Budget capped at half treasury | Healthy AI economies |
| Earthquakes from year 1000 | From 1005 | Build-up grace |
| Unbounded event history | Log capped at 1,000 (`prunedEventCount` keeps positions stable) | Bounded saves |
| Hafen next to any own tile | Needs an adjacent own LAND tile | Stops coast-chaining exploit |
| Troop merge/disband/rename any time | Forbidden at war (war state is keyed to the troop list) | Consistent bookkeeping |

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
