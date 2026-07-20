import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/settings_service.dart';

/// Options sub-menu (reached from the main menu): currently the UI
/// language. 'Device language' is the default — German devices get
/// German, everything else English (PROJECT_REQUIREMENTS "Language").
class OptionsScreen extends StatefulWidget {
  const OptionsScreen({super.key});

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
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
        ],
      ),
    );
  }
}
