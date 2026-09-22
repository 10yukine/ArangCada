(() => {
  const choices = ['system', 'light', 'dark'];
  let preference = 'system';
  try { preference = localStorage.getItem('arangcada-appearance') || 'system'; } catch (_) {}
  if (!choices.includes(preference)) preference = 'system';
  const apply = value => {
    if (value === 'system') delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = value;
  };
  apply(preference);
  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('[data-appearance]').forEach(select => {
      select.value = preference;
      select.addEventListener('change', () => {
        preference = choices.includes(select.value) ? select.value : 'system';
        apply(preference);
        try { localStorage.setItem('arangcada-appearance', preference); } catch (_) {}
        document.querySelectorAll('[data-appearance]').forEach(control => { control.value = preference; });
      });
    });
  });
})();
