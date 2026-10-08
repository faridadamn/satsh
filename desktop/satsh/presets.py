"""Built-in agent profiles shipped with satsh desktop (same files as the Android app's assets/presets)."""
import os

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "presets")
NAMES = {
    "web-designer": "🎨 Web Designer — UI web anti-slop (AGENTS.md + DESIGN.md + gambar referensi)",
    "cybersecurity": "🛡️ Cyber Security — audit & hardening server, cek secret bocor, keamanan web app, triase insiden",
    "devops": "🚀 DevOps — rilis aman + rollback, backup & restore, Docker, Nginx + SSL",
    "code-reviewer": "🔍 Code Reviewer — review diff dengan bukti, jalanin tes, audit dependency",
}


def ids():
    if not os.path.isdir(BASE):
        return []
    return sorted(d for d in os.listdir(BASE) if os.path.isfile(os.path.join(BASE, d, "profile.json")))


def load(pid):
    root = os.path.join(BASE, pid)
    if pid not in ids():
        raise ValueError("Preset %s ga ada" % pid)
    out = {}
    for dirpath, _, files in os.walk(root):
        for f in files:
            full = os.path.join(dirpath, f)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            with open(full, "r", encoding="utf-8") as fh:
                out[rel] = fh.read()
    return out


def all_loaders():
    return {pid: (lambda p=pid: load(p)) for pid in ids()}
