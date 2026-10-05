// The confirm-email page. Kept in its own file so the site's
// Content-Security-Policy can refuse every inline script.
(() => {
  const button = document.getElementById('confirm-button');
  const status = document.getElementById('confirm-status');
  const say = (text, tone = 'error') => { status.textContent = text; status.dataset.tone = tone; };
  const token = new URLSearchParams(window.location.search).get('token') || '';
  if (!token) {
    button.hidden = true;
    say('This link is incomplete. Open the link in your email again, or ask for a new one in the app.');
    return;
  }
  // The token is redeemed on a button press, not on page load: mail scanners
  // open links to check them, and that must not use the link up.
  button.addEventListener('click', async () => {
    button.disabled = true;
    say('Confirming your email…', 'info');
    try {
      const response = await fetch('https://zzcqyhtizvkuhrpfneth.supabase.co/functions/v1/confirm-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token }),
      });
      const result = await response.json().catch(() => ({}));
      if (response.ok) {
        button.hidden = true;
        say('Your email is confirmed. You can go back to the app.', 'info');
        return;
      }
      say(result.error || 'The email could not be confirmed. Try again later.');
    } catch (_) {
      say('Could not reach ArangCada. Check your connection and try again.');
    }
    button.disabled = false;
  });
})();
