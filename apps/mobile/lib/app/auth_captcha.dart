import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/app_config.dart';
import '../core/widgets/arang_dialog.dart';
import 'router.dart';

/// Runs the human check Supabase Auth asks for before a sign-in, sign-up or
/// reset request, and answers with its single-use token.
///
/// Cloudflare Turnstile has no Android SDK; it runs on a web page, so the
/// check is a small web view over whatever screen is showing. Usually it
/// passes without a tap.
///
/// Null only when this build has no check page. A configured check must
/// finish before sending an Auth request, even before server enforcement.
Future<String?> authCaptchaToken() async {
  if (AppConfig.authCaptchaUrl.isEmpty) return null;
  final page = Uri.tryParse(AppConfig.authCaptchaUrl);
  final context = rootNavigatorKey.currentContext;
  if (page == null || !page.isScheme('https') || context == null) {
    throw const AuthException(
      'Security check unavailable',
      code: 'captcha_failed',
    );
  }
  final token = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AuthCaptchaDialog(page),
  );
  if (token == null || token.isEmpty) {
    throw const AuthException(
      'Security check incomplete',
      code: 'captcha_failed',
    );
  }
  return token;
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
          SizedBox(
            width: 180,
            height: 164,
            child: WebViewWidget(controller: _web),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(onPressed: () => _close(null), child: const Text('Cancel')),
    ],
  );
}
