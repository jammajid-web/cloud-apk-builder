import 'package:flutter_test/flutter_test.dart';
import 'package:chatwave/main.dart';

void main() {
  testWidgets('ChatWave setup screen renders', (tester) async {
    await tester.pumpWidget(const ChatWaveApp(supabaseConfigured: false));
    expect(find.text('ChatWave'), findsOneWidget);
    expect(find.text('Flutter + Dart + Supabase'), findsOneWidget);
  });
}
