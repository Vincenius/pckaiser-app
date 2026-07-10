import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' show AiDifficulty;

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
    AiDifficulty.leicht => 'Leicht',
    AiDifficulty.mittel => 'Mittel',
    AiDifficulty.schwer => 'Schwer',
  };

  static String descriptionFor(AiDifficulty difficulty) => switch (difficulty) {
    AiDifficulty.leicht =>
      'Die KI wirtschaftet nachlässig, rüstet halbherzig '
          'und verübt keine Attentate.',
    AiDifficulty.mittel =>
      'Die KI spielt wie das Original — gelegentliche '
          'Kriege und seltene Attentate.',
    AiDifficulty.schwer =>
      'Die KI plant Wirtschaft und Militär, bildet '
          'Truppen aus und greift gezielt Schwächere an.',
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
