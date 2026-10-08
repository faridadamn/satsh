"""Remote (cloudflared): finds it by itself, downloads the right build (Win7 → 2023.10.0), clear errors,
link only "ready" once it opens, an old satsh holding the port gets replaced.

    python tests/test_remote.py            # offline checks
    python tests/test_remote.py --online   # + real download from GitHub
"""
import os
import stat
import subprocess
import sys
import tempfile
import threading
import time

os.environ["SATSH_HOME"] = tempfile.mkdtemp(prefix="satshrm")
os.environ["PATH"] = "/usr/bin:/bin"  # no cloudflared on PATH
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from satsh import remote  # noqa: E402
from satsh.config import cfg  # noqa: E402
from satsh.remote import Tunnel, cf_asset, find_cloudflared  # noqa: E402


def ok(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print("  ✓", msg)


def wait(fn, t=20):
    end = time.time() + t
    while time.time() < end:
        if fn():
            return True
        time.sleep(0.2)
    return False


def fake_cf(body):
    p = os.path.join(tempfile.mkdtemp(), "cloudflared")
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body)
    os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC)
    return p


def main(online):
    ok(find_cloudflared() is None, "nothing found on a clean laptop")
    t = Tunnel()
    t.start(8771)
    ok(not t.running and "belum ada" in t.error and "Download cloudflared" in t.error, "clear error instead of WinError 2")

    real = (remote.IS_WIN, remote.is_old_windows, remote.platform.machine)
    try:
        remote.IS_WIN = True
        remote.platform.machine = lambda: "AMD64"
        remote.is_old_windows = lambda: True
        ok(cf_asset() == ("2023.10.0", "cloudflared-windows-amd64.exe"), "Win7 64-bit → cloudflared 2023.10.0")
        remote.platform.machine = lambda: "x86"
        ok(cf_asset() == ("2023.10.0", "cloudflared-windows-386.exe"), "Win7 32-bit → 386 build")
        remote.is_old_windows = lambda: False
        remote.platform.machine = lambda: "AMD64"
        ok(cf_asset() == ("latest", "cloudflared-windows-amd64.exe"), "Win10/11 → latest")
    finally:
        remote.IS_WIN, remote.is_old_windows, remote.platform.machine = real

    cfg.set("cloudflared", r"C:\tools\cloudflared.exe")
    ok(find_cloudflared() is None, "stale path in settings ignored")
    good = fake_cf('echo "INF |  https://abc-def-123.trycloudflare.com  |"\nsleep 30\n')
    cfg.set("cloudflared", good)
    ok(find_cloudflared() == good, "path from settings used")
    t.start(8771)
    ok(wait(lambda: t.url == "https://abc-def-123.trycloudflare.com"), "tunnel URL picked up")
    t.stop()
    ok(not t.running, "stop")

    bad = fake_cf('echo "ERR failed to request quick Tunnel: dial tcp: i/o timeout"\nexit 1\n')
    cfg.set("cloudflared", bad)
    t.start(8771)
    ok(wait(lambda: not t.running and t.error), "process that dies…")
    ok("berhenti (kode 1)" in t.error and "i/o timeout" in t.error, "…tells why: " + t.error)
    cfg.set("cloudflared", "")

    real_dns = (remote.dns_public, remote.dns_local, remote.reachable, remote.telegram)
    sent = []
    try:
        Tunnel.CHECK_S = 4
        remote.telegram = lambda text: sent.append(text) or True
        remote.dns_public = lambda h: True
        state = {"local": False}
        remote.dns_local = lambda h: state["local"]
        remote.reachable = lambda u: state["local"]
        cfg.set("cloudflared", good)
        t = Tunnel()
        t.start(8771)
        ok(wait(lambda: t.url) and not t.ready, "URL shown but not ready yet")
        ok(wait(lambda: t.note and "ISP" in t.note, 5), "waiting note says the laptop's DNS is behind: " + str(t.note))
        state["local"] = True
        ok(wait(lambda: t.ready and not t.error, 8), "ready once it opens")
        ok(sent and sent[-1].startswith("🟢") and t.url in sent[-1], "Telegram gets the link only when it works")
        t.stop()
        state["local"] = False
        sent.clear()
        t.start(8771)
        ok(wait(lambda: t.ready and t.error, 12), "gives up after the check window…")
        ok("ipconfig /flushdns" in t.error and "data seluler" in t.error, "…with a DNS hint: " + t.error[:70])
        ok(sent and sent[-1].startswith("🟡"), "Telegram told it may not open from the laptop")
        t.stop()
    finally:
        remote.dns_public, remote.dns_local, remote.reachable, remote.telegram = real_dns
        cfg.set("cloudflared", "")

    from http.server import BaseHTTPRequestHandler, HTTPServer
    from satsh import server as srv

    class Old(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):  # 2.4.1 and older: no /api/version
            self.send_response(404)
            self.end_headers()

        def do_POST(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"{}")
            threading.Thread(target=old.shutdown).start()

    old = HTTPServer(("127.0.0.1", 0), Old)
    port = old.server_address[1]
    th = threading.Thread(target=lambda: (old.serve_forever(), old.server_close()))
    th.start()
    ok(srv.running_version(port) == "", "old satsh detected (no /api/version)")
    new = srv.take_over(port)
    ok(new is not None and new.server_address[1] == port, "old one asked to quit, new one took the port")
    new.server_close()
    th.join(5)
    ok(srv.running_version(1) is None, "nothing on the port → not satsh")

    if online:
        t = Tunnel()
        t.fetch()
        ok(wait(lambda: t.download and t.download.get("done"), 180), "download finished (%s)" % t.download)
        ok(not t.download.get("error"), "no download error")
        exe = find_cloudflared()
        ok(exe == remote.cf_local(), "downloaded into ~/.satsh/bin and found automatically")
        v = subprocess.run([exe, "--version"], capture_output=True, text=True, timeout=30).stdout
        ok("cloudflared version" in v, "it runs: " + v.strip()[:60])
    print("REMOTE OK")


if __name__ == "__main__":
    main("--online" in sys.argv)
