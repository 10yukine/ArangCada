import 'package:arangcada/app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('offline bootstrap routes an anonymous user to login', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: ArangCadaApp()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Prefill a demo account'), findsOneWidget);
  });
}
