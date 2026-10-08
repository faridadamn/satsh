#!/usr/bin/env python3
"""markas — shared workspace for Adam and his agents (satsh, Hermes, agy, Muse, …).

Targets, achievement log and chat rooms in one SQLite file. Every agent talks to it
the same way: run this CLI (over SSH, or locally like Hermes on the same VPS).
No network port, no extra libraries. Python 3.6+.

  markas status [--json]                         ringkasan: target aktif, log & obrolan terbaru
  markas brief [--for NAMA]                      ringkasan markdown buat ditempel ke prompt agent
  markas target add "judul" [--owner X] [--deadline YYYY-MM-DD] [--metric "ukuran sukses"]
  markas target update ID [--progress N] [--status aktif|selesai|batal|ditunda] [--owner X] [--note "…"]
  markas target list [--all]
  markas log "apa yang dicapai" [--target ID] [--proof URL]
  markas say "pesan" [--room umum] [--to NAMA]
  markas read [--room umum] [--limit 30]
  markas inbox --for NAMA                         pesan yang nyebut NAMA dan belum dibaca (lalu ditandai dibaca)
  markas member add NAMA [--desc "…"] [--via "cara ngobrol"]   |   markas member list

Global: --as NAMA (siapa yang nulis; default env MARKAS_AS atau "adam"), --json, MARKAS_HOME (default ~/.markas)
"""
import argparse
import datetime as dt
import json
import os
import re
import sqlite3
import sys

VERSION = "1.0"
HOME = os.environ.get("MARKAS_HOME") or os.path.join(os.path.expanduser("~"), ".markas")
DB = os.path.join(HOME, "markas.db")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")

SCHEMA = """
CREATE TABLE IF NOT EXISTS members (name TEXT PRIMARY KEY, descr TEXT DEFAULT '', via TEXT DEFAULT '', created TEXT);
CREATE TABLE IF NOT EXISTS targets (
  id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, owner TEXT DEFAULT '', deadline TEXT DEFAULT '',
  metric TEXT DEFAULT '', progress INTEGER DEFAULT 0, status TEXT DEFAULT 'aktif',
  created TEXT, updated TEXT, created_by TEXT DEFAULT '');
CREATE TABLE IF NOT EXISTS logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT, who TEXT, target_id INTEGER, text TEXT, proof TEXT DEFAULT '');
CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT, room TEXT DEFAULT 'umum', who TEXT, to_name TEXT DEFAULT '', text TEXT);
CREATE TABLE IF NOT EXISTS reads (name TEXT PRIMARY KEY, last_id INTEGER DEFAULT 0);
"""

DEFAULT_MEMBERS = [
    ("adam", "Bos. Yang punya semua target.", "satsh / Telegram"),
    ("satsh", "Agent umum di HP & laptop Adam (ketua rapat).", "satsh"),
    ("web-designer", "Profil satsh buat UI web anti-slop.", "satsh"),
    ("hermes", "Hermes Agent di VPS adamn.", "CLI: hermes -z / Telegram"),
    ("agy", "Antigravity CLI di Termux HP Adam.", "satsh (agent eksternal)"),
    ("muse", "Meta Muse di aplikasi Muse.", "satsh kontrol HP"),
]


def now():
    return dt.datetime.now().replace(microsecond=0).isoformat(sep=" ")


def db():
    os.makedirs(HOME, exist_ok=True)
    try:
        os.chmod(HOME, 0o700)
    except OSError:
        pass
    c = sqlite3.connect(DB, timeout=15)
    c.row_factory = sqlite3.Row
    c.executescript(SCHEMA)
    if not c.execute("SELECT 1 FROM members LIMIT 1").fetchone():
        c.executemany("INSERT OR IGNORE INTO members VALUES (?,?,?,?)", [(n, d, v, now()) for n, d, v in DEFAULT_MEMBERS])
        c.commit()
    return c


def rows(cur):
    return [dict(r) for r in cur.fetchall()]


def who(a):
    w = (a.as_ or os.environ.get("MARKAS_AS") or "adam").strip().lower()
    if not NAME_RE.match(w):
        die("nama --as ga valid: %r (huruf kecil/angka/strip)" % w)
    return w


def die(msg, code=2):
    sys.stderr.write("markas: %s\n" % msg)
    sys.exit(code)


def out(a, data, text):
    if a.json:
        print(json.dumps(data, ensure_ascii=False, indent=1))
    else:
        print(text)


def bar(p):
    p = max(0, min(100, int(p or 0)))
    return "[" + "#" * (p // 10) + "." * (10 - p // 10) + "] %3d%%" % p


def fmt_target(t):
    bits = [t.get("owner") and "PIC " + t["owner"], t.get("deadline") and "tenggat " + t["deadline"], t.get("metric") and "ukuran: " + t["metric"]]
    return "#%d %s %s (%s)%s" % (t["id"], bar(t["progress"]), t["title"], t["status"], ("\n     " + " · ".join(b for b in bits if b)) if any(bits) else "")


def fmt_log(l):
    return "%s  %s: %s%s%s" % (l["at"][5:16], l["who"], l["text"], (" [#%d]" % l["target_id"]) if l.get("target_id") else "", (" (" + l["proof"] + ")") if l.get("proof") else "")


def fmt_msg(m):
    return "%s  [%s] %s%s: %s" % (m["at"][5:16], m["room"], m["who"], (" → " + m["to_name"]) if m.get("to_name") else "", m["text"])


def snapshot(c, logs=10, msgs=15):
    targets = rows(c.execute("SELECT * FROM targets WHERE status IN ('aktif','ditunda') ORDER BY (deadline='' ), deadline, id"))
    done = c.execute("SELECT COUNT(*) FROM targets WHERE status='selesai'").fetchone()[0]
    return {
        "version": VERSION,
        "targets": targets,
        "selesai": done,
        "logs": rows(c.execute("SELECT * FROM logs ORDER BY id DESC LIMIT ?", (logs,)))[::-1],
        "messages": rows(c.execute("SELECT * FROM messages ORDER BY id DESC LIMIT ?", (msgs,)))[::-1],
        "members": rows(c.execute("SELECT name, descr, via FROM members ORDER BY created, name")),
    }


# ------------------------------------------------------------------ commands
def cmd_init(a, c):
    out(a, {"ok": True, "db": DB}, "Markas siap di %s" % DB)


def cmd_status(a, c):
    s = snapshot(c)
    lines = ["== MARKAS ==", "Target aktif (%d, selesai %d):" % (len(s["targets"]), s["selesai"])]
    lines += ["  " + fmt_target(t) for t in s["targets"]] or ["  (belum ada)"]
    lines += ["", "Pencapaian terbaru:"] + (["  " + fmt_log(l) for l in s["logs"]] or ["  (belum ada)"])
    lines += ["", "Obrolan terbaru:"] + (["  " + fmt_msg(m) for m in s["messages"]] or ["  (sepi)"])
    out(a, s, "\n".join(lines))


def cmd_brief(a, c):
    s = snapshot(c, logs=8, msgs=10)
    me = (a.for_ or "").lower()
    lines = ["# Markas (workspace bareng Adam & agent-agentnya)", "", "## Target aktif"]
    for t in s["targets"]:
        mine = " ← PUNYA LU" if me and t.get("owner") == me else ""
        lines.append("- #%d %s — %d%% (%s)%s%s%s" % (t["id"], t["title"], t["progress"], t["status"], " · PIC " + t["owner"] if t["owner"] else "",
                                                    " · tenggat " + t["deadline"] if t["deadline"] else "", mine))
    if not s["targets"]:
        lines.append("- (belum ada)")
    lines += ["", "## Pencapaian terbaru"] + ["- " + fmt_log(l) for l in s["logs"]]
    lines += ["", "## Obrolan terbaru"] + ["- " + fmt_msg(m) for m in s["messages"]]
    lines += ["", "Lapor progress: `markas log \"…\" --target ID --as NAMA` · update: `markas target update ID --progress N --as NAMA` · ngobrol: `markas say \"…\" --as NAMA`"]
    out(a, s, "\n".join(lines))


def cmd_target(a, c):
    w = who(a)
    if a.action == "add":
        title = " ".join(a.rest).strip()
        if not title:
            die("judul target kosong")
        cur = c.execute("INSERT INTO targets (title, owner, deadline, metric, created, updated, created_by) VALUES (?,?,?,?,?,?,?)",
                        (title, (a.owner or "").lower(), a.deadline or "", a.metric or "", now(), now(), w))
        c.execute("INSERT INTO logs (at, who, target_id, text) VALUES (?,?,?,?)", (now(), w, cur.lastrowid, "bikin target: " + title))
        c.commit()
        t = dict(c.execute("SELECT * FROM targets WHERE id=?", (cur.lastrowid,)).fetchone())
        return out(a, t, "Target dibikin: " + fmt_target(t))
    if a.action == "update":
        if not a.rest or not a.rest[0].lstrip("#").isdigit():
            die("pakai: markas target update ID [--progress N] [--status …]")
        tid = int(a.rest[0].lstrip("#"))
        t = c.execute("SELECT * FROM targets WHERE id=?", (tid,)).fetchone()
        if not t:
            die("target #%d ga ada" % tid)
        sets, vals, notes = [], [], []
        if a.progress is not None:
            p = max(0, min(100, a.progress))
            sets.append("progress=?"), vals.append(p), notes.append("progress %d%%→%d%%" % (t["progress"], p))
            if p >= 100 and not a.status:
                a.status = "selesai"
        if a.status:
            if a.status not in ("aktif", "selesai", "batal", "ditunda"):
                die("status: aktif|selesai|batal|ditunda")
            sets.append("status=?"), vals.append(a.status), notes.append("status → " + a.status)
        for col, val in (("owner", a.owner and a.owner.lower()), ("deadline", a.deadline), ("metric", a.metric)):
            if val is not None:
                sets.append(col + "=?"), vals.append(val), notes.append("%s → %s" % (col, val))
        if not sets and not a.note:
            die("ga ada yang diubah")
        if sets:
            c.execute("UPDATE targets SET %s, updated=? WHERE id=?" % ", ".join(sets), vals + [now(), tid])
        c.execute("INSERT INTO logs (at, who, target_id, text) VALUES (?,?,?,?)", (now(), w, tid, "; ".join(notes + ([a.note] if a.note else []))))
        c.commit()
        t = dict(c.execute("SELECT * FROM targets WHERE id=?", (tid,)).fetchone())
        return out(a, t, "Diupdate: " + fmt_target(t))
    if a.action == "list":
        q = "SELECT * FROM targets" + ("" if a.all else " WHERE status IN ('aktif','ditunda')") + " ORDER BY id"
        ts = rows(c.execute(q))
        return out(a, ts, "\n".join(fmt_target(t) for t in ts) or "(belum ada target)")
    die("target add|update|list")


def cmd_log(a, c):
    w, text = who(a), " ".join(a.rest).strip()
    if not text:
        die("isi lognya kosong")
    if a.target and not c.execute("SELECT 1 FROM targets WHERE id=?", (a.target,)).fetchone():
        die("target #%d ga ada" % a.target)
    cur = c.execute("INSERT INTO logs (at, who, target_id, text, proof) VALUES (?,?,?,?,?)", (now(), w, a.target, text, a.proof or ""))
    c.commit()
    l = dict(c.execute("SELECT * FROM logs WHERE id=?", (cur.lastrowid,)).fetchone())
    out(a, l, "Kecatat: " + fmt_log(l))


def cmd_say(a, c):
    w, text = who(a), " ".join(a.rest).strip()
    if not text:
        die("pesannya kosong")
    room = (a.room or "umum").lower()
    cur = c.execute("INSERT INTO messages (at, room, who, to_name, text) VALUES (?,?,?,?,?)", (now(), room, w, (a.to or "").lower(), text))
    c.commit()
    m = dict(c.execute("SELECT * FROM messages WHERE id=?", (cur.lastrowid,)).fetchone())
    out(a, m, "Terkirim: " + fmt_msg(m))


def cmd_read(a, c):
    q, vals = "SELECT * FROM messages", []
    if a.room:
        q += " WHERE room=?"
        vals.append(a.room.lower())
    ms = rows(c.execute(q + " ORDER BY id DESC LIMIT ?", vals + [a.limit]))[::-1]
    out(a, ms, "\n".join(fmt_msg(m) for m in ms) or "(sepi)")


def cmd_inbox(a, c):
    me = (a.for_ or who(a)).lower()
    last = (c.execute("SELECT last_id FROM reads WHERE name=?", (me,)).fetchone() or [0])[0]
    ms = rows(c.execute("SELECT * FROM messages WHERE id>? AND who<>? AND (to_name=? OR to_name='semua' OR text LIKE ?) ORDER BY id",
                        (last, me, me, "%@" + me + "%")))
    top = c.execute("SELECT MAX(id) FROM messages").fetchone()[0] or 0
    c.execute("INSERT INTO reads (name, last_id) VALUES (?,?) ON CONFLICT(name) DO UPDATE SET last_id=excluded.last_id", (me, top))
    c.commit()
    out(a, ms, "\n".join(fmt_msg(m) for m in ms) or "(ga ada pesan baru buat %s)" % me)


def cmd_member(a, c):
    if a.action == "add":
        name = (a.rest[0] if a.rest else "").lower()
        if not NAME_RE.match(name):
            die("nama member ga valid")
        c.execute("INSERT INTO members VALUES (?,?,?,?) ON CONFLICT(name) DO UPDATE SET descr=excluded.descr, via=excluded.via",
                  (name, a.desc or "", a.via or "", now()))
        c.commit()
    ms = rows(c.execute("SELECT name, descr, via FROM members ORDER BY created, name"))
    out(a, ms, "\n".join("- %s: %s (%s)" % (m["name"], m["descr"], m["via"]) for m in ms))


def main(argv=None):
    p = argparse.ArgumentParser(prog="markas", description="Workspace bareng Adam & agent-agentnya.")
    p.add_argument("--as", dest="as_")
    p.add_argument("--json", action="store_true")
    p.add_argument("--version", action="version", version="markas " + VERSION)
    sub = p.add_subparsers(dest="cmd")
    for name in ("init", "status"):
        sub.add_parser(name)
    b = sub.add_parser("brief")
    b.add_argument("--for", dest="for_")
    t = sub.add_parser("target")
    t.add_argument("action", choices=["add", "update", "list"])
    t.add_argument("rest", nargs="*")
    for f in ("--owner", "--deadline", "--metric", "--status", "--note"):
        t.add_argument(f)
    t.add_argument("--progress", type=int)
    t.add_argument("--all", action="store_true")
    lg = sub.add_parser("log")
    lg.add_argument("rest", nargs="*")
    lg.add_argument("--target", type=int)
    lg.add_argument("--proof")
    s = sub.add_parser("say")
    s.add_argument("rest", nargs="*")
    s.add_argument("--room")
    s.add_argument("--to")
    r = sub.add_parser("read")
    r.add_argument("--room")
    r.add_argument("--limit", type=int, default=30)
    ib = sub.add_parser("inbox")
    ib.add_argument("--for", dest="for_")
    m = sub.add_parser("member")
    m.add_argument("action", choices=["add", "list"])
    m.add_argument("rest", nargs="*")
    m.add_argument("--desc")
    m.add_argument("--via")
    # allow global flags anywhere (agents put --as/--json at the end)
    argv = list(sys.argv[1:] if argv is None else argv)
    glob = []
    for flag in ("--json",):
        while flag in argv:
            argv.remove(flag)
            glob.append(flag)
    if "--as" in argv:
        i = argv.index("--as")
        glob += argv[i:i + 2]
        del argv[i:i + 2]
    a = p.parse_args(glob + argv)
    if not a.cmd:
        p.print_help()
        return
    c = db()
    {"init": cmd_init, "status": cmd_status, "brief": cmd_brief, "target": cmd_target, "log": cmd_log, "say": cmd_say,
     "read": cmd_read, "inbox": cmd_inbox, "member": cmd_member}[a.cmd](a, c)


if __name__ == "__main__":
    main()
