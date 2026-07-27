# Project Checklist — PCKaiser Mobile

Progress tracker. Spec: `ORIGINAL_GAME.md` (§-refs). Dated decisions/fixes:
`docs/HISTORY.md`. Rules-version changelog: `game_core/src/state/versioning.dart`.

## Phase 0 — Setup ✅
- [x] Flutter workspace: `client/` (Flutter 3.44.1) + `packages/game_core` (pure Dart)
- [x] Save format: one JSON file per named slot (`save_service.dart`); no CI (Jenkins reserved for V2 backend)
- [x] Tile assets imported (38 indices, §24)

## Phase 1 — World & State ✅
- [x] State model + JSON (add-only forward compat), `GameEvent`, `visibleStateFor`, seeded Borland-LCG RNG (§2, §25)
- [x] Map generation (§3), new-game setup (§5), build/claim/demolish/religion actions (§4), golden tests

## Phase 2 — Turn Pipeline ✅
- [x] Round/turn driver (§6.1), economy (§7), food/population/popularity (§8), market + trade ships (§9), movement roll (§6.3)
- [x] Protect-new-players rule (years ≤ 1009); auto-save after each turn

## Phase 3 — Dynasty & Society ✅
- [x] Aging/death/succession incl. ruler aliasing (§15, §19), births/marriages/divorce/Islamic crisis (§14)
- [x] Titles & promotion (§16); Kurfürsten, Kaiser/Sultan elections, bribery, chronicle/epithets (§17)
- [x] Pending-decisions queue (marriageConsent, heirChoice, childName, electionBribe, electorVote, coercion, convertOrDie)

## Phase 4 — Conflict & Events ✅
- [x] Troops (§10), war loop + termination + settlement (§11), coercion (§12), plunder (§11.5)
- [x] Espionage & assassination (§13); world events + bankruptcy/strife/replacement dynasties (§18, §19); win check (§19.3)

## Phase 5 — AI ✅
- [x] AI turn script (§20) via the same action primitives; AI war movement (v7: defender fights back)
- [x] 200-year full-AI smoke test + `tool/sim_report.dart`

## Phase 6 — Flutter Client (V1 local) ✅
- [x] Flame map (single rasterized Picture, color-blind-safe borders + captions), tile sheet, HUD, event feed + recap
- [x] Undo stack, hidden-info views, menus, war panel + settlement UI, setup flow, hot-seat handoff, save slots
- [x] Accessibility baseline (48dp targets, semantics); interactive tutorial (`client/lib/tutorial/`)
- [x] Localization: full de/en UI translation (menus, events, war, tutorial, engine messages, realm exonyms); Options sub-menu language picker, device-language default (2026-07-20)

> Not yet run on a device/emulator (no Android toolchain here). Logic is test-covered; rendering/gestures need a visual pass.

## Phase 7 — Polish & Release (V1)
- [ ] Performance measurement on device (`flutter run --profile`; map already 1 draw call/frame)
- [x] App icons + store metadata (`store/metadata.md`); sound/music skipped by decision
- [ ] Beta round (TestFlight / Play internal) — signing + README steps ready; needs device + store accounts
- [x] README run/test/build/deploy docs (standing rule: keep current)
- [x] Update-safe versioning (schema migrations + rules gates + latest-rules adoption; see versioning.dart)

## Phase 8 — Online Mode (V2)
- [x] Dart shelf backend (`backend/`): players/matches routes, state documents, turn endpoint (ARCHITECTURE.md) — JSON file store behind `GameStore` (PostgreSQL later)
- [x] Server-side simulation advance; `visibleStateFor` on all responses
- [x] Host match settings + turn timers; timeout sweep (reminder push pending FCM)
- [x] Retention sweep: stale finished/waiting/silent-active matches deleted daily, `MATCH_EXPIRING` warning push (2026-07-27)
- [x] Client online foundation: device identity, `ApiClient`, lobby (create/join/list, polling); server URL via `--dart-define=PCKAISER_SERVER_URL`
- [x] In-match play screen against the server (async `GameSession` round-trips; submissions return their events; out-of-turn decisions prompted from the waiting view)
- [x] Human-vs-human wars: two-sided war-round input (`ActiveWar.actingSlot`, attacker hands over to the defender), hot-seat handoff locally, `war_round_timeout` war clock online with AI fallback on timeout
- [x] Online wars vs the AI are interactive on the **full turn timer** (the short war clock now only governs human-vs-human duels); per-unit war stance (`TroopStance`: hold position / attack) steers unattended rounds; AI keeps a home guard on its base (2026-06-24, appVersion 0.1.4)
- [x] Lobby rework: 5-letter room codes, no fixed player count, creator starts the match (`POST /matches/:id/start`)
- [x] FCM HTTP-v1 push (`FIREBASE_SERVICE_ACCOUNT`, logged stub without it); Docker compose + Nginx example in `backend/deploy/` (backups = volume tar cron, see nginx.conf.example)
- [x] Leave/delete matches (`POST /matches/:id/leave`): creator deletes a waiting match, leaving a running one hands the realm(s) to the AI (`playerLeft` event); lobby + match-screen UI; `--dart-define=PCKAISER_INSTANCE` for two clients on one desktop
- [x] Client push (firebase_messaging): permission prompt on online setup/launch, token upload via `PATCH /players/:id`, notification tap opens the match; optional — app builds/runs without Firebase config (README "Push notifications")
- [x] Home screen lists running online matches ("Du bist am Zug !" first, 20 s poll)
- [x] Off-turn read-only view ("Reich & Karte ansehen"): map + Info menu (Dynastien, Kaiserchronik, …) over ALL owned realms with realm switcher, actions disabled; `visibleStateFor` filters per player instead of per slot (2026-07-07)
- [x] War takeover & preparation rework (2026-07-13, 0.1.18): key points = Stadt/Burg/Palast only; total conquest annexes the loser's whole territory into the winner's realm (loser slot vacated — no §19 aliasing); per-troop stance orders during the preparation window over the visible map (war panel + off-turn viewer; `SetTroopStance` accepted out of turn online); every involuntary human realm loss gets an explicit popup (`seatLost` event, `human` payload flags)
- [ ] Real-device/system test of an online match (two devices against a deployed server, incl. push)
