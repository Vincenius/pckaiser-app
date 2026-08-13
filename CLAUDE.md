# CLAUDE Project Guide

PCKaiser mobile clone (Flutter + Flame, Android/iOS). V1 = local hot-seat; V2 = online with the same state model and rules. Keep this file updated when scope/architecture changes.

## Key rules
- Touch-only input, pinch-zoom map. Auto-save after every completed turn.
- First 10 in-game years: no random deaths or eliminations; deliberate assassinations still resolve.
- ONE pure-Dart rules engine (`packages/game_core`) shared by client and the future Dart-shelf server; only persistence/orchestration differ. Logic is pure: `(state, action, rng) → state`, RNG injected.
- World = up to 30 realms, up to 16 human. Setup option "Kartengröße" (since 2026-07-21): Groß 80×44 (default, 10–30 realms, def. 30), Mittel 64×36 (8–24, def. 20), Klein 48×28 (6–16, def. 12) — `MapSize` in game_core; realm count = `state.realmCount` (realms list length), never the `World.realmCount` constant (that is the 30-slot table maximum).
- Updates never break running games (`game_core/src/state/versioning.dart`): JSON changes additive (new field + `fromJson` default); reshapes bump `currentSchemaVersion` + migration. **Gameplay rules are NOT versioned — every game always plays the latest rules.** The `appVersion` (in `versioning.dart`, mirrored in each `pubspec.yaml`) should stay in sync with the current branch name; in an online match a seat on an older build must update before its next turn (server returns 426; the match view flags `update_required`). See ARCHITECTURE.md "Versioning & compatibility".
- Hidden information is part of the domain model: `visibleStateFor(state, slot)` filters every view (local hot-seat AND server); espionage reveals fuzzed intel.
- Modern UX deviations (event feed, in-turn undo, named save slots, accessibility, online turn timers) are specified in PROJECT_REQUIREMENTS.md.
- Interactive tutorial (`client/lib/tutorial/`): a real fixed-seed game with a scripted overlay, completes within the first turn, never saved. **Whenever gameplay rules, prices, menu names or UI flows change, update `tutorial_steps.dart` in the same change.**
- Bilingual UI (de/en, since 2026-07-20): **never hardcode user-visible strings.** Client text goes through `tr('<area>.<key>')` (`client/lib/l10n/strings.dart` + `parts/*_strings.dart`, `{param}` placeholders); building/troop/realm display names through `l10n/labels.dart` (`realmName(slot)`, not `gc.countryNames[slot]`). Engine-produced messages (ActionException, reason strings) use `coreMessage(key)` from `game_core`'s de/en catalog (`src/l10n/messages.dart`); strings stored in game state (unit/person/town names) stay language-neutral. Language: Options sub-menu, default = device language.

## Files
- `ORIGINAL_GAME.md` — traced spec of the original; source of truth for all rules (§-references).
- `ARCHITECTURE.md` — architecture + V2 online design · `PROJECT_REQUIREMENTS.md` — V1 requirements + deviations.
- `CHECKLIST.md` — progress tracker · `docs/HISTORY.md` — dated decision/fix log (lookups).
- `README.md` — run/test/build/deploy. **Update it in the same change whenever those steps change.**
