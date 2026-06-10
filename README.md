# PC Kaiser

A mobile-first remake of the 1992 German strategy classic *PC Kaiser*
(Martin Gelter) for Android and iOS — Flutter + Flame. Rule one of 30
medieval realms: build, trade, marry, scheme, elect a Kaiser and conquer,
until one dynasty rules the whole map. 1–16 human players hot-seat on one
device; the AI plays the rest.

V1 is fully local/offline. The rules engine is a pure Dart package shared
verbatim with the planned async-multiplayer backend (V2).

## Repository layout

| Path | What it is |
|---|---|
| `client/` | Flutter app (UI, Flame map, save slots) |
| `packages/game_core/` | Pure Dart rules engine — all game logic, no Flutter deps |
| `packages/game_core/tool/sim_report.dart` | Headless 200-year simulation report (dev tool) |
| `imgs/` | Original tile graphics (38 indices, see §24 of the spec) |
| `store/` | Store-listing metadata (EN/DE) |
| `ORIGINAL_GAME.md` | The traced spec of the original game — source of truth for all rules |
| `ARCHITECTURE.md` | System architecture incl. the V2 online design |
| `PROJECT_REQUIREMENTS.md` | Product requirements for V1 |
| `CHECKLIST.md` | Phase-by-phase progress tracker and decision log |

## Prerequisites

- **Flutter ≥ 3.44 (stable)** — includes the Dart SDK.
  Install: <https://docs.flutter.dev/get-started/install>, then make sure
  `flutter/bin` is on your `PATH` (`flutter doctor` to verify).
- For Android builds: Android SDK + platform tools (easiest via Android
  Studio; `flutter doctor` walks you through it).
- For iOS builds: a Mac with Xcode; standard Flutter iOS setup.

No other services are needed — the game is fully offline.

## Run locally

```bash
# 1. Fetch dependencies (game_core is wired in via a path dependency)
cd client
flutter pub get

# 2. List connected devices / emulators
flutter devices

# 3. Run (debug)
flutter run                      # picks the default device
flutter run -d <device-id>       # or pick one explicitly
```

Useful during development:

```bash
flutter run --profile            # realistic performance (60 fps target)
dart run tool/sim_report.dart    # in packages/game_core: headless 200-year sim
```

## Tests & analysis

Run this before every push — keep it green (no CI for the app yet;
Jenkins will be used for the backend later):

```bash
# Rules engine
cd packages/game_core
dart pub get
dart analyze --fatal-infos
dart test                        # includes the 200-year full-AI smoke test

# App
cd client
flutter pub get
flutter analyze
flutter test
```

## Build the APK / App Bundle

### Debug-signed build (for quick installs on a test device)

```bash
cd client
flutter build apk                # output: build/app/outputs/flutter-apk/app-release.apk
```

Without a release keystore this falls back to **debug signing** — fine for
sideloading on test devices, not accepted by the Play Store.

### Release-signed build

1. Create a keystore once (keep it safe — losing it means losing the
   ability to update the app):

   ```bash
   keytool -genkey -v -keystore ~/pckaiser-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias pckaiser
   ```

2. Create `client/android/key.properties` (git-ignored, never commit):

   ```properties
   storeFile=/home/you/pckaiser-release.jks
   storePassword=...
   keyAlias=pckaiser
   keyPassword=...
   ```

3. Build:

   ```bash
   cd client
   flutter build apk --release          # APK for direct distribution
   flutter build appbundle --release    # AAB for the Play Store
   ```

   Outputs land in `client/build/app/outputs/`.

### iOS

```bash
cd client
flutter build ipa --release
```

Requires a Mac with Xcode and an Apple Developer account; then upload via
Xcode/Transporter to TestFlight.

## Deploy / release flow

1. Bump `version:` in `client/pubspec.yaml` (e.g. `0.2.0+2` — the `+N`
   build number must increase for every store upload).
2. Run the full test suites (see above).
3. `flutter build appbundle --release` with the release keystore.
4. Upload to **Play Console → Internal testing** (beta round), promote to
   production after the round. Store texts live in `store/metadata.md`;
   screenshots still need to be taken on a device.
5. iOS: `flutter build ipa --release` → TestFlight.

App icons are generated from the original castle tile; regenerate after
changing `client/assets/icon/*` with:

```bash
cd client && dart run flutter_launcher_icons
```

The V2 online backend (Dart shelf + PostgreSQL, Docker + Nginx) is designed
in `ARCHITECTURE.md` but not implemented yet; this section will grow when
it lands.

## Status

Phases 0–6 of `CHECKLIST.md` are implemented and tested (121 tests):
complete rules engine (economy, dynasty, elections, war, espionage, world
events, AI) plus the playable Flutter client. Phase 7 (device validation,
beta) is in progress — the app has not yet had its first on-device visual
pass. Known open items are tracked at the end of `CHECKLIST.md`.

> Maintenance note: this README is part of the definition of done — update
> it with every change to setup, build, test or deploy steps (see
> `CLAUDE.md`).
