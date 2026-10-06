// The security check inside the ArangCada app's sign-in screens. Kept in its
// own file so the site's Content-Security-Policy can refuse every inline
// script. The app listens on the ArangCaptcha channel; in an ordinary browser
// there is no such channel and nothing is sent anywhere.
//
// It stays out of sight while Cloudflare can decide by itself. The app is told
// when a tap is wanted, and how tall to open, and when it no longer is.
(() => {
  const say = (message) => window.ArangCaptcha?.postMessage(message);
  let widget;

  window.captchaReady = () => {
    const box = document.getElementById('check');
    // Cloudflare's wide box needs 300 px; a narrower phone gets the compact one.
    const compact = box.clientWidth < 300;
    widget = window.turnstile.render(box, {
      sitekey: box.dataset.sitekey,
      action: 'sign-in',
      theme: 'light',
      size: compact ? 'compact' : 'flexible',
      appearance: 'interaction-only',
      callback: (token) => say('token:' + token),
      'expired-callback': () => say('expired'),
      'error-callback': () => {
        say('failed');
        return true; // handled; Turnstile need not log it as well
      },
      // Heights are Cloudflare's box plus this page's 8 px margins.
      'before-interactive-callback': () => say('interactive:' + (compact ? 156 : 81)),
      'after-interactive-callback': () => say('idle'),
    });
  };

  // A token works once, so the app asks for another after spending one.
  window.captchaAgain = () => {
    if (widget !== undefined) window.turnstile.reset(widget);
  };
})();
