"""Remote access from the phone: Cloudflare quick tunnel + Telegram notifications."""
import json
import os
import re
import subprocess
import threading
import urllib.parse
import urllib.request

from .config import cfg


def telegram(text):
    token = cfg.secret("telegramToken")
    chat = cfg.get("telegramChat")
    if not token or not chat:
        return False
    data = urllib.parse.urlencode({"chat_id": chat, "text": text, "disable_web_page_preview": "true"}).encode()
    try:
        urllib.request.urlopen("https://api.telegram.org/bot%s/sendMessage" % token, data=data, timeout=15).read()
        return True
    except Exception:
        return False


class Tunnel:
    def __init__(self):
        self.proc = None
        self.url = None
        self.error = None
        self.listeners = []

    def _changed(self):
        for cb in list(self.listeners):
            try:
                cb()
            except Exception:
                pass

    @property
    def running(self):
        return self.proc is not None and self.proc.poll() is None

    def start(self, port):
        if self.running:
            return
        exe = (cfg.get("cloudflared") or "").strip().strip('"') or "cloudflared"
        self.url, self.error = None, None
        try:
            flags = 0x08000000 if os.name == "nt" else 0
            self.proc = subprocess.Popen([exe, "tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:%d" % port],
                                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, creationflags=flags)
        except Exception as e:
            self.error = "Ga bisa jalanin cloudflared: %s" % e
            self._changed()
            return

        def read():
            for raw in iter(self.proc.stdout.readline, b""):
                line = raw.decode("utf-8", "replace")
                m = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", line)
                if m and not self.url:
                    self.url = m.group(0)
                    self._changed()
                    telegram("🟢 satsh desktop online\n%s" % self.url)
            self.proc = None
            self.url = None
            self._changed()

        threading.Thread(target=read, daemon=True).start()
        self._changed()

    def stop(self):
        if self.proc:
            try:
                self.proc.terminate()
            except Exception:
                pass
        self.proc, self.url = None, None
        self._changed()

    def status(self):
        return {"running": self.running, "url": self.url, "error": self.error}


tunnel = Tunnel()
