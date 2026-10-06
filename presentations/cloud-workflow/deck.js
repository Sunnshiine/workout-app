(() => {
  const deck = document.querySelector('.deck');
  const slides = [...document.querySelectorAll('section.slide')];
  const presenter = new URLSearchParams(location.search).has('presenter');
  let current = -1;
  let audience = null;

  addArrowheads();

  function fit() {
    const s = Math.min(innerWidth / 1920, innerHeight / 1080);
    deck.style.setProperty('--fit', s);
  }

  function indexFromHash() {
    const n = parseInt(location.hash.slice(1), 10);
    return Number.isFinite(n) ? clamp(n - 1) : 0;
  }

  function clamp(i) {
    return Math.max(0, Math.min(slides.length - 1, i));
  }

  function go(i, { broadcast = true } = {}) {
    i = clamp(i);
    if (i === current) return;
    current = i;
    slides.forEach((s, k) => s.classList.toggle('active', k === i));
    history.replaceState(null, '', `${location.pathname}${location.search}#${i + 1}`);
    if (presenter) renderPresenter();
    if (!broadcast) return;
    const msg = { deckSlide: i };
    if (audience && !audience.closed) audience.postMessage(msg, '*');
    if (window.opener && !presenter) window.opener.postMessage(msg, '*');
  }

  addEventListener('keydown', (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const next = ['ArrowRight', 'ArrowDown', 'PageDown', ' ', 'Enter'];
    const prev = ['ArrowLeft', 'ArrowUp', 'PageUp', 'Backspace'];
    if (next.includes(e.key)) go(current + 1);
    else if (prev.includes(e.key)) go(current - 1);
    else if (e.key === 'Home') go(0);
    else if (e.key === 'End') go(slides.length - 1);
    else if (e.key === 'f' || e.key === 'F') toggleFullscreen();
    else return;
    e.preventDefault();
  });
  addEventListener('hashchange', () => go(indexFromHash()));
  addEventListener('message', (e) => {
    if (typeof e.data?.deckSlide !== 'number') return;
    // A reloaded presenter has lost its window handle; the audience's next key press hands it back.
    if (presenter) audience = e.source;
    go(e.data.deckSlide, { broadcast: false });
  });

  function toggleFullscreen() {
    if (document.fullscreenElement) document.exitFullscreen();
    else document.documentElement.requestFullscreen?.();
  }

  function addArrowheads() {
    for (const path of document.querySelectorAll('path[data-arrow]')) {
      const len = path.getTotalLength();
      const tip = path.getPointAtLength(len);
      const back = path.getPointAtLength(len - 12);
      const a = Math.atan2(tip.y - back.y, tip.x - back.x);
      const size = +path.dataset.arrow || 22;
      const wing = (t) => `${tip.x - size * Math.cos(a + t)} ${tip.y - size * Math.sin(a + t)}`;
      const head = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      head.setAttribute('d', `M${wing(0.5)} L${tip.x} ${tip.y} L${wing(-0.5)}`);
      head.setAttribute('pathLength', '1');
      for (const attr of ['class', 'stroke', 'stroke-width', 'style']) {
        if (path.hasAttribute(attr)) head.setAttribute(attr, path.getAttribute(attr));
      }
      const d = parseInt(path.style.getPropertyValue('--d') || '0', 10);
      head.style.setProperty('--d', `${d + 240}ms`);
      head.style.setProperty('animation-duration', '120ms');
      path.after(head);
    }
  }

  let ui;
  let startedAt = Date.now();

  function buildPresenter() {
    document.body.classList.add('presenter');
    ui = document.createElement('div');
    ui.className = 'presenter-ui';
    ui.innerHTML = `
      <header>
        <span class="count"></span>
        <button type="button" data-open>Open audience window</button>
        <span>Arrows, Space, or a clicker drive both windows. Press F in the audience window for fullscreen.</span>
        <span class="clock" title="Click to reset">0:00</span>
      </header>
      <div class="p-slides">
        <div class="p-now"><div class="label">Now</div><div class="frame"></div></div>
        <div class="p-next"><div class="label">Next</div><div class="frame"></div></div>
      </div>
      <div class="p-notes"><div class="label">Notes</div><div data-presenter-notes></div></div>`;
    document.body.append(ui);
    ui.querySelector('[data-open]').addEventListener('click', () => {
      audience = window.open(`${location.pathname}#${current + 1}`, 'deck-audience');
    });
    const clock = ui.querySelector('.clock');
    clock.addEventListener('click', () => { startedAt = Date.now(); });
    setInterval(() => {
      const s = Math.floor((Date.now() - startedAt) / 1000);
      clock.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
    }, 500);
    addEventListener('resize', renderPresenter);
  }

  function mount(frame, slide) {
    frame.replaceChildren();
    frame.classList.toggle('empty', !slide);
    if (!slide) return;
    const copy = slide.cloneNode(true);
    copy.classList.add('active');
    copy.querySelector('aside.notes')?.remove();
    copy.style.transform = `scale(${frame.clientWidth / 1920})`;
    frame.append(copy);
  }

  function renderPresenter() {
    if (!ui) return;
    const [now, next] = ui.querySelectorAll('.frame');
    mount(now, slides[current]);
    mount(next, slides[current + 1]);
    ui.querySelector('.count').textContent = `${current + 1} / ${slides.length}  ·  ${slides[current].dataset.title}`;
    const notes = slides[current].querySelector('aside.notes');
    ui.querySelector('[data-presenter-notes]').innerHTML = notes ? notes.innerHTML : '';
  }

  if (presenter) buildPresenter();
  fit();
  addEventListener('resize', fit);
  go(indexFromHash(), { broadcast: false });
})();
