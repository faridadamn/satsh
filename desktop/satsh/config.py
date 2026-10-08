"""Settings + secrets. Data lives in %USERPROFILE%\\.satsh (override with SATSH_HOME).

Secrets are encrypted with Windows DPAPI (tied to the Windows user account),
so copying the folder to another PC doesn't leak API keys / passwords.
"""
import base64
import json
import os
import threading
import uuid

HOME = os.environ.get("SATSH_HOME") or os.path.join(os.path.expanduser("~"), ".satsh")
os.makedirs(HOME, exist_ok=True)

_lock = threading.RLock()
_SETTINGS = os.path.join(HOME, "settings.json")
_SECRETS = os.path.join(HOME, "secrets.json")

DEFAULTS = {
    "port": 8771,
    "theme": "dark",
    "providers": [
        # tried in order; next one is used when a call fails (fallback chain)
        {"id": "p1", "kind": "openai", "name": "OpenAI", "base": "https://api.openai.com/v1", "model": "gpt-4.1-mini"},
    ],
    "autoApprove": False,
    "toolGroupsOff": [],
    "agentPrompt": "",
    "reviewEvery": 6,
    "ctxChars": 80000,
    "supabaseUrl": "",
    "shell": "cmd",  # cmd | powershell
    "cloudflared": "",
    "telegramChat": "",
    "remoteEnabled": False,
}


def new_id():
    return uuid.uuid4().hex


# ------------------------------------------------------------------ DPAPI
if os.name == "nt":
    import ctypes
    from ctypes import wintypes

    class _BLOB(ctypes.Structure):
        _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]

    def _blob(data):
        buf = ctypes.create_string_buffer(data, len(data))
        return _BLOB(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_char))), buf

    def _protect(data):
        inp, _keep = _blob(data)
        out = _BLOB()
        if not ctypes.windll.crypt32.CryptProtectData(ctypes.byref(inp), u"satsh", None, None, None, 0, ctypes.byref(out)):
            raise OSError("CryptProtectData gagal")
        try:
            return ctypes.string_at(out.pbData, out.cbData)
        finally:
            ctypes.windll.kernel32.LocalFree(out.pbData)

    def _unprotect(data):
        inp, _keep = _blob(data)
        out = _BLOB()
        if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(inp), None, None, None, None, 0, ctypes.byref(out)):
            raise OSError("CryptUnprotectData gagal")
        try:
            return ctypes.string_at(out.pbData, out.cbData)
        finally:
            ctypes.windll.kernel32.LocalFree(out.pbData)
else:  # dev / tests on Linux

    def _protect(data):
        return data

    def _unprotect(data):
        return data


class Config:
    def __init__(self):
        self.data = dict(DEFAULTS)
        self.secrets = {}
        self.listeners = []
        self.load()

    def load(self):
        with _lock:
            if os.path.exists(_SETTINGS):
                try:
                    with open(_SETTINGS, "r", encoding="utf-8") as f:
                        self.data.update(json.load(f))
                except Exception:
                    pass
            if os.path.exists(_SECRETS):
                try:
                    with open(_SECRETS, "r", encoding="utf-8") as f:
                        self.secrets = json.load(f)
                except Exception:
                    self.secrets = {}

    def save(self):
        with _lock:
            tmp = _SETTINGS + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self.data, f, indent=2, ensure_ascii=False)
            os.replace(tmp, _SETTINGS)
        for cb in list(self.listeners):
            try:
                cb()
            except Exception:
                pass

    def get(self, key, default=None):
        v = self.data.get(key)
        return default if v is None else v

    def set(self, key, value):
        self.data[key] = value
        self.save()

    def update(self, values):
        self.data.update(values)
        self.save()

    # secrets ---------------------------------------------------------
    def secret(self, key):
        raw = self.secrets.get(key)
        if not raw:
            return None
        try:
            return _unprotect(base64.b64decode(raw)).decode("utf-8")
        except Exception:
            return None

    def set_secret(self, key, value):
        with _lock:
            if value:
                self.secrets[key] = base64.b64encode(_protect(value.encode("utf-8"))).decode("ascii")
            else:
                self.secrets.pop(key, None)
            tmp = _SECRETS + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self.secrets, f)
            os.replace(tmp, _SECRETS)

    def has_secret(self, key):
        return bool(self.secrets.get(key))


cfg = Config()
