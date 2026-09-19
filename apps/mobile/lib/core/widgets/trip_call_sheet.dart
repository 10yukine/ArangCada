import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/providers/repository_providers.dart';

Uri? tripPhoneUri(String? phone) {
  if (phone == null || !RegExp(r'^\+639[0-9]{9}$').hasMatch(phone)) return null;
  return Uri(scheme: 'tel', path: phone);
}

void showTripCallSheet(BuildContext context, {String? tripId}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _TripCallSheet(tripId: tripId),
  );
}

class _TripCallSheet extends ConsumerStatefulWidget {
  const _TripCallSheet({this.tripId});
  final String? tripId;
  @override
  ConsumerState<_TripCallSheet> createState() => _TripCallSheetState();
}

class _TripCallSheetState extends ConsumerState<_TripCallSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _open() async {
    if (_busy) return;
    final rides = ref.read(liveRideRepositoryProvider);
    final tripId = widget.tripId ?? ref.read(demoStateProvider).liveTripId;
    if (rides == null || tripId == null) {
      setState(() => _error = 'No active ride is available for calling.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Fetch on every tap; do not persist or log contact numbers.
      final phone = await rides
          .counterpartPhone(tripId)
          .timeout(const Duration(seconds: 15));
      if (!mounted || ref.read(liveRideRepositoryProvider) != rides) return;
      final uri = tripPhoneUri(phone);
      if (uri == null) {
        setState(
          () => _error = 'No phone contact is available for this active ride.',
        );
      } else if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          setState(() => _error = 'Could not open a phone app. Try again.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open calling. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(liveRideRepositoryProvider) != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Call your ride partner',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              connected
                  ? 'Opens your phone dialer. You choose whether to place the call. Carrier charges may apply and your caller ID may be shared.'
                  : 'Calling is unavailable for demo accounts. No number will be dialled.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, semanticsLabel: _error),
            ],
            const SizedBox(height: 16),
            if (connected)
              FilledButton(
                onPressed: _busy ? null : _open,
                child: Text(_busy ? 'Opening…' : 'Open phone dialer'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
