// Phone-only reading aids (owner: the site was hard to get around on a phone).
// 1. The two-row sticky header slides away while scrolling down and returns
//    on any scroll up, so long pages get the whole screen for reading.
// 2. Long pages get a floating button: "Contents" on the legal pages (opens
//    and jumps to the table of contents), "Top" elsewhere.
(() => {
  const phone = matchMedia('(max-width: 760px)');
  const header = document.querySelector('.site-header');
  const contents = document.querySelector('details.legal-nav');

  let lastY = scrollY;
  const button = document.createElement('a');
  button.className = 'jump-button';
  button.href = contents ? '#contents' : '#main';
  button.textContent = contents ? 'Contents ↑' : 'Top ↑';
  button.addEventListener('click', event => {
    event.preventDefault();
    if (contents) contents.open = true;
    (contents || document.body).scrollIntoView({ block: 'start' });
    header?.classList.remove('header-away');
  });
  document.body.append(button);

  const update = () => {
    const y = scrollY;
    const long = document.documentElement.scrollHeight > innerHeight * 3;
    // Reading = scrolling down: header and button both step aside so neither
    // covers the text. Any scroll up brings them back.
    const reading = phone.matches && y > 120 && y > lastY;
    if (header) header.classList.toggle('header-away', reading && !header.contains(document.activeElement));
    if (y !== lastY) button.classList.toggle('show', phone.matches && long && y > innerHeight * 1.5 && !reading);
    lastY = y;
  };
  addEventListener('scroll', update, { passive: true });
  phone.addEventListener?.('change', update);
})();
