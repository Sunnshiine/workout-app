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
    var orbitToken = document.getElementById("orbit-token");
    var orbitTokenLabel = document.getElementById("orbit-token-label");
    var consolePhase = document.getElementById("console-phase");
    var consoleHandoff = document.getElementById("console-handoff");
    var consoleArtifact = document.getElementById("console-artifact");
    var stages = [
      { phase: "SELECT", status: "selecting issue", handoff: "SELECTED_ISSUE=159", artifact: "ready-for-agent", x: "50%", y: "4%" },
      { phase: "TARGET", status: "choosing target", handoff: "TARGET_BRANCH=main", artifact: "issue contract", x: "77%", y: "12.8%" },
      { phase: "ISOLATE", status: "isolating worktree", handoff: "WORKTREE=.claude/...", artifact: "agent branch", x: "93.7%", y: "35.8%" },
      { phase: "IMPLEMENT", status: "implementing", handoff: "COMPLETE: tests run", artifact: "working diff", x: "93.7%", y: "64.2%" },
      { phase: "SWIFT REVIEW", status: "reviewing Swift", handoff: "no blocking findings", artifact: "fresh review", x: "77%", y: "87.2%" },
      { phase: "UI VERIFY", status: "checking pixels", handoff: "PASS: visual findings", artifact: "screenshot", x: "50%", y: "96%" },
      { phase: "GATE", status: "running gate", handoff: "all rungs green", artifact: "gate log", x: "23%", y: "87.2%" },
      { phase: "UI GATE", status: "running UI gate", handoff: "UITests passed", artifact: "sim result", x: "6.3%", y: "64.2%" },
      { phase: "SHIP", status: "shipping merge", handoff: "merge: resolve #159", artifact: "pushed commit", x: "6.3%", y: "35.8%" },
      { phase: "CLEANUP", status: "cleaning up", handoff: "issue closed", artifact: "closed loop", x: "23%", y: "12.8%" }
    ];
    var lit = 0, ringTimer = null;
    function step() {
      nodes.forEach(function (n, j) { n.classList.toggle("on", j === lit); });
      var stage = stages[lit] || stages[0];
      if (status) status.textContent = stage.status;
      if (orbitToken) {
        orbitToken.style.setProperty("--orbit-x", stage.x);
        orbitToken.style.setProperty("--orbit-y", stage.y);
      }
      if (orbitTokenLabel) orbitTokenLabel.textContent = stage.phase;
      if (consolePhase) consolePhase.textContent = stage.phase;
      if (consoleHandoff) consoleHandoff.textContent = stage.handoff;
      if (consoleArtifact) consoleArtifact.textContent = stage.artifact;
      lit = (lit + 1) % nodes.length;
    }
    var ringIO = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting && !ringTimer) {
          step();
          if (!reduceMotion) ringTimer = setInterval(step, 620);
        } else if (!e.isIntersecting && ringTimer) {
          clearInterval(ringTimer); ringTimer = null;
        }
      });
    }, { threshold: 0.4 });
    ringIO.observe(ring);
  }

  /* ---------- merge gate ladder ---------- */
  var gate = document.getElementById("gate-ladder");
  if (gate) {
    var rungs = Array.prototype.slice.call(gate.querySelectorAll(".rung"));
    var gateStatusText = document.getElementById("gate-status-text");
    var gateTimers = [];
    function clearGateTimers() {
      gateTimers.forEach(function (timer) { clearTimeout(timer); });
      gateTimers = [];
    }
    function setGateText(index) {
      if (!gateStatusText) return;
      if (index >= rungs.length) {
        gateStatusText.textContent = "ready to merge";
        return;
      }
      gateStatusText.textContent = "running " + (rungs[index].getAttribute("data-gate") || "gate");
    }
    function playGate() {
      clearGateTimers();
      rungs.forEach(function (rung) { rung.classList.remove("complete"); });
      if (reduceMotion) {
        rungs.forEach(function (rung) { rung.classList.add("complete"); });
        setGateText(rungs.length);
        return;
      }
      rungs.forEach(function (rung, i) {
        gateTimers.push(setTimeout(function () {
          rung.classList.add("complete");
          setGateText(i + 1);
        }, i * 260));
      });
      setGateText(0);
    }
    var gateIO = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) playGate();
        else clearGateTimers();
      });
    }, { threshold: 0.38 });
    gateIO.observe(gate);
  }

  /* ---------- gallery proof focus ---------- */
  var galleryTrack = document.getElementById("gallery-track");
  if (galleryTrack) {
    var galleryCards = Array.prototype.slice.call(galleryTrack.querySelectorAll(".gcard"));
    var proofTitle = document.getElementById("gallery-proof-title");
    var proofCopy = document.getElementById("gallery-proof-copy");
    function setGalleryActive(card) {
      galleryCards.forEach(function (item) { item.classList.toggle("active", item === card); });
      var title = card.querySelector(".name");
      var proof = Array.prototype.slice.call(card.querySelectorAll(".proof-strip span"))
        .map(function (el) { return el.textContent; })
        .join(" · ");
      if (proofTitle && title) proofTitle.textContent = title.textContent;
      if (proofCopy) proofCopy.textContent = proof;
    }
    function updateGalleryFromScroll() {
      var trackBox = galleryTrack.getBoundingClientRect();
      var center = trackBox.left + trackBox.width / 2;
      var best = galleryCards[0], bestDistance = Infinity;
      galleryCards.forEach(function (card) {
        var box = card.getBoundingClientRect();
        var distance = Math.abs((box.left + box.width / 2) - center);
        if (distance < bestDistance) {
          best = card;
          bestDistance = distance;
        }
      });
      setGalleryActive(best);
    }
    galleryTrack.addEventListener("scroll", updateGalleryFromScroll, { passive: true });
    galleryCards.forEach(function (card) {
      card.addEventListener("mouseenter", function () { setGalleryActive(card); });
      card.addEventListener("focusin", function () { setGalleryActive(card); });
    });
    setGalleryActive(galleryCards[0]);
    window.addEventListener("resize", updateGalleryFromScroll);
  }

  setActive(0);
})();
