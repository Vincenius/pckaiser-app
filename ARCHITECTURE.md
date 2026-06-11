# Architecture Guide

Turn-based mobile strategy game with async online multiplayer (up to 16 human players per match; the world always has 30 realms — AI fills the rest).
Stack: Flutter + Flame (client) · Dart `shelf` + PostgreSQL (backend) · Firebase Cloud Messaging (push) · Self-hosted via Docker + Nginx.

---

## Principles

- **One game-logic implementation.** All rules live in a pure Dart package (`game_core`) shared verbatim by the Flutter client (local mode) and the Dart server (online mode). Only persistence and orchestration differ.
- **Pure, deterministic logic.** Domain functions take `(state, action, rng)` and return a new state plus emitted events. The RNG is injected (seeded), never global — this makes the logic testable and lets the server reproduce/validate outcomes.
- No auth in v1. Players are identified by a device-generated UUID stored in secure local storage.
- Game state is the source of truth. It lives in a JSONB column on the `matches` table. Never split it across tables.
- The server always validates turns. The client never mutates state directly — it submits an action, the server applies it and returns the new state.
- Push is fire-and-forget. FCM notifies the next human player when it is their turn. Delivery failure is acceptable; the game remains playable without it.

---

## Shared Game Core (Dart package)

```
/packages/game_core
  lib/
    src/
      state/        # GameState, Realm, Dynasty, Person, Town, Troop, Tile — hand-written toJson/fromJson (no codegen; missing fields get defaults for forward compatibility)
      rules/        # economy.dart, population.dart, market.dart, military.dart,
                    # war.dart, espionage.dart, marriage.dart, dynasty.dart,
                    # titles.dart, offices.dart, events.dart, elimination.dart
      ai/           # ai_turn.dart — same action primitives as humans
      actions/      # action types (claim, build, recruit, declareWar, …) + validation
      visibility/   # visibleStateFor(state, slot), IntelReport model
      rng/          # injectable RNG abstraction (seeded)
    game_core.dart
  test/             # golden-state tests per module
```

Key API: `applyAction(GameState, PlayerAction, Rng) → (GameState, List<GameEvent>)`,
`runAiTurn(GameState, int slot, Rng) → (GameState, List<GameEvent>)`,
`runWorldPhase(...)`, `checkWinCondition(GameState)`,
`visibleStateFor(GameState, int slot)`.

`GameEvent`s are the single source for all player-facing notifications: the
client's **event feed** renders them (with filters and a "since your last
turn" recap), and undo/replay tooling consumes the same stream. Events carry
`{year, slot, type, visibility, payload}` — `visibility` controls who sees
them in filtered views (public / owner-only / participants).

### Realm indexing

Realm/dynasty slots follow the original: indices **1–30**, `0` = "Niemand" (unowned/vacant sentinel). The same indices are used in the JSON state and in `match_players.dynasty_index`.

### Pending decisions (required for async online)

Several original mechanics prompt a player **outside their own turn**: marriage consent, Kurfürst votes in a Kaiser election, the defeated ruler's convert-or-die choice, heir selection. The state model represents these as a `pendingDecisions` queue (`{id, type, decidingSlot, payload, deadline?}`):

- **Local mode**: the UI resolves them inline (the device is handed to that player).
- **Online mode**: the turn pipeline pauses, the deciding player is notified via FCM (`type: "YOUR_DECISION"`), and they submit the decision via the same turn endpoint. AI deciders resolve immediately.
- Each decision type defines an AI/default fallback (e.g. marriage consent → 25% roll) so an unresponsive player can be timed out later without breaking the model.

---

## Data Model

```sql
players
  id            UUID PRIMARY KEY   -- generated on device, sent on first request
  display_name  TEXT NOT NULL
  fcm_token     TEXT               -- updated on login / token refresh
  created_at    TIMESTAMPTZ DEFAULT now()

matches
  id            UUID PRIMARY KEY
  current_turn  UUID REFERENCES players   -- human whose input is awaited (turn or pending decision)
  state         JSONB NOT NULL            -- full game state (shared schema with local)
  settings      JSONB NOT NULL DEFAULT '{}'  -- host-chosen match settings, e.g. { "turn_timeout_hours": 24 }
  turn_deadline TIMESTAMPTZ               -- when the awaited input auto-resolves; null = no timer
  status        TEXT NOT NULL             -- waiting | active | finished
  winner        UUID REFERENCES players   -- null until game over
  created_at    TIMESTAMPTZ DEFAULT now()
  updated_at    TIMESTAMPTZ DEFAULT now()

match_players                             -- 2–16 humans per match
  match_id      UUID REFERENCES matches
  player_id     UUID REFERENCES players
  turn_order    SMALLINT NOT NULL         -- 0-based; determines play sequence among humans
  dynasty_index SMALLINT NOT NULL         -- realm slot in game state (1–30)
  PRIMARY KEY (match_id, player_id)

turns
  id            UUID PRIMARY KEY
  match_id      UUID REFERENCES matches
  player_id     UUID REFERENCES players
  action        JSONB NOT NULL
  created_at    TIMESTAMPTZ DEFAULT now()
```

---

## API

Base path: `/api/v1`

| Method | Path | Description |
|--------|------|-------------|
| POST | `/players` | Register device. Body: `{ id, display_name, fcm_token }`. Returns player. |
| PATCH | `/players/:id` | Update display name or FCM token. |
| POST | `/matches` | Create match. Body: `{ player_id, human_count, settings }` (2–16 humans; world is always 30 realms; `settings.turn_timeout_hours`: null/12/24/48/168, host-chosen). Returns match with `status: waiting`. |
| POST | `/matches/:id/join` | Player joins open slot. Body: `{ player_id }`. Sets status to `active` when all human slots filled. |
| GET | `/matches/:id?player_id=` | Get current match state, **filtered for the requesting player** (see State Visibility). |
| POST | `/matches/:id/turn` | Submit a turn action or a pending decision. Body: `{ player_id, action }`. Validates ownership, applies it, advances the simulation, sends FCM to the next awaited human. |
| GET | `/players/:id/matches` | List matches for a player (`active` and `waiting`). |

All responses: `{ data, error }`. HTTP 400 for validation errors, 403 for wrong-turn attempts, 404 for not found.

## Versioning & compatibility

App updates must never break a running game — local saves now, online matches later. Two version numbers travel inside every `GameState` JSON document (`game_core/src/state/versioning.dart`):

- **`schemaVersion`** (`currentSchemaVersion`) — the shape of the JSON. Additive changes (new field with a `fromJson` default) never bump it; this covers almost all evolution. Incompatible reshapes (rename, type change, restructure) bump it by one and add a step to `schemaMigrations`. `GameState.fromJson` migrates old documents transparently, so every load path — local save file and the server's JSONB column — heals automatically. Documents from a *newer* version throw `UnsupportedSchemaVersionException`; the client lists such saves as "update the app" instead of opening them.
- **`rulesVersion`** (`currentRulesVersion`) — the gameplay rules. A rule/balance change bumps the constant and gates the new behavior on `state.rulesVersion >= n`. **Policy (since 2026-06-11, product decision): every game plays under the latest rules** — `adoptLatestRules` (versioning.dart) upgrades the document at the save-load boundary (the client's `SaveService.load` now, the server's document load later), and new games start at the latest version anyway. The per-version gates stay in the engine: they document each change, keep old behavior testable (`GameState.fromJson` remains a faithful decoder that never silently upgrades), and are the re-pinning mechanism if online matches ever need rule stability mid-match.

Online additionally relies on the server being authoritative (clients submit actions, the server's `game_core` applies them) plus two API-level rules: API changes are additive within `/api/v1`, and the server reports a minimum supported client version in match responses so outdated clients get a friendly "please update" prompt instead of undefined behavior (store rollouts are gradual; old and new clients always coexist).

## State Visibility (hidden information)

Espionage only matters if other realms' numbers are actually hidden, so visibility is part of the shared model, not a UI trick:

- `game_core` provides `visibleStateFor(GameState, int slot) → GameState` — strips other realms' treasury, food stocks, troop details and guard level; keeps public data (map ownership, dynasty names/titles/religion, town tiers, offices, chronicle) and the requesting player's own full data.
- The filter also redacts cross-realm internals: an active election's bribes and cast votes (each participant's pending decision carries what they may know), and an active war's unit snapshots / movement budgets for everyone but the two combatants.
- Successful espionage missions write an `IntelReport {targetSlot, year, fuzzedValues}` into the spying realm's private state; reports survive turns and are included in that player's filtered view.
- **Online**: the server applies `visibleStateFor` in `GET /matches/:id` and in turn responses. The authoritative full state never leaves the server.
- **Local hot-seat**: the same filter drives what each seated player sees; the handoff screen sits between turns so nobody scrolls a predecessor's intel.

---

## Turn Flow (online)

1. Client calls `POST /matches/:id/turn` with `{ player_id, action }`.
2. Server checks the action is awaited from this player (`current_turn`, or a pending decision addressed to them). Returns 403 if not.
3. Server applies the action via `game_core.applyAction` with the match's seeded RNG.
4. **Server advances the simulation**: it runs AI realm turns, world events, upkeep, and AI-resolvable pending decisions — looping until the game either needs input from a human (next human turn or a human pending decision) or is over. AI processing happens synchronously in the request; with 30 realms a full inter-human gap is fast (pure state transforms, no I/O).
5. Server checks the win condition. Sets `status: finished` and `winner` if game over.
6. Server sets `current_turn` to the human now awaited (skips eliminated players) and saves state + the action to `turns` (audit/replay).
7. If the match has a turn timer, `turn_deadline = now() + settings.turn_timeout_hours`.
8. Server sends FCM push to that player's `fcm_token` with payload `{ match_id, type: "YOUR_TURN" | "YOUR_DECISION" }`.
9. Server returns the updated match (filtered for the submitting player).

### Turn timeouts

- A scheduled job (every few minutes) selects active matches with `turn_deadline < now()` and auto-resolves the awaited input: an expired **turn** becomes "end turn with no actions" (upkeep already ran); an expired **pending decision** takes its defined AI/default fallback. The simulation then advances as in step 4.
- At ~80% of the timeout a reminder push (`type: "TURN_REMINDER"`) is sent once.
- Timeouts only skip the awaited input — players are never eliminated for idling; they can play their next turn normally.

In local mode the same loop runs on-device: human turns come from the UI, AI turns and world phases from `game_core`, auto-save after every completed turn.

### Human-vs-human wars online: blocking with a short war clock (decided 2026-06-10)

**Problem.** A war runs up to 20 rounds; each round both sides move units, may plunder, and answer the peace question — up to ~40 awaited inputs ping-ponging between the two combatants. `GameState.activeWar` holds at most one war globally (original behavior) and the turn loop pauses while a human-defended war is open, so under the match-level timer (hours/days per input) a single human-vs-human war could freeze the other 14 players for days. Human-vs-AI wars are unaffected — they resolve inside the human's turn like any other action.

**Decision: keep wars blocking, but give war inputs their own short clock.**

- Wars stay sequential and global (one `activeWar`, turn loop paused). This preserves the original semantics — a war resolves inside the declarer's turn — and the `(state, action, rng) → state` replay/audit model. No parallel war track.
- War-round input from the combatant who is not `current_turn` is modeled as a **pending decision** — the mechanism already covers "an action is awaited from a player out of turn order". War rounds never touch `current_turn`.
- While a war awaits human input, `turn_deadline` is set from a separate **war clock** (`settings.war_round_timeout`, default 10 minutes, host-configurable) instead of `turn_timeout_hours`. The existing timeout job needs no new query — only the deadline source differs.
- On war start both combatants get a push (`type: "WAR_STARTED"` — "be online or the AI fights for you"); each awaited war input pushes `YOUR_DECISION` as usual. In practice the war plays as a semi-live session.
- An **expired war input falls back to the existing AI war logic** for that side, for that round (AI movement + the traced peace rules in `rules/war.dart`). The match never stalls; missing war rounds never eliminates anyone (consistent with general timeout policy).
- A combatant can explicitly **delegate the rest of the war to the AI** (same code path as the timeout fallback) when they know they can't attend.
- Bound: fully-AFK worst case ≈ 20 rounds × 2 sides × war clock ≈ 7 h at the default; with both players present a war takes minutes.

**Rejected alternatives:** running the war in parallel with other turns (plunder/conquest/treasury transfers mutate shared state under interleaved turns; breaks replay and the single `activeWar`); WEGO battle-plan submission (deletes the game's main tactical moment); plain blocking under the match timer (unbounded freeze).

**Until the war clock ships (V1):** `DeclareWar` against a human-controlled realm is rejected by the engine (and filtered from the UI) — the local war panel can only seat one human side, so a human-vs-human war would deadlock the match. Human-vs-AI wars are unaffected.

**Seat vs. active player (local client).** While an AI's turn stands paused on a war against a human defender, the engine's `currentPlayer` remains the AI. The client's `GameController.currentSlot` is therefore the *seat*: normally the active player, during a war pause the human war side. The map filter (`visibleStateFor`), status row, recap and decision prompts all key off the seat, and the regular action menus are locked while `warPauseActive` — only war actions are legal then. The online server gets the same distinction naturally (authenticated player vs. turn owner).

---

## RNG & Determinism

- `game_core` never calls a global RNG; every entry point takes an `Rng`.
- Online: the server owns the RNG (seed stored in the match state). Clients never roll dice — outcomes arrive in the returned state/events.
- Local: the device owns the RNG the same way; the seed lives in the save file, which makes saves replayable and bugs reproducible.

---

## FCM Integration

- Backend uses the FCM HTTP v1 API via a Dart client (service account credentials from env).
- Send notification in the turn handler after state is saved.
- FCM token is stored on the `players` table. Client updates it on launch via `PATCH /players/:id`.
- If FCM send fails, log the error but do not fail the turn request.

```dart
// Pseudocode — turn handler (after state saved, current_turn already advanced)
final nextPlayer = await getPlayer(match.currentTurn);
if (nextPlayer.fcmToken != null) {
  try {
    await fcm.send(token: nextPlayer.fcmToken,
                   data: {'match_id': match.id, 'type': 'YOUR_TURN'});
  } catch (err) {
    log.warning('FCM failed', err);
  }
}
```

---

## Project Structure

```
/packages/game_core   # shared pure Dart game logic (see above)

/backend (Dart, shelf)
  bin/server.dart
  lib/
    routes/         # players.dart, matches.dart
    services/       # fcm.dart, db.dart (postgres), timeout_job.dart
    middleware/     # json validation, error envelope
  Dockerfile
  docker-compose.yml

/client (Flutter)
  lib/
    main.dart
    services/       # api_service.dart, player_service.dart, fcm_service.dart, save_service.dart
    game/           # flame components (map, tiles, units)
    screens/        # setup, lobby, match list, game screen, turn summary
  # depends on game_core for all rules; models come from game_core/state
```

---

## Environment Variables (Backend)

```
DATABASE_URL=postgresql://user:pass@localhost:5432/game
FIREBASE_SERVICE_ACCOUNT=<base64-encoded JSON>
PORT=3000
```

---

## Infrastructure

- Docker Compose runs the Dart server + PostgreSQL together.
- Nginx reverse proxies to the server on port 3000, terminates SSL via Let's Encrypt.
- Run `pg_dump` as a daily cron job for backups.
- Flutter app talks to `https://yourdomain.com/api/v1`.

---

## What Is Out of Scope (V1)

- Authentication / JWT
- Matchmaking queue (share match link or ID manually)
- Leaderboard
- Spectator mode
- Real-time (no WebSockets needed — client polls on app foreground)
