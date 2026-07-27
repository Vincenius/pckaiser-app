import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' show World, cityNames;

import '../game/realm_palette.dart';
import '../l10n/labels.dart';
import '../l10n/strings.dart';

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
    required this.color,
    required this.onColorChanged,
    this.maxSlot = World.realmCount,
    this.takenSlots = const {},
    this.takenColors = const {},
    this.randomDorfHint,
    this.header,
  });

  final TextEditingController name;
  final String nameLabel;
  final int nameMaxLength;
  final TextEditingController dorf;
  final int gender;
  final ValueChanged<int> onGenderChanged;

  /// Realm slot 1–[maxSlot], or null = "Zufällig".
  final int? countrySlot;
  final ValueChanged<int?> onCountryChanged;

  /// Chosen map color (ARGB from [RealmPalette.setupChoices]), or null =
  /// the slot-derived default ("Automatisch").
  final int? color;
  final ValueChanged<int?> onColorChanged;

  /// Colors (ARGB) already claimed by other players — greyed out and
  /// unselectable so two realms never share a map color.
  final Set<int> takenColors;

  /// Highest selectable realm slot — the game's realm count (local setup:
  /// the configured value; online joiners see the full 1–30 list, the
  /// server validates against the match settings).
  final int maxSlot;

  /// Realm slots already claimed by other players (online join) — shown
  /// greyed out and unselectable. Empty for local setup and hosting.
  final Set<int> takenSlots;

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
                    segments: [
                      ButtonSegment(value: 0, label: Text(tr('game.male'))),
                      ButtonSegment(value: 1, label: Text(tr('game.female'))),
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
                    // The FormField owns its selection state; the key
                    // rebuilds it whenever the parent-managed value or the
                    // slot range changes (map-size shrink resets picks
                    // beyond the new realm count — without the key the
                    // stale internal value would not even be in `items`).
                    key: ValueKey('land-$countrySlot-$maxSlot'),
                    initialValue: countrySlot,
                    decoration: InputDecoration(
                      labelText: tr('game.landLabel'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(tr('game.random')),
                      ),
                      for (var slot = 1; slot <= maxSlot; slot++)
                        if (takenSlots.contains(slot))
                          // Already claimed by another player — greyed and
                          // unselectable (the server still validates on join).
                          DropdownMenuItem(
                            value: slot,
                            enabled: false,
                            child: Text(
                              tr('game.landTaken', {'name': realmName(slot)}),
                              style: TextStyle(
                                color: Theme.of(context).disabledColor,
                              ),
                            ),
                          )
                        else
                          DropdownMenuItem(
                            value: slot,
                            child: Text(realmName(slot)),
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
                      labelText: tr('game.firstVillage'),
                      helperText: countrySlot == null ? randomDorfHint : null,
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                tr('game.colorLabel'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _colorSwatch(context, null),
                  for (final choice in RealmPalette.setupChoices)
                    _colorSwatch(context, choice.toARGB32()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One tappable color dot; null = "Automatisch" (the slot-derived
  /// default). A color another player already claimed is greyed out.
  Widget _colorSwatch(BuildContext context, int? argb) {
    final theme = Theme.of(context);
    final selected = color == argb;
    final taken = argb != null && !selected && takenColors.contains(argb);
    final swatch = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: argb == null ? theme.colorScheme.surfaceContainerHigh : Color(argb),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? theme.colorScheme.onSurface : theme.dividerColor,
          width: selected ? 2.5 : 1,
        ),
      ),
      child: selected
          ? Icon(Icons.check,
              size: 18,
              color: argb == null ? theme.colorScheme.onSurface : Colors.white)
          : argb == null
              ? Icon(Icons.shuffle,
                  size: 16, color: theme.colorScheme.onSurfaceVariant)
              : null,
    );
    return Tooltip(
      message: argb == null ? tr('game.colorAuto') : '',
      child: taken
          ? Opacity(opacity: 0.25, child: swatch)
          : InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onColorChanged(argb),
              child: swatch,
            ),
    );
  }
}
