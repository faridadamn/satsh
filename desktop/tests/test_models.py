"""Agent switches its own model for a chat and generates pictures with an image model.

    python tests/test_models.py
"""
import base64
import json
import os
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

os.environ["SATSH_HOME"] = tempfile.mkdtemp(prefix="satshmod")
os.environ["SATSH_GEN_DIR"] = tempfile.mkdtemp(prefix="gen")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from satsh import llm  # noqa: E402
from satsh.agent import RunCtx, agent  # noqa: E402
from satsh.config import cfg  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\nfake"
ROUTES = {}
HITS = []


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)))
        HITS.append((self.path, body))
        code, out = ROUTES.get(self.path, (404, '{"error":{"message":"not found"}}'))
        b = out.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)


def ok(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print("  ✓", msg)


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d/v1" % srv.server_address[1]
    cfg.set("providers", [{"id": "r9", "kind": "openai", "name": "9router", "base": base, "model": "ag/gemini-3.8-flash-high"},
                          {"id": "or", "kind": "openai", "name": "OpenRouter", "base": base, "model": "x"}])
    cfg.set_secret("key_r9", "k9")
    cfg.set_secret("key_or", "ko")

    ok(llm.find_provider("9ROUTER")["id"] == "r9" and llm.find_provider("route")["id"] == "r9" and llm.find_provider("or")["id"] == "or",
       "provider found by id / name / part of name")
    ch = llm.default_provider("r9", "cx/gpt-5.5")
    ok(ch.providers[0].model == "cx/gpt-5.5" and ch.providers[1].model == "x", "switched model on that provider, others stay as fallback")
    ok(cfg.get("providers")[0]["model"] == "ag/gemini-3.8-flash-high", "user settings untouched")

    s = {"id": "s1", "messages": []}
    ctx = RunCtx(session=s)
    tools = {t["name"]: t["run"] for t in agent.brain_tools(ctx)}
    ok("default profil" in tools["model_list"]({}) and "9router" in tools["model_list"]({}), "model_list shows providers")
    out = tools["model_switch"]({"provider": "9router", "model": "cx/gpt-5.5"})
    ok(s["model"] == {"provider": "r9", "model": "cx/gpt-5.5"} and ctx.switch_to is not None and "cx/gpt-5.5" in out, "model_switch sets the chat's model")
    ok(s["messages"][-1]["role"] == "event", "user sees the switch in the chat")
    ok(agent.provider(None, s).providers[0].model == "cx/gpt-5.5", "next turn of this chat keeps the switched model")
    tools["model_switch"]({"reset": True})
    ok("model" not in s, "reset back to default")

    # image: /images/generations
    ROUTES.clear()
    ROUTES["/v1/images/generations"] = (200, json.dumps({"data": [{"b64_json": base64.b64encode(PNG).decode()}]}))
    r = tools["image_generate"]({"prompt": "kucing", "provider": "9router", "model": "gpt-image-1"})
    path = r["text"].split("Gambar jadi: ")[1].split(" (")[0]
    ok(open(path, "rb").read() == PNG and path.endswith(".png"), "images/generations b64 saved")

    # image: 9router puts a markdown data URI in a chat reply
    ROUTES.clear()
    HITS.clear()
    ROUTES["/v1/chat/completions"] = (200, json.dumps({"choices": [{"message": {"content": "Nih\n![image](data:image/png;base64,%s)\n" % base64.b64encode(PNG).decode()}, "finish_reason": "stop"}]}))
    r = tools["image_generate"]({"prompt": "logo", "provider": "9router", "model": "ag/gemini-3.1-flash-image"})
    ok([h[0] for h in HITS] == ["/v1/images/generations", "/v1/chat/completions"] and HITS[1][1]["stream"] is False, "falls back to chat completions")
    path = r["text"].split("Gambar jadi: ")[1].split(" (")[0]
    ok(open(path, "rb").read() == PNG and "Nih" in r["text"], "9router data URI picture saved")

    # OpenRouter message.images
    ROUTES["/v1/chat/completions"] = (200, json.dumps({"choices": [{"message": {"content": "", "images": [{"type": "image_url", "image_url": {"url": "data:image/png;base64,%s" % base64.b64encode(PNG).decode()}}]}, "finish_reason": "stop"}]}))
    r = tools["image_generate"]({"prompt": "x", "provider": "OpenRouter", "model": "google/gemini-2.5-flash-image"})
    ok("Gambar jadi" in r["text"], "OpenRouter images[] read")

    ROUTES["/v1/chat/completions"] = (200, '{"choices":[{"message":{"content":"cuma teks"},"finish_reason":"stop"}]}')
    try:
        tools["image_generate"]({"prompt": "x", "provider": "9router", "model": "ag/gemini-3.8-flash-high"})
        ok(False, "text-only model raised")
    except llm.LlmError as e:
        ok("ga ngirim gambar" in str(e), "text-only model says so")
    print("MODELS OK")


if __name__ == "__main__":
    main()
