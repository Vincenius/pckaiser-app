import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' show MapSize;

import '../l10n/strings.dart';

/// Shared "Kartengröße" picker (size segments + realm-count slider) for the
/// local and online setup screens — ONE place for the size labels and the
/// per-size realm ranges. Picking a size resets the realm count to that
/// size's default (the caller receives both callbacks).
class MapSizePicker extends StatelessWidget {
  const MapSizePicker({
    super.key,
    required this.mapSize,
    required this.onMapSizeChanged,
    required this.realmCount,
    required this.onRealmCountChanged,
  });

  final MapSize mapSize;

  /// Called with the new size; the caller is expected to also reset its
  /// realm count to `size.defaultRealmCount`.
  final ValueChanged<MapSize> onMapSizeChanged;
  final int realmCount;
  final ValueChanged<int> onRealmCountChanged;

  static String labelFor(MapSize size) => switch (size) {
    MapSize.klein => tr('setup.mapSizeSmall'),
    MapSize.mittel => tr('setup.mapSizeMedium'),
    MapSize.gross => tr('setup.mapSizeLarge'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(tr('setup.mapSizeLabel'))),
            Flexible(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: SegmentedButton<MapSize>(
                  segments: [
                    // Large-to-small so the default (Groß) sits first.
                    for (final size in MapSize.values.reversed)
                      ButtonSegment(value: size, label: Text(labelFor(size))),
                  ],
                  selected: {mapSize},
                  onSelectionChanged: (s) => onMapSizeChanged(s.first),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            tr('setup.mapSizeHint', {
              'width': mapSize.width,
              'height': mapSize.height,
            }),
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(tr('setup.realmCountLabel', {'count': realmCount})),
        Slider(
          value: realmCount.toDouble(),
          min: mapSize.minRealmCount.toDouble(),
          max: mapSize.maxRealmCount.toDouble(),
          divisions: mapSize.maxRealmCount - mapSize.minRealmCount,
          label: '$realmCount',
          onChanged: (v) => onRealmCountChanged(v.round()),
        ),
        Text(
          tr('setup.realmCountHint', {
            'min': mapSize.minRealmCount,
            'max': mapSize.maxRealmCount,
          }),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
