"""Error log with tracebacks (%USERPROFILE%\\.satsh\\errors.jsonl) — same idea as satsh Android."""
import datetime as dt
import json
import os
import platform
import sys
import threading
import traceback

from . import __version__
from .config import HOME

MAX = 200
_PATH = os.path.join(HOME, "errors.jsonl")
_lock = threading.Lock()
entries = []
listeners = []


def _load():
    if not os.path.exists(_PATH):
        return
    try:
        with open(_PATH, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    entries.append(json.loads(line))
                except Exception:
                    pass
    except Exception:
        pass


_load()


def add(source, exc, context=None, tb=None):
    """Record an exception (call from inside an except block). Never raises."""
    try:
        if tb is None:
            tb = traceback.format_exc()
            if tb.strip() == "NoneType: None":
                tb = ""
        e = {"t": dt.datetime.now().isoformat(timespec="seconds"), "src": source, "msg": ("%s: %s" % (type(exc).__name__, exc))[:2000],
             "stack": "\n".join(tb.strip().splitlines()[-40:]), "ctx": {k: str(v) for k, v in (context or {}).items()}}
        with _lock:
            entries.append(e)
            del entries[:-MAX]
            tmp = _PATH + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write("\n".join(json.dumps(x, ensure_ascii=False) for x in entries) + "\n")
            os.replace(tmp, _PATH)
        for cb in list(listeners):
            try:
                cb(e)
            except Exception:
                pass
    except Exception:
        pass


def clear():
    with _lock:
        del entries[:]
        try:
            os.remove(_PATH)
        except OSError:
            pass


def report(last=MAX):
    pick = entries[-last:]
    out = ["=== satsh desktop error log ===", "versi: %s" % __version__,
           "sistem: %s %s, Python %s (%d-bit)" % (platform.system(), platform.release(), platform.python_version(), 64 if sys.maxsize > 2 ** 32 else 32),
           "dibuat: %s" % dt.datetime.now().isoformat(timespec="seconds"), "jumlah error: %d" % len(pick), ""]
    for e in reversed(pick):
        out.append("[%s] %s" % (e.get("t"), e.get("src")))
        out.append(e.get("msg", ""))
        for k, v in (e.get("ctx") or {}).items():
            out.append("  %s: %s" % (k, v))
        if e.get("stack"):
            out.append(e["stack"])
        out.append("---")
    from . import redact  # reports get shared — never leak keys/passwords

    return redact.text("\n".join(out) + "\n")
