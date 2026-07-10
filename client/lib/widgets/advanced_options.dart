import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' show AiDifficulty, minEventYear;

import 'ai_difficulty_picker.dart';

/// Validates the three event-year fields of [AdvancedOptionsCard]; returns
/// the German error message or null. Shared by the local and the online
/// setup so both screens accept exactly the same years.
String? validateEventYears({
  required String reformation,
  required String ottoman,
  required String warStart,
}) {
  final reformationYear = int.tryParse(reformation);
  if (reformationYear == null || reformationYear < minEventYear) {
    return 'Das ist zu früh !!! (Reformation ≥ $minEventYear)';
  }
  final ottomanYear = int.tryParse(ottoman);
  if (ottomanYear == null || ottomanYear < minEventYear) {
    return 'Das ist zu früh !!! (Osmanen ≥ $minEventYear)';
  }
  final warStartYear = int.tryParse(warStart);
  if (warStartYear == null || warStartYear < 1000) {
    return 'Das ist zu früh !!! (Krieg ab ≥ 1000)';
  }
  return null;
}

/// Collapsed "Erweiterte Optionen" card shared by the local new-game screen
/// and the online create-match screen — ONE place for the option labels and
/// explanations so both setups look and read the same. Online-only rows
/// (e.g. the war round timer) slot in via [extras].
class AdvancedOptionsCard extends StatelessWidget {
  const AdvancedOptionsCard({
    super.key,
    required this.reformation,
    required this.ottoman,
    required this.warStart,
    required this.aiDifficulty,
    required this.onAiDifficultyChanged,
    required this.genderEqualSuccession,
    required this.onGenderEqualSuccessionChanged,
    required this.suggestChildNames,
    required this.onSuggestChildNamesChanged,
    this.extras = const [],
  });

  final TextEditingController reformation;
  final TextEditingController ottoman;
  final TextEditingController warStart;
  final AiDifficulty aiDifficulty;
  final ValueChanged<AiDifficulty> onAiDifficultyChanged;
  final bool genderEqualSuccession;
  final ValueChanged<bool> onGenderEqualSuccessionChanged;
  final bool suggestChildNames;
  final ValueChanged<bool> onSuggestChildNamesChanged;

  /// Extra option rows shown above the common ones (online: war round timer).
  final List<Widget> extras;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // The card already frames the section — no open/closed borders
        // (narrower than overriding dividerColor for all descendants).
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.tune),
        title: const Text('Erweiterte Optionen'),
        subtitle: const Text('Ereignis-Jahre, KI-Stärke, Regeln'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          ...extras,
          AiDifficultyPicker(
            label: 'Stärke der KI-Gegner',
            value: aiDifficulty,
            onChanged: onAiDifficultyChanged,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: reformation,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Jahr der Reformation',
                    helperText: 'Original: 1020',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: ottoman,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Osmanen-Invasion',
                    helperText: 'Original: 1040',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: warStart,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Krieg möglich ab Jahr',
              helperText: 'Original: 1010',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: genderEqualSuccession,
            onChanged: onGenderEqualSuccessionChanged,
            title: const Text('Frauen können überall herrschen'),
            subtitle: const Text(
              'Abweichend vom Original: das älteste Kind erbt '
              'unabhängig vom Geschlecht und Frauen können auch '
              'islamische Reiche erben, ohne auszuscheiden.',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: suggestChildNames,
            onChanged: onSuggestChildNamesChanged,
            title: const Text('Namensvorschläge für Kinder'),
            subtitle: const Text(
              'Bei Geburten einen zufälligen Namen vorschlagen — '
              'ausgeschaltet bleibt das Namensfeld leer.',
            ),
          ),
        ],
      ),
    );
  }
}
