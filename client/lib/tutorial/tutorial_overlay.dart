import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/game_controller.dart';
import 'tutorial_steps.dart';

/// Floating tutorial card over the map: shows the current step, advances
/// automatically when the step's completion check passes on the live game
/// state, and can be minimized to a chip or closed entirely.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.controller,
    required this.onFinish,
    required this.onQuit,
  });

  final GameController controller;

  /// Called when the last step is completed ("Tutorial abschließen") —
  /// leaves the practice game and returns to the main menu.
  final VoidCallback onFinish;

  /// Called when the tutorial is quit early ("Tutorial beenden") — leaves
  /// the practice game and returns to the main menu.
  final VoidCallback onQuit;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  int _index = 0;
  late TutorialBaseline _since = TutorialBaseline(widget.controller);
  bool _minimized = false;

  TutorialStep get _step => tutorialSteps[_index];
  bool get _isLast => _index == tutorialSteps.length - 1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    super.dispose();
  }

  /// Polls the active step's completion check on every game-state change.
  void _check() {
    final done = _step.isDone;
    if (done == null || !done(widget.controller, _since)) return;
    _advance();
  }

  void _advance() {
    if (_isLast) return;
    setState(() {
      _index++;
      _since = TutorialBaseline(widget.controller);
      _minimized = false; // a new step should be seen
    });
  }

  Future<void> _confirmExit() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('tut.quitTitle')),
        content: Text(tr('tut.quitBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('tut.quitConfirm')),
          ),
        ],
      ),
    );
    if (sure == true && mounted) widget.onQuit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_minimized) {
      return Card(
        margin: const EdgeInsets.all(12),
        color: theme.colorScheme.surfaceContainerHigh,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _minimized = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.school, size: 18),
                const SizedBox(width: 8),
                Text(
                  tr('tut.chip', {
                    'step': _index + 1,
                    'total': tutorialSteps.length,
                  }),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_less, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Card(
        margin: const EdgeInsets.all(12),
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.school, size: 18),
                  const SizedBox(width: 8),
                  // Flexible: on narrow screens / large text the title must
                  // ellipsize instead of pushing the buttons off the card.
                  Expanded(
                    child: Text(
                      tr('tut.header', {
                        'step': _index + 1,
                        'total': tutorialSteps.length,
                      }),
                      style: theme.textTheme.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.expand_more, size: 20),
                    tooltip: tr('tut.minimize'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _minimized = true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: tr('tut.quitTooltip'),
                    visualDensity: VisualDensity.compact,
                    onPressed: _confirmExit,
                  ),
                ],
              ),
              Text(_step.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(_step.body, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              if (_step.task != null)
                Row(
                  children: [
                    Icon(
                      Icons.touch_app,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _step.task!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _advance,
                      child: Text(tr('tut.skip')),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _isLast ? widget.onFinish : _advance,
                    child: Text(_isLast ? tr('tut.finish') : tr('tut.next')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
