import '../l10n/strings.dart' show appLocale;
import 'push_kinds.dart';
import 'push_service.dart';
import 'settings_service.dart';

/// The yearly Weltmeisterschaft announcement is an FCM topic broadcast —
/// one topic per UI language (`championship_de` / `championship_en`), since
/// a broadcast cannot be localized per device. This keeps the device in
/// exactly the topic its choices call for: the current UI language when the
/// player opted in (and did not switch it off later), none otherwise.
///
/// Called on launch, on a language change and when the switch flips; every
/// call converges, so a failed (un)subscribe heals on the next one.
Future<void> syncChampionshipTopic() async {
  final push = PushService.instance;
  final settings = SettingsService.instance;
  if (push == null || settings == null) return;
  final wanted =
      settings.championshipPromptAnswered &&
      settings.pushEnabled(pushChampionship);
  for (final lang in const ['de', 'en']) {
    await push.setTopic(
      'championship_$lang',
      subscribed: wanted && lang == appLocale.value,
    );
  }
}
