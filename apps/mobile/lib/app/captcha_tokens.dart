import 'dart:async';

import 'package:flutter/foundation.dart';

/// Keeps the token the in-screen human check last produced.
///
/// The check page reports through [onMessage]: `token:<value>`, `expired`,
/// `failed`, `interactive:<height>` when Cloudflare needs a tap and `idle`
/// when it no longer does. A token works once and lasts five minutes, so
/// [take] hands each one out a single time and asks the page for the next.
class CaptchaTokens extends ChangeNotifier {
  CaptchaTokens({required this.askAgain, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Tells the page to run the check again for a fresh token.
  final void Function() askAgain;
  final DateTime Function() _now;

  // Turnstile tokens last five minutes; stop short of that.
  static const _life = Duration(minutes: 4, seconds: 30);

  String? _token;
  DateTime? _since;
  Completer<void>? _arrived;

  /// How tall the page has to be while a tap is wanted; null when there is
  /// nothing to show.
  double? get openHeight => _openHeight;
  double? _openHeight;

  void onMessage(String message) {
    if (message.startsWith('token:')) {
      _token = message.substring(6);
      _since = _now();
      _arrived?.complete();
      _arrived = null;
    } else if (message == 'expired' || message == 'failed') {
      _token = null;
    } else if (message.startsWith('interactive:')) {
      _openHeight = double.tryParse(message.substring(12));
      notifyListeners();
    } else if (message == 'idle') {
      _openHeight = null;
      notifyListeners();
    }
  }

  bool get _held => _token?.isNotEmpty ?? false;
  bool get _fresh => _held && _now().difference(_since!) < _life;

  /// The token, waiting [patience] for one that is on its way, and up to
  /// [limit] while the person is being asked to tap. Null if none came.
  Future<String?> take({
    Duration patience = const Duration(seconds: 8),
    Duration limit = const Duration(minutes: 2),
  }) async {
    // The page replaces a token only when Cloudflare's own five minutes are
    // up, which is later than this gives up on one.
    if (_held && !_fresh) {
      _token = null;
      askAgain();
    }
    final waited = Stopwatch()..start();
    while (!_fresh) {
      final left = (_openHeight == null ? patience : limit) - waited.elapsed;
      if (left <= Duration.zero) return null;
      // Wake often: a request to tap can begin while this is waiting.
      const glance = Duration(milliseconds: 250);
      await (_arrived ??= Completer<void>()).future.timeout(
        left < glance ? left : glance,
        onTimeout: () {},
      );
    }
    final token = _token;
    _token = null;
    askAgain();
    return token;
  }
}
