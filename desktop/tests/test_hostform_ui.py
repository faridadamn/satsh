"""UI: pasting an ssh/mosh command fills the desktop host form and quick connect.
Needs Playwright + Chromium (dev only):  python tests/test_hostform_ui.py
(CHROMIUM=/path/to/chrome to use a browser Playwright didn't download)"""
import os
import sys
import tempfile
import threading
import time

os.environ["SATSH_HOME"] = tempfile.mkdtemp(prefix="hostui")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from satsh import server  # noqa: E402
from satsh.ssh import ssh  # noqa: E402

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("SKIP: playwright ga ada")
    raise SystemExit(0)

PORT = 8799
threading.Thread(target=lambda: server.serve(PORT, open_browser=False), daemon=True).start()
time.sleep(1.5)
CMD = 'mosh --ssh="ssh -p 2222" abc123@api.instabox.sh'


def ok(c, m):
    if not c:
        raise SystemExit("FAIL " + m)
    print("  ✓", m)


with sync_playwright() as p:
    exe = os.environ.get("CHROMIUM")
    pg = (p.chromium.launch(executable_path=exe) if exe else p.chromium.launch()).new_page()
    errs = []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.goto("http://127.0.0.1:%d/" % PORT)
    pg.evaluate("localStorage.setItem('view','host')")
    pg.reload()
    pg.wait_for_timeout(800)
    pg.get_by_role("button", name="Host baru").click()
    pg.wait_for_timeout(300)
    val = lambda k: pg.locator('input[data-k="%s"]' % k).input_value()  # noqa: E731

    # 1. paste a whole command into the Host field → split up
    pg.locator('input[data-k="host"]').fill(CMD)
    pg.wait_for_timeout(100)
    ok((val("host"), val("port"), val("username")) == ("api.instabox.sh", "2222", "abc123"), "host field splits a pasted mosh line")
    ok(pg.get_by_text("belum bisa mosh").count() == 1, "mosh note shown")
    ok(pg.get_by_text("Keisi: abc123@api.instabox.sh:2222").count() == 1, "filled-from hint")

    # 2. the paste box (Enter)
    box = pg.get_by_placeholder("Tempel di sini — ssh -p 2222 user@host")
    box.fill("ssh -p 2200 -l deploy vps.example.com -t 'tmux a'")
    box.press("Enter")
    ok((val("host"), val("port"), val("username"), val("startup")) == ("vps.example.com", "2200", "deploy", "tmux a"), "paste box fills incl. auto-run")
    pg.get_by_role("button", name="Simpan").click()
    pg.wait_for_timeout(500)
    ok(any(h["host"] == "vps.example.com" and h["port"] == 2200 and h["username"] == "deploy" for h in ssh.hosts), "saved")

    # 3. quick connect with a full ssh command creates the host
    q = pg.get_by_placeholder("user@host:port  atau  ssh -p 2222 user@host  —  quick connect")
    q.fill("ssh -p 2222 abc123@api.instabox.sh")
    q.press("Enter")
    pg.wait_for_timeout(800)
    ok(any(h["host"] == "api.instabox.sh" and h["port"] == 2222 and h["username"] == "abc123" for h in ssh.hosts), "quick connect understands ssh -p")
    ok(not errs, "no page errors %s" % errs)
print("HOST FORM UI OK")
