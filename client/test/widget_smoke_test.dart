import 'package:flutter_test/flutter_test.dart';
import 'package:pckaiser/main.dart';

void main() {
  testWidgets('the app builds and shows the home screen', (tester) async {
    await tester.pumpWidget(const PcKaiserApp());
    await tester.pump();
    expect(find.text('PC Kaiser'), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);
  });
}
