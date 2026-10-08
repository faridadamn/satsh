"""Security: the local web UI must not be drivable by other websites (CSRF / DNS rebinding),
and HTML opened from a host must not reach the satsh API."""
import http.client
import json
import os
import subprocess
import sys
import tempfile
import time

PORT = 8793
OK = []


def check(name, cond):
    if not cond:
        print("  ✗ " + name)
        sys.exit(1)
    OK.append(name)
    print("  ✓ " + name)


def req(method, path, body=None, headers=None):
    c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=10)
    h = {"Host": "127.0.0.1:%d" % PORT}
    h.update(headers or {})
    data = json.dumps(body).encode() if body is not None else None
    c.request(method, path, body=data, headers=h)
    r = c.getresponse()
    out = (r.status, dict(r.getheaders()), r.read())
    c.close()
    return out


def main():
    home = tempfile.mkdtemp(prefix="satsh-sec-")
    env = dict(os.environ, SATSH_HOME=home, HOME=home)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    srv = subprocess.Popen([sys.executable, "-m", "satsh", "--port", str(PORT), "--no-browser"], cwd=root, env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                req("GET", "/api/login-needed")
                break
            except OSError:
                time.sleep(0.2)

        s, _, _ = req("GET", "/api/state")
        check("own UI still works (same host, no Origin)", s == 200)
        s, _, _ = req("POST", "/api/settings", {"theme": "light"}, {"Origin": "http://127.0.0.1:%d" % PORT, "Content-Type": "application/json"})
        check("own UI POST with same Origin works", s == 200)
        s, _, _ = req("POST", "/api/settings", {"theme": "dark"}, {"Origin": "http://localhost:%d" % PORT, "Host": "localhost:%d" % PORT})
        check("localhost alias works", s == 200)

        s, _, _ = req("POST", "/api/settings", {"theme": "light"}, {"Origin": "https://evil.example", "Content-Type": "text/plain"})
        check("cross-site POST (CSRF) refused", s == 403)
        s, _, _ = req("POST", "/api/term/write", {"id": "x", "data": "rm -rf ~\r"}, {"Origin": "null"})
        check("sandboxed page (Origin: null) can't POST", s == 403)
        s, _, _ = req("POST", "/api/login", {"password": "x"}, {"Origin": "https://evil.example"})
        check("cross-site login attempt refused", s == 403)
        s, _, _ = req("GET", "/api/state", headers={"Host": "evil.example:%d" % PORT})
        check("DNS rebinding (foreign Host) refused", s == 403)
        s, _, _ = req("GET", "/api/state", headers={"Origin": "https://evil.example"})
        check("cross-site GET of API refused", s == 403)
        s, _, _ = req("GET", "/api/sftp/raw?host=nope&path=/x", headers={"Origin": "null"})
        check("sandboxed page may still request host files (gets normal error)", s != 403)
    finally:
        srv.terminate()
        srv.wait(5)

    sys.path.insert(0, root)
    os.environ["SATSH_HOME"] = home
    from satsh import server  # noqa

    class Fake(server.Handler):
        def __init__(self):
            self.headers = {}
            self.sent = []
            self.command = "GET"
            self.wfile = open(os.devnull, "wb")

        def send_response(self, code, msg=None):
            self.sent.append(("status", code))

        def send_header(self, k, v):
            self.sent.append((k, v))

        def end_headers(self):
            pass

    f = Fake()
    f._send_stream(lambda o, n: iter([b"<script>1</script>"]), 18, "text/html", untrusted=True)
    csp = dict(f.sent).get("Content-Security-Policy", "")
    check("host HTML served with CSP sandbox (no same-origin)", "sandbox" in csp and "allow-same-origin" not in csp)
    f = Fake()
    f._send_stream(lambda o, n: iter([b"x"]), 1, "text/html")
    check("satsh's own files have no sandbox", "Content-Security-Policy" not in dict(f.sent))
    print("SECURITY OK (%d)" % len(OK))


if __name__ == "__main__":
    main()
