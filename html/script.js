let hideTimer = null;

function getEls() {
  const wrap = document.getElementById('wrap');
  const t    = document.querySelector('.title');
  const s    = document.querySelector('.subtitle');
  return { wrap, t, s };
}

function forceHide() {
  const { wrap } = getEls();
  if (!wrap) return;

  if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }

  // sfuma via
  wrap.classList.remove('show');

  // a transizione conclusa, rimetti display:none
  const onEnd = () => {
    wrap.classList.add('hidden');
    wrap.removeEventListener('transitionend', onEnd);
  };
  wrap.addEventListener('transitionend', onEnd, { once: true });

  // fallback nel caso l'evento non arrivasse (raro)
  setTimeout(() => wrap.classList.add('hidden'), 400);
}

function showBanner(title, subtitle, duration) {
  const { wrap, t, s } = getEls();
  if (!wrap || !t || !s) return;

  // testi
  t.textContent = (title ?? '').toString().trim().toUpperCase();
  s.textContent = (subtitle ?? '').toString();

  // durata "safe"
  const n = Number(duration);
  const finalDur = Number.isFinite(n) && n > 0 ? n : 6000;

  // reset timer precedente
  if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }

  // mostra + innesca transizione
  wrap.classList.remove('hidden');
  // forziamo un reflow o usiamo RAF per essere sicuri che la transizione parta
  requestAnimationFrame(() => wrap.classList.add('show'));

  // auto-hide
  hideTimer = setTimeout(() => {
    hideTimer = null;
    forceHide();
  }, finalDur);
}

// NUI messages
window.addEventListener('message', (e) => {
  const data = e.data || {};
  if (data.action === 'showAnnouncement') {
    showBanner(data.title, data.subtitle, data.duration);
  } else if (data.action === 'hideAnnouncement') {
    forceHide();
  }
});

// Stato iniziale: nascondi subito se la pagina è già caricata
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', forceHide, { once: true });
} else {
  forceHide();
}
