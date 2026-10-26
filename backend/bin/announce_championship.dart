/// One-off: tells players on app builds older than 0.3.0 that this year's
/// Weltmeisterschaft is open for sign-up and that they need to update the
/// app (ARCHITECTURE.md "Weltmeisterschaft"). Run by hand ONCE, after the
/// app update is live in the store and the server has opened the sign-up:
///
///   STORE_DIR=… FIREBASE_SERVICE_ACCOUNT=… dart run bin/announce_championship.dart
///
/// or, in the Docker deployment (compiled into the image, same env):
///
///   docker compose -f backend/deploy/docker-compose.yml exec server /announce_championship
///
/// Players on 0.3.0+ are skipped (they get the opt-in topic push instead),
/// so nobody is notified twice; a second run sends nothing. Same env as the
/// server (bin/server.dart); without FIREBASE_SERVICE_ACCOUNT it only logs.
library;

import 'dart:io';

import 'package:backend/backend.dart';

Future<void> main() async {
  final storeDir = Platform.environment['STORE_DIR'] ?? 'data';
  final push =
      FcmPushService.fromEnv(Platform.environment['FIREBASE_SERVICE_ACCOUNT']);
  if (push == null) print('FIREBASE_SERVICE_ACCOUNT not set — logging only');
  final service = MatchService(FileStore(storeDir), push ?? LogPushService());
  final sent = await service.announceChampionshipToOldBuilds();
  if (sent == null) {
    print('Nothing sent: no championship sign-up is open, or the notice '
        'already went out this year.');
    exit(1);
  }
  print('Sent the update notice to $sent player(s) on older builds.');
  // The FCM client keeps the process alive — leave explicitly.
  exit(0);
}
