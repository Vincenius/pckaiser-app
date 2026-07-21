import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/strings.dart' show tr;
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
  var _mapSize = gc.MapSize.gross;
  var _realmCount = gc.MapSize.gross.defaultRealmCount;

  bool get _isHost => widget.mode == OnlineSetupMode.host;

  /// A new map size resets the realm count to its default; an own country
  /// pick beyond the new count falls back to "Zufällig".
  void _applyMapSize(gc.MapSize size) {
    setState(() {
      _mapSize = size;
      _realmCount = size.defaultRealmCount;
      if ((_slot ?? 0) > _realmCount) _slot = null;
    });
  }

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
      return tr('online.enterRoomCode');
    }
    if (_founder.text.trim().isEmpty) {
      return tr('online.rulerNeedsName');
    }
    // Unlike the local setup there is no empty-Dorf fallback: the server
    // requires a name even for a random country.
    if (_dorf.text.trim().isEmpty) {
      return tr('online.dorfNeedsName');
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
          mapSize: _mapSize,
          realmCount: _realmCount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isHost ? tr('online.newOnlineGame') : tr('online.joinGame'),
        ),
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
              decoration: InputDecoration(
                labelText: tr('online.roomCode'),
                hintText: tr('online.roomCodeHint'),
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (_isHost) ...[
            Text(tr('online.matchSection'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _matchCard(theme),
            const SizedBox(height: 24),
          ],
          Text(tr('online.yourRealm'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          EmpireCard(
            name: _founder,
            nameLabel: tr('online.rulerName'),
            nameMaxLength: 20,
            dorf: _dorf,
            gender: _gender,
            onGenderChanged: (v) => setState(() => _gender = v),
            countrySlot: _slot,
            onCountryChanged: (v) => setState(() => _slot = v),
            // Joiners don't know the host's realm count — they see the
            // full list; the server validates the pick on join.
            maxSlot: _isHost ? _realmCount : gc.World.realmCount,
          ),
          if (_isHost) ...[
            const SizedBox(height: 24),
            AdvancedOptionsCard(
              reformation: _reformation,
              ottoman: _ottoman,
              warStart: _warStart,
              mapSize: _mapSize,
              onMapSizeChanged: _applyMapSize,
              realmCount: _realmCount,
              onRealmCountChanged: (v) => setState(() => _realmCount = v),
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
            child: Text(_isHost ? tr('online.createGame') : tr('online.join')),
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
                Expanded(child: Text(tr('online.turnTimeLimit'))),
                DropdownButton<int?>(
                  value: _timeoutHours,
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(tr('online.off')),
                    ),
                    const DropdownMenuItem(value: 12, child: Text('12 h')),
                    const DropdownMenuItem(value: 24, child: Text('24 h')),
                    const DropdownMenuItem(value: 48, child: Text('48 h')),
                    DropdownMenuItem(
                      value: 168,
                      child: Text(tr('online.sevenDays')),
                    ),
                  ],
                  onChanged: (v) => setState(() => _timeoutHours = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(tr('online.visibility'))),
                // Scale down on narrow screens instead of overflowing
                // (same pattern as the recruit sheet's class picker).
                Flexible(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(tr('online.private')),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(tr('online.public')),
                        ),
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
                    ? tr('online.publicHint')
                    : tr('online.privateHint'),
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
          Expanded(child: Text(tr('online.warTurnTime'))),
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
