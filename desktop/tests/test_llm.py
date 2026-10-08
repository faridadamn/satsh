"""OpenAI-compatible routers (9router…) that answer with an SSE stream even when we didn't ask.

    python tests/test_llm.py
"""
import json
import os
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

os.environ["SATSH_HOME"] = tempfile.mkdtemp(prefix="satshllm")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from satsh import llm  # noqa: E402

REPLY = {"body": "", "ctype": "text/event-stream"}
SENT = {}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        SENT["body"] = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)))
        b = REPLY["body"].encode()
        self.send_response(200)
        self.send_header("Content-Type", REPLY["ctype"])
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)


def ok(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print("  ✓", msg)


def sse(chunks):
    return "".join("data: %s\n\n" % json.dumps(c) for c in chunks) + "data: [DONE]\n\n"


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    p = llm.OpenAICompat("http://127.0.0.1:%d/v1" % srv.server_address[1], "k", "ag/gemini-3.8-flash-high", "9router")
    hist = [{"role": "user", "text": "halo"}]
    tools = [{"name": "shell_run", "description": "x", "params": {"command": {"type": "string"}}, "required": []}]

    REPLY["body"] = sse([
        {"id": "chatcmpl-1", "object": "chat.completion.chunk", "choices": [{"index": 0, "delta": {"role": "assistant", "content": "Halo "}}]},
        {"id": "chatcmpl-1", "object": "chat.completion.chunk", "choices": [{"index": 0, "delta": {"content": "bre!"}}]},
        {"id": "chatcmpl-1", "object": "chat.completion.chunk", "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]},
    ])
    r = p.chat("sys", hist, tools)
    ok(SENT["body"].get("stream") is False, "asks for a non-streamed answer")
    ok(r.text == "Halo bre!" and not r.calls, "streamed text joined (the 9router error)")

    REPLY["body"] = sse([
        {"choices": [{"delta": {"tool_calls": [{"index": 0, "id": "call_a", "function": {"name": "shell_run", "arguments": "{\"comm"}}]}}]},
        {"choices": [{"delta": {"tool_calls": [{"index": 0, "function": {"arguments": "and\": \"dir\"}"}}]}}]},
        {"choices": [{"delta": {"tool_calls": [{"index": 1, "id": "call_b", "function": {"name": "shell_run", "arguments": "{\"command\":\"ver\"}"}}]}}]},
    ])
    r = p.chat("sys", hist, tools)
    ok([c["id"] for c in r.calls] == ["call_a", "call_b"] and r.calls[0]["args"] == {"command": "dir"}, "streamed tool calls rebuilt")

    REPLY["body"] = 'data: {"error":{"message":"quota habis"}}\n\ndata: [DONE]\n\n'
    try:
        p.chat("sys", hist, tools)
        ok(False, "stream error raised")
    except llm.LlmError as e:
        ok(str(e) == "quota habis", "error inside the stream → LlmError (fallback to next provider works)")

    REPLY["body"], REPLY["ctype"] = "<html>502 Bad Gateway</html>", "text/html"
    try:
        p.chat("sys", hist, tools)
        ok(False, "garbage raised")
    except llm.LlmError as e:
        ok("bukan JSON" in str(e), "garbage body → clear error")

    REPLY["body"], REPLY["ctype"] = json.dumps({"choices": [{"message": {"content": "biasa"}}]}), "application/json"
    ok(p.chat("sys", hist, tools).text == "biasa", "plain JSON still works")
    print("LLM OK")


if __name__ == "__main__":
    main()
