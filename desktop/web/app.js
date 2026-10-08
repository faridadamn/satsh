/* satsh desktop — vanilla JS UI */
"use strict";

// ------------------------------------------------------------------ helpers
// let replaceChildren/append ignore null/false (conditional children)
for (const m of ["replaceChildren", "append"]) { const orig = Element.prototype[m]; Element.prototype[m] = function (...k) { return orig.apply(this, k.flat(9).filter((x) => x != null && x !== false)); }; }
const $ = (s, el = document) => el.querySelector(s);
function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k === "class") el.className = v;
    else if (k === "style" && typeof v === "object") Object.assign(el.style, v);
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else if (k === "html") el.innerHTML = v;
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const k of kids.flat(9)) if (k != null && k !== false) el.append(k.nodeType ? k : document.createTextNode(String(k)));
  return el;
}
const P = {
  users: "M16 11a3 3 0 10-3-3 3 3 0 003 3zm-8 0a3 3 0 10-3-3 3 3 0 003 3zm0 2c-2.3 0-7 1.2-7 3.5V19h14v-2.5C15 14.2 10.3 13 8 13zm8 0c-.3 0-.6 0-1 .1a4.2 4.2 0 012 3.4V19h6v-2.5c0-2.3-4.7-3.5-7-3.5z",
  agent: "M12 2l1.8 5.4L19 9l-5.2 1.6L12 16l-1.8-5.4L5 9l5.2-1.6zM19 14l.9 2.6 2.6.9-2.6.9L19 21l-.9-2.6-2.6-.9 2.6-.9zM5 15l.6 1.6 1.6.6-1.6.6L5 19.4l-.6-1.6L2.8 17.2l1.6-.6z",
  host: "M4 4h16a1 1 0 011 1v5a1 1 0 01-1 1H4a1 1 0 01-1-1V5a1 1 0 011-1zm0 9h16a1 1 0 011 1v5a1 1 0 01-1 1H4a1 1 0 01-1-1v-5a1 1 0 011-1zm3-6.5a1.5 1.5 0 100 3 1.5 1.5 0 000-3zm0 9a1.5 1.5 0 100 3 1.5 1.5 0 000-3z",
  brain: "M12 3a4 4 0 00-4 4 4 4 0 00-3 6.7A4 4 0 009 21h.5a2.5 2.5 0 002.5-2.5A2.5 2.5 0 0014.5 21h.5a4 4 0 004-7.3A4 4 0 0016 7a4 4 0 00-4-4zm0 2a2 2 0 012 2v11.5a.5.5 0 01-1 0V7a1 1 0 00-1-1z",
  gear: "M19.4 13a7.5 7.5 0 000-2l2.1-1.6-2-3.4-2.5 1a7 7 0 00-1.7-1L15 3.3h-4l-.4 2.7a7 7 0 00-1.7 1l-2.5-1-2 3.4L6.6 11a7.5 7.5 0 000 2l-2.1 1.6 2 3.4 2.5-1a7 7 0 001.7 1l.4 2.7h4l.4-2.7a7 7 0 001.7-1l2.5 1 2-3.4zM12 15.5a3.5 3.5 0 110-7 3.5 3.5 0 010 7z",
  send: "M12 4l7 7-1.4 1.4L13 7.8V20h-2V7.8l-4.6 4.6L5 11z",
  stop: "M7 7h10v10H7z", plus: "M11 5h2v6h6v2h-6v6h-2v-6H5v-2h6z", close: "M6.4 5L12 10.6 17.6 5 19 6.4 13.4 12l5.6 5.6-1.4 1.4-5.6-5.6L6.4 19 5 17.6l5.6-5.6L5 6.4z",
  history: "M13 3a9 9 0 00-9 9H1l4 4 4-4H6a7 7 0 117 7 7 7 0 01-4.9-2l-1.4 1.4A9 9 0 1013 3zm-1 5v5l4.3 2.5.7-1.2-3.5-2.1V8z",
  term: "M4 4h16a2 2 0 012 2v12a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2zm0 4v10h16V8zm2 2l4 3-4 3-1-1.4L7.6 13 5 11.4zm6 5h6v2h-6z",
  folder: "M10 4l2 2h8a2 2 0 012 2v10a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2z",
  file: "M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8zm-1 7V3.5L18.5 9z",
  edit: "M3 17.2V21h3.8l11-11-3.8-3.8zM20.7 7a1 1 0 000-1.4l-2.3-2.3a1 1 0 00-1.4 0l-1.8 1.8 3.8 3.8z",
  trash: "M6 19a2 2 0 002 2h8a2 2 0 002-2V7H6zM19 4h-3.5l-1-1h-5l-1 1H5v2h14z",
  up: "M7.4 15.4L12 10.8l4.6 4.6L18 14l-6-6-6 6z", down: "M7.4 8.6L12 13.2l4.6-4.6L18 10l-6 6-6-6z",
  left: "M15.4 7.4L14 6l-6 6 6 6 1.4-1.4L10.8 12z", right: "M8.6 16.6L10 18l6-6-6-6-1.4 1.4 4.6 4.6z",
  upload: "M5 20h14v-2H5zm7-16l-5 5h3v6h4V9h3z", download: "M5 20h14v-2H5zm7-2l5-5h-3V4h-4v9H7z",
  save: "M17 3H5a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2V7zm-5 16a3 3 0 110-6 3 3 0 010 6zm3-10H5V5h10z",
  eye: "M12 5C6 5 2 12 2 12s4 7 10 7 10-7 10-7-4-7-10-7zm0 11a4 4 0 110-8 4 4 0 010 8z",
  play: "M8 5v14l11-7z", key: "M7 14a2 2 0 110-4 2 2 0 010 4zm5.6-4A6 6 0 107 18a6 6 0 005.6-4H17v4h4v-4h2v-4z",
  link: "M3.9 12a3.1 3.1 0 013.1-3.1h4V7H7a5 5 0 000 10h4v-1.9H7A3.1 3.1 0 013.9 12zM8 13h8v-2H8zm9-6h-4v1.9h4a3.1 3.1 0 010 6.2h-4V17h4a5 5 0 000-10z",
  more: "M6 10a2 2 0 100 4 2 2 0 000-4zm6 0a2 2 0 100 4 2 2 0 000-4zm6 0a2 2 0 100 4 2 2 0 000-4z",
  check: "M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4z", shield: "M12 2L4 5v6c0 5 3.4 9.7 8 11 4.6-1.3 8-6 8-11V5z",
  clock: "M12 2a10 10 0 100 20 10 10 0 000-20zm1 11V7h-2v8l5 3 1-1.6z", book: "M18 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V4a2 2 0 00-2-2zM6 4h5v8l-2.5-1.5L6 12z",
  globe: "M12 2a10 10 0 100 20 10 10 0 000-20zm6.9 6h-3a15.7 15.7 0 00-1.4-3.6A8 8 0 0118.9 8zM12 4c.8 1.2 1.5 2.5 1.9 4h-3.8c.4-1.5 1.1-2.8 1.9-4zM4.3 14a8 8 0 010-4h3.4a16 16 0 000 4zm.8 2h3a15.7 15.7 0 001.4 3.6A8 8 0 015.1 16zM8 8H5.1a8 8 0 014.4-3.6A15.7 15.7 0 008 8zm4 12c-.8-1.2-1.5-2.5-1.9-4h3.8c-.4 1.5-1.1 2.8-1.9 4zm2.3-6H9.7a14.7 14.7 0 010-4h4.6a14.7 14.7 0 010 4zm.3 5.6c.6-1.1 1.1-2.3 1.4-3.6h3a8 8 0 01-4.4 3.6zm1.7-5.6a16 16 0 000-4h3.4a8 8 0 010 4z",
  menu: "M3 6h18v2H3zm0 5h18v2H3zm0 5h18v2H3z", refresh: "M17.7 6.3A8 8 0 1019.7 14h-2.1a6 6 0 11-1.4-6.2L13 11h7V4z",
  image: "M21 19V5a2 2 0 00-2-2H5a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2zM8.5 13.5l2.5 3 3.5-4.5 4.5 6H5z",
  music: "M12 3v10.6A4 4 0 1014 17V7h4V3z", video: "M17 10.5V7a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h12a1 1 0 001-1v-3.5l4 4v-11z",
  code: "M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6z", wand: "M7.5 5.6L10 7 8.6 4.5 10 2 7.5 3.4 5 2l1.4 2.5L5 7zm12 9.8L17 14l1.4 2.5L17 19l2.5-1.4L22 19l-1.4-2.5L22 14zM22 2l-2.5 1.4L17 2l1.4 2.5L17 7l2.5-1.4L22 7l-1.4-2.5zM14.4 7.3a1 1 0 00-1.4 0L1.3 19a1 1 0 000 1.4l2.3 2.3a1 1 0 001.4 0L16.7 11a1 1 0 000-1.4z",
  power: "M13 3h-2v10h2zm4.8 2.2l-1.4 1.4A7 7 0 1112 5h0a7 7 0 00-4.4 1.6L6.2 5.2A9 9 0 1017.8 5.2z",
};
const icon = (n) => { const s = document.createElementNS("http://www.w3.org/2000/svg", "svg"); s.setAttribute("viewBox", "0 0 24 24"); s.innerHTML = `<path fill="currentColor" d="${P[n] || P.file}"/>`; return s; };
const GRADS = [["#7c5cff", "#22d3ee"], ["#ff5c9a", "#ffa25c"], ["#34d399", "#22d3ee"], ["#fbbf24", "#ff5c9a"], ["#6366f1", "#ec4899"], ["#0ea5e9", "#6366f1"]];
const grad = (i) => `linear-gradient(135deg, ${GRADS[(i || 0) % GRADS.length][0]}, ${GRADS[(i || 0) % GRADS.length][1]})`;
const md = (t) => DOMPurify.sanitize(marked.parse(t || "", { breaks: true, gfm: true }));
const fmtSize = (b) => { const u = ["B", "KB", "MB", "GB"]; let i = 0; while (b >= 1024 && i < 3) { b /= 1024; i++; } return (i ? b.toFixed(1) : b) + " " + u[i]; };
const ago = (ms) => { const d = (Date.now() - ms) / 1000; if (d < 60) return "barusan"; if (d < 3600) return Math.floor(d / 60) + "m"; if (d < 86400) return Math.floor(d / 3600) + "j"; if (d < 604800) return Math.floor(d / 86400) + "h"; const t = new Date(ms); return t.getDate() + "/" + (t.getMonth() + 1); };

async function api(path, body, opts) {
  const r = await fetch(path, body === undefined ? { credentials: "same-origin" } : { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), ...(opts || {}) });
  let j = {};
  try { j = await r.json(); } catch (e) { }
  if (r.status === 401 && j.error === "login") { showLogin(); throw new Error("login"); }
  if (!r.ok) { const e = new Error(j.error || ("HTTP " + r.status)); e.data = j; e.status = r.status; throw e; }
  return j;
}
function toast(msg, err) {
  const t = h("div", { class: "toast" + (err ? " err" : "") }, h("span", { style: { color: err ? "var(--red)" : "var(--green)" } }, err ? "✕" : "✓"), msg);
  $("#toasts").append(t); setTimeout(() => t.remove(), 3200);
}
const tryDo = async (fn, okMsg) => { try { const r = await fn(); if (okMsg) toast(okMsg); return r; } catch (e) { if (e.message !== "login") toast(e.message, true); throw e; } };

function modal(build) {
  return new Promise((resolve) => {
    const bg = h("div", { class: "modal-bg" });
    const close = (v) => { bg.remove(); resolve(v); };
    const m = h("div", { class: "modal" }); m.append(...[].concat(build(close)));
    bg.append(m); bg.addEventListener("mousedown", (e) => { if (e.target === bg && !m.dataset.sticky) close(null); });
    $("#modals").append(bg);
    const f = m.querySelector("input,textarea"); if (f) setTimeout(() => f.focus(), 50);
  });
}
const confirmBox = (title, body, ok = "Hapus", danger = true) => modal((close) => [h("h2", {}, title), h("p", { class: "muted" }, body),
  h("div", { class: "row", style: { justifyContent: "flex-end", marginTop: "16px" } }, h("button", { class: "btn ghost", onclick: () => close(false) }, "Batal"), h("button", { class: "btn " + (danger ? "danger" : "primary"), onclick: () => close(true) }, ok))]);
const askText = (title, initial = "", hint = "", multi = false) => modal((close) => {
  const f = h(multi ? "textarea" : "input", { class: "field", placeholder: hint }); f.value = initial;
  f.addEventListener("keydown", (e) => { if (e.key === "Enter" && !multi) close(f.value); });
  return [h("h2", {}, title), f, h("div", { class: "row", style: { justifyContent: "flex-end", marginTop: "14px" } }, h("button", { class: "btn ghost", onclick: () => close(null) }, "Batal"), h("button", { class: "btn primary", onclick: () => close(f.value) }, "OK"))];
});
function sw(checked, onchange) { const i = h("input", { type: "checkbox" }); i.checked = !!checked; i.onchange = () => onchange(i.checked); return h("label", { class: "switch" }, i, h("span")); }
function seg(opts, val, onpick) { return h("div", { class: "seg" }, opts.map(([v, l]) => h("button", { class: v === val ? "on" : "", onclick: () => onpick(v) }, l))); }

// ---------------------------------------------------------------- app state
const S = { view: localStorage.getItem("view") || "agent", st: null, sid: localStorage.getItem("sid") || null, session: null, expanded: new Set(), sessOpen: false, brainTab: "soul", setTab: "agent", hostSub: null };
function setView(v) { S.view = v; localStorage.setItem("view", v); renderNav(); render(); }
async function refresh() { S.st = await api("/api/state"); document.documentElement.dataset.theme = S.st.settings.theme || "dark"; renderNav(); }

const NAV = [["agent", "Agent", "agent"], ["markas", "Markas", "users"], ["host", "Host", "host"], ["brain", "Otak", "brain"], ["settings", "Pengaturan", "gear"]];
function renderNav() {
  const unread = S.st ? S.st.sessions.filter((m) => m.unread).length : 0;
  const btn = ([v, l, ic]) => h("button", { class: "navbtn" + (S.view === v ? " on" : ""), onclick: () => setView(v) }, icon(ic), h("span", { class: "lbl" }, l), v === "agent" && unread ? h("span", { class: "badge" }, unread) : null);
  $("#side").replaceChildren(h("div", { class: "logo grad-text" }, "satsh", h("small", {}, "desktop " + ((S.st && S.st.version) || ""))), ...NAV.map(btn),
    h("div", { class: "spacer" }), S.st && S.st.tunnel.url ? h("div", { class: "chip", style: { margin: "0 8px" } }, h("span", { class: "dot on" }), "remote on") : null);
  $("#bottomnav").replaceChildren(...NAV.map(btn));
}
function render() {
  if (!S.st) return;
  const main = $("#main");
  const views = { agent: viewAgent, markas: viewMarkas, host: viewHost, brain: viewBrain, settings: viewSettings };
  const box = main.querySelector(".term-box");
  const keepTerm = S.view === "host" && S.hostSub && S.hostSub.type === "term" && box && box.dataset.tid === S.hostSub.id;
  if (keepTerm) return renderTermChrome();
  main.replaceChildren(views[S.view]());
}

// ------------------------------------------------------------------- events
let es = null;
function connectEvents() {
  if (es) es.close();
  es = new EventSource("/api/events");
  let t = null;
  const soon = (fn) => { clearTimeout(t); t = setTimeout(fn, 120); };
  es.onmessage = async (e) => {
    const m = JSON.parse(e.data);
    if (m.type === "session") {
      if (m.data.statusOnly) {
        if (m.data.id === S.sid && S.session) { S.session.status = m.data.status; S.session.busy = m.data.busy; updateThinking(); }
        return;
      }
      if (m.data.id === S.sid) scheduleLoad();
      // sidebar/badges don't need every tick: refresh state at most ~1x/s while the agent works
      clearTimeout(connectEvents.st); connectEvents.st = setTimeout(async () => { await refresh(); if (S.view === "agent") renderSessionsList(); }, m.data.busy ? 900 : 150);
    } else if (m.type === "approval") showApproval(m.data);
    else if (m.type === "approval_done") { const el = document.getElementById("ap-" + m.data.id); if (el) el.closest(".modal-bg").remove(); }
    else if (m.type === "toast") toast(m.data.title + ": " + m.data.body);
    else soon(async () => { await refresh(); if (S.view !== "agent" && !(S.view === "host" && S.hostSub)) render(); else if (S.view === "agent") renderSessionsList(); else renderTermChrome && S.hostSub && S.hostSub.type === "term" && renderTermChrome(); });
  };
  es.onerror = () => { setTimeout(connectEvents, 3000); es.close(); };
}

// --------------------------------------------------------------- approvals
function showApproval(p) {
  if (document.getElementById("ap-" + p.id)) return;
  modal((close) => {
    const ans = async (a) => { await api("/api/approve", { id: p.id, answer: a }); close(); };
    return [h("div", { id: "ap-" + p.id, class: "row" }, h("div", { class: "avatar", style: { background: "rgba(251,191,36,.18)", color: "var(--amber)" } }, icon("shield")),
      h("div", {}, h("h2", { style: { margin: 0 } }, "Agent minta izin"), h("div", { class: "mono muted small" }, p.tool))),
    h("pre", {}, JSON.stringify(p.args, null, 2)),
    h("div", { class: "row" }, h("button", { class: "btn danger", style: { flex: 1 }, onclick: () => ans("no") }, "Tolak"), h("button", { class: "btn primary", style: { flex: 2 }, onclick: () => ans("yes") }, icon("check"), "Izinin")),
    h("button", { class: "btn ghost", style: { width: "100%", marginTop: "6px", color: "var(--muted)" }, onclick: () => ans("all") }, "Izinin semua di chat ini")];
  }).then(() => { });
  const last = $("#modals").lastChild; if (last) last.querySelector(".modal").dataset.sticky = "1";
}

// ==================================================================== AGENT
// Coalesce session refetches: at most one in flight, and one more if something changed meanwhile.
let loadBusy = false, loadAgain = false;
async function scheduleLoad() {
  if (loadBusy) { loadAgain = true; return; }
  loadBusy = true;
  try { do { loadAgain = false; await loadSession(); if (loadAgain) await new Promise((r) => setTimeout(r, 150)); } while (loadAgain); }
  finally { loadBusy = false; }
}
function updateThinking() {
  const el = document.querySelector("#msgs .thinking span");
  if (el) el.textContent = (S.session && S.session.status) || "Mikir…";
  else if (S.session && S.session.busy) renderChat();
}
async function loadSession() {
  if (!S.sid) { S.session = null; return renderChat(); }
  try { S.session = await api("/api/session?id=" + S.sid); } catch (e) { S.sid = null; S.session = null; localStorage.removeItem("sid"); }
  const sp = S.session && S.session.profile;
  if (sp && sp !== S.st.activeProfile && profById(sp)) { await api("/api/profile/activate", { id: sp }); await refresh(); if (S.view === "agent") { render(); return; } }
  renderChat();
}
function openSession(id) { S.sid = id; if (id) localStorage.setItem("sid", id); else localStorage.removeItem("sid"); S.sessOpen = false; S.expanded.clear(); loadSession(); renderSessionsList(); }

function viewAgent() {
  const v = h("div", { class: "view" },
    h("div", { class: "agent-wrap" },
      h("aside", { class: "sessions" + (S.sessOpen ? " open" : ""), id: "sessions" }),
      h("section", { class: "chat" },
        h("div", { class: "topbar" },
          h("button", { class: "icon-btn", title: "Sesi", onclick: () => { S.sessOpen = !S.sessOpen; $("#sessions").classList.toggle("open", S.sessOpen); } }, icon("history")),
          h("h1", { class: "grad-text" }, "Agent"),
          h("button", { class: "chip mono profile-chip", title: "Ganti profil agent — " + (profModel(activeProf()) || "belum ada provider"), onclick: profileMenu }, activeProf().emoji + " " + activeProf().name + " ▾"),
          h("div", { class: "spacer" }),
          h("button", { class: "icon-btn", title: "Chat baru", onclick: () => openSession(null) }, icon("plus")),
          h("button", { class: "icon-btn", title: "Refleksi sesi ini sekarang", onclick: async () => { if (!S.sid) return; toast("Lagi refleksi…"); const r = await tryDo(() => api("/api/review", { sid: S.sid })); toast(r.notes.length ? r.notes.join(", ") : "Ga ada yang perlu disimpen"); } }, icon("wand"))),
        h("div", { class: "msgs", id: "msgs" }),
        h("div", { id: "below" }),
        h("div", { class: "composer-wrap" }, composer()))));
  setTimeout(() => { renderSessionsList(); loadSession(); }, 0);
  return v;
}

function renderSessionsList(q) {
  const el = $("#sessions"); if (!el) return;
  const search = h("input", { class: "field", placeholder: "Cari di semua obrolan…", value: S.sessQ || "" });
  const list = h("div", { class: "list" });
  const fill = async () => {
    const qq = search.value.trim(); S.sessQ = qq;
    if (qq.length >= 2) {
      const hits = await api("/api/search?q=" + encodeURIComponent(qq));
      list.replaceChildren(...(hits.length ? hits.map((x) => h("div", { class: "sess", onclick: () => openSession(x.id) }, h("div", { style: { minWidth: 0 } }, h("div", { class: "t" }, x.title), h("div", { class: "snip" }, x.snippets.join(" · "))))) : [h("div", { class: "muted small", style: { padding: "12px" } }, "Ga ketemu")]));
      return;
    }
    list.replaceChildren(...(S.st.sessions.length ? S.st.sessions.map((m) => h("div", { class: "sess" + (m.id === S.sid ? " on" : "") + (m.unread ? " unread" : ""), onclick: () => openSession(m.id) },
      S.st.profiles.length > 1 ? h("span", { title: (profById(m.profile) || {}).name }, (profById(m.profile) || S.st.profiles[0]).emoji) : null,
      m.cron ? icon("clock") : (S.st.runs[m.id] ? h("span", { class: "dot busy" }) : null),
      h("span", { class: "t" }, m.title), m.unread ? h("span", { class: "badge" }, "•") : h("span", { class: "muted small" }, ago(m.updated)),
      h("button", { class: "icon-btn x", style: { width: "28px", height: "28px" }, title: "Menu", onclick: (e) => { e.stopPropagation(); sessionMenu(m); } }, icon("more")))) : [h("div", { class: "muted small", style: { padding: "12px" } }, "Belum ada sesi")]));
  };
  let tm; search.oninput = () => { clearTimeout(tm); tm = setTimeout(fill, 200); };
  el.replaceChildren(h("div", { style: { padding: "18px 12px 10px" }, class: "col" }, h("div", { class: "row" }, h("b", { style: { fontSize: "18px" } }, "Sesi"), h("div", { class: "spacer" }), h("button", { class: "btn primary", onclick: () => openSession(null) }, icon("plus"), "Baru")), search), list);
  fill();
}
async function sessionMenu(m) {
  const act = await modal((close) => [h("h2", {}, m.title), h("div", { class: "col" }, h("button", { class: "btn", onclick: () => close("rename") }, icon("edit"), "Ganti judul"), h("button", { class: "btn danger", onclick: () => close("delete") }, icon("trash"), "Hapus"))]);
  if (act === "rename") { const t = await askText("Judul sesi", m.title); if (t && t.trim()) await tryDo(() => api("/api/session/rename", { id: m.id, title: t.trim() })); }
  if (act === "delete" && await confirmBox("Hapus sesi?", m.title)) { await tryDo(() => api("/api/session/delete", { id: m.id })); if (m.id === S.sid) openSession(null); }
}

const IDEAS = ["Cek disk, RAM, dan proses paling berat di laptop ini", "Cari file PDF terbaru di Downloads", "Cek kesehatan semua server gw", "Rapihin folder Downloads gw"];
const NODES = new Map(); // render key -> DOM node, reused across renders
function memo(key, make) {
  let n = NODES.get(key);
  if (!n) { n = make(); NODES.set(key, n); }
  memo.used.add(key);
  return n;
}
memo.used = new Set();
function renderChat() {
  const box = $("#msgs"); if (!box) return;
  const s = S.session;
  const nearBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 140;
  const inner = box.firstElementChild && box.firstElementChild.classList.contains("msgs-inner") ? box.firstElementChild : h("div", { class: "msgs-inner" });
  const kids = [];
  memo.used = new Set();
  const sid = s ? s.id : "";
  if (!s || !s.messages.length) {
    kids.push(h("div", { class: "empty stagger" }, h("div", {}, h("div", { class: "ico" }, icon("agent")), h("h3", {}, "Mau dibantuin apa?"), h("div", {}, "Gw bisa ngoprek file & program di laptop, jalanin perintah, server SSH lu, dan Supabase.")),
      h("div", { class: "ideas stagger" }, IDEAS.map((t) => h("button", { class: "idea press", onclick: () => send(t) }, h("span", { style: { color: "var(--cyan)" } }, "⚡"), t)))));
  } else {
    const results = {}; s.messages.forEach((m) => { if (m.role === "tool") results[m.callId] = m; });
    s.messages.forEach((m, i) => {
      if (m.role === "tool") return;
      const k = sid + "/" + i + "/" + m.role + "/" + (m.text || "").length + "/" + (m.text || "").slice(-40);
      if (m.role === "event") return kids.push(memo("e" + k, () => h("div", { class: "event" }, m.text)));
      if (m.role === "user") {
        return kids.push(memo("u" + k, () => {
          let text = m.text, tag = null;
          const sk = /^\[Pakai skill "([^"]+)"\][\s\S]*\nPermintaan user: ([\s\S]*)$/.exec(text);
          if (sk) { tag = "📘 /" + sk[1]; text = sk[2]; }
          const cr = /^\[Jadwal "([^"]+)"/.exec(text); if (cr) tag = "⏰ " + cr[1];
          return h("div", { class: "bubble-u" }, tag ? h("div", { class: "tag" }, tag) : null, h("div", {}, text));
        }));
      }
      if (m.text && m.text.trim()) kids.push(memo("a" + k + (m.isError ? "!" : ""), () => answerBubble(m)));
      (m.calls || []).forEach((c) => {
        const r = results[c.id];
        kids.push(memo("c" + sid + "/" + c.id + "/" + (r ? (r.isError ? "e" : "o") + (r.text || "").length : "-") + (S.expanded.has(c.id) ? "+" : ""), () => toolChip(c, r)));
      });
    });
    if (s.busy) kids.push(h("div", { class: "thinking" }, h("i"), h("i"), h("i"), h("span", {}, s.status || "Mikir…")));
  }
  for (const key of [...NODES.keys()]) if (!memo.used.has(key)) NODES.delete(key);
  // only touch the DOM where it differs
  const cur = inner.children;
  kids.forEach((n, i) => { if (cur[i] !== n) inner.insertBefore(n, cur[i] || null); });
  while (cur.length > kids.length) inner.lastChild.remove();
  if (box.firstElementChild !== inner) box.replaceChildren(inner);
  if (nearBottom || (s && s.busy)) box.scrollTop = box.scrollHeight;
  // todo + slash
  const below = $("#below"); below.replaceChildren();
  const todos = (s && s.todos) || [];
  if (todos.length && (s.busy || todos.some((t) => t.status !== "done"))) {
    const done = todos.filter((t) => t.status === "done").length;
    below.append(h("div", { class: "card todo", style: { margin: "0 auto 8px", maxWidth: "820px" } },
      h("div", { class: "row" }, h("b", {}, "Rencana"), h("div", { class: "spacer" }), h("span", { class: "mono muted small" }, done + "/" + todos.length)),
      h("div", { class: "bar" }, h("i", { style: { width: (100 * done / todos.length) + "%" } })),
      todos.map((t) => h("div", { class: "it" + (t.status === "done" ? " done" : "") }, h("span", {}, t.status === "done" ? "✅" : t.status === "in_progress" ? "⏳" : "○"), t.content))));
  }
  const sendBtn = $("#sendbtn"); if (sendBtn) { sendBtn.classList.toggle("stop", !!(s && s.busy)); sendBtn.replaceChildren(icon(s && s.busy ? "stop" : "send")); }
}
function browserCard(st) {
  const b = S.st.browser || {};
  const path = h("input", { class: "field mono", placeholder: "Otomatis (Chrome / Edge). Isi kalau ga ketemu: C:\\...\\chrome.exe" }); path.value = st.browserPath || "";
  return h("div", { class: "card col" }, h("b", { style: { fontSize: "16px" } }, "Browser agen"),
    h("div", { class: "muted small" }, "Agent buka web pakai Chrome/Edge di laptop ini (profil terpisah, login lu di Chrome ga kesentuh). Cuma nyala pas dipakai, mati sendiri kalau 3 menit nganggur. Matiin grupnya di atas kalau laptop berat."),
    h("div", { class: "mono small", style: { color: b.path ? "var(--green)" : "var(--amber)" } }, b.path ? "✓ " + b.path : "⚠ Chrome / Edge ga ketemu — isi lokasinya di bawah"),
    h("div", { class: "row" }, h("div", { style: { flex: 1 } }, h("b", {}, "Tampilin jendela browser"), h("div", { class: "muted small" }, "Buat nonton agent kerja atau login manual. Mati = jalan di belakang layar (lebih ringan).")), sw(!!st.browserShow, (v) => saveSettings({ browserShow: v }))),
    h("div", { class: "row" }, path, h("button", { class: "btn", onclick: () => saveSettings({ browserPath: path.value.trim() }).then(() => { toast("Kesimpen"); refresh().then(render); }) }, "Simpan")),
    b.running ? h("div", { class: "row" }, h("span", { class: "muted small", style: { flex: 1 } }, "Lagi nyala: " + (b.title || b.url || "")), h("button", { class: "btn", onclick: () => api("/api/browser/stop", {}).then(() => refresh().then(render)) }, "Tutup browser")) : null);
}
function toolChip(c, r) {
  const key = c.id; const open = S.expanded.has(key);
  const a = c.args || {}; const sum = [a.host, a.command || a.path || a.query || a.table || a.url || a.local_path || a.text || a.target || a.name].filter(Boolean).join(" · ");
  const st = !r ? "run" : r.isError ? "err" : "ok";
  const el = h("div", { class: "tool", onclick: () => { open ? S.expanded.delete(key) : S.expanded.add(key); renderChat(); } },
    h("div", { class: "head" }, h("span", { class: "st " + st }), h("b", {}, c.name), h("span", { class: "sum" }, String(sum).replace(/\n/g, " "))),
    open ? h("div", { class: "body" }, JSON.stringify(a, null, 2) + "\n\n→ " + (r ? r.text : "…")) : null,
    r && r.images && r.images.length ? h("div", { class: "shots" }, r.images.map((p) => h("img", { src: "/files?path=" + encodeURIComponent(p), loading: "lazy", onclick: (e) => { e.stopPropagation(); window.open("/files?path=" + encodeURIComponent(p)); } }))) : null);
  return el;
}
function composer() {
  const ta = h("textarea", { rows: 1, placeholder: "Suruh agent ngapain… (ketik / buat skill)", id: "composer" });
  const slash = h("div", { id: "slashbox" });
  const fit = () => { ta.style.height = "auto"; ta.style.height = Math.min(180, ta.scrollHeight) + "px"; };
  const showSlash = () => {
    const v = ta.value; slash.replaceChildren();
    if (!v.startsWith("/") || v.includes(" ")) return;
    const q = v.slice(1).toLowerCase();
    const opts = [["/compress", "ringkas konteks"], ...S.st.skills.map((s) => ["/" + s.name, s.description])].filter((o) => o[0].slice(1).startsWith(q));
    if (!opts.length) return;
    slash.append(h("div", { class: "card slash", style: { padding: "6px" } }, opts.map(([c, d]) => h("div", { class: "opt", onclick: () => { ta.value = c + (c === "/compress" ? "" : " "); slash.replaceChildren(); ta.focus(); } }, h("b", { class: "mono", style: { color: "var(--cyan)" } }, c), h("span", { class: "muted small" }, d)))));
  };
  ta.addEventListener("input", () => { fit(); showSlash(); });
  ta.addEventListener("keydown", (e) => { if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); send(); } });
  const btn = h("button", { class: "send", id: "sendbtn", onclick: () => (S.session && S.session.busy ? api("/api/stop", { sid: S.sid }) : send()) }, icon("send"));
  return h("div", {}, slash, h("div", { class: "composer" }, ta, btn));
}
async function send(text) {
  const ta = $("#composer");
  text = text != null ? text : ta.value;
  if (!text.trim()) return;
  if (S.session && S.session.busy) return;
  if (ta) { ta.value = ""; ta.style.height = "auto"; }
  $("#slashbox") && $("#slashbox").replaceChildren();
  const r = await tryDo(() => api("/api/chat", { sid: S.sid, text }));
  if (r.sid !== S.sid) { S.sid = r.sid; localStorage.setItem("sid", r.sid); }
  await loadSession();
}

// ===================================================================== HOST
const TERMS = {}; // id -> {x, fit, seq, alive}
async function ensureConnected(hst) {
  for (let i = 0; i < 3; i++) {
    try { await api("/api/host/connect", { id: hst.id, password: hst._pw }); return true; }
    catch (e) {
      if (e.status === 409 && e.data && e.data.needTrust) {
        const ok = await modal((close) => [h("h2", { style: { color: e.data.old ? "var(--red)" : "" } }, e.data.old ? "⚠️ Host key BERUBAH!" : "Server baru nih"),
          h("p", { class: "muted" }, e.data.old ? "Fingerprint beda dari sebelumnya. Bisa karena server di-reinstall, atau ada yang nyadap. Lanjut cuma kalau lu yakin." : "Pertama kali connect ke " + hst.host + ". Cocokin fingerprint ini kalau mau aman:"),
          h("pre", {}, e.data.keytype + "\n" + e.data.fp),
          h("div", { class: "row", style: { justifyContent: "flex-end" } }, h("button", { class: "btn ghost", onclick: () => close(false) }, "Tolak"), h("button", { class: "btn " + (e.data.old ? "danger" : "primary"), onclick: () => close(true) }, "Percaya & lanjut"))]);
        if (!ok) return false;
        await api("/api/host/trust", { id: hst.id, keytype: e.data.keytype, fp: e.data.fp });
        continue;
      }
      if (/Password belum|Login gagal/.test(e.message)) {
        const pw = await modal((close) => { const f = h("input", { class: "field", type: "password", placeholder: "Password" }); f.onkeydown = (ev) => ev.key === "Enter" && close(f.value);
          return [h("h2", {}, hst.username + "@" + hst.host), /gagal/.test(e.message) ? h("p", { style: { color: "var(--amber)" } }, e.message) : null, f, h("div", { class: "row", style: { justifyContent: "flex-end", marginTop: "12px" } }, h("button", { class: "btn ghost", onclick: () => close(null) }, "Batal"), h("button", { class: "btn primary", onclick: () => close(f.value) }, "Masuk"))]; });
        if (pw == null) return false;
        hst._pw = pw; continue;
      }
      toast(e.message, true); return false;
    }
  }
  return false;
}
async function openTerminal(hst) {
  if (!(await ensureConnected(hst))) return;
  const r = await tryDo(() => api("/api/term/open", { hostId: hst.id, cols: 100, rows: 30 }));
  S.hostSub = { type: "term", id: r.id }; await refresh(); render(true);
}
function viewHost(force) {
  const sub = S.hostSub;
  if (sub && sub.type === "term") return viewTerm();
  if (sub && sub.type === "sftp") return viewSftp();
  if (sub && sub.type === "file") return viewFile();
  const hosts = S.st.hosts;
  const quick = h("input", { class: "field mono", placeholder: "root@192.168.1.10:22  —  quick connect", style: { maxWidth: "460px" } });
  quick.onkeydown = async (e) => {
    if (e.key !== "Enter") return;
    const m = /^(?:([^@]+)@)?([^:@\s]+)(?::(\d+))?$/.exec(quick.value.trim()); if (!m) return toast("Format: user@host:port", true);
    let hst = hosts.find((x) => x.host === m[2] && String(x.port) === (m[3] || "22") && x.username === (m[1] || "root"));
    if (!hst) hst = (await tryDo(() => api("/api/host", { host: { label: m[2], host: m[2], port: +(m[3] || 22), username: m[1] || "root", auth: "password", color: hosts.length } }))).host;
    await refresh(); openTerminal(hst);
  };
  return h("div", { class: "view" },
    h("div", { class: "topbar" }, h("h1", {}, "Host"), h("div", { class: "spacer" }), h("button", { class: "btn primary", onclick: () => editHost() }, icon("plus"), "Host baru")),
    h("div", { style: { padding: "0 22px 12px" }, class: "row" }, quick),
    S.st.terms.length ? h("div", { class: "term-tabs" }, S.st.terms.map((t) => h("div", { class: "term-tab press", onclick: () => { S.hostSub = { type: "term", id: t.id }; render(); } }, h("span", { class: "dot " + (t.alive ? "on" : "") }), t.label))) : null,
    h("div", { class: "scroll", style: { flex: 1 } }, hosts.length ? h("div", { class: "grid stagger" }, hosts.map((x, i) => hostCard(x))) :
      h("div", { class: "empty" }, h("div", {}, h("div", { class: "ico" }, icon("host")), h("h3", {}, "Belum ada server"), h("div", {}, "Ketik user@ip di atas buat langsung masuk, atau klik Host baru.")))));
}
function hostCard(x) {
  return h("div", { class: "host press", style: { "--g": grad(x.color) }, onclick: () => openTerminal(x) },
    h("div", { class: "row" }, h("div", { class: "avatar", style: { background: grad(x.color) } }, (x.label || x.host)[0].toUpperCase()), h("div", { class: "spacer" }),
      x.connected ? h("span", { class: "dot on" }) : null,
      h("button", { class: "icon-btn", onclick: (e) => { e.stopPropagation(); hostMenu(x); } }, icon("more"))),
    h("h3", {}, x.label), h("div", { class: "mono muted small", style: { whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" } }, x.username + "@" + x.host + (x.port != 22 ? ":" + x.port : "")),
    h("div", { class: "row small", style: { marginTop: "8px", color: GRADS[(x.color || 0) % 6][1] } }, icon(x.auth === "key" ? "key" : "shield"), x.auth === "key" ? "key" : "password", x.startup ? h("span", { class: "muted" }, "▶ auto-run") : null));
}
async function hostMenu(x) {
  const act = await modal((close) => [h("div", { class: "row" }, h("div", { class: "avatar", style: { background: grad(x.color) } }, x.label[0].toUpperCase()), h("div", {}, h("h2", { style: { margin: 0 } }, x.label), h("div", { class: "mono muted small" }, x.username + "@" + x.host))),
    h("div", { class: "col", style: { marginTop: "14px" } },
      h("button", { class: "btn", onclick: () => close("term") }, icon("term"), "Buka terminal"), h("button", { class: "btn", onclick: () => close("sftp") }, icon("folder"), "File (SFTP)"),
      h("button", { class: "btn", onclick: () => close("edit") }, icon("edit"), "Edit"), h("button", { class: "btn", onclick: () => close("key") }, icon("key"), "Bikin & pasang SSH key"),
      x.connected ? h("button", { class: "btn", onclick: () => close("disc") }, icon("power"), "Putusin koneksi") : null,
      h("button", { class: "btn danger", onclick: () => close("del") }, icon("trash"), "Hapus"))]);
  if (act === "term") openTerminal(x);
  if (act === "sftp") { if (await ensureConnected(x)) { S.hostSub = { type: "sftp", hostId: x.id, path: "" }; render(); } }
  if (act === "edit") editHost(x);
  if (act === "disc") await tryDo(() => api("/api/host/disconnect", { id: x.id }));
  if (act === "key" && await ensureConnected(x)) { const r = await tryDo(() => api("/api/keygen", { id: x.id })); modal((c) => [h("h2", {}, "Key kepasang 🎉"), h("p", { class: "muted" }, x.label + " sekarang login pakai key ed25519 ini:"), h("pre", {}, r.public), h("button", { class: "btn primary", onclick: () => c() }, "Sip")]); }
  if (act === "del" && await confirmBox("Hapus " + x.label + "?", "Password & key yang tersimpan ikut kehapus.")) await tryDo(() => api("/api/host/delete", { id: x.id }));
  await refresh(); render();
}
async function editHost(x) {
  x = x || { label: "", host: "", port: 22, username: "root", auth: "password", color: S.st.hosts.length, startup: "" };
  const f = (k, ph, type) => { const i = h("input", { class: "field" + (/host|port|username|startup/.test(k) ? " mono" : ""), placeholder: ph, type: type || "text" }); i.value = x[k] != null ? x[k] : ""; i.dataset.k = k; return i; };
  let auth = x.auth, color = x.color || 0;
  const res = await modal((close) => {
    const pw = h("input", { class: "field", type: "password", placeholder: x.id ? "Password (kosongin = ga diganti)" : "Password (kosongin = ditanya pas connect)" });
    const key = h("textarea", { class: "field mono", placeholder: "-----BEGIN OPENSSH PRIVATE KEY-----", style: { fontSize: "11px" } });
    const pp = h("input", { class: "field", type: "password", placeholder: "Passphrase (kalau ada)" });
    const fileIn = h("input", { type: "file", class: "hidden", onchange: async () => { key.value = await fileIn.files[0].text(); } });
    const authBox = h("div", { class: "col" });
    const drawAuth = () => authBox.replaceChildren(seg([["password", "Password"], ["key", "SSH Key"]], auth, (v) => { auth = v; drawAuth(); }), auth === "password" ? pw : h("div", { class: "col" }, key, h("button", { class: "btn ghost", onclick: () => fileIn.click() }, icon("upload"), "Ambil dari file"), fileIn, pp));
    drawAuth();
    const colors = h("div", { class: "row" });
    const drawColors = () => colors.replaceChildren(...GRADS.map((g, i) => h("div", { class: "press", style: { width: "36px", height: "36px", borderRadius: "12px", background: grad(i), outline: i === color ? "2.5px solid var(--text)" : "none", outlineOffset: "2px" }, onclick: () => { color = i; drawColors(); } })));
    drawColors();
    const fields = [f("label", "Nama (mis. VPS, Laptop Leo)"), f("host", "IP / domain"), f("port", "22"), f("username", "username"), f("startup", "Auto-run pas masuk, mis. tmux new -A -s main")];
    return [h("h2", {}, x.id ? "Edit host" : "Host baru"), h("div", { class: "col" }, fields[0], h("div", { class: "row" }, h("div", { style: { flex: 3 } }, fields[1]), h("div", { style: { flex: 1 } }, fields[2])), fields[3],
      h("label", { class: "lbl" }, "Login pakai"), authBox, h("label", { class: "lbl" }, "Auto-run"), fields[4], h("label", { class: "lbl" }, "Warna"), colors,
      h("div", { class: "row", style: { justifyContent: "flex-end", marginTop: "8px" } }, h("button", { class: "btn ghost", onclick: () => close(null) }, "Batal"),
        h("button", { class: "btn primary", onclick: () => { const o = {}; fields.forEach((i) => (o[i.dataset.k] = i.value.trim())); close({ host: Object.assign({}, x, o, { auth, color, port: +(o.port || 22) }), password: pw.value, key: key.value.trim(), passphrase: pp.value }); } }, "Simpan")))];
  });
  if (!res) return;
  if (!res.host.host) return toast("Alamat host wajib diisi", true);
  if (res.key && !/PRIVATE KEY/.test(res.key)) return toast('Itu bukan private key (harus ada "PRIVATE KEY")', true);
  await tryDo(() => api("/api/host", res), "Kesimpen");
  await refresh(); render();
}

// ----------------------------------------------------------------- terminal
let termCtrl = false, termAlt = false;
function viewTerm() {
  const v = h("div", { class: "view" }, h("div", { class: "topbar", id: "termbar" }), h("div", { class: "term-tabs", id: "termtabs" }), h("div", { class: "term-box", id: "termbox" }), h("div", { class: "keys", id: "termkeys" }));
  setTimeout(() => { renderTermChrome(); mountTerm(S.hostSub.id); }, 0);
  return v;
}
function renderTermChrome() {
  const id = S.hostSub && S.hostSub.id; const t = S.st.terms.find((x) => x.id === id); if (!$("#termbar")) return;
  $("#termbar").replaceChildren(h("button", { class: "icon-btn", onclick: () => { S.hostSub = null; render(); } }, icon("left")),
    h("span", { class: "dot " + (t && t.alive ? "on" : "") }), h("h1", { style: { fontSize: "20px" } }, t ? t.label : "terminal"), h("div", { class: "spacer" }),
    t ? h("button", { class: "icon-btn", title: "File", onclick: () => { S.hostSub = { type: "sftp", hostId: t.hostId, path: "", back: id }; render(); } }, icon("folder")) : null,
    h("button", { class: "icon-btn", title: "Tutup sesi", onclick: async () => { await api("/api/term/close", { id }); TERMS[id] && TERMS[id].x.dispose(); delete TERMS[id]; await refresh(); const next = S.st.terms[0]; S.hostSub = next ? { type: "term", id: next.id } : null; render(); } }, icon("close")));
  $("#termtabs").replaceChildren(...S.st.terms.map((x) => h("div", { class: "term-tab" + (x.id === id ? " on" : ""), onclick: () => { S.hostSub = { type: "term", id: x.id }; $("#main").replaceChildren(viewTerm()); } }, h("span", { class: "dot " + (x.alive ? "on" : "") }), x.label)));
  const k = (label, seq, extra) => h("button", Object.assign({ onclick: () => { sendKey(seq); } }, extra || {}), label);
  $("#termkeys").replaceChildren(k("ESC", "\x1b"), k("TAB", "\t"),
    h("button", { class: termCtrl ? "on" : "", onclick: () => { termCtrl = !termCtrl; renderTermChrome(); } }, "CTRL"), h("button", { class: termAlt ? "on" : "", onclick: () => { termAlt = !termAlt; renderTermChrome(); } }, "ALT"),
    k("↑", "\x1b[A"), k("↓", "\x1b[B"), k("←", "\x1b[D"), k("→", "\x1b[C"), k("^C", "\x03", { style: { color: "var(--pink)" } }), k("/", "/"), k("-", "-"), k("|", "|"), k("~", "~"), k("HOME", "\x1b[H"), k("END", "\x1b[F"), k("PGUP", "\x1b[5~"), k("PGDN", "\x1b[6~"),
    h("button", { onclick: async () => { try { sendKey(await navigator.clipboard.readText()); } catch (e) { toast("Clipboard ga bisa dibaca", true); } } }, "PASTE"));
}
function termWrite(id, data) { if (!data) return; api("/api/term/write", { id, data }).catch(() => { }); }
function sendKey(seq) { const id = S.hostSub && S.hostSub.id; let out = seq; if (termCtrl && seq.length === 1) { const c = seq.toUpperCase().charCodeAt(0); if (c >= 64 && c <= 95) out = String.fromCharCode(c - 64); termCtrl = false; renderTermChrome(); } if (termAlt) { out = "\x1b" + out; termAlt = false; renderTermChrome(); } termWrite(id, out); TERMS[id] && TERMS[id].x.focus(); }
function mountTerm(id) {
  const box = $("#termbox"); if (!box) return;
  let T = TERMS[id];
  if (!T) {
    const x = new Terminal({ fontFamily: "JetBrainsMono, Consolas, monospace", fontSize: +(localStorage.getItem("fontSize") || 14), cursorBlink: true, allowProposedApi: true, scrollback: 10000,
      theme: { background: "#0c0d12", foreground: "#e6e8ef", cursor: "#22d3ee", selectionBackground: "#7c5cff55", black: "#1d2029", red: "#ff5d5d", green: "#34d399", yellow: "#fbbf24", blue: "#7c9cff", magenta: "#b98cff", cyan: "#22d3ee", white: "#d5d7e0", brightBlack: "#5c6070", brightRed: "#ff8080", brightGreen: "#6ee7b7", brightYellow: "#fde68a", brightBlue: "#a5b8ff", brightMagenta: "#d4b5ff", brightCyan: "#67e8f9", brightWhite: "#ffffff" } });
    const fit = new FitAddon.FitAddon(); x.loadAddon(fit);
    T = TERMS[id] = { x, fit, seq: 0, el: h("div", { style: { width: "100%", height: "100%" } }) };
    x.open(T.el);
    let buf = "", tm = null;
    x.onData((d) => { if (termCtrl && d.length === 1) { const c = d.toUpperCase().charCodeAt(0); if (c >= 64 && c <= 95) d = String.fromCharCode(c - 64); termCtrl = false; renderTermChrome(); } if (termAlt) { d = "\x1b" + d; termAlt = false; renderTermChrome(); } buf += d; clearTimeout(tm); tm = setTimeout(() => { termWrite(id, buf); buf = ""; }, 8); });
    x.onResize(({ cols, rows }) => api("/api/term/resize", { id, cols, rows }).catch(() => { }));
    (async function poll() {
      while (TERMS[id] === T) {
        try {
          const r = await api("/api/term/read?id=" + id + "&seq=" + T.seq);
          if (r.data) { const bin = atob(r.data); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); x.write(u); }
          T.seq = r.seq;
          if (!r.alive) { refresh().then(renderTermChrome); break; }
        } catch (e) { await new Promise((r) => setTimeout(r, 1500)); }
      }
    })();
  }
  box.dataset.tid = id;
  box.replaceChildren(T.el);
  setTimeout(() => { try { T.fit.fit(); } catch (e) { } T.x.focus(); }, 30);
  window.onresize = () => { const t = TERMS[S.hostSub && S.hostSub.id]; if (t) try { t.fit.fit(); } catch (e) { } };
}

// --------------------------------------------------------------------- sftp
const KIND = (name) => { const e = (name.split(".").pop() || "").toLowerCase();
  if (["md", "markdown"].includes(e)) return "md"; if (["html", "htm"].includes(e)) return "html";
  if (["png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "bmp"].includes(e)) return "image";
  if (["mp4", "webm", "mkv", "mov", "m4v"].includes(e)) return "video"; if (["mp3", "m4a", "aac", "wav", "ogg", "opus", "flac"].includes(e)) return "audio";
  if (["zip", "gz", "tar", "xz", "7z", "rar", "pdf", "exe", "bin", "so", "iso", "jar", "apk", "woff", "woff2", "ttf"].includes(e)) return "other";
  return "text"; };
const KIND_ICON = { dir: ["folder", "#7c5cff", "rgba(124,92,255,.16)"], md: ["book", "#7c5cff", "rgba(124,92,255,.16)"], html: ["code", "#ff5c9a", "rgba(255,92,154,.16)"], image: ["image", "#34d399", "rgba(52,211,153,.16)"], video: ["video", "#fbbf24", "rgba(251,191,36,.16)"], audio: ["music", "#ff5c9a", "rgba(255,92,154,.16)"], text: ["file", "#22d3ee", "rgba(34,211,238,.16)"], other: ["file", "#8a8fa3", "rgba(138,143,163,.16)"] };
const rawUrl = (hid, p, dl) => "/api/sftp/raw?host=" + hid + "&path=" + encodeURIComponent(p) + (dl ? "&dl=1" : "");
function viewSftp() {
  const sub = S.hostSub; const hst = S.st.hosts.find((x) => x.id === sub.hostId) || {};
  const list = h("div", { class: "files" }, h("div", { class: "muted", style: { padding: "20px" } }, "Ngebuka…"));
  const upIn = h("input", { type: "file", multiple: true, class: "hidden" });
  const join = (n) => (sub.path === "/" ? "" : sub.path) + "/" + n;
  const load = async (p) => {
    try {
      const r = await api("/api/sftp/list?host=" + sub.hostId + "&path=" + encodeURIComponent(p));
      sub.path = r.path; $("#sftppath").textContent = r.path;
      const showHidden = localStorage.getItem("hidden") === "1";
      const items = r.items.filter((i) => showHidden || !i.name.startsWith("."));
      list.replaceChildren(h("div", { class: "stagger" },
        r.path !== "/" ? h("div", { class: "frow", onclick: () => load(r.path.replace(/\/[^/]+\/?$/, "") || "/") }, h("div", { class: "fico", style: { background: "var(--surface2)" } }, icon("up")), h("span", { class: "n" }, ".."), h("span", { class: "muted small" }, "naik")) : null,
        items.map((i) => { const k = i.dir ? null : KIND(i.name); const [ic, col, bg] = KIND_ICON[i.dir ? "dir" : k];
          return h("div", { class: "frow", onclick: () => (i.dir ? load(join(i.name)) : k === "other" ? fileMenu(i) : openFile(join(i.name), i.size)), oncontextmenu: (e) => { e.preventDefault(); fileMenu(i); } },
            h("div", { class: "fico", style: { background: bg, color: col } }, icon(ic)), h("span", { class: "n" }, i.name),
            h("span", { class: "muted small" }, i.dir ? "folder" : fmtSize(i.size)), h("button", { class: "icon-btn", onclick: (e) => { e.stopPropagation(); fileMenu(i); } }, icon("more"))); })));
    } catch (e) { list.replaceChildren(h("div", { class: "empty" }, h("div", {}, h("h3", {}, "Ga bisa dibuka"), e.message))); }
  };
  const openFile = (p, size) => { S.hostSub = { type: "file", hostId: sub.hostId, path: p, size, back: sub }; render(); };
  const fileMenu = async (i) => {
    const p = join(i.name);
    const act = await modal((close) => [h("h2", {}, i.name), h("div", { class: "col" },
      !i.dir ? h("button", { class: "btn", onclick: () => close("open") }, icon("eye"), "Buka / edit") : null,
      !i.dir ? h("button", { class: "btn", onclick: () => close("dl") }, icon("download"), "Download") : null,
      h("button", { class: "btn", onclick: () => close("ren") }, icon("edit"), "Rename"),
      h("button", { class: "btn", onclick: () => close("copy") }, icon("link"), "Copy path"),
      h("button", { class: "btn danger", onclick: () => close("del") }, icon("trash"), "Hapus"))]);
    if (act === "open") openFile(p, i.size);
    if (act === "dl") { const a = h("a", { href: rawUrl(sub.hostId, p, 1), download: i.name }); document.body.append(a); a.click(); a.remove(); }
    if (act === "copy") { navigator.clipboard.writeText(p); toast("Path ke-copy"); }
    if (act === "ren") { const n = await askText("Rename", i.name); if (n && n !== i.name) { await tryDo(() => api("/api/sftp/rename", { host: sub.hostId, from: p, to: join(n) })); load(sub.path); } }
    if (act === "del" && await confirmBox("Hapus " + i.name + "?", i.dir ? "Folder harus kosong dulu." : "Ga bisa di-undo.")) { await tryDo(() => api("/api/sftp/delete", { host: sub.hostId, path: p, dir: i.dir })); load(sub.path); }
  };
  upIn.onchange = async () => {
    for (const f of upIn.files) {
      toast("Upload " + f.name + "…");
      const r = await fetch("/api/sftp/upload?host=" + sub.hostId + "&path=" + encodeURIComponent(join(f.name)), { method: "POST", body: f, credentials: "same-origin" });
      if (!r.ok) toast("Gagal upload " + f.name, true);
    }
    toast("Upload beres"); upIn.value = ""; load(sub.path);
  };
  const v = h("div", { class: "view" },
    h("div", { class: "topbar" }, h("button", { class: "icon-btn", onclick: () => { S.hostSub = sub.back ? { type: "term", id: sub.back } : null; render(); } }, icon("left")),
      h("div", { style: { minWidth: 0 } }, h("h1", { style: { fontSize: "20px" } }, hst.label || "SFTP"), h("div", { class: "mono muted small", id: "sftppath" }, sub.path)), h("div", { class: "spacer" }),
      h("button", { class: "icon-btn", title: "File tersembunyi", onclick: () => { localStorage.setItem("hidden", localStorage.getItem("hidden") === "1" ? "0" : "1"); load(sub.path); } }, icon("eye")),
      h("button", { class: "icon-btn", title: "File baru", onclick: async () => { const n = await askText("File baru", "", "mis. notes.md"); if (n) { await tryDo(() => api("/api/sftp/touch", { host: sub.hostId, path: join(n) })); openFile(join(n), 0); } } }, icon("file")),
      h("button", { class: "icon-btn", title: "Folder baru", onclick: async () => { const n = await askText("Folder baru", "", "nama folder"); if (n) { await tryDo(() => api("/api/sftp/mkdir", { host: sub.hostId, path: join(n) })); load(sub.path); } } }, icon("folder")),
      h("button", { class: "icon-btn", title: "Refresh", onclick: () => load(sub.path) }, icon("refresh")),
      h("button", { class: "btn primary", onclick: () => upIn.click() }, icon("upload"), "Upload"), upIn),
    list);
  setTimeout(() => load(sub.path || ""), 0);
  return v;
}
function viewFile() {
  const sub = S.hostSub; const name = sub.path.split("/").pop(); const kind = sub.forceText ? "text" : KIND(name);
  const textual = ["text", "md", "html"].includes(kind);
  let original = null, mode = textual && kind !== "text" ? "preview" : "edit";
  const body = h("div", { style: { flex: 1, display: "flex", flexDirection: "column", minHeight: 0 } });
  const ta = h("textarea", { spellcheck: "false" }); const gutter = h("div", { class: "gutter" });
  const dirtyDot = h("span", { style: { color: "var(--amber)" } });
  const lines = () => { gutter.textContent = Array.from({ length: ta.value.split("\n").length }, (_, i) => i + 1).join("\n"); };
  ta.oninput = () => { lines(); dirtyDot.textContent = ta.value !== original ? " ●" : ""; };
  ta.onscroll = () => { gutter.scrollTop = ta.scrollTop; };
  ta.onkeydown = (e) => { if (e.key === "Tab") { e.preventDefault(); document.execCommand("insertText", false, "  "); } if ((e.ctrlKey || e.metaKey) && e.key === "s") { e.preventDefault(); save(); } };
  const save = async () => { await tryDo(() => api("/api/sftp/write", { host: sub.hostId, path: sub.path, content: ta.value }), "Kesimpen"); original = ta.value; dirtyDot.textContent = ""; if (mode === "preview") draw(); };
  const url = rawUrl(sub.hostId, sub.path);
  const draw = () => {
    if (mode === "edit" && textual) return body.replaceChildren(h("div", { class: "editor" }, gutter, ta));
    if (kind === "md") return body.replaceChildren(h("div", { class: "preview md" }, h("div", { class: "md", html: md(ta.value) })));
    if (kind === "html") return body.replaceChildren(h("div", { class: "preview" }, h("iframe", { src: "/api/sftp/site/" + sub.hostId + sub.path.split("/").map(encodeURIComponent).join("/") + "?t=" + Date.now() })));
    if (kind === "image") return body.replaceChildren(h("div", { class: "preview media" }, h("img", { src: url })));
    if (kind === "video") return body.replaceChildren(h("div", { class: "preview media" }, h("video", { src: url, controls: true, autoplay: true })));
    if (kind === "audio") { const disc = h("div", { class: "disc" }); const au = h("audio", { src: url, controls: true, autoplay: true, style: { width: "min(520px, 90%)" }, onplay: () => disc.classList.add("playing"), onpause: () => disc.classList.remove("playing") });
      return body.replaceChildren(h("div", { class: "preview media", style: { gap: "28px", alignContent: "center" } }, disc, h("div", { style: { color: "#fff", fontWeight: 700 } }, name), au)); }
    body.replaceChildren(h("div", { class: "empty" }, h("div", {}, h("h3", {}, "Ga bisa di-preview"), h("a", { href: rawUrl(sub.hostId, sub.path, 1), class: "btn primary" }, "Download"))));
  };
  const back = async () => { if (original != null && ta.value !== original && !(await confirmBox("Belum disimpen", "Buang perubahan di " + name + "?", "Buang"))) return; S.hostSub = sub.back; render(); };
  const bar = h("div", { class: "topbar" }, h("button", { class: "icon-btn", onclick: back }, icon("left")),
    h("div", { style: { minWidth: 0 } }, h("h1", { style: { fontSize: "19px" } }, name, dirtyDot), h("div", { class: "mono muted small" }, sub.path)), h("div", { class: "spacer" }),
    textual && kind !== "text" ? seg([["preview", "Preview"], ["edit", "Edit"]], mode, (v) => { mode = v; bar.querySelectorAll(".seg button").forEach((b, i) => b.classList.toggle("on", (i === 0) === (v === "preview"))); draw(); }) : null,
    textual ? h("button", { class: "btn primary", onclick: save }, icon("save"), "Simpan") : h("a", { class: "btn", href: rawUrl(sub.hostId, sub.path, 1) }, icon("download"), "Download"),
    kind === "html" ? h("a", { class: "icon-btn", href: "/api/sftp/site/" + sub.hostId + sub.path, target: "_blank", title: "Buka di tab baru" }, icon("globe")) : null);
  const v = h("div", { class: "view" }, bar, body);
  if (textual) {
    if ((sub.size || 0) > 2 * 1024 * 1024) { body.append(h("div", { class: "empty" }, h("div", {}, h("h3", {}, "File kegedean buat diedit (> 2 MB)")))); return v; }
    fetch(url, { credentials: "same-origin" }).then((r) => r.text()).then((t) => { original = t; ta.value = t; lines(); draw(); });
  } else setTimeout(draw, 0);
  return v;
}

// ==================================================================== BRAIN
function viewBrain() {
  const tabs = [["soul", "Soul"], ["memory", "Memori"], ["skills", "Skill"], ["jobs", "Jadwal"]];
  const pane = h("div", { class: "pane" });
  const v = h("div", { class: "view" }, h("div", { class: "topbar" }, h("h1", { class: "grad-text" }, "Otak " + activeProf().emoji + " " + activeProf().name), h("div", { class: "spacer" }), h("button", { class: "btn", onclick: profileMenu }, "Ganti profil")),
    h("div", { class: "tabs" }, tabs.map(([k, l]) => h("button", { class: S.brainTab === k ? "on" : "", onclick: () => { S.brainTab = k; render(); } }, l))), pane);
  const inner = h("div", { class: "pane-inner stagger" }); pane.append(inner);
  ({ soul: brainSoul, memory: brainMemory, skills: brainSkills, jobs: brainJobs })[S.brainTab](inner);
  return v;
}
function brainSoul(el) {
  const ta = h("textarea", { class: "field mono", style: { minHeight: "52vh", fontSize: "13px", lineHeight: 1.5 } }); ta.value = S.st.soul;
  let preview = true; const box = h("div");
  const draw = () => box.replaceChildren(preview ? h("div", { class: "card md", html: md(ta.value) }) : ta);
  draw();
  el.append(h("div", { class: "row" }, h("div", { class: "muted", style: { flex: 1 } }, "Kepribadian & prinsip agent. Selalu jadi bagian paling atas prompt-nya."),
    h("button", { class: "btn", onclick: () => { preview = !preview; draw(); } }, icon(preview ? "edit" : "eye"), preview ? "Edit" : "Preview"),
    h("button", { class: "btn primary", onclick: () => tryDo(() => api("/api/soul", { text: ta.value }), "Soul kesimpen") }, icon("save"), "Simpan")), box,
    h("button", { class: "btn ghost", style: { color: "var(--muted)" }, onclick: async () => { if (await confirmBox("Reset SOUL?", "Balik ke kepribadian bawaan.", "Reset")) { await api("/api/soul", { text: "" }); await refresh(); render(); } } }, "Reset ke bawaan"));
}
function brainMemory(el) {
  const sec = (target, title, hint) => {
    const items = S.st.memory[target]; const lim = S.st.memory.limits[target]; const used = items.join("\n§\n").length;
    const save = (list) => tryDo(() => api("/api/memory", { target, entries: list })).then(refresh).then(render);
    const edit = async (i) => { const t = await askText(i == null ? "Entri baru" : "Edit entri", i == null ? "" : items[i], "", true); if (!t || !t.trim()) return; const l = items.slice(); i == null ? l.push(t.trim()) : (l[i] = t.trim()); save(l); };
    return h("div", { class: "card col" },
      h("div", { class: "row" }, h("b", { style: { fontSize: "16px" } }, title), h("div", { class: "spacer" }), h("span", { class: "mono small", style: { color: used / lim > .85 ? "var(--amber)" : "var(--muted)" } }, used + "/" + lim), h("button", { class: "icon-btn", onclick: () => edit(null) }, icon("plus"))),
      h("div", { class: "muted small" }, hint), h("div", { class: "meter" + (used / lim > .85 ? " warn" : "") }, h("i", { style: { width: Math.min(100, 100 * used / lim) + "%" } })),
      items.length ? items.map((t, i) => h("div", { class: "entry" }, h("div", { class: "press", onclick: () => edit(i) }, t), h("button", { class: "icon-btn", style: { width: "30px", height: "30px" }, onclick: () => { const l = items.slice(); l.splice(i, 1); save(l); } }, icon("close"))))
        : h("div", { class: "muted small" }, "Masih kosong — agent bakal ngisi sendiri seiring ngobrol."));
  };
  const every = S.st.settings.reviewEvery;
  el.append(sec("user", "Tentang lu", "Preferensi, kebiasaan, gaya kerja lu."), sec("memory", "Catatan agent", "Fakta lingkungan, path project, cara restart, pelajaran."),
    h("div", { class: "card col" }, h("b", { style: { fontSize: "16px" } }, "Refleksi otomatis"), h("div", { class: "muted small" }, "Tiap N pesan, agent review obrolan di background & nyimpen memori/skill yang berguna."),
      seg([[0, "Mati"], [4, "tiap 4"], [6, "tiap 6"], [10, "tiap 10"]], every, (v) => tryDo(() => api("/api/settings", { reviewEvery: v })).then(refresh).then(render))));
}
function skillTag(s) {
  if (!s.builtin) return null;
  return h("span", { class: "chip-tag" + (s.modified ? " warn" : "") }, s.modified ? "bawaan · diubah" : "bawaan");
}
function brainSkills(el) {
  const fileIn = h("input", { type: "file", accept: ".md,text/markdown,text/plain", class: "hidden", onchange: async () => { const raw = await fileIn.files[0].text(); await tryDo(() => api("/api/skill", { raw }), "Skill masuk"); await refresh(); render(); } });
  const changed = S.st.skills.filter((s) => s.modified).length, gone = (S.st.missingBuiltins || []).length;
  el.append(h("div", { class: "row" }, h("div", { class: "muted", style: { flex: 1 } }, "Prosedur yang bisa dipanggil agent (atau lu lewat /nama-skill di chat). Agent bisa bikin & benerin skill sendiri — kecuali skill BAWAAN: itu cuma lu yang bisa ubah."),
    h("button", { class: "btn", onclick: () => pushSkills() }, icon("up"), "Push ke Hermes"),
    h("button", { class: "btn", onclick: () => fileIn.click() }, icon("upload"), "Import"), fileIn, h("button", { class: "btn primary", onclick: () => editSkill() }, icon("plus"), "Skill baru")),
    changed + gone ? h("div", { class: "card row", style: { borderColor: "var(--amber)" } }, icon("refresh"),
      h("div", { style: { flex: 1 } }, "Skill bawaan: " + [changed ? changed + " diubah" : "", gone ? gone + " kehapus" : ""].filter(Boolean).join(", ")),
      h("button", { class: "btn", onclick: async () => { if (!(await confirmBox("Kembaliin skill bawaan?", "Semua skill bawaan balik ke versi asli dari app. Skill buatan lu/agent ga kesentuh."))) return;
        const r = await tryDo(() => api("/api/skill/reset", { all: true })); if (r) toast(r.count + " skill bawaan dikembaliin"); await refresh(); render(); } }, "Kembaliin default")) : null,
    ...S.st.skills.map((s, i) => h("div", { class: "card row press", onclick: () => editSkill(s) }, h("div", { class: "avatar", style: { background: grad(i) } }, icon("book")),
      h("div", { style: { minWidth: 0, flex: 1 } }, h("div", { class: "row", style: { gap: "8px" } }, h("b", { class: "mono" }, "/" + s.name), skillTag(s)), h("div", { class: "muted small" }, s.description)))));
}
async function pushSkills(only) {
  const hosts = S.st.hosts;
  if (!hosts.length) return toast("Tambahin dulu server tempat Hermes jalan (menu Host)", true);
  const LAB = { same: ["sinkron", "var(--green)"], differs: ["beda", "var(--amber)"], missing: ["belum ada", "var(--muted)"] };
  await modal((close) => {
    const pick = h("select", { class: "field" }, hosts.map((x) => h("option", { value: x.id }, x.label + " · " + x.host)));
    pick.value = (S.st.settings.skillPushHost && hosts.some((x) => x.id === S.st.settings.skillPushHost)) ? S.st.settings.skillPushHost : (S.st.settings.markasHost || hosts[0].id);
    const body = h("div", { class: "col" }), chosen = new Set(only ? [only] : []);
    const load = async () => {
      body.replaceChildren(h("div", { class: "muted" }, "Ngecek skill di server…"));
      const r = await tryDo(() => api("/api/skillpush/status", { hostId: pick.value }));
      if (!r) return body.replaceChildren(h("div", { style: { color: "var(--red)" } }, "Gagal nyambung."));
      if (!r.hasAgent) return body.replaceChildren(h("div", { style: { color: "var(--amber)" } }, "Hermes ga ketemu di server ini (~/.hermes ga ada)."));
      if (!only && !chosen.size) r.skills.filter((x) => x.state !== "same").forEach((x) => chosen.add(x.name));
      const btn = h("button", { class: "btn primary" }, icon("up"), "Push");
      const upd = () => { btn.lastChild.textContent = "Push " + chosen.size + " skill"; btn.disabled = !chosen.size; };
      btn.onclick = async () => { btn.disabled = true; const x = await tryDo(() => api("/api/skillpush/push", { hostId: pick.value, names: [...chosen] }));
        if (x) toast(x.errors.length ? x.errors.join("\n") : x.pushed.length + " skill ke-push · kepakai di sesi Hermes berikutnya", !!x.errors.length); chosen.clear(); load(); };
      body.replaceChildren(...r.skills.map((x) => { const cb = h("input", { type: "checkbox" }); cb.checked = chosen.has(x.name); cb.onchange = () => { cb.checked ? chosen.add(x.name) : chosen.delete(x.name); upd(); };
        return h("label", { class: "row", style: { gap: "10px", cursor: "pointer" } }, cb, h("b", { class: "mono" }, "/" + x.name), h("span", { class: "small", style: { color: LAB[x.state][1], fontWeight: 700 } }, LAB[x.state][0]), h("span", { class: "muted small", style: { flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } }, x.description)); }),
        h("div", { class: "row" }, h("div", { class: "spacer" }), btn),
        r.onlyRemote.length ? h("b", { style: { marginTop: "10px" } }, "Cuma ada di Hermes") : null,
        ...r.onlyRemote.map((x) => h("div", { class: "row" }, h("span", { class: "mono", style: { flex: 1 } }, x.name + "  "), h("span", { class: "muted small" }, x.path),
          h("button", { class: "btn", onclick: async () => { const y = await tryDo(() => api("/api/skillpush/pull", { hostId: pick.value, path: x.path })); if (y) { toast('Skill "' + y.name + '" ditarik'); await refresh(); load(); } } }, icon("download"), "Tarik"))));
      upd();
    };
    pick.onchange = () => { chosen.clear(); load(); };
    load();
    return [h("h2", {}, "Push skill ke Hermes"), h("div", { class: "muted small" }, "Skill profil aktif dikirim lewat SSH ke ~/.hermes/skills/satsh/<nama>/. Hermes pakai mulai sesi berikutnya. Tool khusus satsh ga ada di Hermes — skill berisi prosedur shell/CLI paling cocok."),
      pick, body, h("div", { class: "row", style: { marginTop: "12px" } }, h("div", { class: "spacer" }), h("button", { class: "btn ghost", onclick: () => close(null) }, "Tutup"))];
  });
  await refresh(); render();
}
async function editSkill(s) {
  const tpl = "---\nname: nama-skill\ndescription: Kapan skill ini dipakai (agent baca ini buat mutusin)\n---\n# Judul\n\n1. Langkah pertama\n2. Langkah kedua\n";
  const r = await modal((close) => { const ta = h("textarea", { class: "field mono", style: { minHeight: "55vh", fontSize: "12.5px" } }); ta.value = s ? s.raw : tpl;
    return [h("h2", {}, s ? "/" + s.name : "Skill baru", s ? skillTag(s) : null), s && s.builtin ? h("div", { class: "muted small" }, "Skill bawaan — agent cuma bisa baca. Lu bebas edit; \"Kembaliin default\" buat balik ke versi asli.") : null, ta, h("div", { class: "row", style: { marginTop: "12px" } },
      s ? h("button", { class: "btn danger", onclick: () => close({ del: true }) }, icon("trash"), "Hapus") : null,
      s && s.modified ? h("button", { class: "btn", onclick: () => close({ reset: true }) }, icon("refresh"), "Kembaliin default") : null,
      s ? h("button", { class: "btn", onclick: () => close({ push: true }) }, icon("up"), "Push ke Hermes") : null, h("div", { class: "spacer" }),
      h("button", { class: "btn ghost", onclick: () => close(null) }, "Batal"), h("button", { class: "btn primary", onclick: () => close({ raw: ta.value }) }, "Simpan"))]; });
  if (!r) return;
  if (r.push) return pushSkills(s.name);
  if (r.reset) { if (await confirmBox("Kembaliin ke bawaan?", "Perubahan lu di /" + s.name + " bakal ilang.")) await tryDo(() => api("/api/skill/reset", { name: s.name }), "/" + s.name + " balik ke versi bawaan"); }
  else if (r.del) { if (await confirmBox("Hapus skill?", "/" + s.name)) await tryDo(() => api("/api/skill/delete", { name: s.name })); }
  else await tryDo(() => api("/api/skill", { raw: r.raw, old: s && s.name }), "Skill kesimpen");
  await refresh(); render();
}
function brainJobs(el) {
  el.append(h("div", { class: "row" }, h("div", { class: "muted", style: { flex: 1 } }, "Agent kerja otomatis sesuai jadwal (selama satsh nyala). Hasilnya masuk ke sesi ⏰ dan dikirim ke Telegram kalau diset."),
    h("button", { class: "btn primary", onclick: () => editJob() }, icon("plus"), "Jadwal baru")));
  if (!S.st.jobs.length) el.append(h("div", { class: "empty" }, h("div", {}, h("div", { class: "ico" }, icon("clock")), h("h3", {}, "Belum ada jadwal"), "Bisa juga minta langsung di chat: \"tiap jam 7 cek disk VPS\".")));
  S.st.jobs.forEach((j) => el.append(h("div", { class: "card col" },
    h("div", { class: "row" }, h("span", { style: { color: j.enabled ? "var(--cyan)" : "var(--muted)" } }, icon("clock")), h("b", { style: { flex: 1 } }, j.name),
      sw(j.enabled, (v) => tryDo(() => api("/api/job", Object.assign({}, j, { enabled: v }))))),
    h("div", { class: "muted" }, j.prompt), h("div", { class: "mono muted small" }, j.label + " · berikutnya " + j.next + (j.allowRisky ? " · aksi berisiko ON" : "")),
    j.lastResult ? h("div", { class: "small", style: /^GAGAL/.test(j.lastResult) ? { color: "var(--red)" } : null }, "Terakhir: " + j.lastResult) : null,
    /^GAGAL/.test(j.lastResult || "") ? h("button", { class: "copy-btn", style: { alignSelf: "flex-start", color: "var(--red)" }, onclick: openErrorLog }, "Lihat log error") : null,
    h("div", { class: "row" }, h("button", { class: "btn", onclick: () => tryDo(() => api("/api/job/run", { id: j.id }), "Jalan di background…") }, icon("play"), "Jalanin"),
      j.sessionId ? h("button", { class: "btn ghost", onclick: () => { S.sid = j.sessionId; localStorage.setItem("sid", j.sessionId); setView("agent"); } }, "Lihat hasil") : null, h("div", { class: "spacer" }),
      h("button", { class: "icon-btn", onclick: () => editJob(j) }, icon("edit")), h("button", { class: "icon-btn", style: { color: "var(--red)" }, onclick: async () => { if (await confirmBox("Hapus jadwal?", j.name)) { await api("/api/job/delete", { id: j.id }); await refresh(); render(); } } }, icon("trash"))))));
}
async function editJob(j) {
  j = j || { name: "", prompt: "", everyMinutes: 60, dailyAt: null, allowRisky: false, enabled: true };
  let daily = !!j.dailyAt, every = j.everyMinutes || 60, time = j.dailyAt || "07:00", risky = j.allowRisky;
  const r = await modal((close) => {
    const name = h("input", { class: "field", placeholder: "Nama, mis. Cek server pagi" }); name.value = j.name;
    const prompt = h("textarea", { class: "field", placeholder: 'Instruksi buat agent, mis. "Cek disk & RAM semua server, kabarin kalau ada yang > 85%"' }); prompt.value = j.prompt;
    const sched = h("div", { class: "col" });
    const draw = () => sched.replaceChildren(seg([[false, "Interval"], [true, "Harian"]], daily, (v) => { daily = v; draw(); }),
      daily ? (() => { const t = h("input", { class: "field", type: "time", style: { maxWidth: "160px" } }); t.value = time; t.onchange = () => (time = t.value); return t; })()
        : seg([[15, "15 mnt"], [30, "30 mnt"], [60, "1 jam"], [180, "3 jam"], [360, "6 jam"], [720, "12 jam"]], every, (v) => { every = v; draw(); }));
    draw();
    return [h("h2", {}, j.id ? "Edit jadwal" : "Jadwal baru"), h("div", { class: "col" }, name, prompt, sched,
      h("div", { class: "row" }, h("div", { style: { flex: 1 } }, h("b", {}, "Izinin aksi berisiko"), h("div", { class: "muted small" }, "Jalan tanpa lu, jadi ga bisa nanya. Mati = aksi berisiko otomatis ditolak.")), sw(risky, (v) => (risky = v))),
      h("div", { class: "row", style: { justifyContent: "flex-end" } }, h("button", { class: "btn ghost", onclick: () => close(null) }, "Batal"),
        h("button", { class: "btn primary", onclick: () => close({ id: j.id, name: name.value.trim(), prompt: prompt.value.trim(), everyMinutes: every, dailyAt: daily ? time : null, allowRisky: risky, enabled: j.enabled }) }, "Simpan")))];
  });
  if (!r || !r.prompt) return;
  await tryDo(() => api("/api/job", r), "Jadwal kesimpen"); await refresh(); render();
}

// ================================================================= SETTINGS
function viewSettings() {
  const tabs = [["agent", "Agent"], ["conn", "Konektor"], ["remote", "Remote HP"], ["app", "Tampilan"], ["errors", "Log error" + (S.st.errorCount ? " (" + S.st.errorCount + ")" : "")]];
  const inner = h("div", { class: "pane-inner stagger" });
  const v = h("div", { class: "view" }, h("div", { class: "topbar" }, h("h1", {}, "Pengaturan")),
    h("div", { class: "tabs" }, tabs.map(([k, l]) => h("button", { class: S.setTab === k ? "on" : "", onclick: () => { S.setTab = k; render(); } }, l))), h("div", { class: "pane" }, inner));
  ({ agent: setAgent, conn: setConn, remote: setRemote, app: setApp, errors: setErrors })[S.setTab](inner);
  return v;
}
const saveSettings = (o) => tryDo(() => api("/api/settings", o)).then(refresh);
function setAgent(el) {
  const provs = S.st.providers.map((p) => Object.assign({}, p)); const keys = {};
  const PRESETS = [["OpenAI", "openai", "https://api.openai.com/v1", "gpt-4.1-mini"], ["DeepSeek", "openai", "https://api.deepseek.com/v1", "deepseek-chat"], ["OpenRouter", "openai", "https://openrouter.ai/api/v1", "openai/gpt-4.1-mini"], ["Groq", "openai", "https://api.groq.com/openai/v1", "llama-3.3-70b-versatile"], ["Gemini", "gemini", "", "gemini-2.5-flash"], ["Custom", "openai", "", ""]];
  const box = h("div", { class: "col" });
  const persist = async () => { await tryDo(() => api("/api/providers", { providers: provs, keys })); for (const k in keys) delete keys[k]; await refresh(); };
  const draw = () => box.replaceChildren(...provs.map((p, i) => {
    const inp = (k, ph, mono) => { const f = h("input", { class: "field" + (mono ? " mono" : ""), placeholder: ph, style: mono ? { fontSize: "13px" } : null }); f.value = p[k] || ""; f.oninput = () => (p[k] = f.value.trim()); return f; };
    const key = h("input", { class: "field", type: "password", placeholder: p.hasKey ? "API key (tersimpan — isi buat ganti)" : "API key" }); key.oninput = () => (keys[p.id || (p.id = Math.random().toString(16).slice(2, 10))] = key.value.trim());
    const model = inp("model", "model", true);
    return h("div", { class: "prov" },
      h("div", { class: "row" }, h("span", { class: "chip" }, "#" + (i + 1) + (i === 0 ? " utama" : " cadangan")), h("b", { style: { flex: 1 } }, p.name || "Provider"), sw(!p.disabled, (v) => { p.disabled = !v; }),
        h("button", { class: "icon-btn", title: "Naik", onclick: () => { if (i) { provs.splice(i - 1, 0, provs.splice(i, 1)[0]); draw(); } } }, icon("up")),
        h("button", { class: "icon-btn", title: "Hapus", onclick: () => { provs.splice(i, 1); draw(); } }, icon("trash"))),
      h("div", { class: "row" }, inp("name", "Nama"), seg([["openai", "OpenAI-compat"], ["gemini", "Gemini"]], p.kind || "openai", (v) => { p.kind = v; draw(); })),
      p.kind !== "gemini" ? inp("base", "Base URL", true) : null, key,
      h("div", { class: "row" }, model, h("button", { class: "btn", onclick: async () => { await persist(); const r = await tryDo(() => api("/api/models", { id: p.id })); const pick = await modal((c) => [h("h2", {}, "Pilih model"), h("div", { class: "col", style: { maxHeight: "60vh", overflow: "auto" } }, r.models.map((m) => h("button", { class: "btn ghost mono", style: { justifyContent: "flex-start" }, onclick: () => c(m) }, m)))]); if (pick) { p.model = pick; draw(); } } }, "Daftar"),
        h("button", { class: "btn primary", onclick: async () => { await persist(); const r = await tryDo(() => api("/api/test-llm", { id: p.id })); toast("Nyambung: " + r.text.trim()); } }, "Tes")));
  }), h("div", { class: "row" }, h("select", { class: "field", style: { maxWidth: "220px" }, onchange: (e) => { const pr = PRESETS.find((x) => x[0] === e.target.value); if (pr) { provs.push({ id: Math.random().toString(16).slice(2, 10), name: pr[0], kind: pr[1], base: pr[2], model: pr[3] }); draw(); } e.target.value = ""; } },
    h("option", { value: "" }, "+ Tambah provider…"), PRESETS.map((x) => h("option", { value: x[0] }, x[0]))), h("div", { class: "spacer" }), h("button", { class: "btn primary", onclick: () => persist().then(() => toast("Provider kesimpen")) }, icon("save"), "Simpan provider")));
  draw();
  const st = S.st.settings; const off = st.toolGroupsOff || [];
  const prompt = h("textarea", { class: "field", placeholder: "Instruksi tambahan, mis. Leo ada di D:\\leo, dijalanin pakai python leo.py" }); prompt.value = st.agentPrompt || "";
  const GL = { laptop: "File laptop", shell: "Shell & proses", device: "Clipboard, screenshot, info", ssh: "Server SSH", supabase: "Supabase", web: "HTTP GET", browser: "Browser agen (Chrome/Edge)" };
  el.append(h("div", { class: "card col" }, h("b", { style: { fontSize: "16px" } }, "Provider LLM (fallback berurutan)"), h("div", { class: "muted small" }, "Kalau provider #1 error/limit, otomatis pindah ke berikutnya."), box),
    h("div", { class: "card col" }, h("div", { class: "row" }, h("div", { style: { flex: 1 } }, h("b", {}, "Auto-izinin semua aksi"), h("div", { class: "muted small" }, "Agent ga nanya dulu sebelum hapus file / jalanin perintah. Hati-hati.")), sw(st.autoApprove, (v) => saveSettings({ autoApprove: v }))),
    h("div", { class: "card col" }, h("div", { class: "row" }, h("div", { style: { flex: 1 } }, h("b", {}, "Sensor data sensitif di proses agent"), h("div", { class: "muted small" }, "API key, password, token, private key & IP disamarin (••••) di langkah tool, status, dan dialog izin.")), sw(st.redact !== false, (v) => saveSettings({ redact: v })))),
      ...S.st.toolGroups.filter((g) => g !== "misc").map((g) => h("div", { class: "row" }, h("div", { style: { flex: 1 } }, GL[g] || g, h("span", { class: "muted small" }, "  " + (S.st.toolCount[g] || 0) + " tools")), sw(!off.includes(g), (v) => saveSettings({ toolGroupsOff: v ? off.filter((x) => x !== g) : off.concat([g]) })))),
      h("div", { class: "row" }, h("div", { style: { flex: 1 } }, "Shell default"), seg([["cmd", "cmd"], ["powershell", "PowerShell"]], st.shell, (v) => saveSettings({ shell: v }).then(render)))),
    browserCard(st),
    h("div", { class: "card col" }, h("b", {}, "Instruksi tambahan"), prompt, h("button", { class: "btn primary", onclick: () => saveSettings({ agentPrompt: prompt.value }).then(() => toast("Kesimpen")) }, "Simpan")));
}
function setConn(el) {
  const url = h("input", { class: "field mono", placeholder: "https://xxxx.supabase.co" }); url.value = S.st.settings.supabaseUrl || "";
  const key = h("input", { class: "field", type: "password", placeholder: S.st.secrets.supabaseKey ? "Key tersimpan — isi buat ganti" : "anon / service_role key" });
  el.append(h("div", { class: "card col" }, h("b", { style: { fontSize: "16px" } }, "⚡ Supabase"), url, key, h("div", { class: "muted small" }, "service_role = akses penuh (lewatin RLS). Pakai anon kalau mau aman."),
    h("button", { class: "btn primary", onclick: async () => { await saveSettings({ supabaseUrl: url.value.trim() }); if (key.value) await api("/api/secret", { key: "supabaseKey", value: key.value.trim() }); toast("Supabase kesimpen"); await refresh(); render(); } }, "Simpan")));
}
function setRemote(el) {
  const st = S.st; const tn = st.tunnel;
  const pw = h("input", { class: "field", type: "password", placeholder: st.secrets.webPassword ? "Password tersimpan — isi buat ganti" : "Password buat buka dari HP (wajib)" });
  const cf = h("input", { class: "field mono", placeholder: "Kosongin aja = otomatis (atau isi mis. D:\\tools\\cloudflared.exe)" }); cf.value = st.settings.cloudflared || "";
  const dl = tn.download || null, dlBusy = dl && !dl.done;
  const cfRow = h("div", { class: "row" },
    h("div", { class: "mono small", style: { flex: 1, minWidth: 0, color: tn.exe ? "var(--green)" : "var(--amber)" } },
      dlBusy ? "Download cloudflared " + (dl.version === "latest" ? "" : dl.version + " ") + dl.pct + "%…" : dl && dl.error ? dl.error : tn.exe ? "✓ " + tn.exe : "⚠ cloudflared belum ada di laptop ini"),
    h("button", { class: "btn", disabled: !!dlBusy, onclick: () => tryDo(() => api("/api/tunnel/download", {})) }, icon("download"), tn.exe ? "Download ulang" : "Download cloudflared"));
  const tok = h("input", { class: "field", type: "password", placeholder: st.secrets.telegramToken ? "Token bot tersimpan" : "Token bot Telegram (dari @BotFather)" });
  const chat = h("input", { class: "field mono", placeholder: "Chat ID Telegram lu" }); chat.value = st.settings.telegramChat || "";
  el.append(h("div", { class: "card col" }, h("b", { style: { fontSize: "16px" } }, "Buka satsh dari HP"),
    h("div", { class: "muted small" }, "Pakai Cloudflare quick tunnel: dapet link https://….trycloudflare.com yang bisa dibuka dari HP mana aja. Link-nya dikirim ke Telegram tiap kali nyala. Akses dari luar wajib login password."),
    h("label", { class: "lbl" }, "Password web"), pw, h("label", { class: "lbl" }, "Lokasi cloudflared.exe"), cf, cfRow,
    h("div", { class: "row" }, h("div", { style: { flex: 1 } }, "Nyalain otomatis pas satsh start"), sw(st.settings.remoteEnabled, (v) => saveSettings({ remoteEnabled: v }))),
    h("button", { class: "btn", onclick: async () => { if (pw.value) { await api("/api/secret", { key: "webPassword", value: pw.value }); } await saveSettings({ cloudflared: cf.value.trim() }); toast("Kesimpen"); render(); } }, icon("save"), "Simpan"),
    h("div", { class: "row" }, h("span", { class: "dot " + (tn.url && tn.ready ? "on" : tn.running ? "busy" : "") }), h("div", { style: { flex: 1, minWidth: 0 } },
      tn.url ? h("div", {}, h("a", { href: tn.url, target: "_blank", class: "mono" }, tn.url), !tn.ready ? h("div", { class: "muted small" }, "⏳ " + (tn.note || "Nyiapin link…") + " — jangan dibuka dulu") : null, tn.error ? h("div", { class: "small", style: { color: "var(--amber)" } }, tn.error) : null)
        : tn.running ? "Nyambungin tunnel…" : tn.error || "Tunnel mati"),
      tn.url ? h("button", { class: "btn", onclick: () => { navigator.clipboard.writeText(tn.url); toast("Link ke-copy"); } }, "Copy") : null,
      tn.running ? h("button", { class: "btn danger", onclick: () => tryDo(() => api("/api/tunnel/stop", {})) }, "Matiin") : h("button", { class: "btn primary", onclick: () => tryDo(() => api("/api/tunnel/start", {})) }, "Nyalain"))),
    h("div", { class: "card col" }, h("b", { style: { fontSize: "16px" } }, "Telegram"), h("div", { class: "muted small" }, "Buat kirim link remote & hasil jadwal ke HP."), tok, chat,
      h("div", { class: "row" }, h("button", { class: "btn", onclick: async () => { if (tok.value) await api("/api/secret", { key: "telegramToken", value: tok.value.trim() }); await saveSettings({ telegramChat: chat.value.trim() }); toast("Kesimpen"); } }, "Simpan"),
        h("button", { class: "btn primary", onclick: async () => { const r = await tryDo(() => api("/api/telegram/test", {})); toast(r.ok ? "Terkirim, cek Telegram" : "Gagal kirim — cek token & chat ID", !r.ok); } }, "Tes kirim"))));
}
function setApp(el) {
  const st = S.st.settings;
  el.append(h("div", { class: "card col" }, h("b", { style: { fontSize: "16px" } }, "Tema"), seg([["dark", "Gelap"], ["light", "Terang"]], st.theme, (v) => saveSettings({ theme: v }).then(render))),
    h("div", { class: "card col" }, h("b", { style: { fontSize: "16px" } }, "Font terminal"), seg([["12", "12"], ["13", "13"], ["14", "14"], ["16", "16"], ["18", "18"]], localStorage.getItem("fontSize") || "14", (v) => { localStorage.setItem("fontSize", v); Object.values(TERMS).forEach((t) => { t.x.options.fontSize = +v; try { t.fit.fit(); } catch (e) { } }); render(); })),
    h("div", { class: "card col" }, h("b", { style: { fontSize: "16px" } }, "Matiin satsh"), h("div", { class: "muted small" }, "satsh jalan di background (tanpa jendela). Tutup tab browser ga bikin dia mati — pakai tombol ini kalau mau beneran berhenti."),
      h("button", { class: "btn danger", onclick: async () => { if (await confirmBox("Matiin satsh?", "Jadwal & tunnel ikut berhenti. Buka lagi lewat shortcut satsh.", "Matiin")) { await api("/api/shutdown", {}); document.body.replaceChildren(h("div", { class: "empty", style: { height: "100%" } }, h("div", {}, h("div", { class: "ico" }, icon("power")), h("h3", {}, "satsh udah dimatiin"), "Buka lagi lewat shortcut satsh di Desktop."))); } } }, icon("power"), "Matiin")),
    h("div", { class: "card col" }, h("b", {}, "Data"), h("div", { class: "muted small mono" }, "Semua data (host, sesi, memori, skill) ada di folder .satsh di folder user lu. Password & API key dienkripsi pakai akun Windows (DPAPI).")));
}

// ===================================================================== LOGIN
function showLogin() {
  if ($("#login")) return;
  const f = h("input", { class: "field", type: "password", placeholder: "Password" });
  const go = async () => { const r = await fetch("/api/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ password: f.value }), credentials: "same-origin" }); if (r.ok) location.reload(); else { toast("Password salah", true); f.value = ""; } };
  f.onkeydown = (e) => e.key === "Enter" && go();
  document.body.append(h("div", { class: "modal-bg", id: "login", style: { background: "var(--bg)" } }, h("div", { class: "modal col", style: { width: "min(380px,100%)", textAlign: "center" } },
    h("div", { class: "logo grad-text", style: { fontSize: "40px", fontWeight: 700 } }, "satsh"), h("div", { class: "muted" }, "Masukin password buat buka satsh desktop"), f, h("button", { class: "btn primary", onclick: go }, "Masuk"))));
  setTimeout(() => f.focus(), 50);
}

// ====================================================================== BOOT
(async function boot() {
  const ln = await (await fetch("/api/login-needed", { credentials: "same-origin" })).json();
  if (ln.needed) return showLogin();
  await refresh(); render(); connectEvents();
  for (const p of S.st.pending) showApproval(p);
})();

// ================================================================ PROFILES
const PROF_EMOJIS = ["⚡", "🤖", "🧠", "🛠️", "🛵", "💼", "🎬", "🎨", "📈", "🧾", "🌙", "🦊", "🚀", "📚"];
const profById = (id) => S.st.profiles.find((p) => p.id === (id || "default"));
const activeProf = () => profById(S.st.activeProfile) || S.st.profiles[0] || { id: "default", name: "satsh", emoji: "⚡" };
function profModel(p) {
  const all = S.st.providers.filter((x) => !x.disabled);
  const pr = all.find((x) => x.id === (p && p.provider)) || all[0];
  return pr ? pr.model || pr.name : "";
}
async function activateProfile(id) {
  if (id === S.st.activeProfile) return;
  await tryDo(() => api("/api/profile/activate", { id }));
  await refresh();
  if (S.session && S.session.messages.length && (S.session.profile || "default") !== id) openSession(null);
  render();
}
async function profileMenu() {
  const act = await modal((close) => [h("h2", {}, "Profil agent"),
    h("div", { class: "col" }, S.st.profiles.map((p) => h("div", { class: "row prof-row" + (p.id === S.st.activeProfile ? " on" : "") },
      h("button", { class: "btn ghost", style: { flex: 1, justifyContent: "flex-start" }, onclick: () => close({ use: p.id }) },
        h("span", { style: { fontSize: "20px" } }, p.emoji), h("div", { style: { textAlign: "left", minWidth: 0 } }, h("b", {}, p.name), h("div", { class: "muted small" }, [p.desc, profModel(p)].filter(Boolean).join(" · ")))),
      h("button", { class: "icon-btn", title: "Atur", onclick: () => close({ edit: p.id }) }, icon("edit"))))),
    h("button", { class: "btn", onclick: () => close({ add: true }) }, icon("plus"), "Profil baru"),
    (S.st.presets || []).map((pr) => h("button", { class: "btn", onclick: () => close({ preset: pr.id }) }, icon("plus"), "Pasang preset: " + pr.name)),
    h("div", { class: "row" }, h("button", { class: "btn", style: { flex: 1 }, onclick: () => close({ exp: true }) }, "Ekspor zip"), h("button", { class: "btn", style: { flex: 1 }, onclick: () => close({ imp: true }) }, "Impor zip")),
    h("div", { class: "muted small" }, "Zip-nya sama formatnya sama satsh di HP — bisa bolak-balik HP ⇄ laptop.")]);
  if (!act) return;
  if (act.use) return activateProfile(act.use);
  if (act.edit) return editProfile(profById(act.edit));
  if (act.add) {
    const name = await askText("Nama profil baru", "", "mis. Payu Ops");
    if (!name || !name.trim()) return;
    const r = await tryDo(() => api("/api/profile/create", { name: name.trim(), copyFrom: S.st.activeProfile }));
    await refresh();
    return editProfile(r.profile);
  }
  if (act.preset) { const r = await tryDo(() => api("/api/profile/preset", { id: act.preset })); await refresh(); toast(r.profile.emoji + " " + r.profile.name + " kepasang"); if (S.session && S.session.messages.length) openSession(null); return render(); }
  if (act.exp) return exportZip();
  if (act.imp) return importZip();
}
async function editProfile(p) {
  const v = Object.assign({ toolsOff: [] }, p, { toolsOff: (p.toolsOff || []).slice() });
  const GL = { laptop: "File laptop", shell: "Shell & proses", device: "Clipboard, screenshot, info", ssh: "Server SSH", supabase: "Supabase", web: "HTTP GET", browser: "Browser agen (Chrome/Edge)" };
  const res = await modal((close) => {
    const name = h("input", { class: "field", value: v.name });
    const desc = h("input", { class: "field", placeholder: "Buat apa (opsional), mis. ngurus server Payu", value: v.desc || "" });
    const emo = h("div", { class: "row", style: { flexWrap: "wrap", gap: "4px" } });
    const drawEmo = () => emo.replaceChildren(...PROF_EMOJIS.map((e) => h("button", { class: "btn" + (v.emoji === e ? " primary" : ""), style: { padding: "4px 8px", fontSize: "18px" }, onclick: () => { v.emoji = e; drawEmo(); } }, e)));
    drawEmo();
    const prov = h("select", { class: "field" }, h("option", { value: "" }, "Ikut urutan provider"), S.st.providers.map((x) => h("option", { value: x.id }, x.name + " · " + (x.model || ""))));
    prov.value = v.provider || "";
    const groups = S.st.toolGroups.filter((g) => g !== "misc" && g !== "brain");
    return [h("h2", {}, "Atur profil"), emo, h("label", { class: "lbl" }, "Nama"), name, desc, h("label", { class: "lbl" }, "Model utama"), prov,
      h("label", { class: "lbl" }, "Tools yang boleh dipakai"),
      groups.map((g) => h("div", { class: "row" }, h("div", { style: { flex: 1 } }, GL[g] || g), sw(!v.toolsOff.includes(g), (on) => { v.toolsOff = on ? v.toolsOff.filter((x) => x !== g) : v.toolsOff.concat([g]); }))),
      h("div", { class: "row" },
        v.id !== "default" ? h("button", { class: "btn danger", onclick: () => close("delete") }, icon("trash"), "Hapus") : null,
        h("div", { class: "spacer" }),
        h("button", { class: "btn", onclick: () => { Object.assign(v, { name: name.value, desc: desc.value, provider: prov.value }); close("brain"); } }, "Atur otak"),
        h("button", { class: "btn primary", onclick: () => { Object.assign(v, { name: name.value, desc: desc.value, provider: prov.value }); close("save"); } }, icon("save"), "Simpan"))];
  });
  if (res === "delete") {
    if (!(await confirmBox("Hapus profil " + v.name + "?", "Soul, memori & skill profil ini dihapus. Riwayat chat-nya pindah ke profil utama."))) return;
    await tryDo(() => api("/api/profile/delete", { id: v.id }));
    await refresh(); return render();
  }
  if (res !== "save" && res !== "brain") return;
  await tryDo(() => api("/api/profile/update", { id: v.id, name: v.name, emoji: v.emoji, desc: v.desc, provider: v.provider, toolsOff: v.toolsOff }));
  await refresh();
  if (res === "brain") { await activateProfile(v.id); return setView("brain"); }
  render();
}
async function exportZip() {
  const opt = await modal((close) => {
    let ses = false, job = false;
    return [h("h2", {}, "Ekspor otak agent (.zip)"), h("div", { class: "muted" }, "Semua profil: soul, memori, skill, plus profil user. Bisa diimpor di satsh HP atau laptop lain."),
      h("div", { class: "row" }, h("div", { style: { flex: 1 } }, "Ikutin riwayat chat"), sw(false, (x) => (ses = x))),
      h("div", { class: "row" }, h("div", { style: { flex: 1 } }, "Ikutin jadwal"), sw(false, (x) => (job = x))),
      h("button", { class: "btn primary", onclick: () => close({ ses, job }) }, "Download zip")];
  });
  if (!opt) return;
  const a = h("a", { href: "/api/agentzip?sessions=" + (opt.ses ? 1 : 0) + "&jobs=" + (opt.job ? 1 : 0), download: "" });
  document.body.append(a); a.click(); a.remove();
}
function importZip() {
  const inp = h("input", { type: "file", accept: ".zip,application/zip" });
  inp.onchange = async () => {
    const f = inp.files[0]; if (!f) return;
    try {
      const r = await fetch("/api/agentzip/import", { method: "POST", body: f, credentials: "same-origin" });
      const j = await r.json();
      if (!r.ok) throw new Error(j.error || "Gagal");
      toast("Impor beres — " + j.summary);
      await refresh(); render();
    } catch (e) { toast("Gagal impor: " + e.message, true); }
  };
  inp.click();
}

// ============================================================ COPY BLOCKS
function copyText(t, what) {
  const done = () => toast((what || "Teks") + " disalin");
  if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(t).then(done, () => fallback());
  fallback();
  function fallback() { const ta = h("textarea", { style: { position: "fixed", opacity: 0 } }); ta.value = t; document.body.append(ta); ta.select(); try { document.execCommand("copy"); done(); } catch (e) { toast("Gagal nyalin", true); } ta.remove(); }
}
/** Agent answer: every code block and quote gets its own copy button; prose stays selectable. */
function answerBubble(m) {
  const body = h("div", { class: "md", html: md(m.text) });
  body.querySelectorAll("pre").forEach((pre) => {
    const code = pre.querySelector("code");
    const lang = ((code && code.className) || "").replace(/.*language-(\S+).*/, "$1");
    const head = h("div", { class: "code-head" }, h("span", { class: "mono" }, lang && lang !== (code && code.className) ? lang : "kode"),
      h("button", { class: "copy-btn", onclick: (e) => { e.stopPropagation(); copyText((code || pre).textContent.replace(/\n$/, ""), "Kode"); } }, "Salin"));
    const box = h("div", { class: "code-box" });
    pre.replaceWith(box); box.append(head, pre);
  });
  body.querySelectorAll("blockquote").forEach((q) => {
    const btn = h("button", { class: "copy-btn quote-copy", title: "Salin kutipan", onclick: (e) => { e.stopPropagation(); copyText(q.innerText.trim(), "Kutipan"); } }, "Salin");
    q.classList.add("quote-box"); q.prepend(btn);
  });
  const wrap = h("div", { class: "bubble-a" + (m.isError ? " err" : "") }, body);
  if (m.isError) wrap.append(h("div", { class: "copy-all" }, h("button", { class: "copy-btn", style: { color: "var(--red, #ff5c5c)" }, onclick: openErrorLog }, "Lihat log error / kirim laporan")));
  if (m.text.length > 200 || body.querySelector(".code-box,.quote-box")) wrap.append(h("div", { class: "copy-all" }, h("button", { class: "copy-btn", onclick: () => copyText(m.text, "Jawaban") }, "Salin semua")));
  return wrap;
}

// ============================================================== ERROR LOG
function openErrorLog() { S.setTab = "errors"; setView("settings"); }
async function setErrors(el) {
  const r = await api("/api/errors");
  const list = r.entries || [];
  const open = new Set();
  const box = h("div", { class: "col" });
  const fmt = (e) => ["[" + e.t + "] " + e.src, e.msg].concat(Object.entries(e.ctx || {}).map(([k, v]) => "  " + k + ": " + v)).concat(e.stack ? [e.stack] : []).join("\n");
  const draw = () => box.replaceChildren(...(list.length ? list.map((e, i) => h("div", { class: "card col err-entry", onclick: () => { open.has(i) ? open.delete(i) : open.add(i); draw(); } },
    h("div", { class: "row" }, h("b", {}, ({ agent: "Agent", cron: "Jadwal", tool: "Tool", llm: "Provider AI", server: "Server" })[e.src] || e.src),
      (e.ctx && (e.ctx.jadwal || e.ctx.tool)) ? h("span", { class: "muted" }, "· " + (e.ctx.jadwal || e.ctx.tool)) : null, h("div", { class: "spacer" }), h("span", { class: "muted small mono" }, e.t.replace("T", " "))),
    h("div", { style: { color: "var(--text)" } }, e.msg),
    open.has(i) ? [Object.entries(e.ctx || {}).map(([k, v]) => h("div", { class: "muted small" }, k + ": " + v)),
      e.stack ? h("pre", { class: "mono small", style: { whiteSpace: "pre", overflow: "auto", margin: 0 } }, e.stack) : null,
      h("div", { class: "row" }, h("div", { class: "spacer" }), h("button", { class: "copy-btn", onclick: (ev) => { ev.stopPropagation(); copyText(fmt(e), "Error ini"); } }, "Salin"))] : null))
    : [h("div", { class: "card muted" }, "Belum ada error. Kalau ada yang crash atau gagal aneh, detail + traceback-nya muncul di sini.")]));
  draw();
  el.append(h("div", { class: "card col" }, h("b", { style: { fontSize: "16px" } }, "Log error"),
    h("div", { class: "muted small" }, list.length + " error · satsh desktop " + r.version + ". Kirim log ke yang benerin app biar ketahuan baris kodenya."),
    h("div", { class: "row" },
      h("button", { class: "btn", onclick: async () => { const t = await (await fetch("/api/errors/report", { credentials: "same-origin" })).text(); copyText(t, "Log"); } }, "Salin semua"),
      h("a", { class: "btn primary", href: "/api/errors/report", download: "" }, "Download .txt"),
      h("div", { class: "spacer" }),
      list.length ? h("button", { class: "btn danger", onclick: async () => { if (await confirmBox("Hapus semua log?", "")) { await api("/api/errors/clear", {}); await refresh(); render(); } } }, "Hapus") : null)), box);
}

// ------------------------------------------------------------------- markas
const WHO = { adam: "var(--pink)", satsh: "var(--cyan)", hermes: "var(--amber)", muse: "var(--violet)", agy: "var(--green)" };
const whoC = (w) => WHO[w] || "var(--muted)";
function viewMarkas() {
  const body = h("div", { class: "pane-inner stagger" }, h("div", { class: "muted" }, "Ngambil data Markas…"));
  const v = h("div", { class: "view" }, h("div", { class: "pane" }, body));
  api("/api/markas").then((r) => { S.mk = r; S.mkPrompt = r.rapatPrompt; drawMarkas(body, r); }).catch((e) => body.replaceChildren(h("div", { class: "card" }, e.message)));
  return v;
}
function drawMarkas(el, r) {
  const run = async (args, msg) => { await tryDo(() => api("/api/markas/run", { args }), msg); render(); };
  if (!r.configured) {
    const hosts = S.st.hosts;
    const pick = h("select", { class: "field" }, hosts.map((x) => h("option", { value: x.id }, x.label + " (" + x.username + "@" + x.host + ")")));
    const pref = hosts.find((x) => /adamn/i.test(x.label + x.host)); if (pref) pick.value = pref.id;
    el.replaceChildren(h("h1", { class: "grad-text" }, "Markas"),
      h("p", { class: "muted" }, "Workspace bareng lu & semua agent: target, pencapaian, obrolan. Datanya di server lu sendiri (program kecil `markas`, diakses lewat SSH — ga buka port apa-apa). Kalau Hermes ada di server itu, skill-nya ikut dipasang. satsh HP & laptop bisa pakai server yang sama."),
      hosts.length ? h("div", { class: "col", style: { gap: "12px" } }, pick,
        h("button", { class: "btn primary", onclick: async () => { const x = await tryDo(() => api("/api/markas/install", { hostId: pick.value })); toast(x.hermes ? "Markas kepasang + skill Hermes" : "Markas kepasang" + (x.hermesCli ? "" : " (Hermes ga ketemu di server ini)")); render(); } }, icon("power"), "Pasang Markas"),
        h("button", { class: "btn ghost", onclick: async () => { await api("/api/markas/host", { hostId: pick.value }); render(); } }, "Udah kepasang (dari HP) — sambungin aja"))
        : h("div", { class: "card" }, "Tambahin server dulu di menu Host."));
    return;
  }
  const s = r.snap || {};
  const targets = (s.targets || []).filter((t) => t.status === "aktif");
  const members = (s.members || []).map((m) => m.name);
  const job = S.st.jobs.find((j) => j.name === "Rapat Markas");
  const top = h("div", { class: "row", style: { flexWrap: "wrap", gap: "8px" } }, h("h1", { class: "grad-text", style: { margin: 0, fontSize: "28px" } }, "Markas"), h("span", { class: "chip" }, r.host || "server"), h("div", { class: "spacer" }),
    h("button", { class: "icon-btn", title: "Refresh", onclick: () => render() }, icon("refresh")),
    h("button", { class: "btn", onclick: async () => {
      if (await confirmBox(job ? "Matikan rapat harian?" : "Rapat tiap hari jam 08:00?", job ? "" : "satsh bakal nanya PIC tiap target & ngirim rangkuman ke lu.", job ? "Matikan" : "Jadwalkan", !!job)) {
        if (job) await api("/api/job/delete", { id: job.id }); else await api("/api/job", { name: "Rapat Markas", prompt: S.mkPrompt || "[Rapat Markas] jalankan rapat Markas: markas brief, tanya PIC tiap target aktif (tanya_agent), catat (log/target_update), markas say rangkuman ke adam.", dailyAt: "08:00", enabled: true });
        await refresh(); render();
      } } }, icon("history"), job ? "Rapat harian ✓" : "Jadwalkan"),
    h("button", { class: "btn primary", onclick: async () => { const x = await tryDo(() => api("/api/markas/rapat", {})); S.sid = x.sid; localStorage.setItem("sid", x.sid); await refresh(); setView("agent"); loadSession(); } }, icon("users"), "Mulai rapat"));
  const kids = [top];
  if (r.error) kids.push(h("div", { class: "card", style: { color: "var(--red)" } }, r.error, h("div", { class: "row", style: { marginTop: "8px" } }, h("button", { class: "btn ghost", onclick: async () => { await api("/api/markas/host", { hostId: "" }); render(); } }, "Ganti server"))));
  kids.push(h("div", { class: "row" }, h("h2", {}, "Target aktif"), h("span", { class: "muted" }, targets.length + " · selesai " + (s.selesai || 0)), h("div", { class: "spacer" }),
    h("button", { class: "btn", onclick: () => addTarget(members, run) }, "+ Target")));
  if (!targets.length) kids.push(h("div", { class: "muted" }, "Belum ada target. Tambahin, atau suruh agent: \"bikin target Markas: …\""));
  targets.forEach((t) => kids.push(h("div", { class: "card col", style: { cursor: "pointer" }, onclick: () => editTarget(t, run) },
    h("div", { class: "row" }, h("b", { style: { flex: 1 } }, "#" + t.id + " " + t.title), h("b", { style: { color: "var(--cyan)" } }, (t.progress || 0) + "%")),
    h("div", { style: { height: "6px", background: "var(--surface2)", borderRadius: "6px", overflow: "hidden", margin: "4px 0" } }, h("div", { style: { height: "100%", width: (t.progress || 0) + "%", background: "var(--accent)" } })),
    h("div", { class: "row muted", style: { fontSize: "12px", gap: "12px", flexWrap: "wrap" } }, t.owner ? h("b", { style: { color: whoC(t.owner) } }, "PIC " + t.owner) : null,
      t.deadline ? "tenggat " + t.deadline : null, t.metric || null))));
  kids.push(h("h2", {}, "Pencapaian terbaru"));
  (s.logs || []).slice().reverse().slice(0, 12).forEach((l) => kids.push(h("div", { class: "row", style: { alignItems: "flex-start" } }, h("span", { style: { color: whoC(l.who) } }, "✔"),
    h("div", {}, h("b", { style: { color: whoC(l.who) } }, l.who + " "), l.text, l.target_id ? h("span", { class: "muted" }, "  #" + l.target_id) : null, h("span", { class: "muted", style: { fontSize: "11px" } }, "  " + String(l.at || "").slice(5, 16))))));
  kids.push(h("h2", {}, "Obrolan"));
  (s.messages || []).slice().reverse().forEach((m) => kids.push(h("div", { class: "card", style: { padding: "10px 14px", background: m.who === "adam" ? "rgba(124,92,255,.12)" : "" } },
    h("div", { style: { fontSize: "12px", fontWeight: 700, color: whoC(m.who) } }, m.who + (m.to_name ? " → " + m.to_name : "")), h("div", { class: "md", html: md(m.text) }))));
  const inp = h("input", { class: "field", placeholder: "Tulis ke Markas… (awali @hermes buat nyolek)" });
  const send = async () => { let t = inp.value.trim(); if (!t) return; const a = ["say"]; const mm = t.match(/^@([\w-]+)\s+([\s\S]+)/); if (mm) { a.push(mm[2], "--to", mm[1]); } else a.push(t); inp.value = ""; await run(a); };
  inp.addEventListener("keydown", (e) => { if (e.key === "Enter") send(); });
  kids.push(h("div", { class: "row" }, inp, h("button", { class: "btn primary", onclick: send }, icon("send"))));
  el.replaceChildren(...kids);
}
function addTarget(members, run) {
  modal((close) => {
    const title = h("input", { class: "field", placeholder: "Target (mis. 10 UMKM bayar Payu)" });
    const owner = h("select", { class: "field" }, (members.length ? members : ["adam"]).map((n) => h("option", { value: n }, n)));
    const metric = h("input", { class: "field", placeholder: "Ukuran sukses (opsional)" });
    const dl = h("input", { class: "field", type: "date" });
    return [h("h2", {}, "Target baru"), h("div", { class: "col", style: { gap: "10px" } }, title, h("label", { class: "muted" }, "PIC"), owner, metric, h("label", { class: "muted" }, "Tenggat"), dl),
      h("div", { class: "row", style: { justifyContent: "flex-end", marginTop: "14px" } }, h("button", { class: "btn ghost", onclick: () => close() }, "Batal"),
        h("button", { class: "btn primary", onclick: async () => { if (!title.value.trim()) return; close(); const a = ["target", "add", title.value.trim(), "--owner", owner.value];
          if (metric.value.trim()) a.push("--metric", metric.value.trim()); if (dl.value) a.push("--deadline", dl.value); await run(a, "Target ditambah"); } }, "Simpan"))];
  });
}
function editTarget(t, run) {
  modal((close) => {
    const pr = h("input", { type: "range", min: 0, max: 100, step: 5, value: t.progress || 0, style: { width: "100%" } });
    const lbl = h("b", {}, (t.progress || 0) + "%"); pr.oninput = () => { lbl.textContent = pr.value + "%"; };
    const st = h("select", { class: "field" }, ["aktif", "selesai", "ditunda", "batal"].map((x) => h("option", { value: x }, x))); st.value = t.status;
    const note = h("input", { class: "field", placeholder: "Catatan (masuk ke pencapaian)" });
    return [h("h2", {}, "#" + t.id + " " + t.title), h("div", { class: "row" }, pr, lbl), st, note,
      h("div", { class: "row", style: { justifyContent: "flex-end", marginTop: "14px" } }, h("button", { class: "btn ghost", onclick: () => close() }, "Batal"),
        h("button", { class: "btn primary", onclick: async () => { close(); const a = ["target", "update", String(t.id), "--progress", pr.value]; if (st.value !== t.status) a.push("--status", st.value);
          if (note.value.trim()) a.push("--note", note.value.trim()); await run(a, "Target diupdate"); } }, "Simpan"))];
  });
}
