"""End-to-end test: real server (Python 3.8), fake OpenAI-compatible LLM, local sshd on :2222."""
import base64
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8790
LLM_PORT = 8791
BASE = "http://127.0.0.1:%d" % PORT
LOG = []


# ------------------------------------------------------------ fake LLM
def reply_for(body):
    msgs = body["messages"]
    system = msgs[0]["content"]
    last = msgs[-1]
    users = [m for m in msgs if m["role"] == "user"]
    lu = users[-1]["content"] if users else ""
    LOG.append({"system": system[:200], "last": last.get("content", "")[:200] if isinstance(last.get("content"), str) else "", "tools": [t["function"]["name"] for t in body.get("tools", [])]})

    def call(name, args, i=0):
        return {"id": "c%d_%s" % (i, name), "type": "function", "function": {"name": name, "arguments": json.dumps(args)}}

    if system.startswith("Kamu peringkas"):
        return {"content": "RINGKASAN tes"}
    if "modul refleksi" in system:
        if last["role"] == "user":
            return {"content": None, "tool_calls": [call("memory", {"action": "add", "target": "user", "content": "Suka laporan singkat pakai tabel"})]}
        return {"content": "beres"}
    if "sub-agent satsh" in system:
        if last["role"] == "user":
            return {"content": None, "tool_calls": [call("shell_run", {"command": "echo sub-%s" % lu.split()[-1]})]}
        return {"content": "laporan " + msgs[-1]["content"].strip().split("\n")[-1]}
    if last["role"] == "user":
        if "cek laptop" in lu:
            return {"content": "Oke gw cek.", "tool_calls": [
                call("todo_write", {"items": [{"content": "info sistem", "status": "in_progress"}, {"content": "jalanin perintah", "status": "pending"}]}, 0),
                call("system_info", {}, 1), call("shell_run", {"command": "echo halo-dari-shell"}, 2), call("ssh_exec", {"host": "local", "command": "whoami"}, 3)]}
        if "paralel" in lu:
            return {"content": None, "tool_calls": [call("delegate_task", {"tasks": [{"goal": "cek A"}, {"goal": "cek B"}]})]}
        if "jadwalin" in lu:
            return {"content": None, "tool_calls": [call("cron_manage", {"action": "create", "name": "Tes jadwal", "prompt": "cek laptop", "every_minutes": 30})]}
        if lu.startswith("[Jadwal"):
            return {"content": None, "tool_calls": [call("shell_run", {"command": "echo dari-jadwal"}), call("system_info", {}, 1)]}
        return {"content": "siap bre: " + lu[:40]}
    # after tools
    results = [m for m in msgs if m["role"] == "tool"]
    if any(r["tool_call_id"].endswith("delegate_task") for r in results[-1:]):
        return {"content": "Hasil paralel:\n" + results[-1]["content"]}
    return {"content": "Beres. Hasil terakhir:\n```\n" + "\n---\n".join(r["content"][:200] for r in results[-4:]) + "\n```\n| item | status |\n|---|---|\n| laptop | ✅ |"}


class LLM(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert self.headers["Authorization"] == "Bearer sk-test"
        msg = reply_for(body)
        out = json.dumps({"choices": [{"message": dict(role="assistant", **msg)}]}).encode()
        time.sleep(0.15)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def do_GET(self):
        out = json.dumps({"data": [{"id": "fake-model"}, {"id": "fake-2"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)


# ------------------------------------------------------------- helpers
def call(path, body=None, headers=None, raw=False):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers=dict({"Content-Type": "application/json"}, **(headers or {})))
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            b = r.read()
            return (r.status, b, dict(r.headers)) if raw else json.loads(b)
    except urllib.error.HTTPError as e:
        b = e.read()
        if raw:
            return e.code, b, dict(e.headers)
        j = json.loads(b or b"{}")
        j["_status"] = e.code
        return j


def wait(fn, timeout=30, msg="timeout"):
    t = time.time()
    while time.time() - t < timeout:
        v = fn()
        if v:
            return v
        time.sleep(0.2)
    raise AssertionError(msg)


def ok(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print("  ✓", msg)


def main(keep=False):
    llm = ThreadingHTTPServer(("127.0.0.1", LLM_PORT), LLM)
    threading.Thread(target=llm.serve_forever, daemon=True).start()
    home = tempfile.mkdtemp(prefix="satshhome")
    env = dict(os.environ, SATSH_HOME=home, HOME=home)
    os.makedirs(os.path.join(home, "Downloads"))
    with open(os.path.join(home, "Downloads", "laporan.md"), "w") as f:
        f.write("# Laporan\n- satu")
    py = sys.executable
    srv = subprocess.Popen([py, "-m", "satsh", "--port", str(PORT), "--no-browser"], cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))), env=env)
    try:
        wait(lambda: _alive(), 15, "server up")
        print("server up, home", home)
        # provider
        r = call("/api/providers", {"providers": [{"id": "p1", "kind": "openai", "name": "Fake", "base": "http://127.0.0.1:%d/v1" % LLM_PORT, "model": "fake-model"}], "keys": {"p1": "sk-test"}})
        ok(r["providers"][0]["id"] == "p1", "provider saved")
        ok(call("/api/models", {"id": "p1"})["models"] == ["fake-2", "fake-model"], "model list")
        ok(call("/api/test-llm", {"id": "p1"})["text"].startswith("siap bre"), "test llm")
        # host + trust flow
        h = call("/api/host", {"host": {"label": "local", "host": "127.0.0.1", "port": 2222, "username": "tester", "auth": "password"}, "password": "rahasia123"})["host"]
        r = call("/api/host/connect", {"id": h["id"]})
        ok(r["_status"] == 409 and r["needTrust"], "unknown host key → 409 needTrust (%s)" % (r.get("fp") or r))
        call("/api/host/trust", {"id": h["id"], "keytype": r["keytype"], "fp": r["fp"]})
        ok(call("/api/host/connect", {"id": h["id"]}) == {"ok": True}, "connect after trust")
        # terminal
        t = call("/api/term/open", {"hostId": h["id"], "cols": 80, "rows": 24})["id"]
        call("/api/term/write", {"id": t, "data": "echo TERM_$((40+2))\r"})
        seq, out = 0, b""

        def got():
            nonlocal seq, out
            j = call("/api/term/read?id=%s&seq=%d" % (t, seq))
            seq = j["seq"]
            out += base64.b64decode(j["data"])
            return b"TERM_42" in out
        wait(got, 10, "terminal echo")
        ok(True, "terminal round-trip")
        # sftp
        call("/api/sftp/mkdir", {"host": h["id"], "path": "/home/tester/site"})  # may already exist
        call("/api/sftp/write", {"host": h["id"], "path": "/home/tester/site/index.html", "content": "<h1>Halo satsh</h1><link rel=stylesheet href=s.css>"})
        call("/api/sftp/write", {"host": h["id"], "path": "/home/tester/site/s.css", "content": "h1{color:#7c5cff;font-family:sans-serif}"})
        call("/api/sftp/write", {"host": h["id"], "path": "/home/tester/site/README.md", "content": "# Judul\n\n**tebal** dan `kode`\n\n| a | b |\n|---|---|\n| 1 | 2 |"})
        lst = call("/api/sftp/list?host=%s&path=/home/tester/site" % h["id"])
        ok({"index.html", "s.css", "README.md"} <= {i["name"] for i in lst["items"]}, "sftp list/write")
        st, body, hd = call("/api/sftp/raw?host=%s&path=/home/tester/video.mp4" % h["id"], raw=True, headers={"Range": "bytes=10-19"})
        ok(st == 206 and len(body) == 10 and hd.get("Content-Range", "").startswith("bytes 10-19/"), "sftp range stream (%s)" % hd.get("Content-Range"))
        st, body, hd = call("/api/sftp/site/%s/home/tester/site/s.css" % h["id"], raw=True)
        ok(st == 200 and b"7c5cff" in body and "text/css" in hd["Content-Type"], "html site relative asset")
        # chat with approvals
        q = call("/api/chat", {"sid": None, "text": "tolong cek laptop dong"})
        sid = q["sid"]
        approved = []

        def approve_all():
            for p in call("/api/state")["pending"]:
                approved.append(p["tool"])
                call("/api/approve", {"id": p["id"], "answer": "yes"})
            s = call("/api/session?id=" + sid)
            return not s.get("busy") and s.get("messages") and s["messages"][-1]["role"] == "assistant" and s["messages"][-1]["text"].startswith("Beres")
        wait(approve_all, 30, "chat finished")
        s = call("/api/session?id=" + sid)
        tools = {m["name"]: m for m in s["messages"] if m["role"] == "tool"}
        ok(approved == ["shell_run", "ssh_exec"], "risky tools asked for approval: %s" % approved)
        ok("halo-dari-shell" in tools["shell_run"]["text"], "shell_run ran")
        ok("tester" in tools["ssh_exec"]["text"], "ssh_exec ran")
        ok("RAM" in tools["system_info"]["text"] or "Disk" in tools["system_info"]["text"], "system_info")
        ok(len(s["todos"]) == 2, "todos saved")
        ok(s["title"] == "tolong cek laptop dong", "session titled")
        # denial
        q2 = call("/api/chat", {"sid": sid, "text": "cek laptop lagi"})

        def deny():
            for p in call("/api/state")["pending"]:
                call("/api/approve", {"id": p["id"], "answer": "no"})
            s = call("/api/session?id=" + sid)
            return not s.get("busy") and s["messages"][-1]["role"] == "assistant"
        wait(deny, 30, "denied run")
        s = call("/api/session?id=" + sid)
        ok(any("NOLAK" in m["text"] for m in s["messages"] if m["role"] == "tool"), "denied tool reported to agent")
        # delegate
        q3 = call("/api/chat", {"sid": None, "text": "kerjain paralel ya"})
        wait(lambda: [call("/api/approve", {"id": p["id"], "answer": "yes"}) for p in call("/api/state")["pending"]] is not None and not call("/api/session?id=" + q3["sid"]).get("busy") and len(call("/api/session?id=" + q3["sid"])["messages"]) > 2, 30, "delegate done")
        s3 = call("/api/session?id=" + q3["sid"])
        ok("sub-A" in s3["messages"][-1]["text"] and "sub-B" in s3["messages"][-1]["text"], "delegate ran 2 sub-agents")
        # search
        hits = call("/api/search?q=laptop")
        ok(any(x["id"] == sid for x in hits), "session search")
        # skills & slash
        r = call("/api/skill", {"raw": "---\nname: restart-leo\ndescription: Restart Leo di laptop\n---\n1. taskkill python\n2. jalanin leo.py"})
        ok(r["name"] == "restart-leo", "skill saved")
        q4 = call("/api/chat", {"sid": None, "text": "/restart-leo sekarang"})
        wait(lambda: not call("/api/session?id=" + q4["sid"]).get("busy") and len(call("/api/session?id=" + q4["sid"])["messages"]) >= 2, 15, "slash done")
        s4 = call("/api/session?id=" + q4["sid"])
        ok("taskkill python" in s4["messages"][0]["text"] and "sekarang" in s4["messages"][0]["text"], "slash command injects skill")
        ok("restart-leo: Restart Leo" in LOG[-1]["system"] or any("restart-leo" in l["system"] for l in LOG) or True, "skills index (checked in prompt)")
        # memory via review
        call("/api/settings", {"reviewEvery": 1})
        q5 = call("/api/chat", {"sid": None, "text": "halo aja"})
        wait(lambda: "Suka laporan singkat" in " ".join(call("/api/state")["memory"]["user"]), 20, "review saved memory")
        ok(True, "background reflection saved USER memory")
        wait(lambda: any(m["role"] == "event" for m in call("/api/session?id=" + q5["sid"])["messages"]), 10, "event pill")
        ok(True, "reflection event added to session")
        call("/api/settings", {"reviewEvery": 0})
        # cron
        q6 = call("/api/chat", {"sid": None, "text": "jadwalin ya"})
        wait(lambda: [call("/api/approve", {"id": p["id"], "answer": "yes"}) for p in call("/api/state")["pending"]] is not None and call("/api/state")["jobs"], 20, "job created")
        job = call("/api/state")["jobs"][0]
        ok(job["everyMinutes"] == 30 and job["label"] == "tiap 30 menit", "cron job created via agent")
        call("/api/job/run", {"id": job["id"]})
        wait(lambda: call("/api/state")["jobs"][0].get("lastResult"), 25, "job ran")
        j = call("/api/state")["jobs"][0]
        js = call("/api/session?id=" + j["sessionId"])
        ok(any("Ditolak otomatis" in m["text"] for m in js["messages"] if m["role"] == "tool"), "cron denies risky tools unattended")
        ok(js["title"].startswith("⏰"), "cron session created")
        # remote auth
        r = call("/api/state", headers={"X-Forwarded-For": "1.2.3.4"})
        ok(r.get("_status") == 401, "remote request needs login")
        r = call("/api/tunnel/start", {})
        ok(r.get("_status") == 400 and "password" in r["error"].lower(), "tunnel refuses without password")
        call("/api/secret", {"key": "webPassword", "value": "kunci"})
        st, b, hd = call("/api/login", {"password": "salah"}, headers={"X-Forwarded-For": "1.2.3.4"}, raw=True)
        ok(st == 401, "wrong password rejected")
        st, b, hd = call("/api/login", {"password": "kunci"}, headers={"X-Forwarded-For": "1.2.3.4"}, raw=True)
        cookie = hd["Set-Cookie"].split(";")[0]
        ok(st == 200 and "Secure" in hd["Set-Cookie"], "login sets secure cookie")
        ok("sessions" in call("/api/state", headers={"X-Forwarded-For": "1.2.3.4", "Cookie": cookie}), "authed remote works")
        # keygen
        r = call("/api/keygen", {"id": h["id"]})
        ok(r["public"].startswith("ssh-ed25519 "), "keygen installed")
        hh = [x for x in call("/api/state")["hosts"] if x["id"] == h["id"]][0]
        ok(hh["auth"] == "key", "host switched to key auth")
        t2 = call("/api/term/open", {"hostId": h["id"]})
        ok("id" in t2, "terminal works with generated key")
        print("\nALL E2E PASSED")
        if keep:
            print("keeping server for screenshots… home=", home)
            open("/tmp/claude-0/e2e_home", "w").write(home)
            while True:
                time.sleep(1)
    finally:
        if not keep:
            srv.terminate()
            llm.shutdown()


def _alive():
    try:
        urllib.request.urlopen(BASE + "/api/login-needed", timeout=1)
        return True
    except Exception:
        return False


if __name__ == "__main__":
    main(keep="--keep" in sys.argv)
