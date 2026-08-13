# Architecture Guide

Turn-based mobile strategy game with async online multiplayer (V2; up to 16 humans per match, world always 30 realms — AI fills the rest).
Stack: Flutter + Flame (client) · Dart `shelf` + PostgreSQL (backend) · FCM (push) · Docker + Nginx.

## Principles

- **One game-logic implementation**: all rules in a pure Dart package (`game_core`), shared verbatim by client (local) and server (online). Only persistence/orchestration differ.
- **Pure, deterministic logic**: `(state, action, rng) → state + events`; RNG injected and seeded — testable, and the server can reproduce/validate outcomes.
- No auth in V1 of online; players = device-generated UUIDs.
- Game state is the source of truth — one JSONB column on `matches`, never split across tables.
- The server always validates turns; clients submit actions, never mutate state.
- Push is fire-and-forget; the game works without it.

## Shared Game Core (`packages/game_core`)

```
lib/src/
  state/        # GameState, Realm, Dynasty, Person, Town, Troop, Ship … hand-written toJson/fromJson (add-only forward compat)
  rules/        # economy, population, market, troops, war, espionage, dynasty, titles, offices, events, realm_merge, …
  ai/           # ai_turn.dart — same action primitives as humans
  actions/      # PlayerAction types + validation + applyAction dispatcher
  visibility/   # visibleStateFor(state, slot), IntelReport
  rng/          # seeded Borland-LCG Rng
test/           # golden-state + regression tests per module
```

Key API: `applyAction(GameState, PlayerAction, Rng)`, `runAiTurn`, `advanceUntilHuman`, `completeTurn`, `checkWinCondition`, `visibleStateFor`.

`GameEvent {year, slot, type, visibility, payload}` is the single source for all player-facing notifications (event feed, recap, replay); `visibility` = public / owner / participants.

**Realm indexing**: slots 1–30, `0` = "Niemand" — same in JSON state and `match_players.dynasty_index`.

**Pending decisions** (required for async online): mechanics that prompt a player outside their turn (marriage consent, elector votes, convert-or-die, heir choice, coercion) live in a `pendingDecisions` queue `{id, type, decidingSlot, payload}`. Local: resolved inline at the handoff. Online: pipeline pauses, FCM `YOUR_DECISION`, resolved via the turn endpoint. Every type has an AI/default fallback so timeouts can resolve it.

## Data Model

```sql
players       (id UUID PK, display_name TEXT, fcm_token TEXT, created_at)
matches       (id TEXT PK,                -- 5-letter room code (legacy rows: UUID)
               current_turn UUID→players, state JSONB,
               settings JSONB,         -- e.g. {"turn_timeout_hours":24,"war_round_timeout":600,
                                       --        "reformation_year":1020,"ottoman_year":1040,
                                       --        "war_start_year":1010,"is_public":false,
                                       --        "gender_equal_succession":true,
                                       --        "template":null}  -- matchmaking room type
               turn_deadline TIMESTAMPTZ, status TEXT,  -- waiting|active|finished
               auto_start_at TIMESTAMPTZ,   -- matchmaking room: scheduled start
               expiry_warned_at TIMESTAMPTZ,  -- retention sweep: MATCH_EXPIRING warning sent
               war_prep_fallback_deadline TIMESTAMPTZ,  -- war preparation: fixed fallback start
                                       -- (the agreed duel time may be revised, this may not)
               winner UUID→players, created_at, updated_at)
match_players (match_id, player_id, turn_order SMALLINT,
               dynasty_index SMALLINT,  -- realm slot 1–30
               idle_turns SMALLINT,     -- consecutive timed-out turns; ≥3 ⇒ creator may kick
               PK (match_id, player_id))
turns         (id UUID PK, match_id, player_id, action JSONB, created_at)  -- audit/replay
```

## API (`/api/v1`)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/players` | Register device `{id, display_name, fcm_token}` |
| PATCH | `/players/:id` | Update name / FCM token |
| POST | `/matches` | Create `{player_id, settings}` → `status: waiting`, id = 5-letter room code. `settings.is_public` lists it publicly; `settings.gender_equal_succession` (default true) drops male-priority heirs + the §15.5 Islamic crisis |
| GET | `/matches/public` | List open **public** waiting matches with their settings (turn timer, joined count, host) — the lobby's discovery list. Matchmaking rooms come first, each with `seats` + `auto_start_at` |
| POST | `/matches/:id/join` | Join a waiting match (≤ 16 seats, no fixed count) |
| POST | `/matches/:id/start` | Start the match — creator (first seat) only |
| POST | `/matches/:id/leave` | Leave/delete: waiting + creator → match deleted, otherwise the seat is freed; in a running game the realm falls to the AI (`playerLeft` event, awaited input auto-resolves like the timeout sweep); an empty match is deleted |
| POST | `/matches/:id/kick` | `{player_id, target_player_id}` — creator only, allowed once the target has missed ≥ 3 turns by timeout (`idle_turns`); the realm falls to the AI (`playerKicked` public event) |
| GET | `/matches/:id?player_id=` | State **filtered for the requester**; each player row carries `idle_turns` |
| POST | `/matches/:id/turn` | Submit turn action or pending decision (resets the seat's `idle_turns`) |
| GET | `/players/:id/matches` | List player's matches (incl. `is_creator`) |

Match ids are 5-letter uppercase room codes (typed by hand; lowercase
accepted on lookup). There is no fixed player count: players join via the
code until the creator starts the game.

### Matchmaking rooms (2026-07-29, user-designed)

Playing online must not require knowing anybody: the server itself hosts a
small, fixed set of permanently open matches (`backend/lib/src/match_templates.dart`),
listed in the lobby's own "Offizielle Partien" section (`client/lib/widgets/room_card.dart`).

| Room | Map / realms | Seats | Fallback start | Turn | War round |
|------|--------------|-------|----------------|------|-----------|
| Blitz | klein 48×28 / 12 | 4 | 24 h after the 3rd player | 12 h | 5 min |
| Standard | mittel 64×36 / 20 | 6 | 24 h after the 4th player | 24 h | 10 min |
| Kaiserreich | gross 80×44 / 30 | 10 | 24 h after the 6th player | 24 h | 10 min |

- **Exactly one open room per template** (`ensureTemplateMatches`, run at
  server start, in the minute sweep and right after a room starts) — several
  open rooms of the same kind would split the players across half-full lobbies.
- **Starts by itself**: full ⇒ immediately (in `joinMatch`); otherwise
  `matches.auto_start_at` is armed when the `fallbackSeats`-th player joins
  and `sweepTemplates()` starts the room at that instant with the humans it
  has — the remaining realms simply stay AI. Dropping back below the
  threshold disarms it again.
- **No creator**: `settings.template` marks the room; `view`/`matchesForPlayer`
  report `creator_id`/`is_creator` as null/false while it waits, `POST /start`
  is rejected (400), and leaving only frees the seat — even an emptied room
  stays open. Once the room is *running*, its first seat takes over the host
  duty that outlives the start (kicking a permanently idle player).
- The 7-day waiting retention applies to rooms too, and must: a room stuck
  below its threshold for a week is deleted (no game state exists yet) and
  immediately replaced by a fresh one, so a template can never be blocked.
- `settings.template` is stripped from client-supplied settings in `api.dart`
  (like the seed) — only the server hosts rooms. The key is stable and
  language-neutral; the client localizes the display name.

Responses `{data, error}`; 400 validation, 403 wrong turn, 404 missing.
`error` is player-facing prose (since 2026-08-08): `ApiException` carries a
key into the de/en catalog `backend/lib/src/api_messages.dart`, formatted at
response time in the language of the request's `Accept-Language` header (the
app sends it on every call; no header → German). The engine's rule
rejections are already localized (`messageLocale`, from the submit body's
`locale`) and pass through the catalog verbatim.

## Versioning & compatibility

**Every game always plays under the latest rules** — there is no per-game ruleset version to pin or migrate. A rule or balance change ships in a new **app version**; local saves adopt the new behavior on load, and online matches require every seat to run the same app version before they may take their turn.

- **`schemaVersion`** (`game_core/src/state/versioning.dart`) — the JSON *shape* that travels inside every `GameState`. Additive changes (new field + `fromJson` default) never bump it; incompatible reshapes bump it and add a `schemaMigrations` step. `GameState.fromJson` migrates old documents on every load path. Newer-than-supported documents throw `UnsupportedSchemaVersionException` → shown as "update the app".
- **`appVersion`** (`game_core/src/state/versioning.dart`, mirrored in each `pubspec.yaml`) — the single build version shared by client and server. The client sends it with every online turn submission; the server rejects a build that differs from its own (HTTP **426**), and the match view flags `update_required` so the client blocks the turn before it starts. `GET /version` advertises the server's `app_version`.

Online additionally: API changes stay additive within `/api/v1`.

## State Visibility (hidden information)

- `visibleStateFor(GameState, slot)` strips other realms' treasury, food stocks, troops, colony ships, guard level etc.; keeps public data (map ownership, dynasty names/titles/religion, town tiers, offices, chronicle) and the viewer's own realm.
- Hidden information is per **player**, not per realm slot: every realm of the same human player (`humanControlledSlots` — control follows the ruler, §15.4) stays unredacted, incl. its owner-events, pending decisions, assassination orders and recap baselines. Basis of the online off-turn viewer ("Reich & Karte ansehen" → `MapViewerScreen`): read-only map + Info menu with a realm switcher; actions are no-ops (`GameController.readOnly`), the server would 403 them anyway.
- Also redacts election bribes/votes and war snapshots/movement budgets for non-participants; rebuilds troop markers from what the viewer may see; zeroes `rngSeed`.
- Hidden events are redacted **in place** (opaque `redacted` placeholder, slot 0, no payload), never removed: recap baselines and the client's drama-popup tracking address events by absolute position (`prunedEventCount + index`), so the filtered list must keep the master log's indices (0.1.13 fix — removing them silently emptied the online recap).
- Espionage writes fuzzed `IntelReport`s into the spying realm's private state.
- Online: applied to every state response — the authoritative state never leaves the server. Local: the same filter drives each seat's view; the handoff screen blocks the predecessor's intel.

## Turn Flow (online)

1. `POST /matches/:id/turn` `{player_id, action}` — 403 unless awaited from this player.
2. Apply via `game_core.applyAction` with the match's seeded RNG.
3. Advance the simulation (AI turns, world events, upkeep, AI-resolvable decisions) until a human is awaited or the game is over — synchronously in the request (pure transforms, fast).
4. Win check → `status: finished` + `winner`; save state + action to `turns`.
5. Set `current_turn`, `turn_deadline` (if timer), push `YOUR_TURN`/`YOUR_DECISION`; return the filtered match.

**Timeouts**: a periodic job auto-resolves expired inputs (turn → end-turn with no actions; decision → its default), then advances as above. Reminder push at ~80%. Players are never eliminated for idling.

**Retention** (2026-07-27): a daily sweep (`sweepStale`, also run at server start) deletes matches nobody will come back to, keyed off `updated_at`. **Finished** → deleted 30 days after the last update (a game whose humans are all dead/defeated ends as `humansDefeated` and takes this path; before the sweep, a finished match also disappears as soon as every seat left it). **Waiting** → abandoned lobbies deleted after 7 days (no game state exists yet). **Active** → only truly silent matches are reaped: after 351 days without any update every seat gets one `MATCH_EXPIRING` push (`expiry_warned_at` dedups it), and the match is deleted no earlier than 14 days after that warning and 365 days after the last activity; any activity clears the pending warning. Matches WITH a turn timer never reach this age — the timeout sweep advances them at every deadline — so in practice this covers timer-less matches whose remaining humans all went silent.

Local mode runs the same loop on-device (`advanceUntilHuman`); auto-save after every completed turn.

### Human-vs-human wars: sequential round input on a short war clock (decided 2026-06-10, implemented 2026-06-12)

A war is up to 20 rounds × 2 sides of awaited inputs; `activeWar` is global and pauses the turn loop, so the match-level timer would freeze everyone for days.

**Mechanism:** wars stay sequential/global (original semantics, replayable). `ActiveWar.actingSlot` names the side whose interactive input is awaited — attacker first each round, as in the original. In a human-vs-human war the attacker's "Runde beenden" only **hands the round over** to the defender (`handWarRoundOver`); the defender's round end advances the round for real. `warActingSlot(state)` resolves the awaited side everywhere (engine gate on war actions, `GameController.currentSlot`, the server's awaited player); the engine entry point for awaited round input is `endWarRoundFor(state, slot, …)`.
- **Local hot-seat:** every acting-side change raises the regular handoff blocker (`GameController._maybeRequestSeatHandoff`) — the device passes between the combatants each half-round and returns to the paused turn's player when the war ends.
- **Online:** a human-vs-**human** war round runs on the short **war clock** (`settings.war_round_timeout`, default 10 min, host-configurable) — both combatants are expected live (worst case ≈ 20 × 2 × clock ≈ 7 h; live players finish in minutes). A human fighting an **AI** instead gets the full **turn timer** ("time like a normal turn"): an AI can drag a player into a war out of band (during another seat's end-of-turn AI advance), so the attacked player must be able to fight it interactively in the war panel at their leisure — not have it swept out from under them in 10 min. `_warIsHumanVsHuman` in the match service picks the clock. Expired war input falls back to the AI war logic for that side/round, which moves an idle human's units by each unit's **stance** (`TroopStance`: *hold position* — defend the base, advance only once the enemy army is gone; *attack* marches on the enemy capital). `startWar` issues the **starting orders**: the aggressor's units go in on *attack*, the defender's on *hold position* (fix 2026-08-08 — `Troop.stance` defaults to *hold position*, so an attacker who delegated the war without touching a unit had its whole army stand at home for all 20 rounds and the war ended in a guaranteed draw). Both sides re-order every unit individually during the preparation window. An idle attacker thereby hands over; an idle settlement winner auto-settles; both combatants get a `WAR_STARTED` push. (AI sides also always keep one **home guard** on their base so a base is never left wholly undefended.)

**Preparation window + delegation (0.1.13, user-designed):** a human-vs-human war starts in `WarPhase.preparation`: BOTH combatants get a `warPlan` pending decision (created in `startWar`) — command their side live, or hand THIS one war to the stance autopilot (`ActiveWar.autoSlots`; `warSideIsHuman` treats delegated sides like AI sides everywhere — never awaited, AI peace test, auto settlement). Troop stances are NOT part of the answer (the bulk choice was removed 2026-07-13): throughout the preparation window each combatant sets every unit's stance individually over the visible map (`SetTroopStance` — war panel for the attacker/hot-seat, the read-only off-turn map viewer for the online defender; the match service accepts `SetTroopStance` OUT OF TURN while a war involving that realm is in preparation, mirroring the out-of-turn decision path). `resolveWarPreparation` (ai_turn.dart) applies the start rules after each answer and at the deadline: both delegated → the whole war fast-forwards like an AI-vs-AI war; exactly one live side → the rounds begin as soon as both answered; both live → online waits for the preparation deadline (see the duel scheduling below; without an agreed slot the FULL turn timer, armed in `_commit` even with nobody awaited; `_sweepMatch` forces the start) so the duel begins at a fair, predictable time — hot-seat starts immediately (both players are present). Unanswered sides default to the autopilot, so an absent player is protected, never steamrolled. `beginWarRounds` rolls the first round's movement when the preparation ends.

**Duel scheduling (2026-07-08, user-designed; refined 2026-07-24):** a LIVE `warPlan` answer may additionally propose duel start times (`'slots'`: epoch ms UTC on full hours, so both players' proposals land on identical instants). The client offers "sofort" — the top of the answering side's CURRENT hour — plus the following full hours over the turn-timer window (capped at 24 entries; matches without a timer offer 24 h), rendered in local time. Because "sofort" is pinned to the current hour, two sides only agree on it when both answer within the same clock hour — a late answer can no longer start the duel at an arbitrary future instant. Once every side has answered and both play live, the engine stores the earliest common proposal in `war.scheduledStartMs` (`apply_action` warPlan case): a real instant → `_commit` arms `turn_deadline` at exactly that instant (a "sofort" agreement is a current-hour instant already in the past, so `_sweepMatch` fires the start at once; an agreed instant may lie LATER than the full-turn fallback — both sides chose it — and also works without a turn timer); no overlap → null, the full-turn fallback governs. When both answers are in, both sides get a `WAR_START_FIXED` push (agreed or fallback; worded per role — the attacker, who chose first, is told the defender has now chosen) and the second answerer sees an in-app confirmation of the matched appointment; an AGREED start additionally gets one `WAR_START_SOON` reminder ~15 min ahead (`_sendWarStartReminders` in the sweep, deduped via `match.warReminderFor`).

**Revisable plan (2026-08-09, user request).** Nothing about the plan is final until the duel begins: the `WarPrepPlan` action (payload identical to the `warPlan` answer — `auto`, `slots`) may be re-submitted as often as the player likes for as long as `WarPhase.preparation` runs, by EITHER combatant and OUT OF TURN (match service, next to the `SetTroopStance` allowance; the client also permits it through the read-only map viewer, `_prepStanceAllowed`). It covers the three things a player could previously only answer once and then had to live with:
1. **command mode** — switch between commanding live and the stance autopilot (also *back* to live: someone who delegated in a hurry, or was defaulted to the autopilot, may still take the field),
2. **times** — replace the proposed instants (empty list withdraws them), so two sides who found no common hour can widen their offers instead of waiting out the fallback deadline,
3. **transparency** — `war.planAnsweredSlots` (who has already chosen) and both sides' `planSlots` live in the shared war state and survive `visibleStateFor` for the two COMBATANTS (bystanders get every scheduling field cleared), so the time picker can flag the hours that suit the opponent and the panel can say "X hat noch nicht gewählt" / "noch kein gemeinsamer Termin".

`setWarPrepPlan` + `recomputeWarStart` (rules/war.dart) are the ONE place both the `warPlan` answer and `WarPrepPlan` record a plan, so a revision re-derives `scheduledStartMs` exactly like a first answer. Two rules protect the fixed appointment: an agreed instant is never cleared by a LATER delegation (a live opponent planned for it), and `resolveWarPreparation` therefore keeps waiting for that instant instead of applying the one-live-side early start. Server side, `_commit` re-arms `turn_deadline` to the new appointment, falls back to `match.war_prep_fallback_deadline` (the window's FIXED declaration deadline, stored precisely so a withdrawn agreement cannot buy another full turn timer) and re-sends `WAR_START_FIXED` to both sides whenever the agreed instant actually changes.

**No-show rule:** any interactive input during the ROUNDS phase marks the side in `war.actedSlots` (match service); a duelist whose round clock expires while they NEVER acted in this war is handed to the stance autopilot for the rest of the war (`_sweepMatch`) — applied after the round's classic fallback so the handover semantics stay intact, and only in a duel between two HUMAN seats (`_warIsHumanDuel`). That gate used to be `_warIsHumanVsHuman`, which turns false the moment ONE side is delegated: the SECOND absentee was then never handed over and kept the full turn clock for every remaining round, so a duel neither player attended blocked the match for ~20 days (fix 2026-08-08).

**Unattended wars must never stand (2026-08-08).** A war whose every side sits on the autopilot awaits nobody, so no clock belongs to it — left standing it freezes the whole match for good (a running war blocks every normal turn). `warIsUnattended`/`fastForwardUnattendedWar` (game_core) resolve it on the spot; the match service runs the guard in `_resumeAfterWarIfOver`, `_commit` refuses to leave an active war without a deadline (1-minute retry), the timeout sweep isolates per-match failures so one bad match cannot stop every other match's clock, and `_sweepFrozenMatches` revives matches that already entered that state on an older build.

Rejected: parallel war track (shared-state mutation breaks replay), WEGO plans (kills tactics), plain blocking (unbounded freeze), war input as pending decisions (the awaited-player mechanism already models it with less machinery).

**Seat vs. active player (local client):** while a war pauses another realm's turn (an AI attacker's, or the human attacker's while the defender responds), the engine's `currentPlayer` stays that realm; `GameController.currentSlot` is the *seat* (the acting human war side). Map filter, status row, recap, decisions all key off the seat; regular menus are locked while `warPauseActive`.

## RNG & Determinism

`game_core` never uses a global RNG; the seed lives in the state (save file / match row), making saves replayable and outcomes server-verifiable. Clients never roll dice online.

## FCM

HTTP v1 API via a Dart client (service-account creds from env). Send after state save in the turn handler; on failure log and continue (never fail the turn request). Token updated on launch via `PATCH /players/:id`.

Client (`client/lib/services/push_service.dart`, firebase_messaging): permission is requested via the system dialog when the player uses online play (home screen with a configured profile, or right after online setup); the token is uploaded then and on every rotation. Tapping a notification (`data.match_id`) opens the match screen. Push is optional end to end — without the platform Firebase config `PushService.init()` yields nothing and the game runs unchanged (desktop dev builds included); setup steps in README "Push notifications".

## Project Structure

```
/packages/game_core   # shared pure Dart rules engine (above)
/backend              # Dart shelf server (V2): lib/src/{api,match_service,store,models,push_service}.dart, bin/server.dart, Dockerfile
/client               # Flutter: services/ (incl. api_client + online_service), game/ (Flame), screens/ (incl. online lobby), widgets/, tutorial/
```

### V2 implementation status

The server is implemented (`backend/`): players/matches/join/start/turn/
list endpoints, per-requester `visibleStateFor` filtering, the full turn
flow (apply → AI advance → win check → deadline → push), submission
responses carry the action's events (visibility-filtered) for the
client's result popups, the recap baseline moves server-side at end_turn,
the timeout sweep auto-resolves expired input (incl. the war clock), FCM
HTTP-v1 push behind `FIREBASE_SERVICE_ACCOUNT` (logged stub without it),
and a single-node JSON **file store** behind the `GameStore` interface
(PostgreSQL slots in behind the same interface). Matches live under
5-letter room codes; the creator starts the game once everyone joined
(legacy fixed-size matches still auto-start when full). Deployment:
`backend/Dockerfile` + `backend/deploy/` (compose + Nginx example).

The client plays online matches end to end: the `GameSession` interface
(`services/game_session.dart`) splits local and online play —
`LocalGameSession` applies actions through the engine, the
`OnlineGameSession` round-trips every action to `/matches/:id/turn` and
rethrows server rejections as the engine's `ActionException`s, so the
entire game UI (menus, war panel, decisions) runs unchanged on top; the
`GameController` action path is async for both. The server URL is baked
in at build time via `--dart-define=PCKAISER_SERVER_URL` (manual entry is
the dev fallback). Lobby: device identity, create/join (by room code,
auto-uppercased)/list; the waiting room shows the room code and the
creator's "Spiel starten" button; the match screen polls while waiting,
prompts out-of-turn decisions, and opens the regular game screen on your
turn (undo hidden — the server is authoritative). Human-vs-human wars
work online and locally (the war clock / hot-seat handoff above) — V2 is
feature-complete; remaining: device testing.

## Backend env & infra (V2)

`DATABASE_URL`, `FIREBASE_SERVICE_ACCOUNT` (base64 JSON), `PORT=3000`.
Docker Compose (server + Postgres), Nginx reverse proxy + Let's Encrypt, daily `pg_dump` cron.

## Out of Scope (V1 of online)

Auth/JWT, skill-based matchmaking/ranking, leaderboard, spectator mode, WebSockets (client polls on foreground).
