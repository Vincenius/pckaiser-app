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
    required this.onExit,
  });

  final GameController controller;

  /// Called when the tutorial is finished or dismissed — the game simply
  /// continues without the overlay.
  final VoidCallback onExit;

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
        title: const Text('Tutorial beenden?'),
        content: const Text('Du kannst danach normal weiterspielen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Beenden')),
        ],
      ),
    );
    if (sure == true) widget.onExit();
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
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.school, size: 18),
              const SizedBox(width: 8),
              Text('Tutorial ${_index + 1}/${tutorialSteps.length}',
                  style: theme.textTheme.labelLarge),
              const SizedBox(width: 4),
              const Icon(Icons.expand_less, size: 18),
            ]),
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
              Row(children: [
                const Icon(Icons.school, size: 18),
                const SizedBox(width: 8),
                Text(
                    'Tutorial — Schritt ${_index + 1} von '
                    '${tutorialSteps.length}',
                    style: theme.textTheme.labelMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.expand_more, size: 20),
                  tooltip: 'Minimieren',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _minimized = true),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Tutorial beenden',
                  visualDensity: VisualDensity.compact,
                  onPressed: _confirmExit,
                ),
              ]),
              Text(_step.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(_step.body, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              if (_step.task != null)
                Row(children: [
                  Icon(Icons.touch_app,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _step.task!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                  TextButton(
                    onPressed: _advance,
                    child: const Text('Überspringen'),
                  ),
                ])
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _isLast ? widget.onExit : _advance,
                    child: Text(
                        _isLast ? 'Tutorial abschließen' : 'Weiter'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
