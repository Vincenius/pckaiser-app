import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart' as gc;

import '../services/match_setup.dart';
import '../widgets/advanced_options.dart';
import '../widgets/empire_card.dart';

/// What the online setup screen was opened for — hosting shows the match
/// settings (timer, visibility, advanced options), joining only the empire.
enum OnlineSetupMode {
  /// Create a new match: match settings + own empire.
  host,

  /// Join via room code: code field + own empire.
  joinByCode,

  /// Join a public match from the open-games list: own empire only.
  joinPublic,
}

/// Everything the lobby needs after the screen closes: the (possibly
/// entered) room code and the player's setup choices.
class OnlineSetupResult {
  OnlineSetupResult({this.roomCode, required this.setup});

  /// Only set for [OnlineSetupMode.joinByCode].
  final String? roomCode;
  final MatchSetup setup;
}

/// Full-screen online match setup — same look as the local new-game screen
/// (sections, cards, pinned primary button) instead of the former dialog.
/// Pops with an [OnlineSetupResult]; the lobby performs the API calls.
class OnlineSetupScreen extends StatefulWidget {
  const OnlineSetupScreen({super.key, required this.mode, this.displayName});

  final OnlineSetupMode mode;

  /// Pre-fills the founder name with the player's online name.
  final String? displayName;

  @override
  State<OnlineSetupScreen> createState() => _OnlineSetupScreenState();
}

class _OnlineSetupScreenState extends State<OnlineSetupScreen> {
  late final _founder = TextEditingController(text: widget.displayName ?? '');
  final _dorf = TextEditingController();
  final _roomCode = TextEditingController();
  final _reformation = TextEditingController(
    text: '${gc.defaultReformationYear}',
  );
  final _ottoman = TextEditingController(text: '${gc.defaultOttomanYear}');
  final _warStart = TextEditingController(text: '${gc.defaultWarStartYear}');
  var _gender = 0;
  int? _slot;
  int? _timeoutHours = 24;
  var _warRoundMinutes = 10;
  var _isPublic = false;
  var _genderEqualSuccession = true;
  var _suggestChildNames = true;
  var _aiDifficulty = gc.AiDifficulty.mittel;

  bool get _isHost => widget.mode == OnlineSetupMode.host;

  @override
  void dispose() {
    _founder.dispose();
    _dorf.dispose();
    _roomCode.dispose();
    _reformation.dispose();
    _ottoman.dispose();
    _warStart.dispose();
    super.dispose();
  }

  String? _validate() {
    if (widget.mode == OnlineSetupMode.joinByCode &&
        _roomCode.text.trim().length != 5) {
      return 'Bitte den 5-stelligen Raum-Code eingeben';
    }
    if (_founder.text.trim().isEmpty) {
      return 'Der Herrscher braucht einen Namen';
    }
    // Unlike the local setup there is no empty-Dorf fallback: the server
    // requires a name even for a random country.
    if (_dorf.text.trim().isEmpty) {
      return 'Das erste Dorf braucht einen Namen';
    }
    if (_isHost) {
      return validateEventYears(
        reformation: _reformation.text,
        ottoman: _ottoman.text,
        warStart: _warStart.text,
      );
    }
    return null;
  }

  void _submit() {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(
      context,
      OnlineSetupResult(
        roomCode: widget.mode == OnlineSetupMode.joinByCode
            ? _roomCode.text.trim()
            : null,
        setup: MatchSetup(
          founderName: _founder.text.trim(),
          gender: _gender,
          countrySlot: _slot,
          dorfName: _dorf.text.trim(),
          turnTimeoutHours: _timeoutHours,
          warRoundTimeoutSeconds: _warRoundMinutes * 60,
          // Just validated for hosts; joiners keep the untouched defaults.
          reformationYear: int.parse(_reformation.text),
          ottomanYear: int.parse(_ottoman.text),
          warStartYear: int.parse(_warStart.text),
          isPublic: _isPublic,
          genderEqualSuccession: _genderEqualSuccession,
          suggestChildNames: _suggestChildNames,
          aiDifficulty: _aiDifficulty,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isHost ? 'Neue Online-Partie' : 'Partie beitreten'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.mode == OnlineSetupMode.joinByCode) ...[
            TextField(
              controller: _roomCode,
              maxLength: 5,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                // Room codes are 5 capital letters — uppercase as you type.
                TextInputFormatter.withFunction(
                  (oldValue, newValue) =>
                      newValue.copyWith(text: newValue.text.toUpperCase()),
                ),
              ],
              decoration: const InputDecoration(
                labelText: 'Raum-Code',
                hintText: 'z. B. KQXBE',
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (_isHost) ...[
            Text('Partie', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _matchCard(theme),
            const SizedBox(height: 24),
          ],
          Text('Dein Reich', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          EmpireCard(
            name: _founder,
            nameLabel: 'Name des Herrschers',
            nameMaxLength: 20,
            dorf: _dorf,
            gender: _gender,
            onGenderChanged: (v) => setState(() => _gender = v),
            countrySlot: _slot,
            onCountryChanged: (v) => setState(() => _slot = v),
          ),
          if (_isHost) ...[
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
              extras: [_warRoundRow()],
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _submit,
          icon: Icon(_isHost ? Icons.add : Icons.login),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_isHost ? 'Partie erstellen' : 'Beitreten'),
          ),
        ),
      ),
    );
  }

  /// Host-only match settings: turn timer and visibility.
  Widget _matchCard(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Zug-Zeitlimit')),
                DropdownButton<int?>(
                  value: _timeoutHours,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Aus')),
                    DropdownMenuItem(value: 12, child: Text('12 h')),
                    DropdownMenuItem(value: 24, child: Text('24 h')),
                    DropdownMenuItem(value: 48, child: Text('48 h')),
                    DropdownMenuItem(value: 168, child: Text('7 Tage')),
                  ],
                  onChanged: (v) => setState(() => _timeoutHours = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Sichtbarkeit')),
                // Scale down on narrow screens instead of overflowing
                // (same pattern as the recruit sheet's class picker).
                Flexible(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Privat')),
                        ButtonSegment(value: true, label: Text('Öffentlich')),
                      ],
                      selected: {_isPublic},
                      onSelectionChanged: (s) =>
                          setState(() => _isPublic = s.first),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _isPublic
                    ? 'Jeder kann diese Partie in der Liste sehen und '
                          'beitreten.'
                    : 'Nur Spieler mit dem Raum-Code können beitreten.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _warRoundRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Expanded(child: Text('Zugzeit im Krieg')),
          DropdownButton<int>(
            value: _warRoundMinutes,
            items: const [
              DropdownMenuItem(value: 5, child: Text('5 min')),
              DropdownMenuItem(value: 10, child: Text('10 min')),
              DropdownMenuItem(value: 15, child: Text('15 min')),
              DropdownMenuItem(value: 30, child: Text('30 min')),
            ],
            onChanged: (v) =>
                setState(() => _warRoundMinutes = v ?? _warRoundMinutes),
          ),
        ],
      ),
    );
  }
}
