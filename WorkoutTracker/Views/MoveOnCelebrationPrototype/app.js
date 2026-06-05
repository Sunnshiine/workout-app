const session = {
  context: "Week 1 · Day 1",
  movedAt: "7:06 PM",
  firstLogAt: "6:14 PM",
  elapsed: "52 min",
  sets: "5",
  exercises: "2",
  left: "4",
  next: "Week 1 · Day 3",
  quote: "You're fucking amazing.",
  exercisesDone: [
    {
      name: "Back Squat",
      startedAt: "6:14 PM",
      logged: "2",
      total: "3",
      left: "1",
      detail: "225 x 5, RPE 8",
      note: "First Exercise started"
    },
    {
      name: "Bench Press",
      startedAt: "6:47 PM",
      logged: "1",
      total: "2",
      left: "1",
      detail: "155 x 6, RPE 7.5",
      note: "Last Set Log before Move On"
    }
  ]
};

let activeExerciseIndex = 0;
let touchStartX = null;

const variants = [
  { key: "F3", name: "Quiet Finish", render: renderQuietFinish },
  { key: "C2", name: "Workout Route", render: renderWorkoutRoute },
  { key: "E2", name: "Plate Swipe", render: renderPlateSwipe },
  { key: "F2", name: "Night Finish", render: renderNightFinish },
  { key: "H", name: "Route Stack", render: renderHybrid }
];

const app = document.querySelector("#app");
const label = document.querySelector("#variantLabel");
const previous = document.querySelector("#previousVariant");
const next = document.querySelector("#nextVariant");

function currentVariant() {
  const requested = new URLSearchParams(window.location.search).get("variant") ?? "F3";
  const normalized = requested.toUpperCase();
  const aliases = { C: "C2", E: "E2", F: "F3" };
  const key = aliases[normalized] ?? normalized;
  return variants.find((variant) => variant.key === key) ?? variants[0];
}

function setVariant(key) {
  const url = new URL(window.location.href);
  url.searchParams.set("variant", key);
  window.history.replaceState({}, "", url);
  render();
}

function cycle(offset) {
  const active = currentVariant();
  const index = variants.findIndex((variant) => variant.key === active.key);
  const nextIndex = (index + offset + variants.length) % variants.length;
  setVariant(variants[nextIndex].key);
}

function setActiveExercise(index) {
  activeExerciseIndex = (index + session.exercisesDone.length) % session.exercisesDone.length;
  render();
}

function render() {
  const variant = currentVariant();
  app.innerHTML = variant.render(session);
  label.textContent = `${variant.key} · ${variant.name}`;
  document.body.dataset.variant = variant.key;
  bindVariantInteractions();
}

previous.addEventListener("click", () => cycle(-1));
next.addEventListener("click", () => cycle(1));
window.addEventListener("popstate", render);
window.addEventListener("keydown", (event) => {
  const active = document.activeElement;
  const isEditing = active?.matches("input, textarea, [contenteditable='true']");
  if (isEditing) return;
  if (event.key === "ArrowLeft") cycle(-1);
  if (event.key === "ArrowRight") cycle(1);
});

function bindVariantInteractions() {
  document.querySelectorAll("[data-exercise-index]").forEach((button) => {
    button.addEventListener("click", () => setActiveExercise(Number(button.dataset.exerciseIndex)));
  });

  document.querySelectorAll("[data-exercise-step]").forEach((button) => {
    button.addEventListener("click", () => setActiveExercise(activeExerciseIndex + Number(button.dataset.exerciseStep)));
  });

  document.querySelectorAll(".exercise-carousel").forEach((carousel) => {
    carousel.addEventListener("touchstart", (event) => {
      touchStartX = event.touches[0]?.clientX ?? null;
    }, { passive: true });

    carousel.addEventListener("touchend", (event) => {
      if (touchStartX === null) return;
      const endX = event.changedTouches[0]?.clientX ?? touchStartX;
      const delta = endX - touchStartX;
      touchStartX = null;
      if (Math.abs(delta) < 38) return;
      setActiveExercise(activeExerciseIndex + (delta < 0 ? 1 : -1));
    }, { passive: true });
  });
}

function summaryRail(data, extraClass = "") {
  return `
    <section class="summary-rail ${extraClass}" aria-label="Session summary">
      <div><strong>${data.sets}</strong><span>Sets</span></div>
      <div><strong>${data.exercises}</strong><span>Exercises</span></div>
      <div><strong>${data.left}</strong><span>Left</span></div>
    </section>
  `;
}

function timingStrip(data, extraClass = "") {
  return `
    <section class="timing-strip ${extraClass}" aria-label="Session timing">
      <div><span>Started</span><strong>${data.firstLogAt}</strong></div>
      <div><span>Elapsed</span><strong>${data.elapsed}</strong></div>
      <div><span>Moved On</span><strong>${data.movedAt}</strong></div>
    </section>
  `;
}

function timeRange(data, extraClass = "") {
  return `
    <section class="time-range ${extraClass}" aria-label="Session time range">
      <span>${data.firstLogAt}</span>
      <i aria-hidden="true">→</i>
      <span>${data.movedAt}</span>
    </section>
  `;
}

function renderWorkoutRoute(data) {
  const routeItems = [
    { tone: "start", label: "First Set Log", value: data.firstLogAt, meta: "Session opened" },
    ...data.exercisesDone.map((exercise) => ({
      tone: "done",
      label: exercise.name,
      value: `${exercise.logged} of ${exercise.total} Sets`,
      meta: `Started ${exercise.startedAt}`
    })),
    { tone: "move", label: "Move On", value: data.movedAt, meta: data.next }
  ];

  return `
    <article class="screen screen-route">
      <header class="topline">
        <div class="mini-mark">TFN</div>
        <p class="context">${data.context}</p>
      </header>
      <section class="route-intro">
        <h1>The whole Session, closed enough to move.</h1>
        <p>Every Exercise stays visible. Logged work lands first, open Sets stay counted.</p>
      </section>
      <section class="workout-map" aria-label="Completed Session route">
        <div class="route-spine"></div>
        ${routeItems.map((item, index) => `
          <article class="route-node ${item.tone}" style="--i: ${index}">
            <span class="node-dot">${index + 1}</span>
            <div>
              <strong>${item.label}</strong>
              <span>${item.value}</span>
              <em>${item.meta}</em>
            </div>
          </article>
        `).join("")}
      </section>
      ${summaryRail(data, "route-summary")}
      <p class="continue">Tap anywhere to continue</p>
    </article>
  `;
}

function renderPlateSwipe(data) {
  return `
    <article class="screen screen-plate-swipe">
      <header class="topline">
        <p class="context">${data.context}</p>
        <div class="elapsed-chip">${data.elapsed}</div>
      </header>
      <section class="plate-stage" aria-label="Plate Stack summary">
        <div class="bar-pin"></div>
        <div class="plate-disc plate-disc-one"><strong>${data.sets}</strong><span>Sets</span></div>
        <div class="plate-disc plate-disc-two"><strong>${data.exercises}</strong><span>Exercises</span></div>
        <div class="plate-disc plate-disc-three"><strong>${data.left}</strong><span>Left</span></div>
      </section>
      <section class="plate-copy">
        <h1>Swipe the work you moved.</h1>
        <p>Each Exercise keeps its first Set Log time, so the finish feels tied to the real Session.</p>
      </section>
      ${exerciseCarousel(data, "light")}
      ${summaryRail(data, "plate-summary")}
      <p class="continue">Tap anywhere to continue</p>
    </article>
  `;
}

function renderNightFinish(data) {
  return `
    <article class="screen screen-night-v2">
      <header class="night-header">
        <div class="night-mark"><span>TFN</span></div>
        <p class="context">${data.context}</p>
      </header>
      <section class="night-copy">
        <h1>Session moved forward.</h1>
        <p>Logged Sets are saved. The remaining Sets stay with the Week.</p>
      </section>
      ${timingStrip(data, "night-timing")}
      <section class="night-orbit" aria-label="Move On state">
        <span></span>
        <strong>Move On</strong>
        <em>${data.next}</em>
      </section>
      ${summaryRail(data, "night-summary")}
      <p class="continue">Tap anywhere to continue</p>
    </article>
  `;
}

function renderQuietFinish(data) {
  return `
    <article class="screen screen-quiet-finish">
      <header class="night-header">
        <div class="night-mark quiet-mark"><span>TFN</span></div>
        <p class="context">${data.context}</p>
      </header>
      <section class="quiet-message" aria-label="Move On message">
        <p>Move On</p>
        <h1>${data.quote}</h1>
        <span>Logged Sets are saved. Open Sets stay with the Week.</span>
      </section>
      <section class="quiet-atom" aria-label="Move On state">
        <div class="atom-core">
          <strong>${data.elapsed}</strong>
          <span>elapsed</span>
        </div>
      </section>
      ${timeRange(data, "quiet-time-range")}
      ${summaryRail(data, "night-summary quiet-summary")}
      <p class="continue">Tap anywhere to continue</p>
    </article>
  `;
}

function renderHybrid(data) {
  return `
    <article class="screen screen-hybrid">
      <header class="topline">
        <div class="mini-mark">TFN</div>
        <p class="context">${data.context}</p>
      </header>
      <section class="hybrid-hero">
        <div class="hybrid-plate" aria-hidden="true">
          <span>${data.sets}</span>
          <span>${data.exercises}</span>
          <span>${data.left}</span>
        </div>
        <div>
          <h1>${data.quote}</h1>
          <p>Started ${data.firstLogAt}. Moved On ${data.movedAt}. Open Sets stay in view.</p>
        </div>
      </section>
      <section class="mini-route" aria-label="Workout route preview">
        ${data.exercisesDone.map((exercise, index) => `
          <article style="--i: ${index}">
            <span>${index + 1}</span>
            <strong>${exercise.name}</strong>
            <em>${exercise.logged}/${exercise.total} Sets · ${exercise.startedAt}</em>
          </article>
        `).join("")}
      </section>
      ${exerciseCarousel(data, "dark")}
      ${summaryRail(data, "hybrid-summary")}
      <p class="continue">Tap anywhere to continue</p>
    </article>
  `;
}

function exerciseCarousel(data, tone) {
  const exercise = data.exercisesDone[activeExerciseIndex];

  return `
    <section class="exercise-carousel ${tone}" aria-label="Exercise cards">
      <button class="carousel-step" data-exercise-step="-1" type="button" aria-label="Previous Exercise">‹</button>
      <article class="exercise-card" key="${exercise.name}">
        <p>${exercise.note}</p>
        <h2>${exercise.name}</h2>
        <div class="exercise-meter">
          <span style="--filled: ${exercise.logged / exercise.total}"></span>
        </div>
        <dl>
          <div><dt>Started</dt><dd>${exercise.startedAt}</dd></div>
          <div><dt>Logged</dt><dd>${exercise.logged}/${exercise.total} Sets</dd></div>
          <div><dt>Last Set Log</dt><dd>${exercise.detail}</dd></div>
        </dl>
      </article>
      <button class="carousel-step" data-exercise-step="1" type="button" aria-label="Next Exercise">›</button>
      <div class="carousel-dots" aria-label="Exercise selector">
        ${data.exercisesDone.map((item, index) => `
          <button
            class="${activeExerciseIndex === index ? "active" : ""}"
            data-exercise-index="${index}"
            type="button"
            aria-label="${item.name}"
          ></button>
        `).join("")}
      </div>
    </section>
  `;
}

render();
