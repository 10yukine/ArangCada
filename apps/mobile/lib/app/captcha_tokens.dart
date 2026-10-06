import 'dart:async';

import 'package:flutter/foundation.dart';

/// Keeps the token the in-screen human check last produced.
///
/// The check page reports through [onMessage]: `token:<value>`, `expired`,
/// `failed`, `interactive:<height>` when Cloudflare needs a tap and `idle`
/// when it no longer does. A token works once and lasts five minutes, so
/// [take] hands each one out a single time and starts the page over for the
/// next.
class CaptchaTokens extends ChangeNotifier {
  CaptchaTokens({required this.startOver, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Loads the page afresh, which runs the check again from the beginning.
  ///
  /// It is the only way a new token is asked for. Resetting the widget on a
  /// page that had already answered was tried first, and on a phone the second
  /// answer did not come for twenty seconds, while a fresh page answered in a
  /// few (6 Oct 2026).
  final void Function() startOver;
  final DateTime Function() _now;

  // Turnstile tokens last five minutes; stop short of that.
  static const _life = Duration(minutes: 4, seconds: 30);
  // How often a wait looks up: a request to tap can begin in the middle.
  static const _glance = Duration(milliseconds: 250);

  String? _token;
  DateTime? _since;
  Completer<void>? _arrived;
  bool _pageDown = false;
  bool _gone = false;

  bool get isDisposed => _gone;

  /// How tall the page has to be while a tap is wanted; null when there is
  /// nothing to show.
  double? get openHeight => _openHeight;
  double? _openHeight;

  void onMessage(String message) {
    if (_gone) return;
    if (message.startsWith('token:')) {
      _token = message.substring(6);
      _since = _now();
      _wake();
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

  /// The page itself did not load. The next [take] loads it again at once
  /// rather than waiting on a page that is not there.
  void pageFailed() => _pageDown = true;

  @override
  void dispose() {
    // Whoever is waiting in [take] is waiting for a screen that has gone.
    _gone = true;
    _wake();
    super.dispose();
  }

  void _wake() {
    _arrived?.complete();
    _arrived = null;
  }

  void _reload() {
    if (_gone) return;
    // A page that was asking for a tap goes with the reload and may never get
    // to say it has stopped. Left open, the screen would go on showing an
    // empty box and the line telling the person to tap it.
    if (_openHeight != null) {
      _openHeight = null;
      notifyListeners();
    }
    startOver();
  }

  bool get _held => _token?.isNotEmpty ?? false;
  bool get _fresh => _held && _now().difference(_since!) < _life;

  /// The token for one request.
  ///
  /// A check that is already running is given [patience]. If nothing has come
  /// by then the page is loaded afresh, once, and given the same again: a new
  /// start is what gets a stuck check moving, and it happens here, in the
  /// screen, not in a second check on top of it. While the person is being
  /// asked to tap, the wait lasts up to [limit]. Null if no token came or the
  /// screen has gone.
  Future<String?> take({
    Duration patience = const Duration(seconds: 10),
    Duration limit = const Duration(seconds: 45),
  }) async {
    // The page replaces a token only when Cloudflare's own five minutes are
    // up, which is later than this gives up on one.
    if (_held && !_fresh) {
      _token = null;
      _reload();
    }
    var startedOver = false;
    var waited = Duration.zero;
    while (!_fresh) {
      if (_gone) return null;
      final tapWanted = _openHeight != null;
      final allowed = tapWanted ? limit : patience;
      if (_pageDown || waited >= allowed) {
        if (tapWanted || startedOver) return null;
        startedOver = true;
        _pageDown = false;
        _token = null;
        waited = Duration.zero;
        _reload();
        continue;
      }
      final left = allowed - waited;
      final step = left < _glance ? left : _glance;
      await (_arrived ??= Completer<void>()).future.timeout(
        step,
        onTimeout: () {},
      );
      waited += step;
    }
    final token = _token;
    _token = null;
    _reload();
    return token;
  }
}
