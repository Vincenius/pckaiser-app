import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/save_service.dart';
import 'credits_screen.dart';
import 'game_screen.dart';
import 'setup_screen.dart';

/// Landing screen: hero header, the two primary actions (new game and
/// interactive tutorial) and the named game slots — resume or delete
/// (PROJECT_REQUIREMENTS "Multiple named game slots").
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SaveService? _saves;
  List<SaveSlotInfo> _slots = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saves = await SaveService.open();
    final slots = await saves.listSlots();
    if (!mounted) return;
    setState(() {
      _saves = saves;
      _slots = slots;
    });
  }

  Future<void> _openGame(String slotName) async {
    final saves = _saves;
    if (saves == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen.resume(slotName: slotName, saves: saves),
    ));
    _load();
  }

  Future<void> _newGame() async {
    final saves = _saves;
    if (saves == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SetupScreen(saves: saves),
    ));
    _load();
  }

  /// Starts the tutorial game (ephemeral — never saved).
  Future<void> _tutorial() async {
    final saves = _saves;
    if (saves == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen.tutorial(saves: saves),
    ));
    _load();
  }

  Future<void> _deleteSlot(SaveSlotInfo slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('„${slot.name}" löschen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed == true) {
      await _saves!.delete(slot.name);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                // Language toggle (German default, English optional).
                onPressed: () =>
                    appLocale.value = appLocale.value == 'en' ? 'de' : 'en',
                child: Text(appLocale.value.toUpperCase(),
                    semanticsLabel: 'Sprache'),
              ),
            ),
            _header(theme),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _newGame,
              icon: const Icon(Icons.add),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr('newGame')),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _tutorial,
              icon: const Icon(Icons.school),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr('tutorial')),
              ),
            ),
            const SizedBox(height: 28),
            if (_saves == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_slots.isEmpty)
              _emptyState(theme)
            else ...[
              Text(tr('savedGames'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final slot in _slots) _slotCard(theme, slot),
            ],
            const SizedBox(height: 16),
            // Small credits link (original game by Martin Gelter, 1992).
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CreditsScreen())),
                child: Text(
                  tr('credits'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Column(children: [
      const SizedBox(height: 16),
      CircleAvatar(
        radius: 40,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(Icons.castle,
            size: 44, color: theme.colorScheme.onPrimaryContainer),
      ),
      const SizedBox(height: 14),
      Text(
        tr('appTitle'),
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium
            ?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        tr('tagline'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    ]);
  }

  Widget _emptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Icon(Icons.history_edu,
            size: 40, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 8),
        Text(tr('noSaves'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          tr('noSavesHint'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }

  Widget _slotCard(ThemeData theme, SaveSlotInfo slot) {
    // Save written by a newer app version: keep it listed (and deletable)
    // but refuse to open it — loading would fail or corrupt the game.
    final needsUpdate = !slot.isSupported;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(needsUpdate ? Icons.system_update : Icons.castle,
              size: 22, color: theme.colorScheme.onSurfaceVariant),
        ),
        title: Text(slot.name),
        subtitle: Text(needsUpdate
            ? tr('saveNeedsUpdate')
            : 'Anno ${slot.year} · ${slot.humanCount} Spieler · '
                '${slot.savedAt.toLocal().toString().substring(0, 16)}'),
        onTap: needsUpdate
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr('saveNeedsUpdate'))))
            : () => _openGame(slot.name),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Löschen',
          onPressed: () => _deleteSlot(slot),
        ),
      ),
    );
  }
}
