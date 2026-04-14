/* ── Main Entry — imports all CSS modules ──────────────────────────── */
import './css/tokens.css';
import './css/base.css';
import './css/components.css';
import './css/animations.css';
import './css/pages.css';

/* ═══════════════════════════════════════════════════════════════════════
   Cool Website — Main JavaScript
   ═══════════════════════════════════════════════════════════════════════ */

/**
 * Scroll-triggered reveal animations (Intersection Observer).
 * Elements with data-reveal are observed; when they enter
 * the viewport they receive the .is-visible class.
 */
function initScrollReveal() {
  const reveals = document.querySelectorAll('[data-reveal]');
  if (!reveals.length) return;

  const prefersReduced = window.matchMedia(
    '(prefers-reduced-motion: reduce)'
  ).matches;

  if (prefersReduced) {
    reveals.forEach((el) => el.classList.add('is-visible'));
    return;
  }

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12, rootMargin: '0px 0px -40px 0px' }
  );

  reveals.forEach((el) => observer.observe(el));
}

/**
 * Animated number counters.
 * Elements with data-count-to="<number>" animate from 0 to that number.
 */
function initCounters() {
  const counters = document.querySelectorAll('[data-count-to]');
  if (!counters.length) return;

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          const el = entry.target;
          const target = parseInt(el.getAttribute('data-count-to'), 10);
          const suffix = el.getAttribute('data-count-suffix') || '';
          const prefix = el.getAttribute('data-count-prefix') || '';
          const duration = 2000;
          const start = performance.now();

          function step(now) {
            const elapsed = now - start;
            const progress = Math.min(elapsed / duration, 1);
            const eased = 1 - Math.pow(1 - progress, 4); // ease-out quart
            const current = Math.round(eased * target);
            el.textContent = prefix + current.toLocaleString() + suffix;
            if (progress < 1) requestAnimationFrame(step);
          }

          requestAnimationFrame(step);
          observer.unobserve(el);
        }
      });
    },
    { threshold: 0.5 }
  );

  counters.forEach((el) => observer.observe(el));
}

/**
 * Sticky nav scroll detection
 */
function initNavScroll() {
  const nav = document.querySelector('.nav');
  if (!nav) return;

  function onScroll() {
    nav.classList.toggle('nav--scrolled', window.scrollY > 40);
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
}

/**
 * Mobile nav drawer toggle
 */
function initMobileNav() {
  const toggle = document.getElementById('nav-toggle');
  const drawer = document.getElementById('nav-drawer');
  if (!toggle || !drawer) return;

  function closeDrawer() {
    drawer.classList.remove('is-open');
    toggle.setAttribute('aria-expanded', 'false');
    const iconOpen = toggle.querySelector('.icon-menu');
    const iconClose = toggle.querySelector('.icon-close');
    if (iconOpen) iconOpen.style.display = 'block';
    if (iconClose) iconClose.style.display = 'none';
    document.body.style.overflow = '';
  }

  function openDrawer() {
    drawer.classList.add('is-open');
    toggle.setAttribute('aria-expanded', 'true');
    const iconOpen = toggle.querySelector('.icon-menu');
    const iconClose = toggle.querySelector('.icon-close');
    if (iconOpen) iconOpen.style.display = 'none';
    if (iconClose) iconClose.style.display = 'block';
    document.body.style.overflow = 'hidden';
  }

  toggle.addEventListener('click', () => {
    drawer.classList.contains('is-open') ? closeDrawer() : openDrawer();
  });

  // Close on link click
  drawer.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', closeDrawer);
  });

  // Close on Escape key
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && drawer.classList.contains('is-open')) {
      closeDrawer();
      toggle.focus();
    }
  });

  // Close on outside click
  document.addEventListener('click', (e) => {
    if (drawer.classList.contains('is-open') &&
        !drawer.contains(e.target) &&
        !toggle.contains(e.target)) {
      closeDrawer();
    }
  });
}

/**
 * Smooth scroll for same-page anchor links
 */
function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener('click', (e) => {
      const target = document.querySelector(anchor.getAttribute('href'));
      if (!target) return;
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });
}

/**
 * Scroll-to-top button — appears after scrolling down 500px
 */
function initScrollToTop() {
  const btn = document.getElementById('scroll-top');
  if (!btn) return;

  function onScroll() {
    btn.classList.toggle('is-visible', window.scrollY > 500);
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  btn.addEventListener('click', () => {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });
}

/* ── Init on DOM ready ──────────────────────────────────────────────── */
document.addEventListener('DOMContentLoaded', () => {
  initNavScroll();
  initMobileNav();
  initScrollReveal();
  initCounters();
  initSmoothScroll();
  initScrollToTop();
});
