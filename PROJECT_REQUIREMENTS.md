# PC Kaiser Mobile Clone — Project Requirements

## Objective
Create a faithful mobile-first clone of the original PC Kaiser game with modern UX, while preserving the core turn-based strategy and dynasty simulation mechanics.

## Platforms
- Android and iOS mobile apps
- Shared codebase using Flutter + Flame

## Scope
- V1 focus: local game mode only
- Future-ready: architecture must support online mode later
- Online mode should be able to support async multiplayer and push notifications in the future
- Matchmaking in v1 is simple room-based sharing via room code; no random matchmaking

## Core Requirements
- Faithful reproduction of original game systems: map, provinces, economy, population growth, war, espionage, marriage, dynasty events, and win conditions.
- Mobile touch input instead of keyboard controls.
- Pinch-to-zoom support for the map.
- Smart defaults and setup hints during new-game configuration.
- Auto-save after each turn; no manual save required.
- Prevent any player death during the first 10 years of game time.
- Keep features broken into small, isolated, testable units.

## Game Modes
- Local mode (v1): full gameplay experience on device.
- Online mode (future): same data model, server-backed state, async multiplayer, push notifications.
- Local and online state should be as similar as possible; the only difference is storage location.

## Data Model Strategy
- Use a single shared domain model for game state across modes.
- Local mode: persist state on the device using secure local storage or local database.
- Online mode: persist state on a backend server; server is the authoritative source of truth.
- Client actions should be validated by game logic modules.

## UX and Controls
- Replace keyboard navigation with touch-friendly UI components.
- Use tap, long press, and context-sensitive action panels.
- Allow pinch-to-zoom and pan on the map.
- Keep UI modern and uncluttered, but do not implement a full tutorial system in v1.
- Display current turn summary and recent event feedback prominently.
- Base the mobile layout on the original game’s screenshot structure:
  - Primary screen: large map area with touchable provinces.
  - Bottom/action panel for build, trade, espionage, military, and diplomacy options.
  - Separate status/detail screens for ruler info, army, population, and trade results.
  - Between-turn summary screens that show taxes, income, army wages, and movement points.

## Modern Gameplay Adaptation
- Keep original systems but simplify interactions where necessary for mobile.
- Provide helpful defaults and guidance instead of forcing players to remember legacy controls.
- Avoid overwhelming players with raw numeric menus; use concise contextual information.

## Testing and Architecture
- Game logic should be implemented as pure, deterministic functions where possible.
- UI and rendering layers should be separate from rules and game-state logic.
- Support unit testing for the economy, combat, events, AI decisions, and save/load flows.
- Structure features as composable modules that can be extended for online mode.

## Important Constraints
- The first 10 years of a match must be tuned to avoid early eliminations.
- Use the same state format for local and online to minimize divergence.
- Local mode should behave identically to online mode except for persistence and networking.

## Missing Information / Assumptions
- The client stack is Flutter + Flame.
- The asset pipeline, UI design system, and exact server hosting model are not fully defined yet.
- The online backend requirements are currently high-level; detailed backend sync, room code flow, and conflict resolution rules should be designed later.

## Notes
- Keep `ARCHITECTURE.md` and `CLAUDE.md` synchronized with these requirements.
- Prioritize local-game implementation in v1 while preserving future online compatibility.
