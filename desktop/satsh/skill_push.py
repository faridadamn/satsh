"""Push satsh skills to other agents over SSH (and pull theirs back) — same as the Android app.

Hermes Agent reads ~/.hermes/skills/<category>/<name>/SKILL.md and picks up new skills on its next session.
"""
import base64
import datetime as dt
import hashlib
import json
import os
import re
import shlex
import time

from .brain import parse_skill
from .ssh import ssh

HERMES_ROOT = "$HOME/.hermes/skills"
MARKAS_SKILL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "markas", "hermes-SKILL.md")

# tests: fn(cmd) -> (code, stdout, stderr)
exec_override = None


def dir_for(name):
    return "markas" if name == "markas" else "satsh/" + name


def _exec(h, cmd, timeout=45):
    if exec_override is not None:
        return exec_override(cmd)
    chan = ssh.client(h).get_transport().open_session()
    chan.exec_command(cmd)
    out, err = bytearray(), bytearray()
    deadline = time.time() + timeout
    try:
        while True:
            if chan.recv_ready():
                out.extend(chan.recv(65536))
            if chan.recv_stderr_ready():
                d = chan.recv_stderr(65536)
                if len(err) < 20000:
                    err.extend(d)
            if chan.exit_status_ready() and not chan.recv_ready() and not chan.recv_stderr_ready():
                break
            if time.time() > deadline:
                raise ValueError("Kelamaan (>%ds) di %s" % (timeout, h["label"]))
            time.sleep(0.02)
        code = chan.recv_exit_status()
    finally:
        chan.close()
    return code, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")


def hash_of(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def prepare(raw):
    """What lands on the server: the same SKILL.md plus `version` (Hermes expects it) when missing."""
    t = (raw or "").strip()
    m = re.match(r"^---\s*\n([\s\S]*?)\n---", t)
    if not m or re.search(r"^version\s*:", m.group(1), re.M):
        return t + "\n"
    cut = m.end() - 3
    return t[:cut] + "version: 1.0.0\n" + t[cut:] + "\n"


def markas_skill():
    try:
        with open(MARKAS_SKILL, "r", encoding="utf-8") as f:
            return parse_skill(f.read(), "markas")
    except OSError:
        return None


def status(h):
    cmd = ('R="%s"; [ -d "$R" ] || [ -d "$(dirname "$R")" ] || { echo NOAGENT; exit 0; }; echo AGENT; [ -d "$R" ] || exit 0; cd "$R" && '
           'find . -maxdepth 4 -name SKILL.md -not -path "./.hub/*" -not -path "*/node_modules/*" 2>/dev/null | '
           'while IFS= read -r f; do printf "%%s\\t%%s\\n" "$(sha256sum "$f" 2>/dev/null | cut -c1-64)" "$f"; done' % HERMES_ROOT)
    code, out, err = _exec(h, cmd)
    if code != 0:
        raise ValueError("Gagal baca skill di %s: %s" % (h["label"], err.strip() or "exit %s" % code))
    lines = out.splitlines()
    if not lines or lines[0].strip() == "NOAGENT":
        return {"hasAgent": False, "remote": []}
    remote = []
    for l in lines[1:]:
        if "\t" not in l:
            continue
        hsh, path = l.split("\t", 1)
        path = re.sub(r"^\./", "", path)
        parts = path.split("/")
        if len(parts) < 2:
            continue
        remote.append({"name": parts[-2], "path": path, "hash": hsh.strip()})
    return {"hasAgent": True, "remote": remote}


def state_of(st, skill):
    r = next((x for x in st["remote"] if x["name"] == skill["name"]), None)
    if r is None:
        return "missing"
    return "same" if r["hash"] == hash_of(prepare(skill["raw"])) else "differs"


def push(h, skill):
    text = prepare(skill["raw"])
    d = "%s/%s" % (HERMES_ROOT, dir_for(skill["name"]))
    b64 = base64.b64encode(text.encode("utf-8")).decode()
    meta = json.dumps({"from": "satsh", "name": skill["name"], "sha256": hash_of(text), "at": dt.datetime.now().isoformat()[:19]})
    cmd = ('D="%s"; mkdir -p "$D" && printf %%s %s | base64 -d > "$D/SKILL.md.tmp" && mv "$D/SKILL.md.tmp" "$D/SKILL.md" && '
           'printf %%s %s > "$D/.satsh-push.json" && echo PUSHED' % (d, shlex.quote(b64), shlex.quote(meta)))
    code, out, err = _exec(h, cmd)
    if code != 0 or "PUSHED" not in out:
        raise ValueError('Push "%s" gagal: %s' % (skill["name"], err.strip() or "exit %s" % code))
    return "~/.hermes/skills/%s/SKILL.md" % dir_for(skill["name"])


def pull(h, path):
    if ".." in path:
        raise ValueError("Path aneh")
    code, out, err = _exec(h, 'cat "%s"/%s' % (HERMES_ROOT, shlex.quote(path)))
    if code != 0:
        raise ValueError("Gagal baca %s: %s" % (path, err.strip()))
    return out
