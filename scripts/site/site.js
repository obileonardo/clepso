/* Pulse docs site behaviour. No libraries. Everything here is progressive: the pages read fine without it.
   The three playgrounds mirror Swift code exactly; each names its source, and build-site.py prints that source beside it. */
(() => {
  "use strict";
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const store = {
    get(k) { try { return sessionStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { sessionStorage.setItem(k, v); } catch { /* private mode: fine */ } },
  };

  // ------------------------------------------------------------------ dialogs (menu, search): Esc closes, focus returns
  function dialog(el, opener) {
    let last = null;
    const focusables = () => $$("a[href], button, input", el).filter(x => !x.disabled && x.offsetParent !== null);
    function open() {
      // Safari does not focus a button on click, so prefer the opener over whatever happens to have focus.
      last = opener || document.activeElement; el.hidden = false; document.body.style.overflow = "hidden";
      if (opener) opener.setAttribute("aria-expanded", "true");
      (el.querySelector("[autofocus], input") || focusables()[0])?.focus();
    }
    function close() {
      el.hidden = true; document.body.style.overflow = "";
      if (opener) opener.setAttribute("aria-expanded", "false");
      last?.focus?.();
    }
    el.addEventListener("keydown", ev => {
      if (ev.key === "Escape") { ev.preventDefault(); close(); }
      if (ev.key === "Tab") {
        const f = focusables(); if (!f.length) return;
        if (ev.shiftKey && document.activeElement === f[0]) { ev.preventDefault(); f[f.length - 1].focus(); }
        else if (!ev.shiftKey && document.activeElement === f[f.length - 1]) { ev.preventDefault(); f[0].focus(); }
      }
    });
    return { open, close, get isOpen() { return !el.hidden; } };
  }

  const menuEl = $("#px-menu"), menuBtn = $("[data-menu-open]");
  const menu = menuEl && dialog(menuEl, menuBtn);
  if (menu) {
    menuBtn.addEventListener("click", () => { menu.open(); startDither($("canvas", menuEl)); });
    $$("[data-menu-close]").forEach(b => b.addEventListener("click", menu.close));
  }

  // ----------------------------------------------------------------------------------------------------------- search
  const searchEl = $("#px-search");
  const search = searchEl && dialog(searchEl);
  if (search) {
    const input = $("input", searchEl), list = $("ul", searchEl);
    let index = null, hits = [], sel = 0;
    const esc = s => s.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
    async function load() {
      if (index) return;
      try { index = await (await fetch("/assets/search.json")).json(); } catch { index = []; }
    }
    function mark(text, terms) {
      let out = esc(text);
      terms.forEach(t => { out = out.replace(new RegExp("(" + t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "ig"), "<em>$1</em>"); });
      return out;
    }
    function render() {
      const q = input.value.trim().toLowerCase(), terms = q.split(/\s+/).filter(Boolean);
      if (!index) return;
      hits = (terms.length ? index.map(e => {
        const hay = (e.t + " " + e.p + " " + e.x).toLowerCase();
        if (!terms.every(t => hay.includes(t))) return null;
        const score = terms.reduce((s, t) => s + (e.t.toLowerCase().includes(t) ? 4 : 0) + (e.p.toLowerCase().includes(t) ? 2 : 0), 0);
        return [score, e];
      }).filter(Boolean).sort((a, b) => b[0] - a[0]).map(x => x[1]) : index.filter(e => e.top)).slice(0, 12);
      sel = 0;
      list.innerHTML = hits.length ? hits.map((e, i) => `<li role="option" id="px-opt-${i}" aria-selected="${i === 0}"><a href="${e.u}">${mark(e.t, terms)}<small>${esc(e.p)}${e.x ? " · " + mark(e.x.slice(0, 110), terms) : ""}</small></a></li>`).join("")
        : `<li class="px-empty" role="option" aria-disabled="true">Nothing matches “${esc(q)}”. Try limits, levels, pace or privacy.</li>`;
      input.setAttribute("aria-activedescendant", hits.length ? "px-opt-0" : "");
    }
    function move(d) {
      const items = $$("li[role=option]", list).filter(li => !li.classList.contains("px-empty")); if (!items.length) return;
      items[sel]?.setAttribute("aria-selected", "false");
      sel = (sel + d + items.length) % items.length;
      items[sel].setAttribute("aria-selected", "true"); items[sel].scrollIntoView({ block: "nearest" });
      input.setAttribute("aria-activedescendant", items[sel].id);
    }
    input.addEventListener("input", render);
    input.addEventListener("keydown", ev => {
      if (ev.key === "ArrowDown") { ev.preventDefault(); move(1); }
      if (ev.key === "ArrowUp") { ev.preventDefault(); move(-1); }
      if (ev.key === "Enter" && hits[sel]) { ev.preventDefault(); location.href = hits[sel].u; search.close(); }
    });
    list.addEventListener("click", ev => { if (ev.target.closest("a")) search.close(); });
    searchEl.addEventListener("click", ev => { if (ev.target === searchEl) search.close(); });
    const openSearch = async q => { search.open(); await load(); if (typeof q === "string") input.value = q; render(); };
    $$("[data-search-open]").forEach(b => b.addEventListener("click", () => openSearch(b.dataset.q)));
    document.addEventListener("keydown", ev => {
      const typing = /INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName || "");
      if ((ev.key === "k" && (ev.metaKey || ev.ctrlKey)) || (ev.key === "/" && !typing)) { ev.preventDefault(); search.isOpen ? search.close() : openSearch(); }
    });
  }

  // ------------------------------------------------------------------------------------------------ copy code / page
  async function copy(text, btn) {
    const was = btn.textContent;
    try { await navigator.clipboard.writeText(text); btn.textContent = "Copied ✓"; } catch { btn.textContent = "Copy failed"; }
    setTimeout(() => { btn.textContent = was; }, 1600);
  }
  $$("pre").forEach(pre => {
    if (pre.closest(".play") || pre.dataset.nocopy !== undefined) return;
    const b = document.createElement("button"); b.className = "copy"; b.type = "button"; b.textContent = "Copy";
    b.addEventListener("click", () => copy(pre.innerText.replace(/\nCopy$/, ""), b)); pre.appendChild(b);
  });
  $$("[data-copy-page]").forEach(b => b.addEventListener("click", () => {
    const art = $(".article"); if (!art) return;
    const clone = art.cloneNode(true); $$(".copy, .doc-tools, .play, .mobile-tree", clone).forEach(n => n.remove());
    copy(clone.innerText.trim() + "\n\nSource: " + location.href, b);
  }));
  $$("[data-copy-link]").forEach(b => b.addEventListener("click", () => copy(location.href.split("#")[0], b)));

  // ------------------------------------------------------------------------------ on this page: scroll spy and ruler
  const toc = $(".toc");
  if (toc) {
    const links = $$("a", toc), heads = links.map(a => document.getElementById(a.hash.slice(1))).filter(Boolean);
    const fill = $(".ruler i", toc), pct = $(".toc-pct", toc), art = $(".article");
    let ticking = false;
    function update() {
      ticking = false;
      const y = scrollY + innerHeight * 0.3;
      let cur = 0; heads.forEach((h, i) => { if (h.offsetTop <= y) cur = i; });
      links.forEach((a, i) => a.classList.toggle("on", i === cur));
      const top = art.offsetTop, h = Math.max(1, art.offsetHeight - innerHeight * 0.6);
      const p = Math.min(1, Math.max(0, (scrollY - top + innerHeight * 0.3) / h));
      if (fill) fill.style.height = (p * 100).toFixed(1) + "%";
      if (pct) pct.textContent = "READ " + Math.round(p * 100) + "%";
    }
    addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
    update();
  }

  // ------------------------------------------------------------------------------------------------- reveal on scroll
  const rv = $$(".rv");
  if (rv.length && "IntersectionObserver" in window && !reduce) {
    const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } }), { rootMargin: "0px 0px -8% 0px" });
    rv.forEach(el => io.observe(el));
  } else rv.forEach(el => el.classList.add("in"));

  // -------------------------------------------------------------------------- boot sequence (Shader), once a session
  const boot = $(".boot");
  if (boot) {
    if (reduce || store.get("pulse-booted")) boot.remove();
    else {
      store.set("pulse-booted", "1");
      const lines = $(".boot-lines", boot), cells = $$(".boot-bar i", boot);
      const text = JSON.parse(boot.dataset.lines || "[]");
      let done = false, t0 = performance.now();
      const finish = () => { if (done) return; done = true; boot.classList.add("out"); setTimeout(() => boot.remove(), 460); };
      boot.addEventListener("click", finish); addEventListener("keydown", finish, { once: true });
      (function frame(now) {
        if (done) return;
        const p = Math.min(1, (now - t0) / 1500);
        cells.forEach((c, i) => c.classList.toggle("on", i < Math.round(p * cells.length)));
        lines.textContent = text.slice(0, Math.ceil(p * text.length)).join("\n");
        if (p < 1) requestAnimationFrame(frame); else setTimeout(finish, 260);
      })(t0);
    }
  }
  $$(".focus-in-later").forEach(el => el.classList.add("focus-in"));

  // ---------------------------------------------------- dithered sphere with a heartbeat line (Unseen, basement.studio)
  const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map(v => (v + .5) / 16);
  const running = new WeakSet();
  function startDither(cv) {
    if (!cv || running.has(cv)) return;
    running.add(cv);
    const W = +cv.dataset.w || 160, H = +cv.dataset.h || 160; cv.width = W; cv.height = H;
    const ctx = cv.getContext("2d"), img = ctx.createImageData(W, H), d = img.data;
    const beat = cv.dataset.beat !== undefined;
    let visible = true;
    if ("IntersectionObserver" in window) new IntersectionObserver(es => { visible = es[0].isIntersecting; if (visible) requestAnimationFrame(draw); }).observe(cv);
    function draw(ms) {
      const t = (ms || 0) / 1000, cx = W / 2, cy = H / 2, r = Math.min(W, H) * .42;
      const lx = Math.cos(t * .5) * .8, ly = -.45, lz = Math.sin(t * .5) * .6 + .5, ll = Math.hypot(lx, ly, lz);
      const pulse = beat ? (t * .9) % 1 : -1;
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const i = (y * W + x) * 4, dx = (x - cx) / r, dy = (y - cy) / r, q = dx * dx + dy * dy;
        let v = 0;
        if (q <= 1) {
          const dz = Math.sqrt(1 - q);
          v = Math.max(0, (dx * lx + dy * ly + dz * lz) / ll) * .95;
          const lat = Math.asin(dy), lon = Math.atan2(dx, dz) + t * .35;       // a slow graticule turning with the sphere
          if (Math.abs(Math.sin(lat * 6)) < .08 || Math.abs(Math.sin(lon * 6)) < .06) v = Math.min(1, v + .35);
        } else {
          const ring = Math.sqrt(q) - 1;                                          // a faint halo of pixel dust
          v = Math.max(0, .22 - ring * .6) * (0.5 + 0.5 * Math.sin(x * 12.9898 + y * 78.233 + t));
        }
        if (beat) {                                                               // the heartbeat line from the favicon
          const u = x / W, base = cy + r * 1.18;
          const k = ((u - pulse + 1) % 1);
          const spike = k < .04 ? -k / .04 : k < .08 ? (k - .08) / .04 * -1 : 0;
          const ly2 = base + spike * r * .55 + (k > .08 && k < .12 ? (k - .08) * r * 3 : 0);
          if (Math.abs(y - ly2) < 1.1) v = Math.max(v, k < .35 ? 1 : .35);
        }
        const on = v > BAYER[(y & 3) * 4 + (x & 3)];
        d[i] = on ? 77 : 3; d[i + 1] = on ? 255 : 6; d[i + 2] = on ? 143 : 4; d[i + 3] = on ? 255 : 0;
      }
      ctx.putImageData(img, 0, 0);
      if (!reduce && visible && !document.hidden && cv.isConnected && (!cv.closest("[hidden]"))) requestAnimationFrame(draw);
      else running.delete(cv);
    }
    requestAnimationFrame(draw);
    document.addEventListener("visibilitychange", () => { if (!document.hidden && !running.has(cv)) startDither(cv); });
  }
  $$("canvas[data-dither]").filter(c => !c.closest("[hidden]")).forEach(startDither);

  // ------------------------------------------------------------------------------------------------------ playgrounds
  const compact = n => {
    for (const [s, x] of [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "K"]]) if (n >= s) { const v = n / s; return (v === Math.trunc(v) ? v.toFixed(0) : v.toFixed(1)) + x; }
    return String(Math.trunc(n));
  };
  function cells(el, n) { el.innerHTML = Array.from({ length: 50 }, (_, i) => `<i class="${i < Math.round(n / 2) ? "on" : ""}"></i>`).join("") + (el.dataset.marks || ""); }

  // Mirrors PoolReducer.classify: warning 80, critical 95, exhausted 100, hysteresis 3 on the way down.
  const limit = $("[data-play=limit]");
  if (limit) {
    const range = $("input", limit), out = $(".play-out", limit), note = $(".play-note", limit), m = $(".pmeter", limit), val = $("output", limit);
    m.dataset.marks = '<s style="left:80%" data-l="80"></s><s style="left:95%" data-l="95"></s>';
    let prev = "available";
    const LABEL = { available: ["Available", "ok"], warning: ["Approaching limit", "warn"], critical: ["Nearly exhausted", "warn"], exhausted: ["Limit reached", "bad"] };
    function classify(used, previous) {
      if (used >= 100) return "exhausted";
      if (used >= 95) return "critical";
      if (previous === "critical" && used > 95 - 3) return "critical";
      if (used >= 80) return "warning";
      if ((previous === "warning" || previous === "critical") && used > 80 - 3) return "warning";
      return "available";
    }
    function run() {
      const used = +range.value, state = classify(used, prev);
      const held = (state === "warning" && used < 80) || (state === "critical" && used < 95);
      val.textContent = used + "%";
      out.textContent = LABEL[state][0]; out.className = "play-out " + LABEL[state][1];
      m.className = "pmeter " + (state === "available" ? "" : state === "exhausted" ? "bad" : "warn"); cells(m, used);
      note.textContent = held ? `Held: it was ${LABEL[prev][0].toLowerCase()}, and it clears only at ${state === "critical" ? 92 : 77}% or below, so it does not flicker.`
        : state === "available" ? "Drag past 80, then back down to 79: the state stays put." : "";
      prev = state;
    }
    range.addEventListener("input", run); run();
  }

  // Mirrors ModelLevel in ModelsSection.swift: targets 1K, 2K, 5K, 10K … up to 5 quadrillion.
  const level = $("[data-play=level]");
  if (level) {
    const T = []; for (let dec = 1e3; dec <= 1e15; dec *= 10) T.push(dec, dec * 2, dec * 5);
    const input = $("input", level), out = $(".play-out", level), note = $(".play-note", level), m = $(".pmeter", level);
    function run() {
      const output = Math.max(0, Math.floor(+input.value || 0));
      const reached = T.filter(t => t <= output).length, floor = reached ? T[reached - 1] : 0, next = reached < T.length ? T[reached] : T[T.length - 1];
      const p = next > floor ? (output - floor) / (next - floor) : 1;
      out.textContent = "LV " + (reached + 1); out.className = "play-out ok";
      cells(m, p * 100);
      note.textContent = `progress to LV ${reached + 2} · ${compact(output)} / ${compact(next)} (${Math.floor(p * 100)}%, ${compact(next - output)} to go)`;
    }
    input.addEventListener("input", run);
    $$("[data-set]", level).forEach(b => b.addEventListener("click", () => { input.value = b.dataset.set; run(); }));
    run();
  }

  // Mirrors PaceEstimate.estimate (Pace.swift) for a steady rise: flat below 0.5 points an hour, never more than 8×
  // the history ahead, and the reset caps the projection. Wording from Copy.Pace.
  const pace = $("[data-play=pace]");
  if (pace) {
    const [used, rate, span, reset] = $$("input", pace), outs = $$("output", pace), out = $(".play-out", pace), note = $(".play-note", pace);
    const hm = h => { const mins = Math.round(h * 60); return mins >= 60 ? `${Math.floor(mins / 60)}h ${mins % 60}m` : `${mins}m`; };
    function run() {
      const u = +used.value, s = +rate.value, spanMin = +span.value, resetMin = +reset.value;
      outs[0].textContent = u + "%"; outs[1].textContent = s.toFixed(1) + " pts/h"; outs[2].textContent = spanMin + " min"; outs[3].textContent = resetMin ? hm(resetMin / 60) : "unknown";
      let text, cls = "ok", why = "";
      if (u >= 100) { text = "At the limit"; cls = "bad"; }
      else if (spanMin < 10) { text = "Estimate: needs a few more readings"; cls = "dim"; why = "Fewer than 3 readings or under 10 minutes of them."; }
      else if (s <= 0.5) { text = "Estimate: not rising right now"; cls = "dim"; why = "At or below 0.5 points an hour counts as flat."; }
      else {
        const hit = (100 - u) / s, horizon = resetMin ? Math.min(hit, resetMin / 60) : hit;
        if (horizon > (spanMin / 60) * 8) { text = "Estimate: needs a few more readings"; cls = "dim"; why = `${spanMin} min of readings can't speak for ${hm(horizon)} ahead (limit: 8× the history).`; }
        else if (resetMin && hit >= resetMin / 60) { text = `Estimate: about ${Math.round(Math.min(100, u + s * resetMin / 60))}% used by the reset`; why = `The window resets before the line reaches 100% (in ${hm(hit)}).`; }
        else { text = `Estimate: at this pace, 100% in about ${hm(hit)}`; cls = hit < 1 ? "bad" : "warn"; why = "The app shows the clock time instead of a duration."; }
      }
      out.textContent = text; out.className = "play-out " + cls; note.textContent = why;
    }
    [used, rate, span, reset].forEach(i => i.addEventListener("input", run)); run();
  }

  // ------------------------------------------------------------------------- dot timeline (Grok, SpaceXAI, V7)
  $$(".tl").forEach(tl => {
    const dots = $$(".tl-dot", tl), card = $(".tl-card", tl);
    let cur = Math.max(0, dots.findIndex(d => d.getAttribute("aria-pressed") === "true"));
    function show(i, focus) {
      cur = (i + dots.length) % dots.length;
      dots.forEach((d, k) => d.setAttribute("aria-pressed", String(k === cur)));
      const d = dots[cur].dataset, el = (tag, text, cls) => { const x = document.createElement(tag); x.textContent = text; if (cls) x.className = cls; return x; };
      const body = document.createElement("div"); body.append(el("h3", d.t), el("p", d.p), el("span", d.sl, "badge s-" + d.s));
      card.replaceChildren(el("b", d.n), body);
      if (focus) { dots[cur].focus(); dots[cur].scrollIntoView({ block: "nearest", inline: "center", behavior: reduce ? "auto" : "smooth" }); }
    }
    dots.forEach((d, i) => { d.addEventListener("click", () => show(i)); d.addEventListener("keydown", ev => {
      if (ev.key === "ArrowRight") { ev.preventDefault(); show(cur + 1, true); } if (ev.key === "ArrowLeft") { ev.preventDefault(); show(cur - 1, true); } }); });
    $$("[data-tl]", tl).forEach(b => b.addEventListener("click", () => show(cur + +b.dataset.tl, true)));
    show(cur);
  });

  // --------------------------------------------------------------------------------- tabs (BitcoinOS, Maze, Poly)
  $$("[role=tablist]").forEach(list => {
    const tabs = $$("[role=tab]", list);
    function pick(t, focus) {
      tabs.forEach(x => { const on = x === t; x.setAttribute("aria-selected", String(on)); x.tabIndex = on ? 0 : -1;
        const p = document.getElementById(x.getAttribute("aria-controls")); if (p) p.hidden = !on; });
      if (focus) t.focus();
      list.dispatchEvent(new CustomEvent("pick", { detail: t }));
    }
    tabs.forEach((t, i) => { t.addEventListener("click", () => pick(t)); t.addEventListener("keydown", ev => {
      const d = ev.key === "ArrowRight" ? 1 : ev.key === "ArrowLeft" ? -1 : 0; if (d) { ev.preventDefault(); pick(tabs[(i + d + tabs.length) % tabs.length], true); } }); });
    pick(tabs.find(t => t.getAttribute("aria-selected") === "true") || tabs[0]);
  });

  // ------------------------------------------------------------------------------------ screens: stage and thumbs
  const stage = $(".stage");
  if (stage) {
    const big = $(".stage-main img", stage), cap = $(".stage-main figcaption", stage), link = $(".stage-main a", stage);
    function showShot(b) {
      $$(".thumbs button", stage).forEach(x => x.setAttribute("aria-pressed", String(x === b)));
      big.src = b.dataset.src; big.alt = b.dataset.alt; link.href = b.dataset.src;
      const strong = document.createElement("strong"); strong.textContent = b.dataset.title;
      cap.replaceChildren(strong, ". " + b.dataset.note);
    }
    $$(".thumbs button", stage).forEach(b => b.addEventListener("click", () => showShot(b)));
    $$("[role=tablist]", stage).forEach(l => l.addEventListener("pick", ev => {
      const panel = document.getElementById(ev.detail.getAttribute("aria-controls"));
      const first = panel && $("button", panel); if (first) showShot(first);
    }));
    const first = $(".thumbs:not([hidden]) button", stage); if (first) showShot(first);
  }

  // --------------------------------------------------------------------------------- changelog: search and filter
  const cl = $("[data-changelog]");
  if (cl) {
    const q = $("input", cl), chips = $$(".chip", cl), days = $$(".day"), none = $(".none");
    let tag = "";
    function run() {
      const terms = q.value.toLowerCase().split(/\s+/).filter(Boolean); let shown = 0;
      days.forEach(day => { let n = 0;
        $$("li", day).forEach(li => { const ok = (!tag || li.dataset.tag === tag) && terms.every(t => li.dataset.text.includes(t)); li.hidden = !ok; if (ok) n++; });
        day.hidden = !n; shown += n; });
      none.hidden = shown > 0;
    }
    q.addEventListener("input", run);
    chips.forEach(c => c.addEventListener("click", () => { tag = c.dataset.tag; chips.forEach(x => x.setAttribute("aria-pressed", String(x === c))); run(); }));
  }

  // ------------------------------------------------- footer village: load Three.js only when the footer comes near
  const village = $(".village");
  if (village) {
    let started = false;
    const go = () => { if (started) return; started = true;
      import("/assets/village.js").then(m => m.start(village)).catch(() => village.classList.add("no-3d")); };
    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver(es => { if (es.some(x => x.isIntersecting)) { io.disconnect(); go(); } }, { rootMargin: "600px 0px" });
      io.observe(village);
    } else go();
  }

  // ------------------------------------------------------------------- exploded architecture (Atlas): open in view
  $$(".stack").forEach(st => {
    const plates = $$(".plate", st), steps = $$(".steps li", st.closest(".explode") || document);
    if (reduce || !("IntersectionObserver" in window)) st.classList.add("open");
    else new IntersectionObserver((es, o) => es.forEach(e => { if (e.isIntersecting) { st.classList.add("open"); o.disconnect(); } }), { threshold: .35 }).observe(st);
    const light = i => { plates.forEach(p => p.classList.toggle("on", p.dataset.step === String(i))); steps.forEach(s => s.classList.toggle("on", s.dataset.step === String(i))); };
    steps.forEach(s => { s.addEventListener("mouseenter", () => light(s.dataset.step)); s.addEventListener("focus", () => light(s.dataset.step)); });
    if (!reduce && plates.length) { let i = 1; const n = steps.length; const tick = () => { if (!document.hidden) { light(i); i = i % n + 1; } };
      tick(); const iv = setInterval(tick, 2400); steps.forEach(s => s.addEventListener("mouseenter", () => clearInterval(iv))); }
  });
})();
