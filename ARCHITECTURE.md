# Architecture Guide

Turn-based mobile strategy game with async online multiplayer.
Stack: Flutter + Flame (client) · Node.js + Fastify + PostgreSQL (backend) · Firebase Cloud Messaging (push) · Self-hosted via Docker + Nginx.

- Room-based matchmaking in v1: players join using a shared room code. No random matchmaking.
- No analytics or telemetry in v1.

---

## Principles

- Mobile-first design: Android + iOS, touch controls, gesture navigation, pinch-to-zoom map view.
- No auth in v1. Players are identified by a device-generated UUID stored in secure local storage.
- Game state is the source of truth. It lives in a JSONB column on the `matches` table. Never split it across tables.
- The server always validates turns. The client never mutates state directly — it submits an action, the server applies it and returns the new state.
- Local and online modes share the same state model. Local saves state on device, online stores state on the backend.
- Auto-save after each completed turn. No manual save UI in v1.
- The game must protect players from immediate elimination by preventing player deaths during the first 10 years.
- Matchmaking is simple room code sharing in v1; players create or join a room.
- Push is fire-and-forget. FCM notifies the opponent when it is their turn. Delivery failure is acceptable; the game remains playable without it.

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
  player_a      UUID REFERENCES players
  player_b      UUID REFERENCES players
  current_turn  UUID REFERENCES players
  state         JSONB NOT NULL     -- full game state
  status        TEXT NOT NULL      -- waiting | active | finished
  winner        UUID REFERENCES players
  created_at    TIMESTAMPTZ DEFAULT now()
  updated_at    TIMESTAMPTZ DEFAULT now()

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
| POST | `/matches` | Create match. Body: `{ player_id }`. Returns match with `status: waiting`. |
| POST | `/matches/:id/join` | Opponent joins. Body: `{ player_id }`. Sets status to `active`. |
| GET | `/matches/:id` | Get current match state. |
| POST | `/matches/:id/turn` | Submit turn. Body: `{ player_id, action }`. Validates turn ownership, applies action, updates state, sends FCM to opponent. |
| GET | `/players/:id/matches` | List matches for a player (`active` and `waiting`). |

All responses: `{ data, error }`. HTTP 400 for validation errors, 403 for wrong-turn attempts, 404 for not found.

---

## Turn Flow

1. Client calls `POST /matches/:id/turn` with `{ player_id, action }`.
2. Server checks `current_turn === player_id`. Returns 403 if not.
3. Server applies action to `state` JSONB using game logic module.
4. Server checks win condition. Sets `status: finished` and `winner` if game over.
5. Server flips `current_turn` to opponent.
6. Server sends FCM push to opponent's `fcm_token` with payload `{ match_id, type: "YOUR_TURN" }`.
7. Server returns updated match.

---

## FCM Integration

- Backend uses `firebase-admin` Node.js SDK.
- Initialize once at server startup with service account credentials from env.
- Send notification in turn handler after state is saved.
- FCM token is stored on the `players` table. Client updates it on launch via `PATCH /players/:id`.
- If FCM send fails, log the error but do not fail the turn request.

```js
// Pseudocode — turn handler (after state saved)
const opponent = await getPlayer(match.current_turn); // already flipped
if (opponent.fcm_token) {
  await firebaseAdmin.messaging().send({
    token: opponent.fcm_token,
    data: { match_id: match.id, type: 'YOUR_TURN' }
  }).catch(err => log.warn('FCM failed', err));
}
```

---

## Project Structure

```
/backend
  src/
    routes/         # players.js, matches.js
    game/           # logic.js — pure functions: applyAction, checkWinCondition
    services/       # fcm.js, db.js
    plugins/        # postgres.js (fastify-postgres), schema validation
  Dockerfile
  docker-compose.yml

/client (Flutter)
  lib/
    main.dart
    services/       # api_service.dart, player_service.dart, fcm_service.dart
    models/         # player.dart, match.dart, game_state.dart
    game/           # flame components
    screens/        # lobby, match list, game screen
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

- Docker Compose runs Fastify + PostgreSQL together.
- Nginx reverse proxies to Fastify on port 3000, terminates SSL via Let's Encrypt.
- Run `pg_dump` as a daily cron job for backups.
- Flutter app talks to `https://pckaiser.vincentwill.com/api/v1`.

---

## What Is Out of Scope (V1)

- Authentication / JWT
- Matchmaking queue (share match link or ID manually)
- Leaderboard
- Spectator mode
- Real-time (no WebSockets needed — client polls on app foreground)