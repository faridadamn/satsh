"""UI: chat renders incrementally (status ticks don't refetch, unchanged bubbles are reused).
Needs Playwright + Chromium (dev only):  python tests/test_ui.py"""
import os
import sys
import tempfile
import threading
import time

os.environ["SATSH_HOME"] = tempfile.mkdtemp(prefix="ui")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from satsh import server  # noqa: E402
from satsh.agent import agent  # noqa: E402

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("SKIP: playwright ga ada")
    raise SystemExit(0)

PORT = 8798
b = agent.brain
s = b.new_session("ui")
s["messages"] += [{"role": "user", "text": "halo"}, {"role": "assistant", "text": "cek dulu", "calls": [{"id": "c1", "name": "ssh_exec", "args": {"host": "vps", "command": "uptime"}}]}]
b.save_session(s)
agent.live[s["id"]] = s
threading.Thread(target=lambda: server.serve(PORT, open_browser=False), daemon=True).start()
time.sleep(1.5)


def ok(c, m):
    if not c:
        raise SystemExit("FAIL " + m)
    print("  ✓", m)


with sync_playwright() as p:
    pg = p.chromium.launch().new_page()
    errs = []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.goto("http://127.0.0.1:%d/" % PORT)
    pg.evaluate("localStorage.setItem('sid','%s')" % s["id"])
    pg.reload()
    pg.wait_for_timeout(1200)
    ok(pg.locator("#msgs .bubble-u").count() == 1 and pg.locator("#msgs .tool").count() == 1, "initial render")
    first_bubble = pg.evaluate_handle("document.querySelector('#msgs .bubble-u')")
    agent.runs[s["id"]] = {"status": "x", "cancel": False}
    agent._set_status(s, "Jalanin di vps…")
    pg.wait_for_timeout(400)
    ok(pg.locator("#msgs .thinking span").inner_text() == "Jalanin di vps…", "status shows in thinking line")
    agent._set_status(s, "Baca hasil…")
    pg.wait_for_timeout(300)
    ok(pg.locator("#msgs .thinking span").inner_text() == "Baca hasil…", "status updates in place")
    s["messages"].append({"role": "tool", "callId": "c1", "name": "ssh_exec", "text": "exit: 0\nup 3 days"})
    agent._emit_session(s)
    pg.wait_for_timeout(500)
    ok(pg.locator("#msgs .tool .st.ok").count() == 1, "tool chip turns done when its result arrives")
    ok(pg.evaluate("(n) => n === document.querySelector('#msgs .bubble-u')", first_bubble), "unchanged bubble reused (not rebuilt)")
    s["messages"].append({"role": "assistant", "text": "**Beres**: up 3 hari"})
    agent.runs.pop(s["id"])
    agent._emit_session(s)
    pg.wait_for_timeout(600)
    ok(pg.locator("#msgs .bubble-a").last.inner_text().startswith("Beres"), "final answer appended in order")
    ok(pg.locator("#msgs .thinking").count() == 0, "thinking line gone when done")
    pg.locator("#msgs .tool").first.click()
    pg.wait_for_timeout(200)
    ok("up 3 days" in pg.locator("#msgs .tool").first.inner_text(), "tool chip expands")
    pg.locator("#msgs .tool").first.click()
    pg.wait_for_timeout(200)
    ok("up 3 days" not in pg.locator("#msgs .tool").first.inner_text(), "…and collapses")
    ok(not errs, "no JS errors %s" % errs)
print("UI OK")
