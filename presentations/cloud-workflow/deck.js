(() => {
  const deck = document.querySelector('.deck');
  const slides = [...document.querySelectorAll('section.slide')];
  const lastSteps = slides.map((slide) => Math.max(0, ...[...slide.querySelectorAll('[data-step]')].map((el) => +el.dataset.step)));
  const presenter = new URLSearchParams(location.search).has('presenter');
  let at = { slide: -1, step: 0 };
  let audience = null;

  addArrowheads();

  function fit() {
    const s = Math.min(innerWidth / 1920, innerHeight / 1080);
    deck.style.setProperty('--fit', s);
  }

  function place(slide, step) {
    slide = Math.max(0, Math.min(slides.length - 1, slide));
    return { slide, step: Math.max(0, Math.min(lastSteps[slide], step)) };
  }

  function placeFromHash() {
    const [n, s] = location.hash.slice(1).split('.').map((x) => parseInt(x, 10));
    return place(Number.isFinite(n) ? n - 1 : 0, Number.isFinite(s) ? s : 0);
  }

  function reveal(slide, step) {
    for (const el of slide.querySelectorAll('[data-step]')) el.classList.toggle('on', +el.dataset.step <= step);
  }

  function go(target, { broadcast = true } = {}) {
    const { slide, step } = place(target.slide, target.step);
    if (slide === at.slide && step === at.step) return;
    const el = slides[slide];
    // Only a forward step on the same slide animates. Hiding, and arriving on a slide at any step, is instant.
    const animate = slide === at.slide && step > at.step;
    if (!animate) el.classList.add('instant');
    reveal(el, step);
    if (!animate) {
      void el.offsetWidth;
      el.classList.remove('instant');
    }
    if (slide !== at.slide) slides.forEach((s, k) => s.classList.toggle('active', k === slide));
    at = { slide, step };
    history.replaceState(null, '', `${location.pathname}${location.search}#${slide + 1}${step ? `.${step}` : ''}`);
    if (presenter) renderPresenter();
    if (!broadcast) return;
    const msg = { deckSlide: slide, deckStep: step };
    if (audience && !audience.closed) audience.postMessage(msg, '*');
    if (window.opener && !presenter) window.opener.postMessage(msg, '*');
  }

  function following({ slide, step }) {
    if (step < lastSteps[slide]) return { slide, step: step + 1 };
    if (slide < slides.length - 1) return { slide: slide + 1, step: 0 };
    return null;
  }

  function preceding({ slide, step }) {
    if (step > 0) return { slide, step: step - 1 };
    if (slide > 0) return { slide: slide - 1, step: lastSteps[slide - 1] };
    return null;
  }

  addEventListener('keydown', (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const next = ['ArrowRight', 'ArrowDown', 'PageDown', ' ', 'Enter'];
    const prev = ['ArrowLeft', 'ArrowUp', 'PageUp', 'Backspace'];
    let target;
    if (next.includes(e.key)) target = following(at);
    else if (prev.includes(e.key)) target = preceding(at);
    else if (e.key === 'Home') target = { slide: 0, step: 0 };
    else if (e.key === 'End') target = { slide: slides.length - 1, step: lastSteps[slides.length - 1] };
    else if (e.key === 'f' || e.key === 'F') toggleFullscreen();
    else return;
    e.preventDefault();
    if (target) go(target);
  });
  addEventListener('hashchange', () => go(placeFromHash()));
  addEventListener('message', (e) => {
    if (typeof e.data?.deckSlide !== 'number') return;
    // A reloaded presenter has lost its window handle; the audience's next key press hands it back.
    if (presenter) audience = e.source;
    go({ slide: e.data.deckSlide, step: e.data.deckStep ?? 0 }, { broadcast: false });
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
      // The head draws after the shaft: shaft 240 ms, head 120 ms, 360 ms in all.
      const d = parseInt(getComputedStyle(path).getPropertyValue('--d') || '0', 10);
      head.style.setProperty('--d', `${d + 240}ms`);
      head.style.setProperty('--dur', '120ms');
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
        <span class="title"></span>
        <button type="button" data-open>Open audience window</button>
        <span class="hint">Arrows, Space, or a clicker drive both windows. Press F in the audience window for fullscreen.</span>
        <span class="clock" title="Click to reset">0:00</span>
      </header>
      <div class="p-slides">
        <div class="p-now"><div class="label">Now</div><div class="frame"></div></div>
        <div class="p-next"><div class="label">Next</div><div class="frame"></div></div>
      </div>
      <div class="p-notes"><div class="label">Notes</div><div data-presenter-notes></div></div>`;
    document.body.append(ui);
    ui.querySelector('[data-open]').addEventListener('click', () => {
      audience = window.open(`${location.pathname}${location.hash}`, 'deck-audience');
    });
    const clock = ui.querySelector('.clock');
    clock.addEventListener('click', () => { startedAt = Date.now(); });
    setInterval(() => {
      const s = Math.floor((Date.now() - startedAt) / 1000);
      clock.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
    }, 500);
    addEventListener('resize', renderPresenter);
  }

  function mount(frame, state) {
    frame.replaceChildren();
    frame.classList.toggle('empty', !state);
    if (!state) return;
    const copy = slides[state.slide].cloneNode(true);
    copy.classList.add('active');
    copy.querySelector('aside.notes')?.remove();
    reveal(copy, state.step);
    copy.style.transform = `scale(${frame.clientWidth / 1920})`;
    frame.append(copy);
  }

  function renderPresenter() {
    if (!ui) return;
    const [now, next] = ui.querySelectorAll('.frame');
    mount(now, at);
    mount(next, following(at));
    ui.querySelector('.count').textContent = `slide ${at.slide + 1} / ${slides.length}  ·  step ${at.step} / ${lastSteps[at.slide]}`;
    ui.querySelector('.title').textContent = slides[at.slide].dataset.title;
    const notes = slides[at.slide].querySelector('aside.notes');
    ui.querySelector('[data-presenter-notes]').innerHTML = notes ? notes.innerHTML : '';
  }

  if (presenter) buildPresenter();
  fit();
  addEventListener('resize', fit);
  go(placeFromHash(), { broadcast: false });
})();
