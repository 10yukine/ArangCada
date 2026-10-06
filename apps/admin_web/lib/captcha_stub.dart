/// Outside a browser there is no Turnstile; see captcha_web.dart.
Future<String?> turnstileToken(String siteKey) async => null;

/// See captcha_web.dart.
void setCaptchaHost(
  Object? element, {
  bool dark = false,
  void Function(bool open)? onOpen,
}) {}
