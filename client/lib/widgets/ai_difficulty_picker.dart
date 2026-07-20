import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' show AiDifficulty;

import '../l10n/strings.dart';

/// Shared "Stärke der KI-Gegner" picker for the local and online setup
/// screens — ONE place for the level labels and descriptions
/// (and the only spot to touch when a level is added: the segments iterate
/// the enum). Scales down on narrow layouts instead of overflowing (same
/// pattern as the other pickers).
class AiDifficultyPicker extends StatelessWidget {
  const AiDifficultyPicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final AiDifficulty value;
  final ValueChanged<AiDifficulty> onChanged;

  static String labelFor(AiDifficulty difficulty) => switch (difficulty) {
    AiDifficulty.leicht => tr('setup.aiEasy'),
    AiDifficulty.mittel => tr('setup.aiMedium'),
    AiDifficulty.schwer => tr('setup.aiHard'),
  };

  static String descriptionFor(AiDifficulty difficulty) => switch (difficulty) {
    AiDifficulty.leicht => tr('setup.aiEasyDesc'),
    AiDifficulty.mittel => tr('setup.aiMediumDesc'),
    AiDifficulty.schwer => tr('setup.aiHardDesc'),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Flexible(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: SegmentedButton<AiDifficulty>(
                  segments: [
                    for (final difficulty in AiDifficulty.values)
                      ButtonSegment(
                        value: difficulty,
                        label: Text(labelFor(difficulty)),
                      ),
                  ],
                  selected: {value},
                  onSelectionChanged: (s) => onChanged(s.first),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            descriptionFor(value),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
