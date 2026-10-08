"""SSH hosts, connection pool, interactive terminals and SFTP (paramiko)."""
import base64
import io
import json
import os
import socket
import threading
import time

import paramiko

from .config import HOME, cfg, new_id

_HOSTS = os.path.join(HOME, "hosts.json")
_KNOWN = os.path.join(HOME, "known_hosts.json")
_lock = threading.RLock()


class HostKeyUnknown(Exception):
    def __init__(self, host, keytype, fp, old=None):
        self.host, self.keytype, self.fp, self.old = host, keytype, fp, old
        super().__init__(
            ("Host key %s BERUBAH! " % host["host"] if old else "Server baru: ")
            + "%s %s — percayain dulu di tab Host." % (keytype, fp)
        )


def _load(path, default):
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return default


def _save(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
    os.replace(tmp, path)


def fingerprint(key):
    import hashlib

    return "SHA256:" + base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip("=")


def load_pkey(text, passphrase=None):
    errors = []
    for cls in (paramiko.Ed25519Key, paramiko.ECDSAKey, paramiko.RSAKey):
        try:
            return cls.from_private_key(io.StringIO(text), password=passphrase or None)
        except paramiko.PasswordRequiredException:
            raise ValueError("Private key ini butuh passphrase")
        except Exception as e:  # try the next type
            errors.append(str(e))
    raise ValueError("Format private key ga kebaca")


def generate_ed25519(comment="satsh@windows"):
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    k = Ed25519PrivateKey.generate()
    priv = k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH, serialization.NoEncryption()).decode()
    pub = k.public_key().public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH).decode()
    return priv, "%s %s" % (pub, comment)


class Terminal:
    def __init__(self, mgr, host, chan, client):
        self.id = new_id()[:12]
        self.mgr, self.host, self.chan, self.client = mgr, host, chan, client
        self.buf = bytearray()  # scrollback for late joiners
        self.seq = 0
        self.alive = True
        self.cond = threading.Condition()
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        try:
            while True:
                data = self.chan.recv(32768)
                if not data:
                    break
                self._push(data)
        except Exception:
            pass
        self._push(b"\r\n\x1b[38;5;245m\xe2\x97\x8f sesi selesai\x1b[0m\r\n")
        self.alive = False
        with self.cond:
            self.cond.notify_all()

    def _push(self, data):
        with self.cond:
            self.buf.extend(data)
            if len(self.buf) > 400000:
                del self.buf[: len(self.buf) - 300000]
            self.seq += len(data)
            self.cond.notify_all()

    def read_since(self, seq, timeout=25):
        """Long-poll: returns (new_seq, bytes) once there's output after seq."""
        with self.cond:
            if self.seq <= seq and self.alive:
                self.cond.wait(timeout)
            start = len(self.buf) - (self.seq - seq)
            start = max(0, start)
            return self.seq, bytes(self.buf[start:])

    def write(self, data):
        self.chan.sendall(data.encode("utf-8") if isinstance(data, str) else data)

    def resize(self, cols, rows):
        try:
            self.chan.resize_pty(width=int(cols), height=int(rows))
        except Exception:
            pass

    def close(self):
        try:
            self.chan.close()
        except Exception:
            pass
        self.alive = False


class SSHManager:
    def __init__(self):
        self.hosts = _load(_HOSTS, [])
        self.known = _load(_KNOWN, {})
        self.clients = {}
        self.terms = {}
        self.listeners = []

    def changed(self):
        for cb in list(self.listeners):
            try:
                cb("ssh")
            except Exception:
                pass

    # ----------------------------------------------------------- hosts
    def host(self, hid):
        return next((h for h in self.hosts if h["id"] == hid), None)

    def find(self, name):
        n = (name or "").strip().lower()
        for test in (
            lambda h: h["id"] == n or h["label"].lower() == n,
            lambda h: h["host"].lower() == n or ("%s@%s" % (h["username"], h["host"])).lower() == n,
            lambda h: n in h["label"].lower(),
        ):
            h = next((h for h in self.hosts if test(h)), None)
            if h:
                return h
        raise ValueError('Host "%s" ga ketemu. Host yang ada: %s' % (name, ", ".join(h["label"] for h in self.hosts) or "(kosong)"))

    def save_host(self, h, password=None, key=None, passphrase=None):
        with _lock:
            h.setdefault("id", new_id())
            h.setdefault("port", 22)
            h.setdefault("auth", "password")
            self.hosts = [x for x in self.hosts if x["id"] != h["id"]] + [h]
            _save(_HOSTS, self.hosts)
        if password is not None:
            cfg.set_secret("pw_" + h["id"], password)
        if key is not None:
            cfg.set_secret("key_" + h["id"], key)
        if passphrase is not None:
            cfg.set_secret("pp_" + h["id"], passphrase)
        self.disconnect(h["id"])
        self.changed()
        return h

    def delete_host(self, hid):
        self.disconnect(hid)
        with _lock:
            self.hosts = [x for x in self.hosts if x["id"] != hid]
            _save(_HOSTS, self.hosts)
        for k in ("pw_", "key_", "pp_"):
            cfg.set_secret(k + hid, None)
        self.changed()

    def trust(self, host, keytype, fp):
        self.known["%s:%s" % (host["host"], host.get("port", 22))] = "%s %s" % (keytype, fp)
        _save(_KNOWN, self.known)

    # ------------------------------------------------------ connection
    def client(self, h, password=None):
        with _lock:
            c = self.clients.get(h["id"])
            if c is not None:
                t = c.get_transport()
                if t is not None and t.is_active():
                    return c
            c = self._connect(h, password)
            self.clients[h["id"]] = c
            h["lastUsed"] = int(time.time() * 1000)
            _save(_HOSTS, self.hosts)
        self.changed()
        return c

    def _connect(self, h, password=None):
        kid = "%s:%s" % (h["host"], h.get("port", 22))
        mgr = self

        class Policy(paramiko.MissingHostKeyPolicy):
            def missing_host_key(self, client, hostname, key):
                fp = fingerprint(key)
                expected = mgr.known.get(kid)
                if expected == "%s %s" % (key.get_name(), fp):
                    return
                raise HostKeyUnknown(h, key.get_name(), fp, expected)

        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(Policy())
        kw = dict(hostname=h["host"], port=int(h.get("port", 22)), username=h.get("username") or "root",
                  timeout=12, banner_timeout=15, auth_timeout=30, allow_agent=False, look_for_keys=False)
        if h.get("auth") == "key":
            pem = cfg.secret("key_" + h["id"])
            if not pem:
                raise ValueError("Private key host ini belum diisi")
            kw["pkey"] = load_pkey(pem, cfg.secret("pp_" + h["id"]))
        else:
            pw = password or cfg.secret("pw_" + h["id"])
            if not pw:
                raise ValueError("Password belum disimpan buat host ini")
            kw["password"] = pw
        try:
            c.connect(**kw)
        except HostKeyUnknown:
            raise
        except paramiko.AuthenticationException:
            raise ValueError("Login gagal — user/password/key salah")
        except (socket.timeout, TimeoutError):
            raise ValueError("Timeout — server ga kejangkau")
        except ConnectionRefusedError:
            raise ValueError("Port ditolak (SSH-nya nyala belum?)")
        except socket.gaierror:
            raise ValueError("Host ga ketemu (cek alamatnya)")
        c.get_transport().set_keepalive(15)
        return c

    def connected(self, hid):
        c = self.clients.get(hid)
        t = c.get_transport() if c else None
        return bool(t and t.is_active())

    def disconnect(self, hid):
        c = self.clients.pop(hid, None)
        if c:
            try:
                c.close()
            except Exception:
                pass
        for t in [t for t in self.terms.values() if t.host["id"] == hid]:
            t.close()
        self.changed()

    # ------------------------------------------------------------ exec
    def run(self, h, cmd, timeout=60):
        c = self.client(h)
        chan = c.get_transport().open_session()
        chan.exec_command(cmd)
        out, err = bytearray(), bytearray()
        deadline = time.time() + timeout
        timed_out = False
        while True:
            if chan.recv_ready():
                d = chan.recv(65536)
                if len(out) < 200000:
                    out.extend(d)
            if chan.recv_stderr_ready():
                d = chan.recv_stderr(65536)
                if len(err) < 50000:
                    err.extend(d)
            if chan.exit_status_ready() and not chan.recv_ready() and not chan.recv_stderr_ready():
                break
            if time.time() > deadline:
                timed_out = True
                break
            time.sleep(0.02)
        code = None if timed_out else chan.recv_exit_status()
        chan.close()
        parts = ["exit: %s" % ("TIMEOUT %ds (proses dihentiin)" % timeout if timed_out else code)]
        if out:
            parts.append("stdout:\n" + out.decode("utf-8", "replace"))
        if err:
            parts.append("stderr:\n" + err.decode("utf-8", "replace"))
        return "\n".join(parts)

    def sftp(self, h):
        return self.client(h).open_sftp()

    # -------------------------------------------------------- terminal
    def open_terminal(self, h, cols=100, rows=30):
        c = self.client(h)
        chan = c.get_transport().open_session()
        chan.get_pty(term="xterm-256color", width=int(cols), height=int(rows))
        chan.invoke_shell()
        t = Terminal(self, h, chan, c)
        self.terms[t.id] = t
        if h.get("startup"):
            threading.Timer(0.4, lambda: t.write(h["startup"].strip() + "\r")).start()
        self.changed()
        return t

    def close_terminal(self, tid):
        t = self.terms.pop(tid, None)
        if t:
            t.close()
        self.changed()


ssh = SSHManager()
