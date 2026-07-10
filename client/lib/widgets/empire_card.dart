import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' show World, cityNames, countryNames;

/// One player's empire choices — founder name, gender, Land (including
/// "Zufällig") and first Dorf. Shared by the local setup's player cards and
/// the online setup's "Dein Reich" section so the two screens cannot drift.
///
/// The Dorf pre-fill is deliberately conservative: picking a Land only
/// overwrites the field while it holds a previous auto-fill (empty or a
/// historical village name), and switching to "Zufällig" only clears such
/// an auto-fill — a name the player typed is never silently discarded.
class EmpireCard extends StatelessWidget {
  const EmpireCard({
    super.key,
    required this.name,
    required this.nameLabel,
    required this.nameMaxLength,
    required this.dorf,
    required this.gender,
    required this.onGenderChanged,
    required this.countrySlot,
    required this.onCountryChanged,
    this.randomDorfHint,
    this.header,
  });

  final TextEditingController name;
  final String nameLabel;
  final int nameMaxLength;
  final TextEditingController dorf;
  final int gender;
  final ValueChanged<int> onGenderChanged;

  /// Realm slot 1–30, or null = "Zufällig".
  final int? countrySlot;
  final ValueChanged<int?> onCountryChanged;

  /// Helper text under the Dorf field while "Zufällig" is selected (local
  /// setup: an empty Dorf falls back to the drawn realm's village; online
  /// the server requires a name, so no hint is shown).
  final String? randomDorfHint;

  /// Optional first row inside the card (local setup: "Spieler N" + remove).
  final Widget? header;

  /// True while [dorf] holds a value this card itself may overwrite: empty
  /// or one of the historical village names (i.e. a previous auto-fill).
  bool get _dorfIsAutoFill {
    final text = dorf.text.trim();
    return text.isEmpty || cityNames.contains(text);
  }

  void _countryChanged(int? slot) {
    if (_dorfIsAutoFill) {
      dorf.text = slot == null ? '' : cityNames[slot - 1];
    }
    onCountryChanged(slot);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ?header,
            TextField(
              controller: name,
              maxLength: nameMaxLength,
              decoration: InputDecoration(
                labelText: nameLabel,
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Männlich')),
                      ButtonSegment(value: 1, label: Text('Weiblich')),
                    ],
                    selected: {gender},
                    onSelectionChanged: (s) => onGenderChanged(s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: countrySlot,
                    decoration: const InputDecoration(labelText: 'Land'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Zufällig'),
                      ),
                      for (var slot = 1; slot <= World.realmCount; slot++)
                        DropdownMenuItem(
                          value: slot,
                          child: Text(countryNames[slot]),
                        ),
                    ],
                    onChanged: _countryChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: dorf,
                    maxLength: nameMaxLength,
                    decoration: InputDecoration(
                      labelText: 'Erstes Dorf',
                      helperText: countrySlot == null ? randomDorfHint : null,
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
