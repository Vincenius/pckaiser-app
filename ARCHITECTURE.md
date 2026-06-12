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
matches       (id UUID PK, current_turn UUID→players, state JSONB,
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
| POST | `/matches` | Create `{player_id, human_count, settings}` → `status: waiting` |
| POST | `/matches/:id/join` | Join; `active` when full |
| GET | `/matches/:id?player_id=` | State **filtered for the requester** |
| POST | `/matches/:id/turn` | Submit turn action or pending decision |
| GET | `/players/:id/matches` | List player's matches |

Responses `{data, error}`; 400 validation, 403 wrong turn, 404 missing.

## Versioning & compatibility

Two version numbers travel inside every `GameState` JSON (`game_core/src/state/versioning.dart`):

- **`schemaVersion`** — JSON shape. Additive changes (new field + `fromJson` default) never bump it; incompatible reshapes bump it and add a `schemaMigrations` step. `GameState.fromJson` migrates old documents on every load path. Newer-than-supported documents throw `UnsupportedSchemaVersionException` → shown as "update the app".
- **`rulesVersion`** — gameplay rules. Changes bump `currentRulesVersion` and gate on `state.rulesVersion >= n` until the next release consolidates the gates. **Policy: every game plays the latest rules** — `adoptLatestRules` upgrades the document at the save-load boundary (client `SaveService.load`, server document load). Release 1 ships ruleset **v1**: the fourteen pre-release iterations were consolidated into the baseline (history in `docs/HISTORY.md`).

Online additionally: API changes additive within `/api/v1`; the server reports a minimum client version so outdated clients get a friendly update prompt.

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

### Human-vs-human wars online: blocking with a short war clock (decided 2026-06-10)

A war is up to 20 rounds × 2 sides of awaited inputs; `activeWar` is global and pauses the turn loop, so the match-level timer would freeze everyone for days.

**Decision:** wars stay sequential/global (original semantics, replayable), but war-round input from the non-`current_turn` combatant is a **pending decision** on a separate short **war clock** (`settings.war_round_timeout`, default 10 min, host-configurable). Expired war input falls back to the AI war logic for that side/round; a combatant can explicitly delegate the war to the AI; both get a `WAR_STARTED` push. Worst case ≈ 20 × 2 × clock ≈ 7 h; live players finish in minutes.
Rejected: parallel war track (shared-state mutation breaks replay), WEGO plans (kills tactics), plain blocking (unbounded freeze).
**Until then (V1):** engine + UI reject `DeclareWar` against human-controlled realms — the local war panel seats only one human side.

**Seat vs. active player (local client):** while an AI's turn stands paused on a human-defended war, the engine's `currentPlayer` stays the AI; `GameController.currentSlot` is the *seat* (the human war side). Map filter, status row, recap, decisions all key off the seat; regular menus are locked while `warPauseActive`.

## RNG & Determinism

`game_core` never uses a global RNG; the seed lives in the state (save file / match row), making saves replayable and outcomes server-verifiable. Clients never roll dice online.

## FCM

HTTP v1 API via a Dart client (service-account creds from env). Send after state save in the turn handler; on failure log and continue (never fail the turn request). Token updated on launch via `PATCH /players/:id`.

## Project Structure

```
/packages/game_core   # shared pure Dart rules engine (above)
/backend              # Dart shelf server (V2): lib/src/{api,match_service,store,models,push_service}.dart, bin/server.dart, Dockerfile
/client               # Flutter: services/ (incl. api_client + online_service), game/ (Flame), screens/ (incl. online lobby), widgets/, tutorial/
```

### V2 implementation status

The server is implemented (`backend/`): players/matches/join/turn/list
endpoints, per-requester `visibleStateFor` filtering, the full turn flow
(apply → AI advance → win check → deadline → push hook), the timeout
sweep, and a single-node JSON **file store** behind the `GameStore`
interface (PostgreSQL slots in behind the same interface; FCM is a logged
stub behind `PushService` until credentials are wired up). The client
ships the online foundation: device identity, `ApiClient`, and the lobby
(create / join by match ID / list with turn status, polling). **Remaining
milestone:** the in-match play screen against the server — actions must
round-trip (the client cannot roll dice: `rngSeed` never leaves the
server), so the synchronous `GameController` action path needs an async
session variant.

## Backend env & infra (V2)

`DATABASE_URL`, `FIREBASE_SERVICE_ACCOUNT` (base64 JSON), `PORT=3000`.
Docker Compose (server + Postgres), Nginx reverse proxy + Let's Encrypt, daily `pg_dump` cron.

## Out of Scope (V1 of online)

Auth/JWT, matchmaking queue (share match ID), leaderboard, spectator mode, WebSockets (client polls on foreground).
