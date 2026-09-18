import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/driver_documents_repository.dart';
import '../../domain/models/demo_user.dart';

class DriverDocumentsScreen extends ConsumerStatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  ConsumerState<DriverDocumentsScreen> createState() =>
      _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends ConsumerState<DriverDocumentsScreen> {
  Future<DriverRecords?>? _records;

  void _reload() => setState(() {
    _records = ref.read(driverDocumentsRepositoryProvider)?.load();
  });

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(demoStateProvider).currentUser;
    final repository = ref.watch(driverDocumentsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Franchise & documents')),
      body: SafeArea(
        child: user?.role != DemoRole.driver
            ? const Center(
                child: Text('These records are available to drivers.'),
              )
            : repository == null
            ? const EmptyStateCard(
                icon: Icons.description_outlined,
                title: 'Records unavailable',
                message:
                    'Sign in with your registered driver account to view LGU/TODA records. Demo accounts have no uploaded documents.',
              )
            : FutureBuilder<DriverRecords?>(
                future: _records ??= repository.load(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return EmptyStateCard(
                      icon: Icons.cloud_off,
                      title: 'Could not load your records',
                      message: 'Check your connection and try again.',
                      actionLabel: 'Retry',
                      onAction: _reload,
                    );
                  }
                  final records = snapshot.data;
                  if (records == null) {
                    return EmptyStateCard(
                      icon: Icons.description_outlined,
                      title: 'No driver records yet',
                      message:
                          'Contact your LGU/TODA office to check your registration.',
                      actionLabel: 'Refresh',
                      onAction: _reload,
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      const Text(
                        'Managed by your LGU/TODA office. Contact them for corrections or replacement documents.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _RecordField(
                        'Registration status',
                        _status(records.status),
                      ),
                      if (records.rejectionReason != null)
                        _RecordField('Review note', records.rejectionReason),
                      _RecordField('TODA', records.toda),
                      _RecordField('Body number', records.bodyNumber),
                      _RecordField('Plate number', records.plateNumber),
                      _RecordField('Licence expiry', records.licenceExpiresOn),
                      const _RecordField(
                        'MTOP / franchise number',
                        'See your uploaded franchise permit below.',
                      ),
                      const Divider(),
                      Text(
                        'Documents',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (records.documents.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          child: Text('No documents have been uploaded yet.'),
                        ),
                      for (final entry in DriverDocument.labels.entries)
                        Builder(
                          builder: (context) {
                            final matches = records.documents.where(
                              (d) => d.type == entry.key,
                            );
                            final document = matches.isEmpty
                                ? null
                                : matches.first;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(entry.value),
                              subtitle: Text(
                                document == null
                                    ? 'Not uploaded'
                                    : [
                                        _status(document.status),
                                        if (document.rejectionReason != null)
                                          document.rejectionReason!,
                                      ].join('\n'),
                              ),
                              trailing: document == null
                                  ? null
                                  : const Icon(Icons.open_in_full),
                              onTap: document == null
                                  ? null
                                  : () => showDialog<void>(
                                      context: context,
                                      builder: (_) => _DocumentViewer(
                                        repository: repository,
                                        document: document,
                                      ),
                                    ),
                            );
                          },
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh records'),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

String _status(String value) => switch (value) {
  'approved' => 'Approved',
  'pending' || 'pending_review' => 'Pending review',
  'rejected' => 'Rejected',
  'suspended' => 'Suspended',
  'unverified' => 'Not verified',
  _ => 'Status unavailable',
};

class _RecordField extends StatelessWidget {
  const _RecordField(this.label, this.value);
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      value == null || value!.trim().isEmpty ? 'Not recorded' : value!,
    ),
  );
}

class _DocumentViewer extends StatefulWidget {
  const _DocumentViewer({required this.repository, required this.document});
  final DriverDocumentsRepository repository;
  final DriverDocument document;

  @override
  State<_DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<_DocumentViewer> {
  late Future<Uint8List> _bytes;
  MemoryImage? _image;

  @override
  void initState() {
    super.initState();
    _bytes = widget.repository.loadDocument(widget.document.id);
  }

  void _retry() {
    _evict();
    setState(() {
      _bytes = widget.repository.loadDocument(widget.document.id);
    });
  }

  void _evict() {
    final image = _image;
    _image = null;
    if (image != null) unawaited(image.evict());
  }

  @override
  void dispose() {
    _evict();
    super.dispose();
  }

  Widget _error() => EmptyStateCard(
    icon: Icons.broken_image_outlined,
    title: 'Could not open this document',
    message:
        'Try again. If it still fails, ask your LGU/TODA office to check the uploaded image.',
    actionLabel: 'Retry',
    onAction: _retry,
  );

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.document.label),
        leading: IconButton(
          tooltip: 'Close document',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) return _error();
            _image ??= MemoryImage(snapshot.data!);
            return Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image(
                  image: _image!,
                  semanticLabel: widget.document.label,
                  errorBuilder: (_, _, _) => _error(),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
