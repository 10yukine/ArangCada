import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'captcha_stub.dart' if (dart.library.js_interop) 'captcha_web.dart';

String? captchaFailureMessage(Object error) =>
    error is AuthException && error.code == 'captcha_failed'
    ? 'The security check did not finish. Please try again.'
    : null;

/// The Turnstile widget that Supabase Auth checks tokens against. Empty in a
/// build made without one, and then no token is asked for.
const turnstileSiteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');

/// A fresh, single-use token for one sign-in or reset request, or null when no
/// site key is built in or the check could not be completed.
///
/// A missing token is not an error here. Auth decides what it means: nothing
/// while CAPTCHA is off, a refusal once it is on.
Future<String?> captchaToken() => turnstileToken(turnstileSiteKey);

/// Where the human check appears on a form if Cloudflare wants a tap. It takes
/// up no room otherwise, which is nearly always.
class CaptchaSlot extends StatefulWidget {
  const CaptchaSlot({super.key});

  @override
  State<CaptchaSlot> createState() => _CaptchaSlotState();
}

class _CaptchaSlotState extends State<CaptchaSlot> {
  Object? _element;
  bool _open = false;

  void _name(bool dark) => setCaptchaHost(
    this,
    _element,
    dark: dark,
    onOpen: (open) {
      if (mounted) setState(() => _open = open);
    },
  );

  @override
  void dispose() {
    setCaptchaHost(this, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || turnstileSiteKey.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_element != null) _name(dark); // the theme may have been switched
    return Padding(
      padding: EdgeInsets.only(bottom: _open ? 16 : 0),
      child: SizedBox(
        // Cloudflare's wide box is 65 px tall.
        height: _open ? 65 : 1,
        child: HtmlElementView.fromTagName(
          tagName: 'div',
          onElementCreated: (element) {
            _element = element;
            _name(dark);
          },
        ),
      ),
    );
  }
}
