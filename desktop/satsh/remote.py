"""Remote access from the phone: Cloudflare quick tunnel + Telegram notifications."""
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

from .config import HOME, cfg


def telegram(text):
    token = cfg.secret("telegramToken")
    chat = cfg.get("telegramChat")
    if not token or not chat:
        return False
    data = urllib.parse.urlencode({"chat_id": chat, "text": text, "disable_web_page_preview": "true"}).encode()
    try:
        urllib.request.urlopen("https://api.telegram.org/bot%s/sendMessage" % token, data=data, timeout=15).read()
        return True
    except Exception:
        return False


IS_WIN = os.name == "nt"
WIN7_CF = "2023.10.0"  # last cloudflared built with Go 1.20 — newer ones don't start on Windows 7/8
BIN = os.path.join(HOME, "bin")


def is_old_windows():
    if not IS_WIN:
        return False
    v = sys.getwindowsversion()
    return (v.major, v.minor) < (6, 2)  # Win7 = 6.1


def cf_asset():
    """(version, file name) of the cloudflared build that runs on this machine."""
    if IS_WIN:
        m = (platform.machine() or "").lower()
        arch = "amd64" if ("64" in m or os.environ.get("PROCESSOR_ARCHITEW6432")) else "386"
        return (WIN7_CF if is_old_windows() else "latest"), "cloudflared-windows-%s.exe" % arch
    m = (platform.machine() or "").lower()
    arch = "arm64" if m in ("aarch64", "arm64") else "arm" if m.startswith("arm") else "amd64" if "64" in m else "386"
    return "latest", "cloudflared-linux-%s" % arch


def cf_local():
    return os.path.join(BIN, "cloudflared.exe" if IS_WIN else "cloudflared")


def find_cloudflared():
    """Setting > satsh's own copy > PATH > common folders. None if not found."""
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cands = [(cfg.get("cloudflared") or "").strip().strip('"'), cf_local(), shutil.which("cloudflared") or ""]
    if IS_WIN:
        cands += [os.path.join(here, "tools", "cloudflared.exe"), r"C:\tools\cloudflared.exe"]
        cands += [os.path.join(os.environ.get(k, ""), "cloudflared", "cloudflared.exe") for k in ("PROGRAMFILES", "PROGRAMFILES(X86)") if os.environ.get(k)]
    return next((c for c in cands if c and os.path.isfile(c)), None)


def dns_public(host):
    """Does the domain exist on the internet? (Cloudflare DNS-over-HTTPS, so the ISP's DNS doesn't matter)"""
    req = urllib.request.Request("https://cloudflare-dns.com/dns-query?type=A&name=" + urllib.parse.quote(host),
                                 headers={"Accept": "application/dns-json"})
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            return bool(json.loads(r.read().decode()).get("Answer"))
    except Exception:
        return False


def dns_local(host):
    """Does THIS laptop's DNS (usually the ISP's) know the domain yet?"""
    import socket
    try:
        return bool(socket.getaddrinfo(host, 443))
    except Exception:
        return False


def reachable(url):
    """The link really answers (through Cloudflare back to this satsh)."""
    try:
        with urllib.request.urlopen(urllib.request.Request(url + "/api/version", headers={"User-Agent": "satsh-check"}), timeout=10) as r:
            return r.status == 200
    except Exception:
        return False


class Tunnel:
    CHECK_S = 120

    def __init__(self):
        self.proc = None
        self.url = None
        self.ready = False
        self.note = None  # what the readiness check is waiting for
        self.error = None
        self.listeners = []
        self.download = None  # {"pct": 0-100, "error": str|None, "done": bool}

    def _changed(self):
        for cb in list(self.listeners):
            try:
                cb()
            except Exception:
                pass

    @property
    def running(self):
        return self.proc is not None and self.proc.poll() is None

    # --------------------------------------------------------------- download
    def fetch(self, url_base="https://github.com/cloudflare/cloudflared/releases"):
        """Downloads the right cloudflared into ~/.satsh/bin in the background."""
        if self.download and not self.download.get("done"):
            return
        ver, name = cf_asset()
        url = "%s/%s/%s" % (url_base, "latest/download" if ver == "latest" else "download/" + ver, name)
        self.download = {"pct": 0, "error": None, "done": False, "version": ver}
        self._changed()

        def run():
            dst = cf_local()
            part = dst + ".part"
            try:
                os.makedirs(BIN, exist_ok=True)
                req = urllib.request.Request(url, headers={"User-Agent": "satsh-desktop"})
                with urllib.request.urlopen(req, timeout=60) as r, open(part, "wb") as f:
                    total = int(r.headers.get("Content-Length") or 0)
                    got, last = 0, 0
                    while True:
                        chunk = r.read(256 * 1024)
                        if not chunk:
                            break
                        f.write(chunk)
                        got += len(chunk)
                        pct = int(got * 100 / total) if total else 0
                        if pct >= last + 5:
                            last = pct
                            self.download["pct"] = pct
                            self._changed()
                with open(part, "rb") as f:
                    head = f.read(4)
                if got < 5 * 1024 * 1024 or head[:2] not in (b"MZ", b"\x7fE"):
                    raise ValueError("file yang ke-download bukan program cloudflared")
                if os.path.exists(dst):
                    os.remove(dst)
                os.replace(part, dst)
                if not IS_WIN:
                    os.chmod(dst, 0o755)
                if (cfg.get("cloudflared") or "").strip() and not os.path.isfile((cfg.get("cloudflared") or "").strip().strip('"')):
                    cfg.set("cloudflared", "")  # stale path from before → use the downloaded one
                self.download.update(pct=100, done=True)
                self.error = None
            except Exception as e:  # noqa
                self.download.update(done=True, error="Download gagal: %s" % e)
                try:
                    os.remove(part)
                except OSError:
                    pass
            self._changed()

        threading.Thread(target=run, daemon=True).start()

    # ------------------------------------------------------------------ run
    def start(self, port):
        if self.running:
            return
        self.url, self.error = None, None
        exe = find_cloudflared()
        if not exe:
            self.error = "cloudflared.exe belum ada di laptop ini. Klik \"Download cloudflared\" (otomatis), atau isi lokasinya."
            self._changed()
            return
        try:
            flags = 0x08000000 if IS_WIN else 0
            self.proc = subprocess.Popen([exe, "tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:%d" % port],
                                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, creationflags=flags)
        except OSError as e:
            bad_exe = getattr(e, "winerror", None) in (193, 216) or "not a valid" in str(e).lower()
            self.error = ("cloudflared ini ga cocok sama Windows lu%s. Klik \"Download cloudflared\" buat versi yang pas." %
                          (" (Win7 butuh versi %s)" % WIN7_CF if is_old_windows() else "")) if bad_exe else "Ga bisa jalanin cloudflared (%s): %s" % (exe, e)
            self._changed()
            return
        proc = self.proc
        tail = []

        def read():
            for raw in iter(proc.stdout.readline, b""):
                line = raw.decode("utf-8", "replace").strip()
                tail.append(line)
                del tail[:-6]
                m = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", line)
                if m and not self.url:
                    self.url = m.group(0)
                    self.ready, self.note = False, "Link dapet, nunggu DNS-nya siap…"
                    self._changed()
                    threading.Thread(target=self._verify, args=(proc, self.url), daemon=True).start()
            code = proc.wait()
            if self.proc is proc:
                if not self.url:
                    hint = " Kalau ini Win7, pakai cloudflared %s (klik Download cloudflared)." % WIN7_CF if is_old_windows() else ""
                    last = next((l for l in reversed(tail) if l), "")
                    self.error = "cloudflared berhenti (kode %s)%s%s" % (code, (": " + last[-160:]) if last else "", hint)
                self.proc = None
                self.url = None
                self.ready = False
                self._changed()

        threading.Thread(target=read, daemon=True).start()
        self._changed()

    def _verify(self, proc, url):
        """New trycloudflare names take a few seconds–minutes to exist in DNS, and ISP DNS caches the
        "doesn't exist" answer. Only call the link ready (and send it to Telegram) once it really opens."""
        host = urllib.parse.urlparse(url).hostname
        end = time.time() + self.CHECK_S
        pub = loc = False
        while time.time() < end and self.proc is proc and self.url == url:
            pub = pub or dns_public(host)
            loc = dns_local(host)
            if loc and reachable(url):
                self.ready, self.note, self.error = True, None, None
                self._changed()
                telegram("🟢 satsh desktop online\n%s" % url)
                return
            self.note = ("Link dapet, nunggu DNS internet…" if not pub else
                         "DNS internet udah siap, DNS laptop (ISP) belum…" if not loc else "DNS siap, ngetes link…")
            self._changed()
            time.sleep(3)
        if self.proc is not proc or self.url != url:
            return
        self.note = None
        if pub and not loc:
            self.error = ("Link udah aktif di internet, tapi DNS laptop/ISP lu belum kenal domainnya. Coba buka dari HP pakai data seluler, "
                          "atau ganti DNS ke 1.1.1.1 / 8.8.8.8, lalu jalanin: ipconfig /flushdns")
        else:
            self.error = "Link belum bisa dibuka setelah %d detik. Coba Matiin lalu Nyalain lagi (dapet link baru)." % self.CHECK_S
        self.ready = True  # stop showing "waiting"; the link may still work from the phone
        self._changed()
        telegram("🟡 satsh desktop online (DNS belum kebuka dari laptop)\n%s" % url)

    def stop(self):
        p = self.proc
        self.proc, self.url, self.ready, self.note = None, None, False, None
        if p:
            try:
                p.terminate()
            except Exception:
                pass
        self._changed()

    def status(self):
        ver, _ = cf_asset()
        return {"running": self.running, "url": self.url, "ready": self.ready, "note": self.note, "error": self.error, "exe": find_cloudflared() or "",
                "download": self.download, "wantVersion": ver}


tunnel = Tunnel()
