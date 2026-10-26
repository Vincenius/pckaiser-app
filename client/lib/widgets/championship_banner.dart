import 'package:flutter/material.dart';

import '../l10n/strings.dart' show formatTimestamp, tr;
import '../screens/online_match_screen.dart';
import '../screens/online_screen.dart';
import '../screens/online_setup_screen.dart';
import '../services/api_client.dart';
import '../services/championship_topic.dart';
import '../services/online_service.dart';
import '../services/push_service.dart';
import '../services/settings_service.dart';
import 'room_card.dart' show roomSummary;

/// Medal colors of the hall of fame (gold, silver, bronze).
const List<Color> medalColors = [
  Color(0xFFFFC83D),
  Color(0xFFC9D1D9),
  Color(0xFFD08A4E),
];

/// `[DESIGNED 2026-10-26, user request]` The yearly "PCKaiser-
/// Weltmeisterschaft" while its sign-up is open (server
/// `GET /championship`): one 16-seat online match that starts on a fixed
/// date. Shown on the home screen and in the online lobby — ONLY during the
/// sign-up (no running/finished states; results live in the hall of fame).
/// Renders nothing outside the window, without a server, or when the
/// request fails: an announcement never shows an error.
class ChampionshipBanner extends StatefulWidget {
  const ChampionshipBanner({super.key, this.onJoined});

  /// After the player signed up — lets the host screen refresh its lists.
  final VoidCallback? onJoined;

  @override
  State<ChampionshipBanner> createState() => ChampionshipBannerState();
}

class ChampionshipBannerState extends State<ChampionshipBanner> {
  OnlineService? _online;
  Map<String, dynamic>? _info;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Re-fetches the sign-up state (the host screen calls this whenever it
  /// reloads itself, e.g. after returning from a match).
  Future<void> reload() async {
    final online = await OnlineService.load();
    Map<String, dynamic>? info;
    if (online.serverUrl != null) {
      try {
        info = await online.api.championship(playerId: online.playerId);
      } on Object {
        info = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _online = online;
      _info = info;
    });
  }

  Future<void> _openMatch(OnlineService online, String matchId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnlineMatchScreen(service: online, matchId: matchId),
      ),
    );
    await reload();
  }

  Future<void> _join() async {
    final matchId = _info?['match_id'] as String?;
    if (_online == null || matchId == null) return;
    var online = _online!;
    if (!online.isConfigured) {
      // No online profile yet: the lobby asks for the player name first.
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const OnlineScreen()));
      final reloaded = online = await OnlineService.load();
      if (!mounted) return;
      if (!reloaded.isConfigured) {
        setState(() => _online = reloaded);
        return;
      }
    }
    final result = await Navigator.of(context).push<OnlineSetupResult>(
      MaterialPageRoute(
        builder: (_) => OnlineSetupScreen(
          mode: OnlineSetupMode.joinPublic,
          displayName: online.displayName,
          api: online.api,
          matchId: matchId,
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await online.api.joinMatch(
        matchId: matchId,
        playerId: online.playerId!,
        setup: result.setup.setupJson(),
      );
    } on ApiError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      await reload();
      return;
    }
    widget.onJoined?.call();
    if (!mounted) return;
    await _openMatch(online, matchId);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final online = _online;
    if (info == null || online == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final joined = info['joined'] as int? ?? 0;
    final seats = info['seats'] as int? ?? 16;
    final joinedByMe = info['joined_by_me'] == true;
    final full = joined >= seats;
    final settings =
        (info['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      color: medalColors[0].withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: medalColors[0], width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events, color: medalColors[0]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('championship.titleYear', {'year': info['year']}),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  tr('online.seatsOf', {'n': joined, 'max': seats}),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(tr('championship.pitch'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text(
              tr('championship.startsAt', {
                'time': formatTimestamp(info['starts_at'] as String),
              }),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(roomSummary(settings), style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: joinedByMe
                  ? FilledButton.tonalIcon(
                      onPressed: () =>
                          _openMatch(online, info['match_id'] as String),
                      icon: const Icon(Icons.check),
                      label: Text(tr('championship.signedUp')),
                    )
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: medalColors[0],
                        foregroundColor: Colors.black,
                      ),
                      onPressed: full ? null : _join,
                      icon: const Icon(Icons.how_to_reg),
                      label: Text(
                        full ? tr('championship.full') : tr('championship.signUp'),
                      ),
                    ),
            ),
            if (!full && !joinedByMe)
              Text(
                tr('championship.seatsLeft', {'n': seats - joined}),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The one-time "notify me about the Weltmeisterschaft?" question — asked
/// once per install, only where push exists. The announcement is
/// promotional, so the topic is subscribed only after an explicit yes; the
/// answer stays switchable under Options ▸ Notifications.
Future<void> maybeAskChampionshipConsent(BuildContext context) async {
  final settings = SettingsService.instance;
  final push = PushService.instance;
  if (settings == null || push == null) return;
  if (settings.championshipPromptAnswered) return;
  final yes = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.emoji_events, color: medalColors[0], size: 36),
      title: Text(tr('championship.consentTitle')),
      content: Text(tr('championship.consentBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('championship.consentNo')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr('championship.consentYes')),
        ),
      ],
    ),
  );
  await settings.answerChampionshipPrompt(enabled: yes == true);
  // The system permission dialog only after the player said yes here.
  if (yes == true) await push.requestPermission();
  await syncChampionshipTopic();
  // Mirror the switch onto the player record, like the options screen.
  final online = await OnlineService.load();
  await online.syncPushPrefs();
}
