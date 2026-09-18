import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/driver_documents_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/profile/driver_documents_screen.dart';
import 'package:arangcada/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _document = DriverDocument(
  id: 'doc-a',
  type: 'drivers_license',
  status: 'rejected',
  rejectionReason: 'Please supply a clearer photo',
);
const _records = DriverRecords(
  status: 'pending_review',
  toda: 'Test TODA',
  plateNumber: 'ABC123',
  documents: [_document],
);

class _Repository implements DriverDocumentsRepository {
  DriverRecords? records = _records;
  bool fail = false;
  bool imageFail = false;
  int imageRequests = 0;
  Completer<DriverRecords?>? pending;

  @override
  Future<DriverRecords?> load() async {
    if (fail) throw StateError('private transport detail');
    return pending == null ? records : pending!.future;
  }

  @override
  Future<Uint8List> loadDocument(String id) async {
    expect(id, 'doc-a');
    imageRequests++;
    if (imageFail) throw StateError('private signed URL');
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
  }
}

void main() {
  late _Repository repository;
  late DemoState state;
  setUp(() {
    repository = _Repository();
    state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@example.test',
        displayName: 'Driver',
        role: DemoRole.driver,
      ),
    );
  });
  tearDown(() => state.dispose());

  Widget harness({bool demo = false}) => ProviderScope(
    overrides: [
      demoStateProvider.overrideWithValue(state),
      driverDocumentsRepositoryProvider.overrideWithValue(
        demo ? null : repository,
      ),
    ],
    child: const MaterialApp(home: DriverDocumentsScreen()),
  );

  testWidgets('shows loading, actual status, missing values and review notes', (
    tester,
  ) async {
    repository.pending = Completer();
    await tester.pumpWidget(harness());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.pending!.complete(_records);
    await tester.pumpAndSettle();
    expect(find.text('Pending review'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
    await tester.scrollUntilVisible(find.text('Driver’s licence'), 250);
    expect(
      find.textContaining('Please supply a clearer photo'),
      findsOneWidget,
    );
    expect(find.text('Not uploaded'), findsWidgets);
  });

  testWidgets('load error is safe and retry reloads records', (tester) async {
    repository.fail = true;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Could not load your records'), findsOneWidget);
    expect(find.textContaining('private transport'), findsNothing);
    repository.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Test TODA'), findsOneWidget);
  });

  testWidgets('missing records and demo mode have honest empty states', (
    tester,
  ) async {
    repository.records = null;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('No driver records yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(harness(demo: true));
    expect(find.text('Records unavailable'), findsOneWidget);
  });

  testWidgets('document errors retry and opening again reloads the file', (
    tester,
  ) async {
    repository.imageFail = true;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Driver’s licence'), 250);
    await tester.tap(find.text('Driver’s licence'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open this document'), findsOneWidget);
    expect(find.textContaining('private signed'), findsNothing);
    repository.imageFail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repository.imageRequests, 2);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Close document'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver’s licence'));
    await tester.pumpAndSettle();
    expect(repository.imageRequests, 3);
  });

  testWidgets(
    'profile row navigates to the viewer without a fabricated badge',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ProfileScreen()),
          GoRoute(
            path: '/profile/driver-documents',
            builder: (_, _) => const DriverDocumentsScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            demoStateProvider.overrideWithValue(state),
            driverDocumentsRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      expect(find.text('Verified'), findsNothing);
      await tester.tap(find.text('Franchise & documents'));
      await tester.pumpAndSettle();
      expect(find.text('Test TODA'), findsOneWidget);
    },
  );
}
