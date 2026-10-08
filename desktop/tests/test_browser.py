"""Agent browser (Chrome via DevTools, stdlib only) + images reaching the model.

Needs a Chromium-based browser: SATSH_BROWSER=/path/to/chrome, or one on PATH / /opt/pw-browsers.
    python tests/test_browser.py
"""
import json
import os
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

os.environ["SATSH_HOME"] = tempfile.mkdtemp(prefix="satshbr")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from satsh import browser as brmod  # noqa: E402
from satsh import llm  # noqa: E402
from satsh.browser import browser, find_browser, normalize  # noqa: E402
from satsh.tools import tool  # noqa: E402

PAGES = {
    "/": """<html><head><title>Toko Tes</title></head><body style="margin:0;font:16px sans-serif">
<h1>Toko Tes</h1><p>Harga paket hemat: Rp49.000 per bulan.</p>
<a href="/promo" id="promo" style="display:inline-block;padding:10px">Lihat promo</a>
<form action="/cari" method="get"><input name="q" placeholder="Cari produk"><button>Cari</button></form>
<label>Nomor kartu <input name="cc-number" autocomplete="cc-number"></label>
<div id="ikon" style="position:absolute;left:600px;top:400px;width:60px;height:60px;background:#e33" onclick="document.title='ikon diklik'"></div>
<div style="height:2400px"></div><p id="bawah">Kontak: halo@toko.test</p>
</body></html>""",
    "/promo": "<html><head><title>Promo</title></head><body><h1>Promo 50%</h1><a href='/'>Balik</a></body></html>",
}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/cari":
            q = self.path.split("q=")[-1]
            body = "<html><head><title>Hasil</title></head><body><p>Hasil buat: %s</p></body></html>" % q
        else:
            body = PAGES.get(path, "<html><body>404</body></html>")
        b = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)


def ok(cond, msg):
    if not cond:
        browser.stop()
        raise AssertionError(msg)
    print("  ✓", msg)


def raises(fn, needle):
    try:
        fn()
    except Exception as e:  # noqa
        return needle in str(e)
    return False


def main():
    if not find_browser():
        print("SKIP: ga ada Chrome/Chromium")
        return
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % srv.server_address[1]
    run = lambda name, **a: tool(name)["run"](a)  # noqa: E731

    ok(normalize("toko.test/a") == "https://toko.test/a" and "duckduckgo" in normalize("harga vps murah"), "url / search normalize")
    ok("belum kebuka" in run("browser_read"), "read before open says so")

    t0 = time.time()
    out = run("browser_open", url=base + "/")
    ok("Toko Tes" in out and "Rp49.000" in out, "open: title + page text (%.1fs incl. browser start)" % (time.time() - t0))
    ok(browser.running and "--headless" in " ".join(browser.proc.args), "starts headless by default")
    ok('link "Lihat promo"' in out and "isian" in out, "numbered elements listed")
    els = [l for l in out.splitlines() if l.startswith("[")]
    num = lambda pred: next(l for l in els if pred(l)).split("]")[0].strip("[")  # noqa: E731
    n_promo = num(lambda l: "Lihat promo" in l)
    n_search = num(lambda l: "isian" in l and "Cari produk" in l)
    n_cc = num(lambda l: "isian" in l and "Cari produk" not in l)

    out = run("browser_type", n=int(n_search), text="kopi susu", submit=True)
    ok("Hasil buat: kopi+susu" in out or "Hasil buat: kopi%20susu" in out, "type + submit → result page")
    out = run("browser_back")
    ok("Toko Tes" in out, "back")
    out = run("browser_click", n=int(n_promo))
    ok("Promo 50%" in out, "click link → new page")
    run("browser_back")
    out = run("browser_type", n=int(n_cc), text="4111111111111111")
    ok("DITOLAK" in out, "payment field refused")

    out = run("browser_find", text="halo@toko.test")
    ok("Ketemu 1×" in out, "find text")
    look = run("browser_look")
    ok(isinstance(look, dict) and look["images"] and os.path.getsize(look["images"][0]) > 1000, "look returns a real JPEG")
    with open(look["images"][0], "rb") as f:
        ok(f.read(3) == b"\xff\xd8\xff", "…it is a JPEG")
    browser.tab.js("scrollTo(0,0)")
    run("browser_look", marks=False)
    out = run("browser_tap", x=630, y=430)
    ok("ikon diklik" in out, "tap on pixel hits the unlabeled element")

    hist = [{"role": "user", "text": "cek"}, {"role": "assistant", "text": "", "calls": [{"id": "c1", "name": "browser_look", "args": {}}]},
            {"role": "tool", "callId": "c1", "name": "browser_look", "text": look["text"], "images": look["images"]}]
    sent = {}
    real_post = llm._post
    llm._post = lambda url, headers, body, timeout=180: sent.update(body=body) or {"choices": [{"message": {"content": "oke"}}], "candidates": [{"content": {"parts": [{"text": "oke"}]}}]}
    llm.OpenAICompat("http://x", "k", "m").chat("sys", hist, [])
    msgs = sent["body"]["messages"]
    ok(msgs[-1]["role"] == "user" and msgs[-1]["content"][1]["image_url"]["url"].startswith("data:image/jpeg;base64,/9j/"), "OpenAI request carries the screenshot")
    llm.Gemini("k", "m").chat("sys", hist, [])
    parts = sent["body"]["contents"][-1]["parts"]
    ok(any("inlineData" in p for p in parts) and any("functionResponse" in p for p in parts), "Gemini request carries the screenshot")
    old = [dict(hist[2], callId="o%d" % i) for i in range(3)]
    ok(sum(len(v) for v in llm.tool_images(old + hist[1:]).values()) == llm.MAX_IMAGE_MSGS, "only the newest pictures are sent")

    calls = []

    def post(url, headers, body, timeout=180):
        calls.append(body)
        if len(calls) == 1:
            raise llm.LlmError("HTTP 400: image input is not supported by this model")
        return {"choices": [{"message": {"content": "oke"}}]}
    llm._post = post
    ok(llm.OpenAICompat("http://x", "k", "m").chat("sys", hist, []).text == "oke" and "ga bisa lihat gambar" in json.dumps(calls[1]), "text-only model falls back")
    llm._post = real_post

    from PIL import Image
    p = os.path.join(tempfile.mkdtemp(), "struk.png")
    Image.new("RGB", (3000, 1000), (200, 30, 30)).save(p)
    v = run("image_view", path=p)
    with Image.open(v["images"][0]) as im:
        ok(max(im.size) <= 1568 and im.format == "JPEG", "image_view sends a resized JPEG (%dx%d)" % im.size)
    ok(raises(lambda: run("image_view", path=__file__), "Bukan file gambar"), "non-image refused")

    brmod.IDLE_S = 0
    browser.last_used = 0
    end = time.time() + 20
    while browser.running and time.time() < end:
        time.sleep(0.5)
    ok(not browser.running, "closes itself when idle")
    out = run("browser_open", url=base + "/promo")
    ok("Promo" in out, "starts again on demand")
    browser.stop()
    ok(not browser.running, "browser_close / stop")
    print("ALL BROWSER TESTS PASSED")


if __name__ == "__main__":
    main()
