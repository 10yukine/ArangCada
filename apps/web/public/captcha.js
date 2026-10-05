// The security check the ArangCada app shows before it signs someone in.
// Kept in its own file so the site's Content-Security-Policy can refuse every
// inline script. Turnstile calls these by name when the check ends; the app
// listens on the ArangCaptcha channel. In an ordinary browser there is no
// such channel and the token goes nowhere.
window.captchaDone = (token) => window.ArangCaptcha?.postMessage(token);
window.captchaFailed = () => {
  window.ArangCaptcha?.postMessage('');
  return true; // handled; Turnstile need not log it as well
};
