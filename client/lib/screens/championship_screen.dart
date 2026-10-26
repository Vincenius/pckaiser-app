import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../l10n/strings.dart' show formatTimestamp, tr;
import '../services/api_client.dart';
import '../services/online_service.dart';
import '../widgets/championship_banner.dart';
import '../widgets/connection_error.dart';

/// `[DESIGNED 2026-10-26, user request]` Hall of fame of the yearly
/// "PCKaiser-Weltmeisterschaft": every finished championship, newest first,
/// with the full ranking of all its players — gold, silver and bronze
/// trophies for the top three. Reached from the trophy button on the home
/// screen. The banner of an open sign-up sits on top.
class ChampionshipScreen extends StatefulWidget {
  const ChampionshipScreen({super.key});

  @override
  State<ChampionshipScreen> createState() => _ChampionshipScreenState();
}

class _ChampionshipScreenState extends State<ChampionshipScreen> {
  List<Map<String, dynamic>>? _results;
  ApiError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final online = await OnlineService.load();
    List<Map<String, dynamic>>? results;
    ApiError? error;
    if (online.serverUrl != null) {
      try {
        results = [
          for (final r in await online.api.championshipResults(
            playerId: online.playerId,
          ))
            (r as Map).cast<String, dynamic>(),
        ];
      } on ApiError catch (e) {
        error = e;
      }
    }
    if (!mounted) return;
    setState(() {
      _results = results;
      _error = error;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results;
    return Scaffold(
      appBar: AppBar(title: Text(tr('championship.hallOfFame'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const ChampionshipBanner(),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              ConnectionErrorTile(error: _error!, onRetry: _load)
            else if (results == null || results.isEmpty)
              _empty(theme)
            else
              for (final r in results) _yearCard(theme, r),
          ],
        ),
      ),
    );
  }

  Widget _empty(ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
    child: Column(
      children: [
        Icon(
          Icons.emoji_events_outlined,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          tr('championship.noResults'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          tr('championship.noResultsHint'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _yearCard(ThemeData theme, Map<String, dynamic> result) {
    final ranking = [
      for (final s in result['ranking'] as List? ?? const [])
        (s as Map).cast<String, dynamic>(),
    ];
    final finishedAt = result['finished_at'] as String?;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                tr('championship.titleYear', {'year': result['year']}),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: finishedAt == null
                  ? null
                  : Text(
                      tr('championship.finishedOn', {
                        'time': formatTimestamp(finishedAt),
                      }),
                    ),
            ),
            const Divider(height: 1),
            for (final s in ranking) _standingTile(theme, s),
          ],
        ),
      ),
    );
  }

  Widget _standingTile(ThemeData theme, Map<String, dynamic> s) {
    final rank = s['rank'] as int? ?? 0;
    final isYou = s['you'] == true;
    final year = s['year'];
    final status = switch (s['reason']) {
      'winner' => tr('championship.reasonWinner'),
      'survived' => tr('championship.reasonSurvived'),
      'left' => tr('championship.reasonLeft', {'year': year}),
      'kicked' => tr('championship.reasonKicked', {'year': year}),
      _ => tr('championship.reasonEliminated', {'year': year}),
    };
    final medal = rank >= 1 && rank <= 3 ? medalColors[rank - 1] : null;
    return ListTile(
      dense: medal == null,
      leading: medal != null
          ? CircleAvatar(
              backgroundColor: medal.withValues(alpha: 0.18),
              child: Icon(Icons.emoji_events, color: medal),
            )
          : CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Text(
                '$rank',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
      title: Text(
        '${medal != null ? '$rank. ' : ''}${s['name']}'
        '${isYou ? tr('online.youSuffix') : ''}',
        style: TextStyle(
          fontWeight: medal != null || isYou ? FontWeight.bold : null,
          color: isYou ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: Text('${realmName(s['slot'] as int? ?? 1)} · $status'),
    );
  }
}
