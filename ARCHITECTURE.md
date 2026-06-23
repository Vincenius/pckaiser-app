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
               settings JSONB,         -- e.g. {"turn_timeout_hours":24,"war_round_timeout":600}
               turn_deadline TIMESTAMPTZ, status TEXT,  -- waiting|active|finished
               winner UUID→players, created_at, updated_at)
match_players (match_id, player_id, turn_order SMALLINT,
               dynasty_index SMALLINT,  -- realm slot 1–30
               PK (match_id, player_id))
turns         (id UUID PK, match_id, player_id, action JSONB, created_at)  -- audit/replay
```

## API (`/api/v1`)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/players` | Register device `{id, display_name, fcm_token}` |
| PATCH | `/players/:id` | Update name / FCM token |
| POST | `/matches` | Create `{player_id, settings}` → `status: waiting`, id = 5-letter room code |
| POST | `/matches/:id/join` | Join a waiting match (≤ 16 seats, no fixed count) |
| POST | `/matches/:id/start` | Start the match — creator (first seat) only |
| POST | `/matches/:id/leave` | Leave/delete: waiting + creator → match deleted, otherwise the seat is freed; in a running game the realm falls to the AI (`playerLeft` event, awaited input auto-resolves like the timeout sweep); an empty match is deleted |
| GET | `/matches/:id?player_id=` | State **filtered for the requester** |
| POST | `/matches/:id/turn` | Submit turn action or pending decision |
| GET | `/players/:id/matches` | List player's matches (incl. `is_creator`) |

Match ids are 5-letter uppercase room codes (typed by hand; lowercase
accepted on lookup). There is no fixed player count: players join via the
code until the creator starts the game.

Responses `{data, error}`; 400 validation, 403 wrong turn, 404 missing.

## Versioning & compatibility

**Every game always plays under the latest rules** — there is no per-game ruleset version to pin or migrate. A rule or balance change ships in a new **app version**; local saves adopt the new behavior on load, and online matches require every seat to run the same app version before they may take their turn.

- **`schemaVersion`** (`game_core/src/state/versioning.dart`) — the JSON *shape* that travels inside every `GameState`. Additive changes (new field + `fromJson` default) never bump it; incompatible reshapes bump it and add a `schemaMigrations` step. `GameState.fromJson` migrates old documents on every load path. Newer-than-supported documents throw `UnsupportedSchemaVersionException` → shown as "update the app".
- **`appVersion`** (`game_core/src/state/versioning.dart`, mirrored in each `pubspec.yaml`) — the single build version shared by client and server. The client sends it with every online turn submission; the server rejects a build that differs from its own (HTTP **426**), and the match view flags `update_required` so the client blocks the turn before it starts. `GET /version` advertises the server's `app_version`.

Online additionally: API changes stay additive within `/api/v1`.

## State Visibility (hidden information)

- `visibleStateFor(GameState, slot)` strips other realms' treasury, food stocks, troops, colony ships, guard level etc.; keeps public data (map ownership, dynasty names/titles/religion, town tiers, offices, chronicle) and the viewer's own realm.
- Also redacts election bribes/votes and war snapshots/movement budgets for non-participants; rebuilds troop markers from what the viewer may see; zeroes `rngSeed`.
- Espionage writes fuzzed `IntelReport`s into the spying realm's private state.
- Online: applied to every state response — the authoritative state never leaves the server. Local: the same filter drives each seat's view; the handoff screen blocks the predecessor's intel.

## Turn Flow (online)

1. `POST /matches/:id/turn` `{player_id, action}` — 403 unless awaited from this player.
2. Apply via `game_core.applyAction` with the match's seeded RNG.
3. Advance the simulation (AI turns, world events, upkeep, AI-resolvable decisions) until a human is awaited or the game is over — synchronously in the request (pure transforms, fast).
4. Win check → `status: finished` + `winner`; save state + action to `turns`.
5. Set `current_turn`, `turn_deadline` (if timer), push `YOUR_TURN`/`YOUR_DECISION`; return the filtered match.

**Timeouts**: a periodic job auto-resolves expired inputs (turn → end-turn with no actions; decision → its default), then advances as above. Reminder push at ~80%. Players are never eliminated for idling.

Local mode runs the same loop on-device (`advanceUntilHuman`); auto-save after every completed turn.

### Human-vs-human wars: sequential round input on a short war clock (decided 2026-06-10, implemented 2026-06-12)

A war is up to 20 rounds × 2 sides of awaited inputs; `activeWar` is global and pauses the turn loop, so the match-level timer would freeze everyone for days.

**Mechanism:** wars stay sequential/global (original semantics, replayable). `ActiveWar.actingSlot` names the side whose interactive input is awaited — attacker first each round, as in the original. In a human-vs-human war the attacker's "Runde beenden" only **hands the round over** to the defender (`handWarRoundOver`); the defender's round end advances the round for real. `warActingSlot(state)` resolves the awaited side everywhere (engine gate on war actions, `GameController.currentSlot`, the server's awaited player); the engine entry point for awaited round input is `endWarRoundFor(state, slot, …)`.
- **Local hot-seat:** every acting-side change raises the regular handoff blocker (`GameController._maybeRequestSeatHandoff`) — the device passes between the combatants each half-round and returns to the paused turn's player when the war ends.
- **Online:** the awaited combatant runs on the short **war clock** (`settings.war_round_timeout`, default 10 min, host-configurable) instead of the turn timer. Expired war input falls back to the AI war logic for that side/round (an idle attacker thereby hands over; an idle settlement winner auto-settles); both combatants get a `WAR_STARTED` push. Worst case ≈ 20 × 2 × clock ≈ 7 h; live players finish in minutes.

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

Auth/JWT, matchmaking queue (share the room code), leaderboard, spectator mode, WebSockets (client polls on foreground).
