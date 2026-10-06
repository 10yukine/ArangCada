import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _script =
    'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';

Future<void>? _loading;

/// Adds Cloudflare's script the first time a token is needed, so the console
/// carries it only on pages that sign someone in. It cannot be pinned by hash
/// the way the other third-party scripts are: Cloudflare changes it in place.
Future<void> _load() => _loading ??= () {
  final done = Completer<void>();
  final tag = web.HTMLScriptElement()
    ..src = _script
    ..async = true;
  tag.addEventListener('load', ((web.Event _) => done.complete()).toJS);
  tag.addEventListener(
    'error',
    ((web.Event _) {
      _loading = null; // let the next attempt try again
      done.completeError(StateError('Turnstile did not load'));
    }).toJS,
  );
  web.document.head!.append(tag);
  return done.future;
}();

web.HTMLElement? _host;
bool _hostDark = false;
void Function(bool open)? _hostOpen;

/// Names the place on the form in front where the check should appear if a
/// tap is wanted (see `CaptchaSlot`), or clears it with null.
void setCaptchaHost(
  Object? element, {
  bool dark = false,
  void Function(bool open)? onOpen,
}) {
  _host = element as web.HTMLElement?;
  _hostDark = dark;
  _hostOpen = onOpen;
}

/// Runs the check and answers with its token. Nothing is shown while
/// Cloudflare can decide by itself. When it wants a tap, its box appears in
/// the form's own slot, or at the foot of the page where a form has none.
Future<String?> turnstileToken(String siteKey) async {
  if (siteKey.isEmpty) return null;
  try {
    await _load().timeout(const Duration(seconds: 15));
  } catch (_) {
    return null;
  }
  final turnstile = globalContext['turnstile'] as JSObject?;
  if (turnstile == null) return null;

  final host = _host;
  final open = _hostOpen;
  final box = web.HTMLDivElement();
  if (host == null) {
    box.style.cssText =
        'position:fixed;left:50%;bottom:24px;transform:translateX(-50%);'
        'z-index:2147483647';
    web.document.body!.append(box);
  } else {
    host.append(box);
  }
  final token = Completer<String?>();
  void finish(String? value) {
    if (!token.isCompleted) token.complete(value);
  }

  final options = JSObject()
    ..['sitekey'] = siteKey.toJS
    ..['appearance'] = 'interaction-only'.toJS
    ..['size'] = (host == null ? 'normal' : 'flexible').toJS
    ..['theme'] = (host == null ? 'auto' : (_hostDark ? 'dark' : 'light')).toJS
    ..['callback'] = ((JSString value) => finish(value.toDart)).toJS
    ..['error-callback'] = ((JSAny? _) {
      finish(null);
      return true.toJS; // handled; keeps Turnstile from logging it as well
    }).toJS
    ..['before-interactive-callback'] = (() => open?.call(true)).toJS
    ..['after-interactive-callback'] = (() => open?.call(false)).toJS;
  final widget = turnstile.callMethod<JSAny?>('render'.toJS, box, options);
  try {
    return await token.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => null,
    );
  } finally {
    open?.call(false);
    if (widget != null) turnstile.callMethod<JSAny?>('remove'.toJS, widget);
    box.remove();
  }
}
