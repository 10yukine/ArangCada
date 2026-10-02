// The delete-account form. Kept in its own file so the site's
// Content-Security-Policy can refuse every inline script.
(() => {
  const form = document.getElementById('delete-form');
  const button = document.getElementById('delete-button');
  const status = document.getElementById('delete-status');
  const show = document.getElementById('show-password');
  show.addEventListener('click', () => {
    const hidden = form.password.type === 'password';
    form.password.type = hidden ? 'text' : 'password';
    show.textContent = hidden ? 'Hide' : 'Show';
    show.setAttribute('aria-pressed', String(hidden));
  });
  const say = (text, tone = 'error') => { status.textContent = text; status.dataset.tone = tone; };
  // Each error sits under its own field and is tied to it for screen readers.
  const setError = (input, text) => {
    const error = document.getElementById(`${input.id}-error`);
    error.textContent = text || '';
    error.hidden = !text;
    if (text) input.setAttribute('aria-invalid', 'true'); else input.removeAttribute('aria-invalid');
  };
  for (const input of [form.identifier, form.password, form.confirm]) {
    input.addEventListener(input.type === 'checkbox' ? 'change' : 'input', () => setError(input, ''));
  }
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    say('');
    const identifier = form.identifier.value.trim();
    const password = form.password.value;
    setError(form.identifier, identifier ? '' : 'Enter your email or mobile number');
    setError(form.password, password ? '' : 'Enter your password');
    setError(form.confirm, form.confirm.checked ? '' : 'Tick the box to confirm');
    const invalid = form.querySelector('[aria-invalid="true"]');
    if (invalid) return void invalid.focus();
    const turnstile = form.querySelector('[name="cf-turnstile-response"]')?.value;
    if (!turnstile) return void say('Wait for the security check to finish, then try again.');
    button.disabled = true;
    say('Deleting your account…', 'info');
    try {
      const response = await fetch('https://zzcqyhtizvkuhrpfneth.supabase.co/functions/v1/account-deletion', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ identifier, password, turnstile }),
      });
      const result = await response.json().catch(() => ({}));
      if (response.ok) {
        form.replaceChildren(Object.assign(document.createElement('p'), { className: 'delete-done', textContent: 'Your account was deleted. You can close this page.' }));
        return;
      }
      const message = result.error || 'Your account could not be deleted. Try again later.';
      // A failed sign-in never says which part was wrong; the password is the usual fix.
      if (response.status === 401) {
        say('');
        setError(form.password, message);
        form.password.focus();
      } else {
        say(message);
      }
    } catch (_) {
      say('Could not reach ArangCada. Check your connection and try again.');
    }
    form.password.value = '';
    window.turnstile?.reset();
    button.disabled = false;
  });
})();
