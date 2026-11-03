/* pursee.skifi.co: the landing page. The phone in the hero fills in today's
   entries, the feature cards come in as they scroll into view, the web app on
   the laptop takes one more entry, and the import fills a book. */
document.documentElement.classList.add("js");

/* where the store buttons go. The App Store link goes in once Apple has
   approved the app, as https://apps.apple.com/app/id... */
var STORE = {
  play: "https://play.google.com/store/apps/details?id=co.skifi.pursee",
  ios: ""
};

(function () {
  "use strict";
  var MSH = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  var DSH = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  var reduce = window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches;

  function $(s, r) { return (r || document).querySelector(s); }
  function $$(s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); }
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  /* 3,761.37 */
  function money(n) {
    return n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }
  function whole(n) { return Math.round(n).toLocaleString("en-US"); }
  function count(el, from, to, ms, fmt) {
    fmt = fmt || money;
    if (!el) return;
    if (reduce || ms <= 0) { el.textContent = fmt(to); return; }
    var t0 = performance.now();
    (function step(now) {
      var k = Math.min(1, (now - t0) / ms), e = 1 - Math.pow(1 - k, 3);
      el.textContent = fmt(from + (to - from) * e);
      if (k < 1) requestAnimationFrame(step);
    })(t0);
  }
  function seen(el, fn, threshold) {
    if (!("IntersectionObserver" in window)) { fn(true); return; }
    new IntersectionObserver(function (es) { es.forEach(function (e) { fn(e.isIntersecting, e); }); }, { threshold: threshold || 0.2 }).observe(el);
  }
  function ready(fn) { if (document.readyState !== "loading") fn(); else document.addEventListener("DOMContentLoaded", fn); }

  /* Runs a plan of [ms, fn] steps in a loop while the element is on screen. */
  function loop(el, plan, length) {
    var t = 0, next = 0, on = false, last = 0;
    seen(el, function (v) { on = v; }, 0.25);
    (function frame(ts) {
      var dt = last ? Math.min(100, ts - last) : 0;
      last = ts;
      if (on && !document.hidden) {
        t += dt;
        while (next < plan.length && t >= plan[next][0]) { plan[next][1](); next++; }
        if (t >= length) { t = 0; next = 0; }
      }
      requestAnimationFrame(frame);
    })(performance.now());
  }

  ready(function () {
    /* the dates on the screens are today's */
    var now = new Date();
    function back(n) { var d = new Date(now); d.setDate(d.getDate() - n); return d; }
    $$("[data-mshort]").forEach(function (el) { el.textContent = MSH[now.getMonth()] + " " + now.getFullYear(); });
    $$("[data-year]").forEach(function (el) { el.textContent = now.getFullYear(); });
    $$("[data-dn]").forEach(function (el) { el.textContent = pad(back(+el.getAttribute("data-dn")).getDate()); });
    $$("[data-dm]").forEach(function (el) { var d = back(+el.getAttribute("data-dm")); el.textContent = pad(d.getMonth() + 1) + "." + d.getFullYear(); });
    $$("[data-dw]").forEach(function (el) {
      var d = back(+el.getAttribute("data-dw")).getDay();
      el.textContent = DSH[d];
      el.classList.toggle("is-sun", d === 0);
      el.classList.toggle("is-sat", d === 6);
    });
    $$("[data-mo]").forEach(function (el) {
      var m = now.getMonth() - (+el.getAttribute("data-mo"));
      el.textContent = MSH[(m % 12 + 12) % 12];
    });
    calendar();

    /* the store buttons take their links from STORE */
    $$("[data-store]").forEach(function (a) {
      var url = STORE[a.getAttribute("data-store")];
      if (url) {
        a.href = url; a.target = "_blank"; a.rel = "noopener";
      } else {
        a.removeAttribute("target");
        a.addEventListener("click", function (e) { e.preventDefault(); });
      }
    });

    /* on phones a slim bar with "Get the app" shows once the hero is gone,
       and steps aside when the last call is on screen */
    var bar = $("#getbar"), heroEl = $(".hero"), getEl = $("#get");
    if (bar && heroEl && getEl && "IntersectionObserver" in window) {
      var heroIn = true, getIn = false;
      var upd = function () {
        var on = !heroIn && !getIn;
        bar.classList.toggle("on", on);
        bar.setAttribute("aria-hidden", on ? "false" : "true");
        $("a", bar).tabIndex = on ? 0 : -1;
      };
      new IntersectionObserver(function (es) { heroIn = es[0].isIntersecting; upd(); }, { threshold: 0 }).observe($(".hero__get", heroEl) || heroEl);
      new IntersectionObserver(function (es) { getIn = es[0].isIntersecting; upd(); }, { threshold: 0.1 }).observe(getEl);
    }

    /* The glass bars (the one at the top, the "Get the app" bar) turn to dark
       glass while a dark panel is under them, as Apple's glass does: light
       glass over the light page, dark glass over the violet. A panel counts
       when it covers the middle of the bar and most of its width. Both looks
       are tinted enough to read over anything that slides under them. */
    var nav = $("#nav"), adapt = $$("[data-adapt]"), darks = $$(".hero, .big, .cta, .card--big"), toneRaf = 0;
    function tone() {
      toneRaf = 0;
      nav.classList.toggle("is-stuck", window.scrollY > 8);
      adapt.forEach(function (el) {
        var r = el.getBoundingClientRect();
        if (!r.width) return;
        var cy = r.top + r.height / 2, dark = false;
        for (var i = 0; i < darks.length && !dark; i++) {
          var d = darks[i].getBoundingClientRect();
          if (d.top <= cy && d.bottom >= cy && Math.min(r.right, d.right) - Math.max(r.left, d.left) >= r.width * 0.6) dark = true;
        }
        el.classList.toggle("is-dark", dark);
      });
    }
    function onScroll() { if (!toneRaf) toneRaf = requestAnimationFrame(tone); }
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    tone();

    /* the soft light behind the glass only drifts while it is on screen */
    if ("IntersectionObserver" in window) {
      var ambIo = new IntersectionObserver(function (es) {
        es.forEach(function (e) { e.target.classList.toggle("is-off", !e.isIntersecting); });
      }, { rootMargin: "120px 0px" });
      $$(".amb").forEach(function (el) { ambIo.observe(el); });
    }

    /* sections come in as they are scrolled to */
    var io = "IntersectionObserver" in window ? new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { threshold: 0.18, rootMargin: "0px 0px -6% 0px" }) : null;
    $$(".reveal").forEach(function (el) { if (io) io.observe(el); else el.classList.add("in"); });

    /* ---------------------------------------------------------- the calendar in the big card */
    function calendar() {
      var box = $("#vCal");
      if (!box) return;
      var y = now.getFullYear(), m = now.getMonth(), today = now.getDate();
      var first = new Date(y, m, 1).getDay(), days = new Date(y, m + 1, 0).getDate(), prevDays = new Date(y, m, 0).getDate();
      var spend = [86, 0, 245, 52, 130, 0, 64, 310, 41, 0, 175, 98, 22, 0, 156, 74, 0, 268, 35, 112, 0, 59, 143, 0, 81, 205, 47, 0, 96, 30, 66];
      function short(n) { return n >= 1000 ? (n % 1000 ? (n / 1000).toFixed(1) : n / 1000) + "k" : String(n); }
      var UPCOMING = { 15: 75, 20: 300 };
      function cell(cls, day, amt, inc, up) {
        var ec = inc ? "m-in" : up ? "up" : "";
        return '<i' + (cls ? ' class="' + cls + '"' : "") + "><b>" + day + "</b>" +
          (amt ? "<em" + (ec ? ' class="' + ec + '"' : "") + ">" + short(amt) + "</em>" : "") + "</i>";
      }
      var html = '<span class="su">S</span><span>M</span><span>T</span><span>W</span><span>T</span><span>F</span><span class="sa">S</span>';
      for (var p = first - 1; p >= 0; p--) html += cell("dim", prevDays - p);
      for (var d = 1; d <= days; d++) {
        var amt = 0, inc = false;
        if (d === today) amt = 367;
        else if (d === today - 1) amt = 120;
        else if (d === 1 && d < today) { amt = 12000; inc = true; }
        else if (d < today) amt = spend[d - 1];
        /* repeats still to come show faintly on their day */
        var up = d > today && UPCOMING[d];
        html += cell(d === today ? "now" : "", d, up || amt, inc, !!up);
      }
      var cells = first + days, tail = (7 - cells % 7) % 7;
      for (var n = 1; n <= tail; n++) html += cell("dim", n, n === 1 ? 2500 : 0);
      box.innerHTML = html;
    }

    /* ---------------------------------------------------------- the big card: three views */
    (function views() {
      var tabs = $$("#vTabs span"), panes = $$(".vpane");
      if (!tabs.length || reduce) return;
      var i = 0;
      function show(k) {
        tabs.forEach(function (t, j) { t.classList.toggle("on", j === k); });
        panes.forEach(function (p, j) { p.classList.toggle("on", j === k); });
      }
      loop($(".card--big"), [[3400, function () { i = (i + 1) % 3; show(i); }]], 3400);
    })();

    /* ---------------------------------------------------------- the passcode card */
    (function passcode() {
      var box = $("#vPin");
      if (!box || reduce) return;
      var dots = $$(".vpin__dots i", box), keys = $$(".vpin__keys span", box), text = $("[data-pin-t]", box), use = $(".vpin__top use", box);
      var seq = [4, 1, 9, 6];
      function press(k) {
        var key = keys[seq[k] - 1];
        key.classList.add("hit");
        dots[k].classList.add("on");
        setTimeout(function () { key.classList.remove("hit"); }, 260);
      }
      function open() { box.classList.add("open"); text.textContent = "Unlocked"; use.setAttribute("href", "#i-unlock"); }
      function reset() {
        dots.forEach(function (d) { d.classList.remove("on"); });
        box.classList.remove("open"); text.textContent = "Enter passcode"; use.setAttribute("href", "#i-lock");
      }
      loop(box, [[700, function () { press(0); }], [1150, function () { press(1); }], [1600, function () { press(2); }],
        [2050, function () { press(3); }], [2500, open], [5600, reset]], 6200);
    })();

    /* ---------------------------------------------------------- the phone in the hero */
    (function hero() {
      var list = $("#hList");
      if (!list || reduce) return;
      var inEl = $("#hIn"), outEl = $("#hOut"), totEl = $("#hTot"), dayIn = $("#hDayIn"), dayOut = $("#hDayOut"), card = $("#hCard"), budget = $("#hBudget");
      /* each new entry: [income, expense, on the card] in SAR */
      var adds = { a: [0, 95, 95], b: [783, 0, 0], c: [0, 240, 240], d: [0, 14, 0] };
      var START = { inc: 12000, out: 3412.37, dIn: 0, dOut: 18, card: 0 };
      var s;
      function row(k) { return $('[data-s="' + k + '"]', list); }
      function add(k) {
        var r = row(k), v = adds[k];
        r.classList.remove("is-pend");
        r.classList.add("just");
        setTimeout(function () { r.classList.remove("just"); }, 1300);
        if (v[0]) { count(inEl, s.inc, s.inc + v[0], 700); count(dayIn, s.dIn, s.dIn + v[0], 700); }
        if (v[1]) { count(outEl, s.out, s.out + v[1], 700); count(dayOut, s.dOut, s.dOut + v[1], 700); }
        if (v[2]) count(card, s.card, s.card + v[2], 700);
        count(totEl, s.inc - s.out, s.inc + v[0] - s.out - v[1], 700);
        s.inc += v[0]; s.out += v[1]; s.dIn += v[0]; s.dOut += v[1]; s.card += v[2];
      }
      function reset() {
        s = { inc: START.inc, out: START.out, dIn: START.dIn, dOut: START.dOut, card: START.card };
        Object.keys(adds).forEach(function (k) { row(k).classList.add("is-pend"); });
        budget.classList.remove("show");
        inEl.textContent = money(s.inc); outEl.textContent = money(s.out); totEl.textContent = money(s.inc - s.out);
        dayIn.textContent = money(s.dIn); dayOut.textContent = money(s.dOut); card.textContent = money(s.card);
      }
      reset();
      loop($(".stage"), [[1500, function () { add("a"); }], [3100, function () { add("b"); }], [4700, function () { add("c"); }],
        [6300, function () { add("d"); }], [7600, function () { budget.classList.add("show"); }], [14600, reset]], 16000);
    })();

    /* ---------------------------------------------------------- the web app on the laptop */
    (function web() {
      var row = $("#wNew");
      if (!row || reduce) return;
      var out = $("#wOut"), tot = $("#wTot"), day = $("#wDay"), food = $("#wFood"), bar = $("#wFoodBar");
      var INC = 12783, OUT = 3761.37, DAY = 367, ADD = 186.4;
      function reset() {
        row.classList.add("is-pend"); row.classList.remove("just");
        out.textContent = money(OUT); tot.textContent = money(INC - OUT); day.textContent = money(DAY);
        food.textContent = "768 of 1,200"; bar.style.setProperty("--p", "64%");
      }
      function add() {
        row.classList.remove("is-pend"); row.classList.add("just");
        setTimeout(function () { row.classList.remove("just"); }, 1500);
        count(out, OUT, OUT + ADD, 700); count(tot, INC - OUT, INC - OUT - ADD, 700); count(day, DAY, DAY + ADD, 700);
        food.textContent = "954 of 1,200"; bar.style.setProperty("--p", "80%");
      }
      reset();
      loop($(".lap"), [[1800, add], [7400, reset]], 8200);
    })();

    /* ---------------------------------------------------------- the import, in the second phone */
    (function importer() {
      var box = $("#imp");
      if (!box || reduce) return;
      var n = $("#impN"), bar = $("#impBar"), rows = $$(".imp__r", box), done = $("#impDone"), btn = $("#impBtn");
      var TOTAL = 3218;
      function reset() {
        rows.forEach(function (r) { r.classList.remove("is-done", "just"); });
        done.classList.remove("is-on"); btn.classList.remove("is-on");
        n.textContent = "0"; bar.style.width = "0";
      }
      function tick(k) { rows[k].classList.add("is-done", "just"); }
      function read() {
        count(n, 0, TOTAL, 2900, whole);
        var t0 = performance.now();
        (function step(t) {
          var k = Math.min(1, (t - t0) / 2900);
          bar.style.width = (100 * (1 - Math.pow(1 - k, 3))).toFixed(1) + "%";
          if (k < 1) requestAnimationFrame(step);
        })(t0);
      }
      reset();
      loop(box, [[700, read], [1300, function () { tick(0); }], [2000, function () { tick(1); }], [2700, function () { tick(2); }],
        [3700, function () { tick(3); }], [4300, function () { done.classList.add("is-on"); btn.classList.add("is-on"); }], [9200, reset]], 10000);
    })();
  });
})();

/* Liquid glass. The refraction (an SVG filter used through backdrop-filter)
   only works in Chromium, so it is switched on there alone; Safari and
   Firefox keep the plain blur. And on buttons and pills, a soft light follows
   the pointer: --sx and --sy place it, CSS only moves it (transform). */
(function () {
  var mm = function (q) { return window.matchMedia && matchMedia(q).matches; };
  var brands = navigator.userAgentData && navigator.userAgentData.brands;
  var chromium = !!(brands && brands.some(function (b) { return /Chromium/.test(b.brand); }));
  if (chromium && window.CSS && CSS.supports("backdrop-filter", "blur(1px)") && !mm("(prefers-reduced-transparency: reduce)")) {
    document.documentElement.classList.add("lg-warp");
  }
  if (mm("(prefers-reduced-motion: reduce)")) return;
  var el = null, px = 0, py = 0, raf = 0;
  function place() {
    raf = 0;
    if (!el) return;
    var r = el.getBoundingClientRect();
    el.style.setProperty("--sx", (px - r.left - r.width / 2).toFixed(1) + "px");
    el.style.setProperty("--sy", (py - r.top - r.height / 2).toFixed(1) + "px");
  }
  function track(e) {
    var t = e.target && e.target.closest ? e.target.closest(".lg-press") : null;
    if (!t) return;
    el = t; px = e.clientX; py = e.clientY;
    if (!raf) raf = requestAnimationFrame(place);
  }
  document.addEventListener("pointermove", track, { passive: true });
  document.addEventListener("pointerdown", track, { passive: true });
})();

/* the coins around the hero phone drift a little with the pointer */
(function () {
  if (!window.matchMedia || !matchMedia("(pointer: fine)").matches || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  var hero = document.querySelector(".hero");
  if (!hero) return;
  var items = [].slice.call(hero.querySelectorAll(".coin[data-depth]"));
  if (!items.length) return;
  var raf = 0, x = 0, y = 0;
  hero.addEventListener("pointermove", function (e) {
    var r = hero.getBoundingClientRect();
    x = (e.clientX - r.left) / r.width - 0.5;
    y = (e.clientY - r.top) / r.height - 0.5;
    if (raf) return;
    raf = requestAnimationFrame(function () {
      raf = 0;
      items.forEach(function (el) {
        var d = parseFloat(el.getAttribute("data-depth")) || 1;
        el.style.transform = "translate3d(" + (-x * d * 12).toFixed(1) + "px," + (-y * d * 12).toFixed(1) + "px,0)";
      });
    });
  });
  hero.addEventListener("pointerleave", function () {
    items.forEach(function (el) { el.style.transform = ""; });
  });
})();
