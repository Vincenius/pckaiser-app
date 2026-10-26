import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckaiser/l10n/strings.dart';
import 'package:pckaiser/widgets/room_card.dart';

/// The yearly Weltmeisterschaft (2026-10-26): the server sends the room key
/// `championship` for its match; the client names it, and a start days away
/// reads as a date rather than an hour countdown.
void main() {
  tearDown(() => appLocale.value = 'de');

  test('the championship room key has a localized name and a trophy', () {
    appLocale.value = 'de';
    expect(roomTitle('championship'), 'Weltmeisterschaft');
    appLocale.value = 'en';
    expect(roomTitle('championship'), 'World Championship');
    expect(roomIcon('championship'), Icons.emoji_events);
  });

  test('a start days away is shown as a date, a near one as a countdown', () {
    appLocale.value = 'de';
    final far = DateTime.now().toUtc().add(const Duration(days: 6));
    expect(
      roomStartLine(joined: 3, seats: 16, autoStartAt: far.toIso8601String()),
      startsWith('Startet am '),
    );
    final near = DateTime.now().toUtc().add(const Duration(hours: 5));
    expect(
      roomStartLine(joined: 3, seats: 16, autoStartAt: near.toIso8601String()),
      startsWith('Startet in '),
    );
  });

  test('every championship string exists in both languages', () {
    const keys = [
      'championship.title',
      'championship.titleYear',
      'championship.pitch',
      'championship.startsAt',
      'championship.signUp',
      'championship.signedUp',
      'championship.full',
      'championship.seatsLeft',
      'championship.roomWaiting',
      'championship.consentTitle',
      'championship.consentBody',
      'championship.consentYes',
      'championship.consentNo',
      'championship.hallOfFame',
      'championship.finishedOn',
      'championship.noResults',
      'championship.noResultsHint',
      'championship.reasonWinner',
      'championship.reasonSurvived',
      'championship.reasonEliminated',
      'championship.reasonLeft',
      'championship.reasonKicked',
      'online.startsAt',
    ];
    for (final locale in ['de', 'en']) {
      appLocale.value = locale;
      for (final key in keys) {
        expect(tr(key), isNot(key), reason: '$key missing in $locale');
      }
    }
  });
}
