import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/save_service.dart';
import 'game_screen.dart';
import 'setup_screen.dart';

/// Landing screen: multiple named game slots — resume, delete or start a
/// new game (PROJECT_REQUIREMENTS "Multiple named game slots").
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('appTitle')),
        actions: [
          // Language toggle (English default, German optional).
          TextButton(
            onPressed: () =>
                appLocale.value = appLocale.value == 'en' ? 'de' : 'en',
            child: Text(appLocale.value.toUpperCase(),
                semanticsLabel: 'Language'),
          ),
        ],
      ),
      body: _saves == null
          ? const Center(child: CircularProgressIndicator())
          : _slots.isEmpty
              ? Center(
                  child: Text(tr('newGame'),
                      style: Theme.of(context).textTheme.titleMedium))
              : ListView.builder(
                  itemCount: _slots.length,
                  itemBuilder: (context, i) {
                    final slot = _slots[i];
                    return ListTile(
                      minVerticalPadding: 16,
                      leading: const Icon(Icons.castle),
                      title: Text(slot.name),
                      subtitle: Text(
                          'Anno ${slot.year} — ${slot.humanCount} 👤 — '
                          '${slot.savedAt.toLocal().toString().substring(0, 16)}'),
                      onTap: () => _openGame(slot.name),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete',
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Delete "${slot.name}"?'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete')),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await _saves!.delete(slot.name);
                            _load();
                          }
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newGame,
        icon: const Icon(Icons.add),
        label: Text(tr('newGame')),
      ),
    );
  }
}
