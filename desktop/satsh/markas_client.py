"""Markas = shared workspace (targets, achievements, chat) for Adam and his agents.

Lives on one of his servers as the `markas` CLI (SQLite). satsh desktop talks to it over SSH,
same as satsh Android — both read/write the same database.
"""
import json
import os
import shlex
import time

from .config import cfg
from .ssh import ssh

CLI = '"$HOME/.local/bin/markas"'
FILES = ("markas.py", "hermes-SKILL.md", "install.sh")
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "markas")

# tests: fn(cmd, timeout) -> (code, stdout, stderr)
exec_override = None

RAPAT_PROMPT = """[Rapat Markas]
Lu ketua rapat. Langkah:
1. markas brief → lihat target aktif & PIC-nya.
2. Buat tiap target aktif, minta update ke PIC-nya: hermes → tanya_agent (pertanyaan singkat: target #ID, progress %, yang udah, kendala); agy / muse → tanya_agent (dari laptop ini mereka cuma bisa dititipin pesan di Markas, catat "nunggu jawaban"); satsh / web-designer → jawab sendiri dari riwayat & memori; adam → jangan ditanya, catat aja "nunggu update Adam".
3. Catat tiap jawaban ke markas: log (target=ID) dan target_update kalau progress-nya jelas berubah.
4. markas say rangkuman rapat (maks 8 baris) to=adam.
5. Jawaban akhir: rangkuman yang sama — target mana yang jalan, yang mandek, dan 1-3 hal yang butuh keputusan Adam."""


def q(s):
    return shlex.quote(str(s))


def host_id():
    return cfg.get("markasHost", "") or ""


def host():
    return ssh.host(host_id()) if host_id() else None


def configured():
    return exec_override is not None or host() is not None


def execute(cmd, timeout=60):
    if exec_override is not None:
        return exec_override(cmd, timeout)
    h = host()
    if h is None:
        raise ValueError("Markas belum dipasang. Buka menu Markas → pilih server → Pasang.")
    chan = ssh.client(h).get_transport().open_session()
    chan.exec_command(cmd)
    out, err = bytearray(), bytearray()
    deadline = time.time() + timeout
    try:
        while True:
            if chan.recv_ready():
                d = chan.recv(65536)
                if len(out) < 400000:
                    out.extend(d)
            if chan.recv_stderr_ready():
                d = chan.recv_stderr(65536)
                if len(err) < 50000:
                    err.extend(d)
            if chan.exit_status_ready() and not chan.recv_ready() and not chan.recv_stderr_ready():
                break
            if time.time() > deadline:
                raise ValueError("Kelamaan (>%ds) di %s" % (timeout, h["label"]))
            time.sleep(0.02)
        code = chan.recv_exit_status()
    finally:
        chan.close()
    return code, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")


def run(args, who="adam", as_json=False, timeout=60):
    cmd = " ".join([CLI] + [q(a) for a in args] + ["--as", q(who)] + (["--json"] if as_json else []))
    code, out, err = execute(cmd, timeout)
    if code == 127 or "markas: not found" in err or "No such file" in err:
        raise ValueError("Markas belum kepasang di server. Buka menu Markas → Pasang.")
    if code != 0:
        raise ValueError(err.strip().replace("markas: ", "", 1) or "markas gagal (exit %s)" % code)
    return out.strip()


def status():
    return json.loads(run(["status"], as_json=True))


def install(hid):
    h = ssh.host(hid)
    if h is None:
        raise ValueError("Server ga ketemu")
    sf = ssh.sftp(h)
    try:
        home = sf.normalize(".")
        d = home.rstrip("/") + "/.markas"
        try:
            sf.mkdir(d)
        except IOError:
            pass
        for n in FILES:
            with open(os.path.join(HERE, n), "rb") as f:
                data = f.read()
            with sf.open(d + "/" + n, "wb") as w:
                w.write(data)
    finally:
        sf.close()
    cfg.set("markasHost", hid)
    code, out, err = execute('sh "$HOME/.markas/install.sh"', 60)
    if code != 0 or "MARKAS_OK" not in out:
        raise ValueError("Pasang gagal: " + (err or out))
    return out


def ask_hermes(prompt, timeout=300):
    full = "[Dari satsh lewat Markas — jawab singkat & jujur. Kalau ini soal progress, catat juga pakai skill markas.]\n" + prompt
    code, out, err = execute("bash -lc %s </dev/null" % q("hermes -z " + q(full)), timeout)
    if code == 127 or "command not found" in err:
        raise ValueError("Hermes ga ketemu di server Markas (perintah `hermes`).")
    if code != 0 and not out.strip():
        raise ValueError("Hermes error (exit %s): %s" % (code, err.strip()))
    return out.strip() or "(Hermes ga jawab apa-apa)"
