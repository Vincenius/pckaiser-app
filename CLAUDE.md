# CLAUDE Project Guide

Use this file as the short project reference for building the PC Kaiser mobile clone.
Keep it updated whenever the project scope or architecture changes.

## Project intent
- Build a mobile-first clone of PC Kaiser for Android and iOS using Flutter + Flame.
- V1 is local play; online mode must be supported later with the same game state model.
- Preserve the original game feel, but modernize controls and UX.

## Key rules
- Touch input only, with pinch-to-zoom map gestures.
- Auto-save after every completed turn.
- First 10 in-game years: no random dynasty deaths (aging, disease) and no eliminations. Deliberate assassinations still resolve normally.
- Local and online share the same domain model AND the same game-logic implementation: one pure Dart package (`game_core`) used by client and server; only persistence/orchestration differs. The backend is Dart (shelf), not Node.
- The world always has 30 realms (original layout); up to 16 are human players.
- Keep game logic pure and testable: `(state, action, rng) → state`, RNG injected.
- Updates must never break running games (`game_core/src/state/versioning.dart`): `GameState` JSON changes must be additive (new field + `fromJson` default); incompatible reshapes bump `currentSchemaVersion` plus a `schemaMigrations` step. Gameplay rule/balance changes bump `currentRulesVersion` and gate on `state.rulesVersion` — running games keep their original rules. See ARCHITECTURE.md "Versioning & compatibility".
- Hidden information is part of the domain model: other realms' treasury/stocks/army/guards are hidden; `visibleStateFor(state, slot)` filters every view (local hot-seat AND server responses); espionage reveals fuzzed intel.
- Modern UX deviations (event feed, undo within turn, named save slots, accessibility, host-configurable online turn timers) are specified in PROJECT_REQUIREMENTS.md.
- The home screen offers an interactive tutorial (`client/lib/tutorial/`): a real fixed-seed single-player game with a scripted step overlay that walks through the basic actions, completes within the first turn (no step ends the turn), and is never saved (ephemeral session, no handoff/recap popups). **Whenever gameplay rules, prices, menu names or UI flows change, update the tutorial steps (`client/lib/tutorial/tutorial_steps.dart`) in the same change.**

## Important files
- `ORIGINAL_GAME.md` — source game mechanics spec.
- `ARCHITECTURE.md` — system architecture and backend plan.
- `PROJECT_REQUIREMENTS.md` — current requirements for v1.
- `CHECKLIST.md` — step-by-step project plan and progress tracker.
- `README.md` — how to run, test, build and deploy. **Always keep it up to
  date**: any change to setup, build, test or deploy steps must update the
  README in the same change.

## Implementation advice
- Use a shared state format for game data in both local and online modes.
- Implement UI and game-rule layers separately.
- Design small, isolated modules for economy, population, war, espionage, and events.

## Keep this file up to date
Whenever requirements, architecture, or scope change, update `CLAUDE.md` and `ARCHITECTURE.md` together. Whenever run/test/build/deploy steps change, update `README.md` in the same change.
