# Project Checklist — PC Kaiser Mobile

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
- [ ] Localization: full §23 string-table import (basic en/de toggle exists)

> Not yet run on a device/emulator (no Android toolchain here). Logic is test-covered; rendering/gestures need a visual pass.

## Phase 7 — Polish & Release (V1)
- [ ] Performance measurement on device (`flutter run --profile`; map already 1 draw call/frame)
- [x] App icons + store metadata (`store/metadata.md`); sound/music skipped by decision
- [ ] Beta round (TestFlight / Play internal) — signing + README steps ready; needs device + store accounts
- [x] README run/test/build/deploy docs (standing rule: keep current)
- [x] Update-safe versioning (schema migrations + rules gates + latest-rules adoption; see versioning.dart)

## Phase 8 — Online Mode (V2)
- [ ] Dart shelf backend: players/matches routes, JSONB state, turn endpoint (ARCHITECTURE.md)
- [ ] Server-side simulation advance; `visibleStateFor` on all responses
- [ ] Host match settings + turn timers; timeout job + reminder push
- [ ] Human-vs-human war clock (pending decisions + `war_round_timeout`, delegate-to-AI, WAR_STARTED push)
- [ ] FCM push, match lifecycle, Docker + Nginx deployment, backups
