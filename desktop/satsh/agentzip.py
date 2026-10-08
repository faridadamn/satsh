"""Portable "agent brain" zip — the SAME format satsh on Android reads and writes.

    satsh-agent.json                     manifest (format, version, profiles…)
    USER.md                              shared "about the user"
    profiles/<id>/SOUL.md
    profiles/<id>/MEMORY.md
    profiles/<id>/skills/<name>/SKILL.md
    sessions/<id>.json                   (optional)
    cron.json                            (optional; imported paused)
"""
import datetime as dt
import io
import json
import os
import re
import zipfile

from .brain import (MEMORY_LIMIT, PROFILE_ID_RE, SEP, SESSION_ID_RE, SKILL_NAME_RE, USER_LIMIT, CronJob, _rw,
                    default_profile, parse_skill)
from .config import cfg

FORMAT = "satsh-agent"
VERSION = 1


def export(brain, profiles=None, sessions=False, jobs=False, source="windows"):
    ids = [p["id"] for p in brain.profiles if profiles is None or p["id"] in profiles]
    buf = io.BytesIO()
    sess_ids = []
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        def put(name, text):
            z.writestr(name, (text or "").encode("utf-8"))

        for pid in ids:
            v = brain.view(pid)
            put("profiles/%s/SOUL.md" % pid, v.soul)
            put("profiles/%s/MEMORY.md" % pid, v.memory)
            for s in v.skills:
                put("profiles/%s/skills/%s/SKILL.md" % (pid, s["name"]), s["raw"])
        put("USER.md", brain.user)
        if sessions:
            for m in brain.sessions:
                if (m.get("profile") or "default") not in ids:
                    continue
                p = brain._p("sessions", "%s.json" % m["id"])
                if os.path.exists(p):
                    put("sessions/%s.json" % m["id"], _rw(p))
                    sess_ids.append(m["id"])
        if jobs:
            put("cron.json", json.dumps([dict(j) for j in brain.jobs if (j.get("profile") or "default") in ids], ensure_ascii=False))
        put("satsh-agent.json", json.dumps({
            "format": FORMAT, "version": VERSION, "from": source, "exported": dt.datetime.now().isoformat(),
            "profiles": [brain.profile(i) for i in ids], "sessions": len(sess_ids), "jobs": bool(jobs),
        }, ensure_ascii=False, indent=2))
    return buf.getvalue()


def merge_entries(current, incoming, limit):
    """Adds entries of [incoming] that [current] lacks, up to [limit] chars. Returns (text, skipped)."""
    def split(t):
        return [e.strip() for e in (t or "").split(SEP) if e.strip()]

    out, skipped = split(current), 0
    for e in split(incoming):
        if e in out:
            continue
        if len(SEP.join(out + [e])) > limit:
            skipped += 1
            continue
        out.append(e)
    return SEP.join(out), skipped


def import_zip(brain, data):
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        raise ValueError("Bukan file zip")
    names = set(z.namelist())

    def text(name):
        if name not in names:
            return None
        return z.read(name).decode("utf-8", "replace")

    raw = text("satsh-agent.json")
    if raw is None:
        raise ValueError("Bukan zip otak agent satsh (satsh-agent.json ga ada)")
    man = json.loads(raw)
    if man.get("format") != FORMAT:
        raise ValueError("Format zip bukan " + FORMAT)
    if (man.get("version") or 1) > VERSION:
        raise ValueError("Zip dari satsh versi lebih baru — update satsh desktop dulu")

    local_providers = {p.get("id") for p in cfg.get("providers", [])}
    notes, mem_skipped = [], 0
    for inc in man.get("profiles") or []:
        pid = (inc or {}).get("id", "")
        if not PROFILE_ID_RE.match(pid):
            continue
        inc = dict(default_profile(), **{k: inc.get(k) for k in ("id", "name", "emoji", "desc", "provider", "toolsOff") if inc.get(k) is not None})
        if inc["provider"] not in local_providers:
            inc["provider"] = ""
        cur = brain.profile(pid)
        if cur is None:
            brain.profiles.append(inc)
        else:
            cur.update(name=inc["name"], emoji=inc["emoji"], desc=inc["desc"], toolsOff=inc["toolsOff"])
            if inc["provider"]:
                cur["provider"] = inc["provider"]
        d = brain.dir_of(pid)
        os.makedirs(os.path.join(d, "skills"), exist_ok=True)
        soul = text("profiles/%s/SOUL.md" % pid)
        if soul and soul.strip():
            _rw(os.path.join(d, "SOUL.md"), soul)
        merged, sk = merge_entries(_rw(os.path.join(d, "MEMORY.md")), text("profiles/%s/MEMORY.md" % pid) or "", MEMORY_LIMIT)
        mem_skipped += sk
        _rw(os.path.join(d, "MEMORY.md"), merged)
        n_sk = 0
        rx = re.compile(r"^profiles/%s/skills/([^/]+)/SKILL\.md$" % re.escape(pid))
        for name in names:
            m = rx.match(name)
            if not m or not SKILL_NAME_RE.match(m.group(1)):
                continue
            body = z.read(name).decode("utf-8", "replace")
            if not parse_skill(body):
                continue
            _rw(os.path.join(d, "skills", m.group(1), "SKILL.md"), body)
            n_sk += 1
        brain.reload_profile(pid)
        notes.append("%s %s (%d skill)" % (inc["emoji"], inc["name"], n_sk))
    brain.save_profiles()

    user_in = text("USER.md")
    if user_in is not None:
        merged, sk = merge_entries(brain.user, user_in, USER_LIMIT)
        mem_skipped += sk
        brain.active.set_entries("user", [e for e in merged.split(SEP) if e.strip()])

    n_sess = 0
    for name in names:
        m = re.match(r"^sessions/([^/]+)\.json$", name)
        if not m or not SESSION_ID_RE.match(m.group(1)) or m.group(1) == "index":
            continue
        try:
            s = json.loads(z.read(name).decode("utf-8"))
        except Exception:
            continue
        if s.get("id") != m.group(1) or not isinstance(s.get("messages"), list):
            continue
        if s.get("profile") and not brain.profile(s["profile"]):
            s["profile"] = None
        local = next((x for x in brain.sessions if x["id"] == s["id"]), None)
        if local and local.get("updated", 0) >= s.get("updated", 0):
            continue
        for k, v in (("contextStart", 0), ("summary", ""), ("todos", []), ("userTurns", 0), ("unread", False)):
            s.setdefault(k, v)
        s.setdefault("created", s.get("updated") or 0)
        _rw(brain._p("sessions", "%s.json" % s["id"]), json.dumps(s, ensure_ascii=False))
        meta = {"id": s["id"], "title": s.get("title") or "Chat", "updated": s.get("updated") or 0,
                "unread": False, "cron": bool(s.get("cronJobId")), "profile": s.get("profile")}
        if local:
            local.update(meta)
        else:
            brain.sessions.append(meta)
        n_sess += 1
    if n_sess:
        brain.save_index()

    n_jobs = 0
    cron = text("cron.json")
    if cron:
        try:
            have = {j["id"] for j in brain.jobs}
            for j in json.loads(cron):
                if not isinstance(j, dict) or not j.get("id") or j["id"] in have or not j.get("prompt"):
                    continue
                j = CronJob(j)
                j.update(enabled=False, lastRun=None, sessionId=None)
                j.setdefault("created", j.get("created") or 0)
                if j.get("profile") and not brain.profile(j["profile"]):
                    j["profile"] = None
                brain.jobs.append(j)
                n_jobs += 1
            if n_jobs:
                brain.save_jobs()
        except Exception:
            pass

    parts = []
    if notes:
        parts.append("Profil: " + ", ".join(notes))
    if user_in is not None:
        parts.append("Profil user digabung")
    if n_sess:
        parts.append("%d sesi" % n_sess)
    if n_jobs:
        parts.append("%d jadwal (di-pause, nyalain manual)" % n_jobs)
    if mem_skipped:
        parts.append("%d entri memori ga muat (kepenuhan)" % mem_skipped)
    parts.append("dari %s" % man.get("from", "?"))
    return " · ".join(parts)
