import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../data/providers/repository_providers.dart';

/// The public tracking site. Tokens are opened at `/t/<token>` there.
const String trackingSiteBase = 'https://track.arangcada.app';

Uri tripTrackingUri(String token) =>
    Uri.parse('$trackingSiteBase/t/${Uri.encodeComponent(token)}');

/// Lets a rider send family a live link to their current trip.
///
/// Copy covers every chat app (Messenger, Viber, ...) without a share-sheet
/// dependency; "Send by text" opens the SMS app through url_launcher, which
/// the app already ships. [createLink] exists for tests; by default the link
/// comes from the server, which only issues one to the verified rider of an
/// unfinished trip and reuses it on every tap.
void showTripShareSheet(
  BuildContext context, {
  Future<Uri> Function()? createLink,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _TripShareSheet(createLink: createLink),
  );
}

class _TripShareSheet extends ConsumerStatefulWidget {
  const _TripShareSheet({this.createLink});

  final Future<Uri> Function()? createLink;

  @override
  ConsumerState<_TripShareSheet> createState() => _TripShareSheetState();
}

class _TripShareSheetState extends ConsumerState<_TripShareSheet> {
  Uri? _link;
  String? _error;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final link = await (widget.createLink ?? _fromServer)().timeout(
        const Duration(seconds: 15),
      );
      if (mounted) setState(() => _link = link);
    } on PostgrestException catch (error) {
      // The server's refusals are written for people ("verify your mobile
      // number before sharing a ride link", "this trip has already ended").
      if (mounted) setState(() => _error = _sentence(error.message));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not create a link. Check your connection and try again.',
        );
      }
    }
  }

  Future<Uri> _fromServer() async {
    final rides = ref.read(liveRideRepositoryProvider);
    if (rides == null) throw StateError('No live trip');
    return tripTrackingUri(await rides.createShareLink());
  }

  String _sentence(String message) => message.isEmpty
      ? message
      : '${message[0].toUpperCase()}${message.substring(1)}.';

  Future<void> _copy(Uri link) async {
    await Clipboard.setData(ClipboardData(text: link.toString()));
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _sendText(Uri link) async {
    final body = 'Follow my ArangCada tricycle ride live: $link';
    final sms = Uri.parse('sms:?body=${Uri.encodeComponent(body)}');
    if (!await launchUrl(sms, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _error = 'Could not open your messaging app.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Share your trip', style: AppTypography.displaySm),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Anyone with this link can follow your tricycle live. It stops '
              'showing your location when the trip ends.',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_error != null) ...[
              Text(
                _error!,
                style: AppTypography.bodySm.copyWith(color: AppColors.danger),
              ),
              if (link == null) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ),
              ],
            ] else if (link == null)
              const Text('Creating your link…', style: AppTypography.bodySm),
            if (link != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  border: Border.all(color: AppColors.border),
                ),
                child: SelectableText(
                  link.toString(),
                  style: AppTypography.bodySm,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: () => _copy(link),
                icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
                label: Text(_copied ? 'Link copied' : 'Copy link'),
              ),
              if (_copied) ...[
                const SizedBox(height: AppSpacing.xxs),
                const Text(
                  'Paste it in Messenger, Viber or any chat.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton.icon(
                onPressed: () => _sendText(link),
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Send by text'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
