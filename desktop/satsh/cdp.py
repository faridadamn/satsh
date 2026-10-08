"""Tiny Chrome DevTools Protocol client — stdlib only (works offline, Python 3.8+, Win7).

Just enough WebSocket (RFC 6455, client side) to talk to a local Chrome/Edge started with
--remote-debugging-port. One reader thread routes replies by id and keeps recent events.
"""
import base64
import json
import os
import socket
import struct
import threading
import time
import urllib.parse


class CdpError(Exception):
    pass


class WebSocket:
    def __init__(self, url, timeout=15):
        u = urllib.parse.urlparse(url)
        if u.hostname not in ("127.0.0.1", "localhost", "::1"):
            raise CdpError("DevTools cuma boleh lokal")
        self.sock = socket.create_connection((u.hostname, u.port or 80), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        path = (u.path or "/") + (("?" + u.query) if u.query else "")
        req = ("GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n") % (path, u.hostname, u.port or 80, key)
        self.sock.sendall(req.encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise CdpError("DevTools nutup koneksi pas handshake")
            head += chunk
        status = head.split(b"\r\n", 1)[0]
        if b" 101 " not in status + b" ":
            raise CdpError("Handshake DevTools gagal: %s" % status.decode("latin-1"))
        self._buf = head.split(b"\r\n\r\n", 1)[1]
        self.sock.settimeout(None)
        self._wlock = threading.Lock()

    def _read(self, n):
        while len(self._buf) < n:
            chunk = self.sock.recv(max(65536, n - len(self._buf)))
            if not chunk:
                raise CdpError("Koneksi DevTools putus")
            self._buf += chunk
        out, self._buf = self._buf[:n], self._buf[n:]
        return out

    def _send_frame(self, opcode, payload):
        head = bytearray([0x80 | opcode])
        n = len(payload)
        if n < 126:
            head.append(0x80 | n)
        elif n < 65536:
            head.append(0x80 | 126)
            head += struct.pack(">H", n)
        else:
            head.append(0x80 | 127)
            head += struct.pack(">Q", n)
        mask = os.urandom(4)
        head += mask
        body = bytes(b ^ mask[i % 4] for i, b in enumerate(payload)) if n < 4096 else _mask_fast(payload, mask)
        with self._wlock:
            self.sock.sendall(bytes(head) + body)

    def send(self, text):
        self._send_frame(0x1, text.encode("utf-8"))

    def recv(self):
        """Next complete text message (handles fragments, ping, close)."""
        parts, first_op = [], None
        while True:
            b0, b1 = self._read(2)
            fin, op = b0 & 0x80, b0 & 0x0F
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8))[0]
            mask = self._read(4) if b1 & 0x80 else None
            data = self._read(n)
            if mask:
                data = _mask_fast(data, mask)
            if op == 0x8:
                raise CdpError("DevTools nutup koneksi")
            if op == 0x9:
                self._send_frame(0xA, data)
                continue
            if op == 0xA:
                continue
            if op in (0x1, 0x2):
                first_op, parts = op, [data]
            elif op == 0x0:
                parts.append(data)
            if fin and first_op is not None:
                return b"".join(parts).decode("utf-8", "replace")

    def close(self):
        try:
            self._send_frame(0x8, b"")
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass


def _mask_fast(data, mask):
    # XOR via big ints: fast enough for multi-MB screenshots without numpy
    n = len(data)
    if not n:
        return b""
    m = (mask * (n // 4 + 1))[:n]
    return (int.from_bytes(data, "big") ^ int.from_bytes(m, "big")).to_bytes(n, "big")


class Cdp:
    """One DevTools target (a tab). call() is blocking and thread-safe."""

    def __init__(self, ws_url):
        self.ws = WebSocket(ws_url)
        self._id = 0
        self._lock = threading.Lock()
        self._cond = threading.Condition()
        self._replies = {}
        self.events = []  # (method, params), last 200
        self.alive = True
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        try:
            while True:
                msg = json.loads(self.ws.recv())
                with self._cond:
                    if "id" in msg:
                        self._replies[msg["id"]] = msg
                    else:
                        self.events.append((msg.get("method"), msg.get("params") or {}))
                        del self.events[:-200]
                    self._cond.notify_all()
        except Exception:
            pass
        with self._cond:
            self.alive = False
            self._cond.notify_all()

    def call(self, method, params=None, timeout=30):
        with self._lock:
            self._id += 1
            mid = self._id
        self.ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
        end = time.time() + timeout
        with self._cond:
            while mid not in self._replies:
                if not self.alive:
                    raise CdpError("Browser ketutup")
                left = end - time.time()
                if left <= 0:
                    raise CdpError("Browser ga jawab (%s, >%ds)" % (method, timeout))
                self._cond.wait(left)
            r = self._replies.pop(mid)
        if "error" in r:
            raise CdpError("%s: %s" % (method, r["error"].get("message")))
        return r.get("result") or {}

    def wait_event(self, method, timeout=15, since=0):
        """Waits for event [method] arriving after index [since] of self.events."""
        end = time.time() + timeout
        with self._cond:
            while True:
                for m, p in self.events[since:]:
                    if m == method:
                        return p
                left = end - time.time()
                if left <= 0 or not self.alive:
                    return None
                self._cond.wait(left)

    def js(self, expr, timeout=20):
        r = self.call("Runtime.evaluate", {"expression": expr, "returnByValue": True, "awaitPromise": True}, timeout)
        if r.get("exceptionDetails"):
            d = r["exceptionDetails"]
            raise CdpError("JS error: %s" % ((d.get("exception") or {}).get("description") or d.get("text")))
        return (r.get("result") or {}).get("value")

    def close(self):
        self.alive = False
        self.ws.close()
