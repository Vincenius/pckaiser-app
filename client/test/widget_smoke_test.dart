import 'package:flutter_test/flutter_test.dart';
import 'package:pckaiser/main.dart';

void main() {
  testWidgets('the app builds and shows the home screen', (tester) async {
    await tester.pumpWidget(const PcKaiserApp());
    await tester.pump();
    expect(find.text('PC Kaiser'), findsOneWidget);
    // German is the v1 default locale.
    expect(find.text('Neues Spiel'), findsOneWidget);
  });
}
