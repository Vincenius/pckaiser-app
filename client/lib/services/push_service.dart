import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Client side of ARCHITECTURE.md "FCM": permission prompt, device token
/// and notification taps. Push is strictly optional — on platforms
/// without FCM (desktop dev builds) or when the Firebase config files
/// are missing (README "Push notifications"), [init] yields no service
/// and the game simply runs without push.
class PushService {
  PushService._();

  static PushService? _instance;

  /// Null when push is unavailable on this device/build.
  static PushService? get instance => _instance;

  static Future<PushService?> init() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
    try {
      // Reads the native config (google-services.json /
      // GoogleService-Info.plist); throws when it is missing.
      await Firebase.initializeApp();
    } on Object catch (e) {
      debugPrint('[push] Firebase unavailable: $e');
      return null;
    }
    return _instance = PushService._();
  }

  StreamSubscription<String>? _refreshSub;

  /// Asks the player for notification permission via the system dialog
  /// (iOS and Android 13+; an already answered prompt is not shown
  /// again). Returns whether notifications may be shown.
  Future<bool> requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } on Object catch (e) {
      debugPrint('[push] permission request failed: $e');
      return false;
    }
  }

  Future<String?> token() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } on Object catch (e) {
      debugPrint('[push] no token: $e');
      return null;
    }
  }

  /// FCM rotates tokens occasionally; [handler] re-uploads the fresh one
  /// (PATCH /players/:id). Replaces any previous handler.
  void onTokenRefresh(void Function(String token) handler) {
    _refreshSub?.cancel();
    _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      handler,
      onError: (Object e) => debugPrint('[push] token refresh failed: $e'),
    );
  }

  /// Calls [handler] with the match id whenever the player enters the
  /// app by tapping a push notification — both from a cold start
  /// (initial message) and from the background. The server puts
  /// `match_id` into every message's data payload.
  Future<void> onMatchOpened(void Function(String matchId) handler) async {
    void emit(RemoteMessage? message) {
      final matchId = message?.data['match_id'];
      if (matchId is String && matchId.isNotEmpty) handler(matchId);
    }

    FirebaseMessaging.onMessageOpenedApp.listen(emit);
    emit(await FirebaseMessaging.instance.getInitialMessage());
  }
}
