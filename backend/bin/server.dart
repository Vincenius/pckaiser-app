/// Server entry point. Env:
///   PORT                      — listen port (default 3000)
///   STORE_DIR                 — file-store data directory (default ./data)
///   FIREBASE_SERVICE_ACCOUNT  — base64 service-account JSON; enables FCM
///                               push (logged stub without it)
///
/// The timeout sweep runs once a minute (ARCHITECTURE.md "Timeouts");
/// the retention sweep once a day and at startup (ARCHITECTURE.md
/// "Retention").
library;

import 'dart:async';
import 'dart:io';

import 'package:backend/backend.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;
  final storeDir = Platform.environment['STORE_DIR'] ?? 'data';

  final store = FileStore(storeDir);
  final push =
      FcmPushService.fromEnv(Platform.environment['FIREBASE_SERVICE_ACCOUNT']);
  if (push != null) print('FCM push enabled');
  final service = MatchService(store, push ?? LogPushService());
  final api = Api(service);

  Timer.periodic(const Duration(minutes: 1), (_) async {
    try {
      final swept = await service.sweepExpired();
      if (swept > 0) print('[sweep] auto-resolved $swept expired match(es)');
    } on Object catch (e) {
      print('[sweep] failed: $e');
    }
    // Matchmaking rooms: start the ones past their fallback deadline and
    // keep exactly one open room per template (match_templates.dart).
    try {
      final started = await service.sweepTemplates();
      if (started > 0) print('[rooms] auto-started $started room(s)');
    } on Object catch (e) {
      print('[rooms] failed: $e');
    }
  });

  Future<void> retention() async {
    try {
      final removed = await service.sweepStale();
      if (removed > 0) print('[retention] deleted $removed stale match(es)');
    } on Object catch (e) {
      print('[retention] failed: $e');
    }
  }

  unawaited(retention());
  Timer.periodic(const Duration(hours: 24), (_) => retention());

  // Open the matchmaking rooms right away — the lobby must offer them from
  // the first request, not a minute after the server came up.
  unawaited(service.ensureTemplateMatches().catchError(
      (Object e) => print('[rooms] initial setup failed: $e')));

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(api.handler);
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('PCKaiser server listening on :${server.port} (store: $storeDir)');
}
