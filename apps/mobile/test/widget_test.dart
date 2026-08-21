import 'package:arangcada/app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('anonymous bootstrap shows login without visible test tools', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: ArangCadaApp()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Test accounts'), findsNothing);
  });
}
