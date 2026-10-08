"""HTTP server: static web UI + JSON API + Server-Sent Events. Stdlib only."""
import base64
import hmac
import json
import mimetypes
import os
import posixpath
import queue
import secrets
import stat
import threading
import time
import traceback
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import agentzip, errlog, presets, redact, skill_push
from . import markas_client as markas
from . import llm as llm_mod
from .agent import agent, bus, cron
from .brain import CronJob, now_ms
from .config import HOME, cfg, new_id
from .browser import browser
from .remote import telegram, tunnel
from .ssh import HostKeyUnknown, generate_ed25519, ssh
from .tools import TOOLS

WEB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web")
TOKENS = set()
_HTTPD = None
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("text/markdown", ".md")
mimetypes.add_type("font/ttf", ".ttf")

ssh.listeners.append(lambda w: bus.emit("ssh", {}))
tunnel.listeners.append(lambda: bus.emit("tunnel", tunnel.status()))


class ApiError(Exception):
    def __init__(self, msg, code=400, extra=None):
        super().__init__(msg)
        self.code, self.extra = code, extra or {}


def _host(hid):
    h = ssh.host(hid)
    if not h:
        raise ApiError("Host ga ada", 404)
    return h


def state():
    providers = []
    for p in cfg.get("providers", []):
        providers.append(dict(p, hasKey=cfg.has_secret("key_" + p["id"])))
    b = agent.brain
    return {
        "settings": {k: v for k, v in cfg.data.items() if k != "providers"},
        "providers": providers,
        "secrets": {k: cfg.has_secret(k) for k in ("supabaseKey", "telegramToken", "webPassword")},
        "hosts": [dict(h, connected=ssh.connected(h["id"])) for h in sorted(ssh.hosts, key=lambda h: -(h.get("lastUsed") or 0))],
        "terms": [{"id": t.id, "hostId": t.host["id"], "label": t.host["label"], "alive": t.alive} for t in ssh.terms.values()],
        "sessions": b.sessions,
        "runs": {sid: {"status": redact.text(r["status"])} for sid, r in agent.runs.items()},
        "skills": [{"name": s["name"], "description": s["description"], "raw": s["raw"], "builtin": b.active.is_builtin(s["name"]),
                    "modified": b.active.is_modified(s)} for s in b.skills],
        "missingBuiltins": b.active.missing_builtins(),
        "jobs": [dict(j, next=j.next_run().strftime("%Y-%m-%d %H:%M"), label=j.schedule_label()) for j in b.jobs],
        "memory": {"memory": b.entries("memory"), "user": b.entries("user"), "limits": {"memory": b.limit("memory"), "user": b.limit("user")}},
        "soul": b.soul,
        "profiles": b.profiles,
        "activeProfile": b.active_id,
        "presets": [{"id": i, "name": presets.NAMES.get(i, i)} for i in presets.ids() if not b.profile(i)],
        "version": __import__("satsh").__version__,
        "tunnel": tunnel.status(),
        "browser": browser.status(),
        "pending": agent.pending_list(),
        "toolGroups": sorted({t["group"] for t in TOOLS}),
        "toolCount": {g: len([t for t in TOOLS if t["group"] == g]) for g in {t["group"] for t in TOOLS}},
        "home": os.path.expanduser("~"),
        "errorCount": len(errlog.entries),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "satsh"
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    # ---------------------------------------------------------- helpers
    @property
    def is_remote(self):
        h = self.headers
        return bool(h.get("Cf-Connecting-Ip") or h.get("X-Forwarded-For") or h.get("Cf-Ray")) or self.client_address[0] not in ("127.0.0.1", "::1")

    def origin_ok(self, strict=True):
        """Blocks cross-site requests (CSRF) and DNS rebinding.

        Local requests must address us as 127.0.0.1/localhost:<port>. If the browser
        sends an Origin, it must be this same origin; "null" (sandboxed pages served
        from a host) is refused on [strict] paths so they can't drive the API."""
        host = (self.headers.get("Host") or "").strip().lower()
        if not self.is_remote:
            port = self.server.server_address[1]
            if host not in ("127.0.0.1:%d" % port, "localhost:%d" % port):
                return False
        origin = (self.headers.get("Origin") or "").strip().lower().rstrip("/")
        if not origin or not strict:
            return True
        return origin in ("http://" + host, "https://" + host)

    def authed(self):
        if not self.is_remote:
            return True
        c = self.headers.get("Cookie") or ""
        for part in c.split(";"):
            k, _, v = part.strip().partition("=")
            if k == "satsh_auth" and v in TOKENS:
                return True
        return False

    def send_json(self, obj, code=200, headers=None):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def jbody(self):
        raw = self.body()
        return json.loads(raw.decode("utf-8")) if raw else {}

    def q(self):
        return {k: v[0] for k, v in urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).items()}

    def send_file(self, path, ctype=None, download=None):
        size = os.path.getsize(path)
        self._send_stream(lambda off, ln: _local_reader(path, off, ln), size, ctype or mimetypes.guess_type(path)[0] or "application/octet-stream", download)

    def _send_stream(self, reader, size, ctype, download=None, untrusted=False):
        rng = self.headers.get("Range")
        start, end, code = 0, size - 1, 200
        if rng and rng.startswith("bytes=") and size:
            a, _, b = rng[6:].split(",")[0].partition("-")
            if a == "":
                start = max(0, size - int(b))
            else:
                start = int(a)
                if b:
                    end = min(int(b), size - 1)
            if start >= size:
                self.send_response(416)
                self.send_header("Content-Range", "bytes */%d" % size)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            code = 206
        length = max(0, end - start + 1) if size else 0
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        if untrusted:
            # Files from a host run in an opaque origin: scripts work, the satsh API doesn't.
            self.send_header("Content-Security-Policy", "sandbox allow-scripts allow-forms allow-popups allow-modals allow-downloads")
            self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store")
        if code == 206:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        if download:
            self.send_header("Content-Disposition", "attachment; filename*=UTF-8''" + urllib.parse.quote(download))
        self.end_headers()
        if self.command == "HEAD" or not length:
            return
        try:
            for chunk in reader(start, length):
                self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

    # ------------------------------------------------------------ verbs
    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        try:
            # Pages served from a host (raw/site) may fetch their own assets with Origin: null.
            if not self.origin_ok(strict=not path.startswith(("/api/sftp/raw", "/api/sftp/site/"))):
                return self.send_json({"error": "forbidden"}, 403)
            if path == "/api/version":
                return self.send_json({"version": __import__("satsh").__version__})
            if path == "/api/login-needed":
                return self.send_json({"needed": not self.authed()})
            if path.startswith("/api/") or path == "/files":
                if not self.authed():
                    return self.send_json({"error": "login"}, 401)
                return self.get_api(path)
            # static
            rel = "index.html" if path in ("/", "") else posixpath.normpath(urllib.parse.unquote(path)).lstrip("/")
            full = os.path.normpath(os.path.join(WEB, rel))
            if not full.startswith(WEB) or not os.path.isfile(full):
                full = os.path.join(WEB, "index.html")
            return self.send_file(full)
        except ApiError as e:
            self.send_json(dict({"error": str(e)}, **e.extra), e.code)
        except Exception as e:  # noqa
            traceback.print_exc()
            errlog.add("server", e, {"GET": urllib.parse.urlparse(self.path).path})
            try:
                self.send_json({"error": str(e)}, 500)
            except Exception:
                pass

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        try:
            if not self.origin_ok():
                return self.send_json({"error": "forbidden"}, 403)
            if path == "/api/login":
                pw = cfg.secret("webPassword") or ""
                given = (self.jbody().get("password") or "")
                if pw and hmac.compare_digest(pw, given):
                    tok = secrets.token_urlsafe(24)
                    TOKENS.add(tok)
                    return self.send_json({"ok": True}, headers={"Set-Cookie": "satsh_auth=%s; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000%s" % (tok, "; Secure" if self.is_remote else "")})
                time.sleep(1)
                return self.send_json({"error": "Password salah"}, 401)
            if not self.authed():
                return self.send_json({"error": "login"}, 401)
            return self.post_api(path)
        except ApiError as e:
            self.send_json(dict({"error": str(e)}, **e.extra), e.code)
        except HostKeyUnknown as e:
            self.send_json({"error": str(e), "needTrust": True, "keytype": e.keytype, "fp": e.fp, "old": e.old, "hostId": e.host["id"]}, 409)
        except Exception as e:  # noqa
            traceback.print_exc()
            if not isinstance(e, (ValueError, OSError, KeyError)):
                errlog.add("server", e, {"POST": urllib.parse.urlparse(self.path).path})
            self.send_json({"error": str(e)}, 400)

    # -------------------------------------------------------------- GET
    def get_api(self, path):
        q = self.q()
        if path == "/api/state":
            return self.send_json(state())
        if path == "/api/events":
            return self.sse()
        if path == "/api/session":
            s = agent.session(q.get("id", ""))
            if not s:
                raise ApiError("Sesi ga ada", 404)
            if s.get("unread"):
                s["unread"] = False
                agent.brain.mark_read(s["id"])
                if s["id"] not in agent.runs:
                    agent.brain.save_session(s)
            return self.send_json(redact.session_view(dict(s, **agent.state(s["id"]))))
        if path == "/api/search":
            return self.send_json(agent.brain.search_sessions(q.get("q", ""), limit=20))
        if path == "/api/term/read":
            t = ssh.terms.get(q.get("id"))
            if not t:
                return self.send_json({"alive": False, "seq": 0, "data": ""})
            seq, data = t.read_since(int(q.get("seq") or 0))
            return self.send_json({"seq": seq, "data": base64.b64encode(data).decode(), "alive": t.alive})
        if path == "/api/sftp/list":
            h = _host(q["host"])
            sf = ssh.sftp(h)
            try:
                p = sf.normalize(q.get("path") or ".")
                items = []
                for e in sf.listdir_attr(p):
                    isdir = stat.S_ISDIR(e.st_mode or 0)
                    if stat.S_ISLNK(e.st_mode or 0):
                        try:
                            isdir = stat.S_ISDIR(sf.stat(posixpath.join(p, e.filename)).st_mode)
                        except Exception:
                            pass
                    items.append({"name": e.filename, "dir": isdir, "size": e.st_size or 0, "mtime": e.st_mtime or 0})
                items.sort(key=lambda x: (not x["dir"], x["name"].lower()))
                return self.send_json({"path": p, "items": items})
            finally:
                sf.close()
        if path == "/api/sftp/raw":
            h = _host(q["host"])
            p = q["path"]
            sf = ssh.sftp(h)
            try:
                st = sf.stat(p)
                if stat.S_ISDIR(st.st_mode):
                    p = posixpath.join(p, "index.html")
                    st = sf.stat(p)

                def reader(off, ln):
                    with sf.open(p, "rb") as f:
                        f.seek(off)
                        f.prefetch(ln) if ln > 1024 * 1024 else None
                        left = ln
                        while left > 0:
                            chunk = f.read(min(65536, left))
                            if not chunk:
                                break
                            left -= len(chunk)
                            yield chunk

                ctype = mimetypes.guess_type(p)[0] or "application/octet-stream"
                if ctype.startswith("text/") or ctype in ("application/javascript", "application/json"):
                    ctype += "; charset=utf-8"
                self._send_stream(reader, st.st_size or 0, ctype, posixpath.basename(p) if q.get("dl") else None, untrusted=True)
            finally:
                sf.close()
            return
        if path.startswith("/api/sftp/site/"):
            # /api/sftp/site/<hostId>/<path...> — lets HTML pages load relative assets
            rest = path[len("/api/sftp/site/"):]
            hid, _, rp = rest.partition("/")
            self.path = "/api/sftp/raw?" + urllib.parse.urlencode({"host": hid, "path": "/" + urllib.parse.unquote(rp)})
            return self.get_api("/api/sftp/raw")
        if path == "/api/agentzip":
            data = agentzip.export(agent.brain, sessions=q.get("sessions") == "1", jobs=q.get("jobs") == "1")
            name = "satsh-agent-%s.zip" % time.strftime("%Y%m%d")
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Content-Disposition", 'attachment; filename="%s"' % name)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
            return
        if path == "/api/markas":
            h = markas.host()
            r = {"configured": markas.configured(), "hostId": markas.host_id(), "host": h["label"] if h else "", "rapatPrompt": markas.RAPAT_PROMPT}
            if r["configured"]:
                try:
                    r["snap"] = markas.status()
                except Exception as e:  # noqa
                    r["error"] = str(e)
            return self.send_json(r)
        if path == "/api/errors":
            return self.send_json({"entries": list(reversed(errlog.entries)), "version": __import__("satsh").__version__})
        if path == "/api/errors/report":
            data = errlog.report().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Content-Disposition", 'attachment; filename="satsh-error-log-%s.txt"' % time.strftime("%Y%m%d-%H%M"))
            self.end_headers()
            self.wfile.write(data)
            return
        if path == "/files":
            p = q.get("path", "")
            if not os.path.isfile(p):
                raise ApiError("File ga ada", 404)
            return self.send_file(p)
        raise ApiError("Ga ada endpoint " + path, 404)

    def sse(self):
        sub = bus.subscribe()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Accel-Buffering", "no")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        try:
            self.wfile.write(b": hi\n\n")
            self.wfile.flush()
            while True:
                try:
                    msg = sub.get(timeout=15)
                    self.wfile.write(("data: %s\n\n" % json.dumps(msg, ensure_ascii=False)).encode("utf-8"))
                except queue.Empty:
                    self.wfile.write(b": ping\n\n")
                self.wfile.flush()
        except Exception:
            pass
        finally:
            bus.unsubscribe(sub)
            self.close_connection = True

    # ------------------------------------------------------------- POST
    def post_api(self, path):
        if path == "/api/sftp/upload":
            q = self.q()
            h = _host(q["host"])
            n = int(self.headers.get("Content-Length") or 0)
            sf = ssh.sftp(h)
            try:
                with sf.open(q["path"], "wb") as f:
                    f.set_pipelined(True)
                    left = n
                    while left > 0:
                        chunk = self.rfile.read(min(65536, left))
                        if not chunk:
                            break
                        f.write(chunk)
                        left -= len(chunk)
            finally:
                sf.close()
            return self.send_json({"ok": True})
        if path == "/api/agentzip/import":
            n = int(self.headers.get("Content-Length") or 0)
            if n > 200 * 1024 * 1024:
                raise ApiError("Zip kegedean")
            summary = agentzip.import_zip(agent.brain, self.rfile.read(n))
            bus.emit("brain", {"what": "profiles"})
            return self.send_json({"summary": summary})
        d = self.jbody()
        b = agent.brain
        ok = {"ok": True}
        if path == "/api/markas/install":
            out = markas.install(d["hostId"])
            return self.send_json({"ok": True, "hermes": "HERMES_SKILL_OK" in out, "hermesCli": "HERMES_CLI_OK" in out})
        if path == "/api/markas/host":
            cfg.set("markasHost", d.get("hostId") or "")
            return self.send_json(ok)
        if path == "/api/markas/run":
            args = [str(x) for x in (d.get("args") or [])]
            if not args or args[0] not in ("target", "log", "say", "read", "brief", "status", "inbox"):
                raise ApiError("perintah markas ga diizinin")
            out = markas.run(args, who="adam")
            bus.emit("markas", {})
            return self.send_json({"out": out})
        if path == "/api/markas/rapat":
            b.set_active("default")
            return self.send_json({"sid": agent.send(None, markas.RAPAT_PROMPT)})
        if path == "/api/errors/clear":
            errlog.clear()
            return self.send_json(ok)
        # ---------------- profiles
        if path == "/api/profile/activate":
            b.set_active(d["id"])
            return self.send_json(ok)
        if path == "/api/profile/create":
            p = b.create_profile(d.get("name", ""), emoji=d.get("emoji") or "🤖", desc=d.get("desc", ""),
                                 copy_from=d.get("copyFrom") or None)
            return self.send_json({"profile": p})
        if path == "/api/profile/update":
            p = b.update_profile(d["id"], name=(d.get("name") or "").strip() or None, emoji=d.get("emoji"), desc=d.get("desc"),
                                 provider=d.get("provider"), toolsOff=d.get("toolsOff"))
            return self.send_json({"profile": p})
        if path == "/api/profile/preset":
            p = b.install_preset(presets.load(d["id"]))
            b.set_active(p["id"])
            return self.send_json({"profile": p})
        if path == "/api/profile/delete":
            b.delete_profile(d["id"])
            return self.send_json(ok)
        # ---------------- agent
        if path == "/api/chat":
            return self.send_json({"sid": agent.send(d.get("sid"), d.get("text", ""))})
        if path == "/api/stop":
            agent.stop(d.get("sid"))
            return self.send_json(ok)
        if path == "/api/approve":
            agent.answer(d.get("id"), d.get("answer"))
            return self.send_json(ok)
        if path == "/api/session/rename":
            s = agent.session(d["id"])
            if s:
                s["title"] = d["title"].strip() or s["title"]
                b.save_session(s)
            return self.send_json(ok)
        if path == "/api/session/delete":
            b.delete_session(d["id"])
            return self.send_json(ok)
        if path == "/api/review":
            s = agent.session(d["sid"])
            if not s or not s["messages"]:
                raise ApiError("Sesinya masih kosong")
            return self.send_json({"notes": agent.review(s, agent.provider())})
        # ---------------- brain
        if path == "/api/soul":
            b.save_soul(d.get("text", ""))
            return self.send_json(ok)
        if path == "/api/memory":
            items = [x.strip() for x in d.get("entries", []) if x.strip()]
            if len("\n§\n".join(items)) > b.limit(d["target"]):
                raise ApiError("Kepenuhan, ringkas dulu")
            b.set_entries(d["target"], items)
            return self.send_json(ok)
        if path == "/api/skill":
            name = b.save_skill(d.get("raw", ""))
            if d.get("old") and d["old"] != name:
                b.delete_skill(d["old"])
            return self.send_json({"name": name})
        if path == "/api/skill/delete":
            b.delete_skill(d["name"])
            return self.send_json(ok)
        if path == "/api/browser/stop":
            browser.stop()
            return self.send_json(ok)
        if path == "/api/skill/reset":
            if d.get("all"):
                return self.send_json({"count": b.active.reset_all_builtins()})
            b.active.reset_skill(d["name"])
            return self.send_json(ok)
        if path == "/api/skillpush/status":
            h = _host(d["hostId"])
            st = skill_push.status(h)
            mk = skill_push.markas_skill()
            alls = list(b.skills) + ([mk] if mk and not b.skill("markas") else [])
            names = {s["name"] for s in alls}
            cfg.set("skillPushHost", h["id"])
            return self.send_json({"hasAgent": st["hasAgent"],
                                   "skills": [{"name": s["name"], "description": s["description"], "state": skill_push.state_of(st, s)} for s in alls] if st["hasAgent"] else [],
                                   "onlyRemote": [r for r in st["remote"] if r["name"] not in names]})
        if path == "/api/skillpush/push":
            h = _host(d["hostId"])
            mk = skill_push.markas_skill()
            done, errs = [], []
            for n in d.get("names") or []:
                sk = b.skill(n) or (mk if n == "markas" else None)
                if not sk:
                    errs.append("%s: ga ada" % n)
                    continue
                try:
                    skill_push.push(h, sk)
                    done.append(n)
                except Exception as e:  # noqa
                    errs.append(str(e))
            return self.send_json({"pushed": done, "errors": errs})
        if path == "/api/skillpush/pull":
            raw = skill_push.pull(_host(d["hostId"]), d["path"])
            return self.send_json({"name": b.save_skill(raw)})
        if path == "/api/job":
            j = b.job(d.get("id")) if d.get("id") else None
            if j is None:
                j = CronJob(id=new_id(), created=now_ms(), lastRun=None, lastResult="", sessionId=None)
                b.jobs.append(j)
            daily = d.get("dailyAt") or None
            j.update(name=d.get("name") or "Tugas", prompt=d.get("prompt", ""), dailyAt=daily,
                     everyMinutes=None if daily else int(d.get("everyMinutes") or 60), enabled=d.get("enabled", True),
                     allowRisky=bool(d.get("allowRisky")))
            b.save_jobs()
            return self.send_json(ok)
        if path == "/api/job/delete":
            b.jobs = [j for j in b.jobs if j["id"] != d["id"]]
            b.save_jobs()
            return self.send_json(ok)
        if path == "/api/job/run":
            j = b.job(d["id"])
            threading.Thread(target=cron.run, args=(j,), daemon=True).start()
            return self.send_json(ok)
        # ---------------- settings
        if path == "/api/settings":
            vals = {k: v for k, v in d.items() if k in cfg.data and k != "providers"}
            changed_browser = any(k in vals and vals[k] != cfg.get(k) for k in ("browserShow", "browserPath", "toolGroupsOff"))
            cfg.update(vals)
            redact.enabled = cfg.get("redact", True) is not False
            if changed_browser:
                browser.stop()  # next use starts with the new settings
            bus.emit("settings", {})
            return self.send_json(ok)
        if path == "/api/secret":
            if d["key"] not in ("supabaseKey", "telegramToken", "webPassword"):
                raise ApiError("key ga dikenal")
            cfg.set_secret(d["key"], d.get("value") or None)
            bus.emit("settings", {})
            return self.send_json(ok)
        if path == "/api/providers":
            ps = []
            for p in d.get("providers", []):
                p = {k: p.get(k) for k in ("id", "kind", "name", "base", "model", "disabled")}
                p["id"] = p.get("id") or new_id()[:8]
                ps.append(p)
            cfg.set("providers", ps)
            for k, v in (d.get("keys") or {}).items():
                if v:
                    cfg.set_secret("key_" + k, v)
            bus.emit("settings", {})
            return self.send_json({"providers": ps})
        if path == "/api/provider/delete-key":
            cfg.set_secret("key_" + d["id"], None)
            return self.send_json(ok)
        if path == "/api/models":
            p = next((x for x in cfg.get("providers", []) if x["id"] == d["id"]), None)
            if not p:
                raise ApiError("Provider ga ada")
            return self.send_json({"models": llm_mod.build(p).models()})
        if path == "/api/test-llm":
            p = next((x for x in cfg.get("providers", []) if x["id"] == d["id"]), None)
            r = llm_mod.build(p).chat("Jawab super singkat.", [{"role": "user", "text": 'Bilang "siap bre" aja'}], [])
            return self.send_json({"text": r.text})
        # ---------------- ssh
        if path == "/api/host":
            h = {k: d["host"].get(k) for k in ("id", "label", "host", "port", "username", "auth", "color", "startup") if d["host"].get(k) is not None}
            h["port"] = int(h.get("port") or 22)
            h["label"] = h.get("label") or h.get("host")
            old = ssh.host(h.get("id")) if h.get("id") else None
            if old:
                h = dict(old, **h)
            h = ssh.save_host(h, password=d.get("password") or None, key=d.get("key") or None, passphrase=d.get("passphrase") or None)
            return self.send_json({"host": h})
        if path == "/api/host/delete":
            ssh.delete_host(d["id"])
            return self.send_json(ok)
        if path == "/api/host/connect":
            ssh.client(_host(d["id"]), password=d.get("password"))
            return self.send_json(ok)
        if path == "/api/host/trust":
            ssh.trust(_host(d["id"]), d["keytype"], d["fp"])
            return self.send_json(ok)
        if path == "/api/host/disconnect":
            ssh.disconnect(d["id"])
            return self.send_json(ok)
        if path == "/api/keygen":
            h = _host(d["id"])
            priv, pub = generate_ed25519()
            line = pub.replace("'", "")
            out = ssh.run(h, "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && (grep -qxF '%s' ~/.ssh/authorized_keys || echo '%s' >> ~/.ssh/authorized_keys) && echo KEY_OK" % (line, line))
            if "KEY_OK" not in out:
                raise ApiError("Gagal pasang key: " + out)
            ssh.save_host(dict(h, auth="key"), key=priv)
            return self.send_json({"public": pub})
        if path == "/api/term/open":
            t = ssh.open_terminal(_host(d["hostId"]), d.get("cols") or 100, d.get("rows") or 30)
            return self.send_json({"id": t.id})
        if path == "/api/term/write":
            t = ssh.terms.get(d["id"])
            if t:
                t.write(d.get("data", ""))
            return self.send_json(ok)
        if path == "/api/term/resize":
            t = ssh.terms.get(d["id"])
            if t:
                t.resize(d["cols"], d["rows"])
            return self.send_json(ok)
        if path == "/api/term/close":
            ssh.close_terminal(d["id"])
            return self.send_json(ok)
        if path in ("/api/sftp/write", "/api/sftp/mkdir", "/api/sftp/rename", "/api/sftp/delete", "/api/sftp/touch"):
            sf = ssh.sftp(_host(d["host"]))
            try:
              try:
                if path == "/api/sftp/write":
                    with sf.open(d["path"], "wb") as f:
                        f.write(d.get("content", "").encode("utf-8"))
                elif path == "/api/sftp/touch":
                    try:
                        sf.stat(d["path"])
                        raise ApiError("File udah ada")
                    except IOError:
                        sf.open(d["path"], "wb").close()
                elif path == "/api/sftp/mkdir":
                    sf.mkdir(d["path"])
                elif path == "/api/sftp/rename":
                    sf.rename(d["from"], d["to"])
                else:
                    (sf.rmdir if d.get("dir") else sf.remove)(d["path"])
              except IOError as e:
                msg = str(e)
                raise ApiError("Gagal: " + ("udah ada / folder ga kosong / ga ada izin" if msg in ("Failure", "") else msg))
            finally:
                sf.close()
            return self.send_json(ok)
        # ---------------- remote
        if path == "/api/tunnel/start":
            if not cfg.has_secret("webPassword"):
                raise ApiError("Set password web dulu sebelum buka akses remote")
            tunnel.start(int(cfg.get("port")))
            return self.send_json(ok)
        if path == "/api/tunnel/download":
            tunnel.fetch()
            return self.send_json(ok)
        if path == "/api/tunnel/stop":
            tunnel.stop()
            return self.send_json(ok)
        if path == "/api/shutdown":
            if self.is_remote:
                raise ApiError("Matiin cuma bisa dari laptopnya langsung", 403)
            self.send_json(ok)
            threading.Thread(target=lambda: (time.sleep(0.3), tunnel.stop(), browser.stop(), _HTTPD.shutdown()), daemon=True).start()
            return
        if path == "/api/telegram/test":
            return self.send_json({"ok": telegram("👋 Tes dari satsh desktop")})
        raise ApiError("Ga ada endpoint " + path, 404)


def _local_reader(path, off, ln):
    with open(path, "rb") as f:
        f.seek(off)
        left = ln
        while left > 0:
            chunk = f.read(min(65536, left))
            if not chunk:
                break
            left -= len(chunk)
            yield chunk


class Server(ThreadingHTTPServer):
    daemon_threads = True
    # Windows' SO_REUSEADDR lets a SECOND process bind the same port (requests then hit either one at
    # random — an old satsh would keep answering after an update). Bind exclusively there instead.
    allow_reuse_address = os.name != "nt"

    def server_bind(self):
        import socket

        if os.name == "nt" and hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


def open_ui(url):
    """Prefer a modern browser — Win7's default might still be IE11, which can't run the UI."""
    import webbrowser

    if os.name == "nt":
        pf = [os.environ.get(k, "") for k in ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA")]
        cands = []
        for base in pf:
            cands += [os.path.join(base, "Google", "Chrome", "Application", "chrome.exe"),
                      os.path.join(base, "Microsoft", "Edge", "Application", "msedge.exe"),
                      os.path.join(base, "Mozilla Firefox", "firefox.exe")]
        for c in cands:
            if c and os.path.isfile(c):
                import subprocess

                subprocess.Popen([c, url])
                return
    webbrowser.open(url)


def running_version(port):
    """Version of the satsh already on [port]: str, "" for an old one without /api/version, None if it's not satsh."""
    import urllib.error
    import urllib.request

    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/api/version" % port, timeout=3) as r:
            return json.loads(r.read().decode("utf-8")).get("version", "")
    except urllib.error.HTTPError as e:
        return "" if e.code == 404 else None
    except Exception:
        return None


def take_over(port):
    """After an update the OLD satsh may still hold the port (install.bat starts the new one while
    the old keeps running). Ask it to quit and take its place. Returns the new server or None."""
    import urllib.request

    mine = __import__("satsh").__version__
    other = running_version(port)
    if other is None or other == mine:
        return None
    print("satsh %s masih jalan — gantiin pakai %s…" % (other or "versi lama", mine))
    try:
        origin = "http://127.0.0.1:%d" % port
        req = urllib.request.Request(origin + "/api/shutdown", data=b"{}", method="POST",
                                     headers={"Content-Type": "application/json", "Origin": origin})
        urllib.request.urlopen(req, timeout=5).read()
    except Exception:  # noqa
        pass
    for _ in range(40):
        time.sleep(0.25)
        try:
            return Server(("127.0.0.1", port), Handler)
        except OSError:
            continue
    return None


def serve(port=None, open_browser=True):
    port = int(port or cfg.get("port", 8771))
    redact.enabled = cfg.get("redact", True) is not False
    try:
        redact.learn(cfg.secret_values())
    except Exception:  # noqa
        pass
    url = "http://127.0.0.1:%d" % port
    try:
        httpd = Server(("127.0.0.1", port), Handler)
    except OSError:
        httpd = take_over(port)
        if httpd is None:
            # the same version is already running → just open its UI
            print("satsh udah jalan di %s" % url)
            if open_browser:
                open_ui(url)
            return
    global _HTTPD
    _HTTPD = httpd
    cron.on_done = lambda title, body: (bus.emit("toast", {"title": title, "body": body}), telegram("%s\n%s" % (title, body)) if cfg.get("telegramChat") else None)
    cron.start()
    if cfg.get("remoteEnabled") and cfg.has_secret("webPassword"):
        tunnel.start(port)
    print("satsh desktop jalan di %s  (Ctrl+C buat berhenti)" % url)
    if open_browser:
        threading.Timer(0.8, lambda: open_ui(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        tunnel.stop()
        browser.stop()
