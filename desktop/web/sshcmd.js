// Turns a pasted connection line into host form fields — same rules as the
// app's lib/ssh_command.dart (keep them in sync):
//   ssh -p 2222 user@host · ssh user@host -p2222 · ssh -l user host
//   ssh -o Port=2222 -o User=user host · ssh://user@host:2222
//   user@host:2222 · host:2222 · [::1]:2222
//   mosh --ssh="ssh -p 2222" user@host   (connects over plain SSH)
//   sshpass -p 'pw' ssh -p 2222 user@host (password goes to the form)
// parse() returns {host, port, user, password, command, notes} or null.
(function (root) {
  "use strict";
  const WITH_ARG = new Set("bBcDEeFIiJLlmOopPQRSWw".split(""));
  const KEY_NOTE = (v) => 'Key "' + v + '" ada di komputer — tempel isinya / pilih file-nya di bagian SSH Key';
  const JUMP_NOTE = (v) => 'Lewat jump host "' + v + '": satsh desktop belum bisa jump host, sambungin dari host itu';

  function split(s) {
    const out = [];
    let cur = "", has = false, q = null;
    for (let i = 0; i < s.length; i++) {
      const c = s[i];
      if (q === "'") { if (c === "'") q = null; else cur += c; }
      else if (q === '"') {
        if (c === '"') q = null;
        else if (c === "\\" && i + 1 < s.length && '"\\$`'.includes(s[i + 1])) cur += s[++i];
        else cur += c;
      } else if (c === "'" || c === '"') { q = c; has = true; }
      // Backslash escapes only space/quotes/backslash, so Windows paths (C:\…\ssh.exe) survive.
      else if (c === "\\" && i + 1 < s.length && " \t'\"\\".includes(s[i + 1])) { cur += s[++i]; has = true; }
      else if (c === " " || c === "\t") { if (has || cur) out.push(cur); cur = ""; has = false; }
      else { cur += c; has = true; }
    }
    if (q) throw new Error("kutip ga ketutup");
    if (has || cur) out.push(cur);
    return out;
  }

  const validPort = (p) => (p > 0 && p < 65536 ? p : null);

  function parseTarget(s) {
    let x = (s || "").trim(), port = null, user = null;
    if (!x) return null;
    if (/^ssh:\/\//i.test(x)) { x = x.slice(6); const sl = x.indexOf("/"); if (sl >= 0) x = x.slice(0, sl); }
    const at = x.lastIndexOf("@");
    if (at >= 0) {
      user = x.slice(0, at); x = x.slice(at + 1);
      const semi = user.indexOf(";"); if (semi >= 0) user = user.slice(0, semi);
      if (!user) user = null;
    }
    const v6 = /^\[([0-9a-fA-F:.%a-zA-Z]+)\](?::(\d+))?$/.exec(x);
    if (v6) { x = v6[1]; if (v6[2]) port = +v6[2]; }
    else { const m = /^([^:\s]+):(\d+)$/.exec(x); if (m) { x = m[1]; port = +m[2]; } }
    if (port != null) port = validPort(port);
    if (!/^[A-Za-z0-9._\-:%]+$/.test(x)) return null;
    return { host: x, port, user };
  }

  // One option at t[i]; returns tokens used (0 = not an option).
  function option(t, i, notes, o) {
    const a = t[i];
    if (a.startsWith("--")) return 1;
    if (!WITH_ARG.has(a[1])) {
      let j = 1;
      while (j < a.length && !WITH_ARG.has(a[j])) j++;
      if (j === a.length) return 1;
      const t2 = t.slice(); t2[i] = "-" + a.slice(j);
      return option(t2, i, notes, o);
    }
    const f = a[1], inline = a.length > 2 ? a.slice(2) : null;
    const v = inline != null ? inline : (i + 1 < t.length ? t[i + 1] : null);
    if (v == null) return 1;
    if (f === "p") { const p = validPort(parseInt(v, 10)); if (p) o.port = p; }
    else if (f === "l") o.user = v;
    else if (f === "i") notes.push(KEY_NOTE(v));
    else if (f === "J") notes.push(JUMP_NOTE(v));
    else if (f === "L" || f === "R" || f === "D") notes.push("Port forward -" + f + " " + v + ": bikin lewat agent / ssh biasa");
    else if (f === "o") {
      const m = /^\s*(\w+)\s*[= ]\s*(.+?)\s*$/.exec(v);
      if (m) {
        const k = m[1].toLowerCase(), val = m[2];
        if (k === "port") { const p = validPort(parseInt(val, 10)); if (p) o.port = p; }
        else if (k === "user") o.user = val;
        else if (k === "proxyjump") notes.push(JUMP_NOTE(val));
        else if (k === "identityfile") notes.push(KEY_NOTE(val));
      }
    }
    return inline != null ? 1 : 2;
  }

  function parseSsh(t, i, notes, allowNoHost) {
    const o = { port: null, user: null };
    let target = null, rest = [];
    while (i < t.length) {
      const a = t[i];
      if (target != null) {
        if (a.startsWith("-") && a.length > 1 && !rest.length) {
          const n = option(t, i, notes, o);
          if (n > 0) { i += n; continue; }
        }
        rest = t.slice(i); break;
      }
      if (a === "--") { i++; if (i < t.length) target = t[i]; i++; continue; }
      if (a.startsWith("-") && a.length > 1) { const n = option(t, i, notes, o); i += n > 0 ? n : 1; continue; }
      target = a; i++;
    }
    if (target == null) return allowNoHost ? { host: "", port: o.port, user: o.user } : null;
    const b = parseTarget(target);
    if (!b) return null;
    const cmd = rest.join(" ").trim();
    return { host: b.host, port: o.port != null ? o.port : b.port, user: b.user != null ? b.user : o.user, command: cmd || null };
  }

  function parse(input) {
    const lines = String(input || "").trim().split(/[\r\n]+/).map((l) => l.trim()).filter(Boolean);
    if (!lines.length) return null;
    let text = lines.find((l) => /(^|\s)(ssh|mosh|sshpass)(\s|$)|^ssh:\/\//.test(l)) || lines[0];
    text = text.replace(/^[$#>%]\s+/, "");
    let t;
    try { t = split(text); } catch (e) { return null; }
    if (!t.length) return null;
    const notes = [];
    let password = null, i = 0;

    if (t[i] === "sshpass") {
      i++;
      while (i < t.length && t[i].startsWith("-")) {
        const f = t[i];
        if (f === "-p" && i + 1 < t.length) { password = t[i + 1]; i += 2; }
        else if (f.startsWith("-p") && f.length > 2) { password = f.slice(2); i++; }
        else if ((f === "-f" || f === "-d") && i + 1 < t.length) i += 2;
        else i++;
      }
    }

    if (i < t.length && t[i] === "mosh") {
      i++;
      let inner = null, target = null;
      while (i < t.length) {
        const a = t[i];
        if (a === "--") break;
        if (a.startsWith("--ssh=") || a === "--ssh") {
          const v = a === "--ssh" ? (i + 1 < t.length ? t[++i] : "") : a.slice(6);
          try { inner = parseSsh(split(v), 1, notes, true); } catch (e) { /* ignore */ }
        } else if (["-p", "--port", "--server", "--client", "--predict", "--bind-server"].includes(a)) i++;
        else if (!a.startsWith("-") && target == null) target = a;
        i++;
      }
      const b = target && parseTarget(target);
      if (!b) return null;
      notes.unshift("satsh belum bisa mosh — nyambungnya pakai SSH biasa");
      return { host: b.host, port: b.port != null ? b.port : (inner && inner.port), user: b.user != null ? b.user : (inner && inner.user), password, command: null, notes };
    }

    if (i < t.length && (t[i] === "ssh" || t[i].endsWith("/ssh") || t[i] === "ssh.exe" || /\\ssh(\.exe)?$/i.test(t[i]))) {
      const r = parseSsh(t, i + 1, notes, false);
      if (!r) return null;
      return { host: r.host, port: r.port, user: r.user, password, command: r.command, notes };
    }
    if (t.length === 1) { const b = parseTarget(t[0]); return b && Object.assign(b, { password: null, command: null, notes: [] }); }
    return null;
  }

  const api = { parse };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.SshCommand = api;
})(typeof window !== "undefined" ? window : this);
