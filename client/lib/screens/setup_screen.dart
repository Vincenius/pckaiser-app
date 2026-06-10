import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' hide World;

import '../services/save_service.dart';
import 'game_screen.dart';

class _PlayerDraft {
  _PlayerDraft(int defaultSlot)
      : name = TextEditingController(),
        dorf = TextEditingController(text: cityNames[defaultSlot - 1]),
        countrySlot = defaultSlot;

  final TextEditingController name;
  final TextEditingController dorf;
  int countrySlot;
  int gender = 0;
}

/// New-game setup (§5 + PROJECT_REQUIREMENTS smart defaults): slot name,
/// 1–16 players with founder/gender/country/Dorf, Reformation and Ottoman
/// years (pre-filled 1020/1040, validated ≥ 1011).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.saves});

  final SaveService saves;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _slotName = TextEditingController(text: 'Partie 1');
  final _reformation = TextEditingController(text: '1020');
  final _ottoman = TextEditingController(text: '1040');
  final List<_PlayerDraft> _players = [_PlayerDraft(1)];
  bool _starting = false;

  int _nextFreeSlot() {
    for (var slot = 1; slot <= 30; slot++) {
      if (!_players.any((p) => p.countrySlot == slot)) return slot;
    }
    return 1;
  }

  String? _validate() {
    final reformation = int.tryParse(_reformation.text);
    final ottoman = int.tryParse(_ottoman.text);
    if (reformation == null || reformation < minEventYear) {
      return 'Das ist zu früh !!! (Reformation ≥ $minEventYear)';
    }
    if (ottoman == null || ottoman < minEventYear) {
      return 'Das ist zu früh !!! (Ottoman ≥ $minEventYear)';
    }
    if (_slotName.text.trim().isEmpty) return 'Name the save slot';
    for (final p in _players) {
      if (p.name.text.trim().isEmpty) return 'Every founder needs a name';
      if (p.dorf.text.trim().isEmpty) return 'Every first Dorf needs a name';
    }
    final slots = _players.map((p) => p.countrySlot).toSet();
    if (slots.length != _players.length) {
      return 'Two players picked the same country';
    }
    return null;
  }

  Future<void> _start() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _starting = true);
    final setup = GameSetup(
      humans: [
        for (final p in _players)
          HumanPlayerSetup(
            founderName: p.name.text.trim(),
            gender: p.gender,
            countrySlot: p.countrySlot,
            dorfName: p.dorf.text.trim(),
          ),
      ],
      reformationYear: int.parse(_reformation.text),
      ottomanYear: int.parse(_ottoman.text),
      seed: DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF,
    );
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GameScreen.create(
        slotName: _slotName.text.trim(),
        setup: setup,
        saves: widget.saves,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New game')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _slotName,
            decoration: const InputDecoration(labelText: 'Save slot name'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _reformation,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Reformation year'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _ottoman,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Ottoman year'),
              ),
            ),
          ]),
          const Divider(height: 32),
          for (var i = 0; i < _players.length; i++) _playerCard(i),
          const SizedBox(height: 8),
          if (_players.length < 16)
            OutlinedButton.icon(
              onPressed: () =>
                  setState(() => _players.add(_PlayerDraft(_nextFreeSlot()))),
              icon: const Icon(Icons.person_add),
              label: const Text('Add player'),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _starting ? null : _start,
            icon: _starting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: const Text('Start'),
          ),
        ],
      ),
    );
  }

  Widget _playerCard(int i) {
    final p = _players[i];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Text('Player ${i + 1}',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (_players.length > 1)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove player',
                onPressed: () => setState(() => _players.removeAt(i)),
              ),
          ]),
          TextField(
            controller: p.name,
            decoration: const InputDecoration(labelText: 'Founder name'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Männlich')),
                  ButtonSegment(value: 1, label: Text('Weiblich')),
                ],
                selected: {p.gender},
                onSelectionChanged: (s) =>
                    setState(() => p.gender = s.first),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: p.countrySlot,
                decoration: const InputDecoration(labelText: 'Country'),
                items: [
                  for (var slot = 1; slot <= 30; slot++)
                    DropdownMenuItem(
                        value: slot, child: Text(countryNames[slot])),
                ],
                onChanged: (v) => setState(() {
                  p.countrySlot = v ?? p.countrySlot;
                  p.dorf.text = cityNames[p.countrySlot - 1];
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: p.dorf,
                decoration: const InputDecoration(labelText: 'First Dorf'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
