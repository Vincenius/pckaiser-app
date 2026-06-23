import 'package:game_core/game_core.dart' as gc;

/// App version shown on the About screen and sent to the server with every
/// online turn (the match rejects a seat on a different build until it
/// updates). The canonical value lives in `game_core` so the client and
/// server always compare the same string.
///
/// KEEP IN SYNC with `version:` in `pubspec.yaml` — guarded by
/// `test/app_version_test.dart`.
const String appVersion = gc.appVersion;
