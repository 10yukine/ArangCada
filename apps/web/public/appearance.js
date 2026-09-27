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
    // Long legal tables of contents start collapsed on phones.
    if (matchMedia('(max-width: 760px)').matches) document.querySelectorAll('details.legal-nav').forEach(d => { d.open = false; });
    document.querySelectorAll('[data-print]').forEach(button => button.addEventListener('click', () => window.print()));
    // Contents: mark the section currently being read.
    const links = [...document.querySelectorAll('.legal-nav a[href^="#"]')];
    const sections = links.map(link => document.getElementById(decodeURIComponent(link.hash.slice(1)))).filter(Boolean);
    if (sections.length && 'IntersectionObserver' in window) {
      const mark = id => links.forEach(link => link.setAttribute('aria-current', link.hash.slice(1) === id ? 'true' : 'false'));
      const observer = new IntersectionObserver(entries => {
        const visible = entries.filter(entry => entry.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        if (visible.length) mark(visible[0].target.id);
      }, { rootMargin: '-90px 0px -70% 0px' });
      sections.forEach(section => observer.observe(section));
    }
    const controls = [...document.querySelectorAll('[data-appearance]')];
    const updateControls = () => controls.forEach(select => {
      select.value = preference;
      select.parentElement.dataset.mode = preference;
      select.title = 'Appearance: ' + preference;
    });
    updateControls();
    controls.forEach(select => {
      select.addEventListener('change', () => {
        preference = choices.includes(select.value) ? select.value : 'system';
        apply(preference);
        try { localStorage.setItem('arangcada-appearance', preference); } catch (_) {}
        updateControls();
      });
    });
  });
})();
