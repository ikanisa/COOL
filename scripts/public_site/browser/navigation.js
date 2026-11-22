  const homeHeader = document.querySelector('.route-home .site-header');
  const homeHero = document.querySelector('.route-home .hero');
  if (homeHeader && homeHero) {
    let headerFrame = 0;
    const syncHeader = () => {
      headerFrame = 0;
      homeHeader.classList.toggle('on-light',
        homeHero.getBoundingClientRect().bottom <= homeHeader.getBoundingClientRect().bottom);
    };
    const scheduleHeader = () => {
      if (!headerFrame) headerFrame = requestAnimationFrame(syncHeader);
    };
    window.addEventListener('scroll', scheduleHeader, { passive: true });
    window.addEventListener('resize', scheduleHeader);
    syncHeader();
  }
  const nav = document.querySelector('[data-site-nav]');
  const button = document.querySelector('[data-menu-button]');
  if (button && nav) {
    const setMenu = (open, returnFocus = false) => {
      nav.classList.toggle('open', open);
      document.body.classList.toggle('menu-open', open);
      button.setAttribute('aria-expanded', String(open));
      button.textContent = open ? 'Close' : 'Menu';
      document.querySelectorAll('main, .site-footer').forEach((element) => {
        element.inert = open;
      });
      if (open) nav.querySelector('a')?.focus();
      else if (returnFocus) button.focus();
    };
    button.addEventListener('click', () => setMenu(!nav.classList.contains('open')));
    document.addEventListener('keydown', (event) => {
      if (!nav.classList.contains('open')) return;
      if (event.key === 'Escape') {
        event.preventDefault();
        setMenu(false, true);
      }
      if (event.key === 'Tab') {
        const controls = [button, ...nav.querySelectorAll('a[href], button')];
        const first = controls[0], last = controls[controls.length - 1];
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault(); last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault(); first.focus();
        }
      }
    });
    nav.addEventListener('click', (event) => {
      if (event.target.closest('a')) setMenu(false);
    });
    window.addEventListener('resize', () => {
      if (window.innerWidth > 1100) setMenu(false);
    });
  }
  if (window.location.hash === '#/privacy') {
    window.location.replace('/privacy/');
  }
