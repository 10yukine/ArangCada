(() => {
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  if (reducedMotion.matches || !('IntersectionObserver' in window)) return;

  const active = new Set();
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      observer.unobserve(entry.target);
      // Content stays visible if JS or animation support is unavailable.
      if (reducedMotion.matches || !entry.target.animate) return;
      const animation = entry.target.animate([
        { opacity: 0, transform: 'translateY(12px)' },
        { opacity: 1, transform: 'translateY(0)' },
      ], { duration: 420, easing: 'cubic-bezier(.2,.8,.2,1)' });
      active.add(animation);
      animation.onfinish = () => active.delete(animation);
    });
  }, { threshold: 0.12 });

  document.querySelectorAll('.fact, .journey-head, .steps li, .band-grid > div, .roles li, .questions > div, .project > div')
    .forEach(element => observer.observe(element));
  reducedMotion.addEventListener('change', () => {
    if (!reducedMotion.matches) return;
    observer.disconnect();
    active.forEach(animation => animation.cancel());
    active.clear();
  });
})();
