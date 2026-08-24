import 'l10n/strings.dart';

/// One release's "What's new" entry: the app version it ships with plus the
/// bullet keys (resolved through `tr()`, so the text is localized and lives
/// in `l10n/parts/whatsnew_strings.dart`).
class ReleaseNote {
  const ReleaseNote(this.version, this.itemKeys);

  /// The release version this entry belongs to — compared against
  /// [appVersion] (`app_version.dart`) to decide whether to show it.
  final String version;

  /// `tr()` keys for the bullet list, in display order.
  final List<String> itemKeys;

  /// The bullets localized for the active UI language.
  List<String> items() => [for (final k in itemKeys) tr(k)];
}

/// The release-notes catalog, newest first. Add one entry per release:
/// bump [appVersion] AND append a `ReleaseNote` here (with matching
/// `whatsnew.<version>.<i>` keys) in the same change — otherwise an
/// updated user sees no notes. Entries for versions the user already
/// dismissed are never re-shown (SettingsService stores the last-seen
/// version), so only the *latest* entry is ever displayed.
const List<ReleaseNote> releaseNotes = [
  ReleaseNote('0.2.7', [
    'whatsnew.0_2_7.0',
    'whatsnew.0_2_7.1',
    'whatsnew.0_2_7.2',
    'whatsnew.0_2_7.3',
    'whatsnew.0_2_7.4',
  ]),
  ReleaseNote('0.2.6', [
    'whatsnew.0_2_6.0',
    'whatsnew.0_2_6.1',
    'whatsnew.0_2_6.2',
    'whatsnew.0_2_6.3',
  ]),
];

/// The release note for [version], or null if that version has none.
ReleaseNote? releaseNotesFor(String version) {
  for (final note in releaseNotes) {
    if (note.version == version) return note;
  }
  return null;
}
