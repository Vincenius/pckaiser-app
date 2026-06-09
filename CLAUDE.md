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
- First 10 in-game years must not allow dynasty deaths.
- Local and online should share the same domain model; only persistence differs.
- Keep game logic pure and testable.

## Important files
- `ORIGINAL_GAME.md` — source game mechanics spec.
- `ARCHITECTURE.md` — system architecture and backend plan.
- `PROJECT_REQUIREMENTS.md` — current requirements for v1.

## Implementation advice
- Use a shared state format for game data in both local and online modes.
- Implement UI and game-rule layers separately.
- Design small, isolated modules for economy, population, war, espionage, and events.

## Keep this file up to date
Whenever requirements, architecture, or scope change, update `CLAUDE.md` and `ARCHITECTURE.md` together.
