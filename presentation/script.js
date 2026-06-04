/* =================================================================
   Deck interactions — vanilla, no deps.
   · builds the section rail from [data-label]
   · scroll progress bar + active-section tracking
   · IntersectionObserver reveals (+ count-ups)
   · keyboard navigation (arrows / space / digits / home / end)
   · the Ralph ring auto-advances its lit stage while in view
   ================================================================= */
(function () {
  "use strict";

  var slides = Array.prototype.slice.call(document.querySelectorAll(".slide"));
  var rail = document.getElementById("rail");
  var progress = document.getElementById("progress");
  var current = -1;

  /* ---------- build the rail ---------- */
  slides.forEach(function (slide, i) {
    var btn = document.createElement("button");
    btn.innerHTML = '<span class="dot"></span><span class="label">' +
      (slide.getAttribute("data-label") || slide.id) + "</span>";
    btn.setAttribute("aria-label", "Go to " + (slide.getAttribute("data-label") || slide.id));
    btn.addEventListener("click", function () { goTo(i); });
    rail.appendChild(btn);
  });
  var dots = Array.prototype.slice.call(rail.querySelectorAll("button"));

  function setActive(i) {
    if (i === current) return;
    current = i;
    dots.forEach(function (d, j) { d.classList.toggle("active", j === i); });
  }
  function goTo(i) {
    i = Math.max(0, Math.min(slides.length - 1, i));
    slides[i].scrollIntoView({ behavior: "smooth", block: "start" });
  }

  /* ---------- scroll progress ---------- */
  function onScroll() {
    var h = document.documentElement;
    var max = h.scrollHeight - h.clientHeight;
    var pct = max > 0 ? (h.scrollTop || window.pageYOffset) / max * 100 : 0;
    progress.style.width = pct.toFixed(2) + "%";
  }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* ---------- reveals + active tracking ---------- */
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) {
        e.target.querySelectorAll(".reveal, .stagger").forEach(function (el) { el.classList.add("in"); });
        if (e.target.classList.contains("reveal") || e.target.classList.contains("stagger")) {
          e.target.classList.add("in");
        }
        runCounts(e.target);
      }
    });
  }, { threshold: 0.18 });

  // observe the reveal/stagger blocks directly so nested ones fire too
  document.querySelectorAll(".reveal, .stagger").forEach(function (el) { io.observe(el); });

  // track which slide is centered for the rail + keyboard index
  var nav = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) setActive(slides.indexOf(e.target));
    });
  }, { threshold: 0.5 });
  slides.forEach(function (s) { nav.observe(s); });

  /* ---------- count-ups ---------- */
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  function runCounts(scope) {
    scope.querySelectorAll("[data-count]").forEach(function (el) {
      if (el.dataset.done) return;
      el.dataset.done = "1";
      var target = parseFloat(el.getAttribute("data-count"));
      var suffix = el.getAttribute("data-suffix") || "";
      function fmt(n) { return Math.round(n).toLocaleString("en-US") + suffix; }
      if (reduceMotion) { el.textContent = fmt(target); return; }
      var dur = 1100, t0 = null;
      function tick(ts) {
        if (t0 === null) t0 = ts;
        var p = Math.min(1, (ts - t0) / dur);
        var eased = 1 - Math.pow(1 - p, 3);
        el.textContent = fmt(target * eased);
        if (p < 1) requestAnimationFrame(tick);
        else el.textContent = fmt(target);
      }
      requestAnimationFrame(tick);
    });
  }

  /* ---------- keyboard navigation ---------- */
  document.addEventListener("keydown", function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    var k = e.key;
    if (k === "ArrowDown" || k === "ArrowRight" || k === "PageDown" || k === " " || k === "Spacebar") {
      e.preventDefault(); goTo(current + 1);
    } else if (k === "ArrowUp" || k === "ArrowLeft" || k === "PageUp") {
      e.preventDefault(); goTo(current - 1);
    } else if (k === "Home") {
      e.preventDefault(); goTo(0);
    } else if (k === "End") {
      e.preventDefault(); goTo(slides.length - 1);
    } else if (/^[1-9]$/.test(k)) {
      e.preventDefault(); goTo(parseInt(k, 10) - 1);
    } else if (k === "0") {
      e.preventDefault(); goTo(slides.length - 1);
    }
  });

  /* ---------- Ralph ring auto-advance ---------- */
  var ring = document.getElementById("ring");
  if (ring) {
    var nodes = Array.prototype.slice.call(ring.querySelectorAll(".node"));
    var status = document.getElementById("ring-status");
    var labels = [
      "selecting issue",
      "choosing target",
      "isolating worktree",
      "implementing",
      "reviewing Swift",
      "checking pixels",
      "running gate",
      "running UI gate",
      "shipping merge",
      "cleaning up"
    ];
    var lit = 0, ringTimer = null;
    function step() {
      nodes.forEach(function (n, j) { n.classList.toggle("on", j === lit); });
      if (status) status.textContent = labels[lit] || "x every phase";
      lit = (lit + 1) % nodes.length;
    }
    var ringIO = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting && !ringTimer) {
          step(); ringTimer = setInterval(step, 620);
        } else if (!e.isIntersecting && ringTimer) {
          clearInterval(ringTimer); ringTimer = null;
        }
      });
    }, { threshold: 0.4 });
    ringIO.observe(ring);
  }

  setActive(0);
})();
