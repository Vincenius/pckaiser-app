import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/online_service.dart';
import '../services/push_kinds.dart';
import '../services/settings_service.dart';

/// Options sub-menu (reached from the main menu): the UI language and the
/// optional online notifications. 'Device language' is the default —
/// German devices get German, everything else English
/// (PROJECT_REQUIREMENTS "Language").
///
/// `[DESIGNED 2026-08-24, user request]` The notification switches cover
/// the courtesy pushes around a war appointment ([optionalPushKinds]); all
/// are on by default. Turning one off really stops it: the choice is
/// stored locally AND uploaded to the player's server record, which is
/// what the sending side checks.
class OptionsScreen extends StatefulWidget {
  const OptionsScreen({super.key});

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  OnlineService? _online;

  @override
  void initState() {
    super.initState();
    // Only needed to upload a changed switch — the screen renders from the
    // local settings and stays usable while this is still loading.
    OnlineService.load().then((service) {
      if (mounted) setState(() => _online = service);
    });
  }

  Future<void> _setPush(String kind, bool enabled) async {
    await SettingsService.instance?.setPushEnabled(kind, enabled);
    if (mounted) setState(() {});
    final online = _online;
    if (online == null || !online.isConfigured) return;
    // The server is the one that decides what to send, so a failed upload
    // means the switch has not taken effect yet — say so instead of
    // leaving a switch that quietly lies. The next launch retries.
    if (!await online.syncPushPrefs() && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('notifySyncFailed'))));
    }
  }

  Future<void> _setLanguage(String choice) async {
    await SettingsService.instance?.setLanguageChoice(choice);
    // The app rebuilds via appLocale; setState refreshes the check marks
    // even when the resolved locale did not change.
    if (mounted) setState(() {});
  }

  Widget _languageTile(
    ThemeData theme, {
    required String value,
    required String title,
    String? subtitle,
    required String selectedChoice,
  }) {
    final selected = selectedChoice == value;
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: selected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      selected: selected,
      onTap: () => _setLanguage(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choice = SettingsService.instance?.languageChoice ?? 'system';
    return Scaffold(
      appBar: AppBar(title: Text(tr('options'))),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              tr('language'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          _languageTile(
            theme,
            value: 'system',
            title: tr('languageSystem'),
            subtitle: tr('languageSystemHint'),
            selectedChoice: choice,
          ),
          _languageTile(
            theme,
            value: 'de',
            title: tr('languageGerman'),
            selectedChoice: choice,
          ),
          _languageTile(
            theme,
            value: 'en',
            title: tr('languageEnglish'),
            selectedChoice: choice,
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              tr('notifications'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              tr('notificationsHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final kind in optionalPushKinds)
            SwitchListTile(
              title: Text(tr(pushKindTitleKey(kind))),
              subtitle: Text(tr(pushKindSubtitleKey(kind))),
              value: SettingsService.instance?.pushEnabled(kind) ?? true,
              onChanged: (on) => _setPush(kind, on),
            ),
        ],
      ),
    );
  }
}
