import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' hide World;

import '../l10n/strings.dart';
import '../services/save_service.dart';
import '../widgets/advanced_options.dart';
import '../widgets/empire_card.dart';
import 'game_screen.dart';

class _PlayerDraft {
  _PlayerDraft(int defaultSlot)
    : name = TextEditingController(),
      dorf = TextEditingController(text: cityNames[defaultSlot - 1]),
      countrySlot = defaultSlot;

  final TextEditingController name;
  final TextEditingController dorf;

  /// Realm slot 1–30, or null = drawn at random when the game starts.
  int? countrySlot;
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
  final _slotName = TextEditingController(text: tr('setup.defaultSlotName'));
  final _reformation = TextEditingController(text: '$defaultReformationYear');
  final _ottoman = TextEditingController(text: '$defaultOttomanYear');
  final _warStart = TextEditingController(text: '$defaultWarStartYear');
  final List<_PlayerDraft> _players = [_PlayerDraft(1)];
  // Removed drafts are disposed with the screen, not immediately — their
  // TextFields may still be attached during the removal frame.
  final List<_PlayerDraft> _removedPlayers = [];
  bool _starting = false;
  // Deviation from the original — on by default for new games.
  bool _genderEqualSuccession = true;
  bool _suggestChildNames = true;
  AiDifficulty _aiDifficulty = AiDifficulty.mittel;

  int _nextFreeSlot() {
    for (var slot = 1; slot <= 30; slot++) {
      if (!_players.any((p) => p.countrySlot == slot)) return slot;
    }
    return 1;
  }

  String? _validate() {
    final yearError = validateEventYears(
      reformation: _reformation.text,
      ottoman: _ottoman.text,
      warStart: _warStart.text,
    );
    if (yearError != null) return yearError;
    if (_slotName.text.trim().isEmpty) {
      return tr('setup.errorSlotName');
    }
    for (final p in _players) {
      if (p.name.text.trim().isEmpty) {
        return tr('setup.errorFounderName');
      }
      // With a random country the Dorf may stay empty — it falls back to
      // the drawn realm's historical first village.
      if (p.countrySlot != null && p.dorf.text.trim().isEmpty) {
        return tr('setup.errorDorfName');
      }
    }
    final chosen = _players.map((p) => p.countrySlot).whereType<int>();
    if (chosen.length != chosen.toSet().length) {
      return tr('setup.errorDuplicateCountry');
    }
    return null;
  }

  @override
  void dispose() {
    _slotName.dispose();
    _reformation.dispose();
    _ottoman.dispose();
    _warStart.dispose();
    for (final p in _players.followedBy(_removedPlayers)) {
      p.name.dispose();
      p.dorf.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // Starting a game writes the save immediately — never silently destroy
    // an existing slot (the name field is pre-filled with a default!).
    if (await widget.saves.exists(_slotName.text.trim())) {
      if (!mounted) return;
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('setup.overwriteTitle')),
          content: Text(
            tr('setup.overwriteBody', {'name': _slotName.text.trim()}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('setup.overwrite')),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
    }
    if (!mounted) return;
    setState(() => _starting = true);
    final setup = GameSetup(
      // "Zufällig" countries (null slot) and their empty Dorf names are
      // resolved inside newGame from the game seed, so the draw is part
      // of the reproducible setup.
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
      warStartYear: int.parse(_warStart.text),
      genderEqualSuccession: _genderEqualSuccession,
      suggestChildNames: _suggestChildNames,
      aiDifficulty: _aiDifficulty,
      seed: DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF,
    );
    if (!mounted) return;
    // push + pop (not pushReplacement): replacing this route would resolve
    // the home screen's await immediately, so its save list would refresh
    // before the game exists instead of when the player returns to it.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen.create(
          slotName: _slotName.text.trim(),
          setup: setup,
          saves: widget.saves,
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('newGame'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _slotName,
            maxLength: maxNameLength,
            decoration: InputDecoration(
              labelText: tr('setup.slotNameLabel'),
              counterText: '',
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _players.length == 1
                ? tr('setup.playersHeading')
                : tr('setup.playersHeadingCount', {'count': _players.length}),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _players.length; i++) _playerCard(i),
          const SizedBox(height: 8),
          if (_players.length < 16)
            OutlinedButton.icon(
              onPressed: () =>
                  setState(() => _players.add(_PlayerDraft(_nextFreeSlot()))),
              icon: const Icon(Icons.person_add),
              label: Text(tr('setup.addPlayer')),
            ),
          const SizedBox(height: 24),
          AdvancedOptionsCard(
            reformation: _reformation,
            ottoman: _ottoman,
            warStart: _warStart,
            aiDifficulty: _aiDifficulty,
            onAiDifficultyChanged: (v) => setState(() => _aiDifficulty = v),
            genderEqualSuccession: _genderEqualSuccession,
            onGenderEqualSuccessionChanged: (v) =>
                setState(() => _genderEqualSuccession = v),
            suggestChildNames: _suggestChildNames,
            onSuggestChildNamesChanged: (v) =>
                setState(() => _suggestChildNames = v),
          ),
        ],
      ),
      // Pinned start button: reachable without scrolling past 16 players.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _starting ? null : _start,
          icon: _starting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(tr('setup.startGame')),
          ),
        ),
      ),
    );
  }

  Widget _playerCard(int i) {
    final p = _players[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: EmpireCard(
        name: p.name,
        nameLabel: tr('setup.founderNameLabel'),
        nameMaxLength: maxNameLength,
        dorf: p.dorf,
        gender: p.gender,
        onGenderChanged: (v) => setState(() => p.gender = v),
        countrySlot: p.countrySlot,
        onCountryChanged: (v) => setState(() => p.countrySlot = v),
        randomDorfHint: tr('setup.randomDorfHint'),
        header: Row(
          children: [
            Text(
              tr('setup.playerN', {'n': i + 1}),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            if (_players.length > 1)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: tr('setup.removePlayer'),
                onPressed: () =>
                    setState(() => _removedPlayers.add(_players.removeAt(i))),
              ),
          ],
        ),
      ),
    );
  }
}
