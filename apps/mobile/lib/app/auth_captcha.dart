import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:webview_flutter/webview_flutter.dart';

import '../config/app_config.dart';
import '../core/widgets/arang_dialog.dart';
import 'captcha_tokens.dart';
import 'router.dart';
import 'theme/app_colors.dart';
import 'theme/app_dimensions.dart';
import 'theme/app_typography.dart';

/// Runs the human check Supabase Auth asks for before a sign-in, sign-up or
/// reset request, and answers with its single-use token.
///
/// Cloudflare Turnstile has no Android SDK; it runs on a web page in a web
/// view. A screen that signs someone in carries an [AuthCaptchaBox], which
/// has usually finished before the button is pressed, and that box is the
/// only check such a screen ever shows. A screen without one opens the check
/// in a dialog.
///
/// A missing token is left to Auth to refuse while CAPTCHA is enforced.
/// This preserves server-side recovery if the check service is unavailable.
/// Leaving the screen aborts locally instead of submitting after navigation.
Future<String?> authCaptchaToken() async {
  final page = Uri.tryParse(AppConfig.authCaptchaUrl);
  if (page == null || !page.isScheme('https')) return null;
  return captchaFrom(AuthCaptchaBox.inFront, () async {
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AuthCaptchaDialog(page),
    );
  });
}

/// The token from the check on the screen in front, or from [dialog] where
/// that screen has none. Never one after the other: a second check on top of
/// one the person can already see only starts the wait again.
@visibleForTesting
Future<String?> captchaFrom(
  CaptchaTokens? inScreen,
  Future<String?> Function() dialog,
) async {
  final token = inScreen != null ? await inScreen.take() : await dialog();
  if (inScreen?.isDisposed ?? false) {
    throw const AuthException(
      'The security check did not finish',
      code: 'captcha_failed',
    );
  }
  return token;
}

/// The human check as part of a screen. It takes up no room while Cloudflare
/// can decide by itself, which is nearly always; when a tap is wanted it
/// opens to the height of Cloudflare's box, where the screen placed it.
class AuthCaptchaBox extends StatefulWidget {
  const AuthCaptchaBox({super.key});

  /// Stands in for the web view in widget tests and sample renders.
  @visibleForTesting
  static WidgetBuilder? debugStandIn;

  static final _onScreen = <_AuthCaptchaBoxState>[];

  /// The check on the screen in front, if that screen carries one.
  static CaptchaTokens? get inFront =>
      _onScreen.isEmpty ? null : _onScreen.last._tokens;

  @override
  State<AuthCaptchaBox> createState() => _AuthCaptchaBoxState();
}

class _AuthCaptchaBoxState extends State<AuthCaptchaBox> {
  WebViewController? _web;
  Uri? _page;
  late final _tokens = CaptchaTokens(
    startOver: () {
      final page = _page;
      if (page != null) {
        unawaited(_web?.loadRequest(page).catchError((_) {}));
      }
    },
  );

  @override
  void initState() {
    super.initState();
    final page = Uri.tryParse('${AppConfig.authCaptchaUrl}-inline');
    if (AppConfig.authCaptchaUrl.isEmpty ||
        page == null ||
        !page.isScheme('https')) {
      return;
    }
    _page = page;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        // The name captcha-inline.js on the website posts to.
        'ArangCaptcha',
        onMessageReceived: (message) => _tokens.onMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              request.isMainFrame && request.url != page.toString()
              ? NavigationDecision.prevent
              : NavigationDecision.navigate,
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) _tokens.pageFailed();
          },
        ),
      )
      ..loadRequest(page);
    _tokens.addListener(_opened);
    AuthCaptchaBox._onScreen.add(this);
  }

  @override
  void dispose() {
    AuthCaptchaBox._onScreen.remove(this);
    _tokens.dispose();
    super.dispose();
  }

  void _opened() {
    if (!mounted) return;
    setState(() {});
    if (_tokens.openHeight == null) return;
    // It may have opened below the fold while the keyboard is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final standIn = AuthCaptchaBox.debugStandIn;
    if (standIn != null) return standIn(context);
    final web = _web;
    if (web == null) return const SizedBox.shrink();
    return CaptchaSlotLayout(
      open: _tokens.openHeight,
      child: WebViewWidget(controller: web),
    );
  }
}

/// Where the check sits in a screen: a sliver while shut, and while a tap is
/// wanted, Cloudflare's box with a line above it saying what to do. The box
/// itself says "Verify you are human" in English and nothing else.
@visibleForTesting
class CaptchaSlotLayout extends StatelessWidget {
  const CaptchaSlotLayout({required this.open, required this.child, super.key});

  /// How tall Cloudflare's box is while it wants a tap; null while shut.
  final double? open;
  final Widget child;

  // Room for Cloudflare's taller, compact box and the page's margins.
  static const _pageHeight = 160.0;
  static const _pageMargin = 8.0;

  @override
  Widget build(BuildContext context) {
    final open = this.open;
    return Padding(
      padding: EdgeInsets.only(top: open == null ? 0 : AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (open != null)
            // Read out when it appears: it arrives without being asked for.
            Semantics(
              liveRegion: true,
              child: Padding(
                // Starts where Cloudflare's box does: the check page draws
                // it this far in.
                padding: const EdgeInsets.fromLTRB(
                  _pageMargin,
                  0,
                  _pageMargin,
                  AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'I-tap ang kahon para magpatuloy.',
                      style: AppTypography.bodySm,
                    ),
                    Text(
                      'Tap the box to continue.',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // The page keeps its full size while shut, so it goes on running;
          // only a sliver of it takes up room.
          SizedBox(
            height: open ?? 1,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: _pageHeight,
                maxHeight: _pageHeight,
                // Shut, the page is still there at full size under the clip.
                // A screen reader must not find a box nobody can see.
                child: ExcludeSemantics(excluding: open == null, child: child),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthCaptchaDialog extends StatefulWidget {
  const _AuthCaptchaDialog(this.page);

  final Uri page;

  @override
  State<_AuthCaptchaDialog> createState() => _AuthCaptchaDialogState();
}

class _AuthCaptchaDialogState extends State<_AuthCaptchaDialog> {
  late final WebViewController _web;
  late final Timer _giveUp;
  bool _failed = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        // The name captcha.js on the website posts the token to.
        'ArangCaptcha',
        onMessageReceived: (message) => _close(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          // The view shows the check page and nothing else.
          onNavigationRequest: (request) =>
              request.isMainFrame && request.url != widget.page.toString()
              ? NavigationDecision.prevent
              : NavigationDecision.navigate,
          onWebResourceError: (error) {
            if ((error.isForMainFrame ?? false) && mounted) {
              setState(() => _failed = true);
            }
          },
        ),
      )
      ..loadRequest(widget.page);
    _giveUp = Timer(const Duration(minutes: 2), () => _close(null));
  }

  @override
  void dispose() {
    _giveUp.cancel();
    super.dispose();
  }

  void _close(String? token) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(token == null || token.isEmpty ? null : token);
  }

  @override
  Widget build(BuildContext context) => ArangDialog(
    title: 'Security check',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _failed
              ? 'The check could not load. Check your connection and try '
                    'again.'
              : 'One moment. If a box appears, tap it.',
        ),
        if (!_failed) ...[
          const SizedBox(height: 12),
          // Turnstile compact is 150x140 CSS pixels, plus the page margins.
          Center(
            child: SizedBox(
              width: 180,
              height: 164,
              child: WebViewWidget(controller: _web),
            ),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(onPressed: () => _close(null), child: const Text('Cancel')),
    ],
  );
}
