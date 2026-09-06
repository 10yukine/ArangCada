import 'package:arangcada/core/widgets/arang_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders initials when imageUrl is null (every existing call '
      'site keeps working unchanged)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ArangAvatar(name: 'Juan Dela Cruz')),
      ),
    );

    expect(find.text('JC'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('renders the photo via Image.network when imageUrl is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArangAvatar(
            name: 'Juan Dela Cruz',
            imageUrl: 'https://example.test/signed/photo.jpg',
          ),
        ),
      ),
    );

    expect(find.text('JC'), findsNothing);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, 'https://example.test/signed/photo.jpg');
  });

  testWidgets('falls back to initials when the network image fails to load '
      '-- never a broken-image icon where an identity is meant to be', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArangAvatar(
            name: 'Juan Dela Cruz',
            imageUrl: 'https://example.test/signed/broken.jpg',
          ),
        ),
      ),
    );
    // Let the network request fail in the test environment.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('JC'), findsOneWidget);
  });
}
