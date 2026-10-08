"""The agent's brain on disk: SOUL.md, MEMORY.md, USER.md, skills/, sessions/, cron.json.
Same formats as satsh on Android."""
import datetime as dt
import json
import os
import re
import shutil
import threading
import time

from .config import HOME, new_id

MEMORY_LIMIT = 2200
USER_LIMIT = 1375
SEP = "\n§\n"

DEFAULT_SOUL = """# SOUL — siapa kamu

Kamu **satsh agent**: partner ngoprek yang hidup di laptop Windows user. Kamu bisa megang file & program di laptop, jalanin perintah, server SSH user, Supabase, dan internet.

## Gaya
- Bahasa Indonesia santai (gw/lu), to the point, ga bertele-tele. Boleh bercanda dikit.
- Jawab singkat dulu; detail kalau diminta.
- Kalau bisa dikerjain sendiri pakai tools, kerjain. Jangan nyuruh user ngetik perintah.

## Prinsip
- Teliti sebelum aksi destruktif. Cek dulu, baru eksekusi.
- Jujur kalau gagal atau ga yakin.
- Ingat hal penting tentang user & lingkungannya pakai memori, dan simpan cara kerja yang kepake berulang jadi skill.
"""

# Working rules every newly summoned agent gets (light adoption of the "7 bagian CLAUDE.md" checklist).
WORK_PRINCIPLES = """## Cara kerja (berlaku buat semua tugas)
- **Sederhana dulu, tapi tuntas.** Ukurannya: bakal di-approve senior engineer ga? Kalau rumit, sederhanain. Kalau setengah jadi, belum selesai.
- **Rencana dulu** buat tugas 3+ langkah: tulis pakai todo_write, update statusnya sambil jalan. Rencana yang NGUBAH sistem (hapus, deploy, ubah config, restart) → tunjukin dulu & tunggu "oke" user.
- **Bukti, bukan klaim.** Jangan bilang "beres" sebelum ada bukti: output perintah, log, hasil tes, atau diff. Taruh buktinya (singkat) di laporan.
- **Bug/error: telusuri sendiri dulu.** Baca log, cari akar masalah, coba perbaiki. Nanya user cuma kalau bener-bener buntu atau butuh keputusan.
- **Belajar dari koreksi.** Tiap dikoreksi user, catat pelajarannya ke memori (target=memory, awali "Pelajaran:") biar ga ngulang.
- **Konteks tetap bersih.** Riset/eksplorasi panjang yang bisa dipisah → delegate_task."""


def new_agent_soul(name, desc="", body=""):
    b = (body or "").strip() or "# SOUL — %s\n\n%s\n" % (name, (desc or "").strip() or "Kamu agent %s." % name)
    b = b.strip()
    return b + "\n" if "## Cara kerja" in b else b + "\n\n" + WORK_PRINCIPLES + "\n"


DEFAULT_SKILLS = {
    "cek-server": """---
name: cek-server
description: Health check cepat server SSH — disk, RAM, CPU load, uptime, service gagal, port terbuka. Pakai kalau user minta cek/monitor kondisi server.
---
# Cek kesehatan server

1. Kalau user ga nyebut server, pakai `ssh_hosts` lalu cek semua yang ada (atau tanya kalau banyak).
2. Jalanin satu perintah gabungan biar hemat:
   ```
   echo "== uptime"; uptime; echo "== disk"; df -h -x tmpfs -x devtmpfs | head -20; echo "== ram"; free -h; echo "== top cpu"; ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -6; echo "== failed"; systemctl --failed --no-legend 2>/dev/null | head; echo "== ports"; ss -tulpn 2>/dev/null | head -20
   ```
3. Rangkum dalam tabel kecil per server: Disk (paling penuh), RAM kepake, load, service gagal.
4. Tandai ⚠️ kalau disk > 85%, RAM available < 10%, load > jumlah core, atau ada service failed. Kasih saran 1 baris buat tiap masalah.
""",
    "deploy-git": """---
name: deploy-git
description: Deploy app dari git di server — pull, install dependency, build, restart (pm2/systemd/docker). Pakai kalau user bilang deploy/update app di server.
---
# Deploy dari git

1. Pastiin server & folder project (cek memori dulu — mungkin udah pernah dicatat).
2. Cek status: `cd <dir> && git status --short && git log -1 --oneline`. Ada perubahan lokal belum di-commit → STOP, kasih tau user.
3. `git pull --ff-only`.
4. Deteksi tipe project: `package.json` → `npm ci` + `npm run build` (kalau ada); `requirements.txt` → `pip install -r requirements.txt`; `docker-compose.yml` → `docker compose up -d --build`.
5. Restart: cek `pm2 ls` / `systemctl list-units --type=service | grep <nama>`.
6. Verifikasi: log 20 baris terakhir + curl health endpoint kalau ada.
7. Simpan ke memori: folder project + cara restart.
""",
    "rapihin-folder": """---
name: rapihin-folder
description: Beresin folder berantakan di laptop (Downloads/Desktop) — kelompokin per jenis file dan laporin file gede/duplikat. Pakai kalau user minta rapihin/bersihin folder.
---
# Rapihin folder

1. `fs_list` folder target (default Downloads user).
2. Rencanain subfolder: Dokumen, Gambar, Video, Audio, Installer (exe/msi), Arsip (zip/rar/7z), Lainnya.
3. Tampilin ringkasan rencana & MINTA KONFIRMASI user dulu.
4. Pindahin pakai `fs_move` satu-satu, jangan timpa file yang udah ada.
5. Laporin file > 200MB dan nama mirip duplikat (mis. `x (1).pdf`). Jangan hapus tanpa izin.
""",
    "cek-laptop-bekas": r"""---
name: cek-laptop-bekas
description: Cek kondisi laptop Windows (bekas yang mau dibeli atau laptop sendiri) — kesehatan baterai asli, kesehatan SSD/HDD, riwayat crash/mati mendadak, spek asli, aktivasi, plus checklist fisik & harga wajar. Pakai kalau user mau beli laptop bekas atau nanya kondisi laptopnya.
---
# Cek laptop bekas (Windows 7/10/11)

Semua perintah di bawah read-only. Jalanin pakai shell_run (cmd kecuali ditulis PowerShell). Kalau satsh lagi ga di laptop itu, kasih perintahnya ke user.

1. **Spek & identitas**: `wmic cpu get name,numberofcores,maxclockspeed` · `wmic memorychip get capacity,speed,manufacturer` · `wmic computersystem get manufacturer,model,totalphysicalmemory` · `wmic bios get serialnumber,smbiosbiosversion` · `wmic path win32_videocontroller get name,driverversion`. Cocokin sama klaim penjual.
2. **Baterai**:
   - Win8/10/11: `powercfg /batteryreport /output "%TEMP%\battery.html"` → `fs_read` file itu: bandingin DESIGN CAPACITY vs FULL CHARGE CAPACITY (+ CYCLE COUNT). Kesehatan = full ÷ design.
   - Win7 (atau kalau di atas gagal): `wmic /namespace:\\root\wmi path BatteryStaticData get DesignedCapacity` dan `wmic /namespace:\\root\wmi path BatteryFullChargedCapacity get FullChargedCapacity` (butuh jalanin satsh sebagai admin kalau ditolak).
   - < 80% = mulai drop, < 60% = siap ganti baterai.
3. **SSD/HDD**: `wmic diskdrive get model,mediatype,size,status` (status selain "OK", mis. "Pred Fail" = 🔴). Win8+: PowerShell `Get-PhysicalDisk | Select FriendlyName,MediaType,HealthStatus,Size`. Buat detail SMART (jam nyala, bad sector, sisa umur SSD) saranin CrystalDiskInfo.
4. **Riwayat crash / mati mendadak** (PowerShell): `Get-WinEvent -FilterHashtable @{LogName='System';Id=41,6008,1001} -MaxEvents 30 | Select TimeCreated,Id,Message | Format-List`. Id 41/6008 = mati ga normal, 1001 = BSOD. Banyak dalam 30 hari = 🔴 (cek suhu / RAM / adaptor).
5. **Windows asli?** `cscript //nologo %windir%\system32\slmgr.vbs /xpr`.
6. **Suhu**: pas idle & pas buka YouTube, saranin HWMonitor. CPU > 90°C pas ringan = pasta/kipas kotor.
7. **Checklist fisik buat user**: keyboard semua tombol (buka en.key-test.ru), touchpad & klik, layar (dead pixel: buka gambar warna penuh merah/hijau/biru/putih/hitam), engsel goyang, webcam, speaker, mic, semua port USB/HDMI/audio, charger ori & ga panas berlebih, Wi-Fi/Bluetooth, bekas bongkar (baut), BIOS ga dikunci password.
8. **Harga**: `browser_open` cari "harga <model> bekas" → rentang wajar, potongan buat tiap temuan (baterai drop ≈ harga baterai baru, SSD bermasalah ≈ SSD baru).
9. **Laporan**: vonis (layak / cek lagi / waspada), temuan + bukti output, harga wajar, pertanyaan buat penjual.
""",
}

_lock = threading.RLock()


def now_ms():
    return int(time.time() * 1000)


def title_from(text):
    t = re.sub(r"\s+", " ", text or "").strip()
    if not t:
        return "Chat baru"
    return t if len(t) <= 42 else t[:40] + "…"


def parse_skill(raw, fallback=None):
    m = re.match(r"^---\s*\n([\s\S]*?)\n---\s*\n?([\s\S]*)$", raw.lstrip())
    name, desc, body = fallback or "", "", raw
    if m:
        for line in m.group(1).split("\n"):
            if ":" not in line:
                continue
            k, v = line.split(":", 1)
            k, v = k.strip(), v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            if k == "name":
                name = v
            elif k == "description":
                desc = v
        body = m.group(2)
    if not name:
        return None
    return {"name": name, "description": desc, "body": body.strip(), "raw": raw}


class CronJob(dict):
    """dict-backed so it serializes trivially."""

    def schedule_label(self):
        if self.get("dailyAt"):
            return "tiap hari " + self["dailyAt"]
        m = self.get("everyMinutes") or 60
        if m % 1440 == 0:
            return "tiap %d hari" % (m // 1440)
        if m % 60 == 0:
            return "tiap %d jam" % (m // 60)
        return "tiap %d menit" % m

    def next_run(self, now=None):
        now = now or dt.datetime.now()
        last = dt.datetime.fromtimestamp(self["lastRun"] / 1000) if self.get("lastRun") else None
        created = dt.datetime.fromtimestamp(self.get("created", now_ms()) / 1000)
        if self.get("dailyAt"):
            h, mi = [int(x) for x in self["dailyAt"].split(":")]
            slot = now.replace(hour=h, minute=mi, second=0, microsecond=0)
            if slot > now:
                return slot
            if (last and last >= slot) or created > slot:
                return slot + dt.timedelta(days=1)
            return slot
        every = dt.timedelta(minutes=self.get("everyMinutes") or 60)
        return (last or created) + every

    def is_due(self, now=None):
        now = now or dt.datetime.now()
        return bool(self.get("enabled", True)) and self.next_run(now) <= now


PROFILE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")
SKILL_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,48}$")
SESSION_ID_RE = re.compile(r"^[0-9A-Za-z_-]{6,64}$")


def _rw(path, text=None):
    """Read (text=None) or atomically write a UTF-8 file."""
    if text is None:
        if not os.path.exists(path):
            return ""
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def default_profile():
    return {"id": "default", "name": "satsh", "emoji": "⚡", "desc": "", "provider": "", "toolsOff": []}


class ProfileBrain:
    """SOUL.md, MEMORY.md and skills/ of one agent profile. USER.md is shared (lives on Brain)."""

    def __init__(self, brain, pid, root):
        self.brain, self.id, self.root = brain, pid, root
        self.soul, self.memory, self.skills = DEFAULT_SOUL, "", []

    def _p(self, *parts):
        return os.path.join(self.root, *parts)

    @property
    def meta(self):
        return self.brain.profile(self.id) or dict(default_profile(), id=self.id, name=self.id)

    OLD_DEFAULTS = ("cek-server", "deploy-git", "rapihin-folder")  # shipped before .defaults-seen existed

    def load(self, seed=True):
        os.makedirs(self._p("skills"), exist_ok=True)
        fresh = not os.path.exists(self._p("SOUL.md"))
        if fresh and seed:
            _rw(self._p("SOUL.md"), DEFAULT_SOUL)
        if seed and self.id == "default":
            self._seed_new_defaults(fresh)
        self.soul = _rw(self._p("SOUL.md")) or DEFAULT_SOUL
        self.memory = _rw(self._p("MEMORY.md"))
        self._load_skills()

    def _seed_new_defaults(self, fresh):
        """Writes built-in skills this install hasn't been offered yet (a skill the user deleted stays deleted)."""
        p = self._p(".defaults-seen")
        try:
            seen = json.loads(_rw(p) or "x")
        except Exception:
            seen = [] if fresh else list(self.OLD_DEFAULTS)
        changed = False
        for name, raw in DEFAULT_SKILLS.items():
            if name in seen:
                continue
            if not os.path.exists(self._p("skills", name, "SKILL.md")):
                _rw(self._p("skills", name, "SKILL.md"), raw)
            seen.append(name)
            changed = True
        if changed or not os.path.exists(p):
            _rw(p, json.dumps(seen))

    # ------------------------------------------------------------ soul
    def save_soul(self, text):
        self.soul = text if text.strip() else DEFAULT_SOUL
        _rw(self._p("SOUL.md"), self.soul)
        self.brain.changed("soul")

    # ---------------------------------------------------------- memory
    def entries(self, target):
        src = self.brain.user if target == "user" else self.memory
        return [e.strip() for e in src.split(SEP) if e.strip()]

    def limit(self, target):
        return USER_LIMIT if target == "user" else MEMORY_LIMIT

    def set_entries(self, target, items):
        text = SEP.join(items)
        with _lock:
            if target == "user":
                self.brain.user = text
                _rw(self.brain._p("USER.md"), text)
            else:
                self.memory = text
                _rw(self._p("MEMORY.md"), text)
        self.brain.changed("memory")

    def memory_op(self, action, target, content=None, old_text=None):
        if target not in ("user", "memory"):
            raise ValueError('target harus "memory" atau "user"')
        items = self.entries(target)
        lim = self.limit(target)

        def find():
            q = (old_text or "").strip()
            if not q:
                raise ValueError("old_text wajib buat " + action)
            hits = [i for i, e in enumerate(items) if q in e]
            if not hits:
                raise ValueError('Ga ada entri yang mengandung "%s"' % q)
            if len(hits) > 1:
                raise ValueError("Ada %d entri yang cocok, pakai old_text yang lebih spesifik" % len(hits))
            return hits[0]

        c = (content or "").strip()
        if action == "add":
            if not c:
                raise ValueError("content kosong")
            if c in items:
                return "Udah ada, ga ditambah."
            items.append(c)
        elif action == "replace":
            if not c:
                raise ValueError("content kosong")
            items[find()] = c
        elif action == "remove":
            items.pop(find())
        else:
            raise ValueError("action harus add/replace/remove")
        size = len(SEP.join(items))
        if size > lim:
            raise ValueError(
                "%s bakal %d/%d karakter — kepenuhan. Gabungin/ringkas atau hapus entri lama dulu (replace/remove), lalu coba lagi."
                % (target.upper(), size, lim)
            )
        self.set_entries(target, items)
        return "OK. %s sekarang %d/%d karakter, %d entri." % (target.upper(), size, lim, len(items))

    def memory_block(self):
        m, u = self.memory.strip(), self.brain.user.strip()
        return (
            "\n## MEMORI KAMU (%d/%d karakter) — catatan lingkungan, fakta proyek, pelajaran\n%s\n\n"
            "## PROFIL USER (%d/%d karakter) — siapa user, preferensi, gaya kerja\n%s"
            % (len(m), MEMORY_LIMIT, m or "(kosong)", len(u), USER_LIMIT, u or "(kosong)")
        )

    # ---------------------------------------------------------- skills
    def _load_skills(self):
        out = []
        base = self._p("skills")
        if os.path.isdir(base):
            for d in sorted(os.listdir(base)):
                f = os.path.join(base, d, "SKILL.md")
                if os.path.isfile(f):
                    s = parse_skill(_rw(f), d)
                    if s:
                        out.append(s)
        out.sort(key=lambda s: s["name"])
        self.skills = out

    def skill(self, name):
        name = (name or "").strip().lower()
        return next((s for s in self.skills if s["name"] == name), None)

    # ------------------------------------------------- built-in skills
    @property
    def builtins(self):
        """Skills that ship with satsh for this profile (name -> SKILL.md). Read-only for the agent."""
        return self.brain.builtin_skills.get(self.id, {})

    def is_builtin(self, name):
        return (name or "").strip().lower() in self.builtins

    def is_modified(self, s):
        return self.is_builtin(s["name"]) and s["raw"].strip() != self.builtins[s["name"]].strip()

    def missing_builtins(self):
        return [n for n in self.builtins if not self.skill(n)]

    @staticmethod
    def locked_msg(name):
        return ('Skill "%s" itu skill BAWAAN — cuma user yang boleh ubah/hapus (Otak → Skill). '
                'Kalau butuh versi lain, bikin skill baru dengan nama beda (mis. "%s-custom").' % (name, name))

    def reset_skill(self, name):
        raw = self.builtins.get(name)
        if raw is None:
            raise ValueError('Skill "%s" bukan skill bawaan' % name)
        _rw(self._p("skills", name, "SKILL.md"), raw.strip())
        self._load_skills()
        self.brain.changed("skills")

    def reset_all_builtins(self):
        n = 0
        for name in self.builtins:
            s = self.skill(name)
            if s and not self.is_modified(s):
                continue
            self.reset_skill(name)
            n += 1
        return n

    def save_skill(self, raw, expect=None, by_agent=False):
        s = parse_skill(raw)
        if not s:
            raise ValueError("SKILL.md wajib punya frontmatter:\n---\nname: nama-skill\ndescription: kapan dipakai\n---")
        if not SKILL_NAME_RE.match(s["name"]):
            raise ValueError('Nama skill harus huruf kecil/angka/strip, mis. "cek-server"')
        if not s["description"]:
            raise ValueError("description wajib diisi")
        if expect and expect != s["name"]:
            raise ValueError('name di frontmatter ("%s") beda sama "%s"' % (s["name"], expect))
        if by_agent and self.is_builtin(s["name"]):
            raise ValueError(self.locked_msg(s["name"]))
        _rw(self._p("skills", s["name"], "SKILL.md"), raw.strip())
        self._load_skills()
        self.brain.changed("skills")
        return s["name"]

    def delete_skill(self, name, by_agent=False):
        if by_agent and self.is_builtin(name):
            raise ValueError(self.locked_msg(name))
        p = self._p("skills", name)
        if SKILL_NAME_RE.match(name or "") and os.path.isdir(p):
            shutil.rmtree(p)
        self._load_skills()
        self.brain.changed("skills")

    def skills_index(self):
        if not self.skills:
            return "(belum ada skill)"
        return "\n".join("- %s%s: %s" % (s["name"], " [bawaan, read-only]" if self.is_builtin(s["name"]) else "", s["description"]) for s in self.skills)


class Brain:
    """profiles.json + per-profile brains, shared USER.md, sessions/, cron.json.
    Same layout as satsh on Android; the default profile lives in the root."""

    def __init__(self, root=None):
        self.root = root or os.path.join(HOME, "agent")
        self.listeners = []
        self.user = ""
        self.profiles = []
        self.active_id = "default"
        self.presets_seen = []  # built-in presets already offered once (deleted ones stay deleted)
        self.builtin_skills = {"default": dict(DEFAULT_SKILLS)}  # profile id -> {skill name: SKILL.md}
        self._views = {}
        self.active = None
        self.sessions = []  # list of meta dicts
        self.jobs = []
        self.load()

    def changed(self, what="brain"):
        for cb in list(self.listeners):
            try:
                cb(what)
            except Exception:
                pass

    def _p(self, *parts):
        return os.path.join(self.root, *parts)

    def _read(self, name):
        return _rw(self._p(name))

    def _write(self, name, text):
        _rw(self._p(name), text)

    def load(self):
        os.makedirs(self._p("sessions"), exist_ok=True)
        self.user = self._read("USER.md")
        self._views = {}
        self._load_profiles()
        self.active = self.view(self.active_id)
        self._load_sessions()
        self._load_jobs()

    # -------------------------------------------- active-profile shortcuts
    soul = property(lambda self: self.active.soul)
    memory = property(lambda self: self.active.memory)
    skills = property(lambda self: self.active.skills)

    def save_soul(self, text):
        self.active.save_soul(text)

    def entries(self, target):
        return self.active.entries(target)

    def limit(self, target):
        return self.active.limit(target)

    def set_entries(self, target, items):
        self.active.set_entries(target, items)

    def memory_op(self, *a, **kw):
        return self.active.memory_op(*a, **kw)

    def memory_block(self):
        return self.active.memory_block()

    def skill(self, name):
        return self.active.skill(name)

    def save_skill(self, raw, expect=None):
        return self.active.save_skill(raw, expect)

    def delete_skill(self, name):
        self.active.delete_skill(name)

    def skills_index(self):
        return self.active.skills_index()

    # ------------------------------------------------------- profiles
    def dir_of(self, pid):
        return self.root if pid == "default" else self._p("profiles", pid)

    def profile(self, pid):
        pid = pid or "default"
        return next((p for p in self.profiles if p["id"] == pid), None)

    def _load_profiles(self):
        self.profiles, self.active_id = [], "default"
        raw = self._read("profiles.json")
        if raw:
            try:
                j = json.loads(raw)
                self.profiles = [dict(default_profile(), **p) for p in j.get("profiles", []) if PROFILE_ID_RE.match(p.get("id", ""))]
                self.active_id = j.get("active") or "default"
                self.presets_seen = [x for x in j.get("presetsSeen", []) if isinstance(x, str)]
            except Exception:
                pass
        if not self.profile("default"):
            self.profiles.insert(0, default_profile())
        if not self.profile(self.active_id):
            self.active_id = "default"

    def save_profiles(self):
        self._write("profiles.json", json.dumps({"active": self.active_id, "profiles": self.profiles, "presetsSeen": self.presets_seen},
                                                ensure_ascii=False, indent=1))
        self.changed("profiles")

    def view(self, pid):
        pid = pid if (pid and self.profile(pid)) else "default"
        v = self._views.get(pid)
        if v is None:
            v = ProfileBrain(self, pid, self.dir_of(pid))
            v.load()
            self._views[pid] = v
        return v

    def set_active(self, pid):
        if not self.profile(pid):
            raise ValueError("Profil ga ada")
        self.active_id = pid
        self.active = self.view(pid)
        self.save_profiles()

    @staticmethod
    def slug(name):
        s = re.sub(r"[^a-z0-9]+", "-", (name or "").lower()).strip("-")[:24]
        return s or "agent"

    def create_profile(self, name, emoji="🤖", desc="", copy_from=None):
        base = self.slug(name)
        pid = "default-2" if base == "default" else base
        k = 2
        while self.profile(pid):
            pid = "%s-%d" % (base, k)
            k += 1
        p = dict(default_profile(), id=pid, name=(name or "").strip() or pid, emoji=emoji, desc=desc)
        d = self.dir_of(pid)
        os.makedirs(os.path.join(d, "skills"), exist_ok=True)
        if copy_from:
            src = self.view(copy_from)
            _rw(os.path.join(d, "SOUL.md"), src.soul)
            for sk in src.skills:
                _rw(os.path.join(d, "skills", sk["name"], "SKILL.md"), sk["raw"])
        self.profiles.append(p)
        self.save_profiles()
        return p

    def update_profile(self, pid, **vals):
        p = self.profile(pid)
        if not p:
            raise ValueError("Profil ga ada")
        for k in ("name", "emoji", "desc", "provider", "toolsOff"):
            if k in vals and vals[k] is not None:
                p[k] = vals[k]
        self.save_profiles()
        return p

    def delete_profile(self, pid):
        if pid == "default" or not self.profile(pid):
            return
        self.profiles = [p for p in self.profiles if p["id"] != pid]
        self._views.pop(pid, None)
        d = self.dir_of(pid)
        if os.path.isdir(d):
            shutil.rmtree(d)
        for m in self.sessions:
            if m.get("profile") == pid:
                m["profile"] = None
        self._save_index()
        for j in self.jobs:
            if j.get("profile") == pid:
                j["profile"] = None
        self.save_jobs()
        if self.active_id == pid:
            self.active_id = "default"
            self.active = self.view("default")
        self.save_profiles()

    def install_preset(self, files):
        """files: {"profile.json": …, "SOUL.md": …, "skills/<name>/SKILL.md": …}. Memory of an existing profile is kept."""
        meta = json.loads(files["profile.json"])
        pid = meta.get("id", "")
        if not PROFILE_ID_RE.match(pid) or pid == "default":
            raise ValueError("id preset ga valid")
        self.register_preset_skills(pid, files)
        d = self.dir_of(pid)
        os.makedirs(os.path.join(d, "skills"), exist_ok=True)
        for rel, text in files.items():
            if rel == "SOUL.md" or re.match(r"^LICENSE[\w.-]*$", rel) or re.match(r"^skills/[a-z0-9][a-z0-9-]{1,48}/SKILL\.md$", rel):
                _rw(os.path.join(d, *rel.split("/")), text)
        cur = self.profile(pid)
        if cur is None:
            self.profiles.append(dict(default_profile(), **{k: meta[k] for k in ("id", "name", "emoji", "desc", "provider", "toolsOff") if k in meta}))
        else:
            cur.update(name=meta.get("name", cur["name"]), emoji=meta.get("emoji", cur["emoji"]), desc=meta.get("desc", cur["desc"]))
        if pid not in self.presets_seen:
            self.presets_seen.append(pid)
        self.reload_profile(pid)
        self.save_profiles()
        return self.profile(pid)

    def auto_install_presets(self, presets):
        """presets: {id: loader()}. Installs presets never offered before."""
        added = []
        for pid, load in presets.items():
            try:
                files = load()
                self.register_preset_skills(pid, files)  # installed earlier too: its skills stay read-only for the agent
                if pid in self.presets_seen:
                    continue
                self.install_preset(files)
                added.append(pid)
            except Exception:
                if pid not in self.presets_seen:
                    self.presets_seen.append(pid)
                self.save_profiles()
        return added

    def register_preset_skills(self, pid, files):
        out = {}
        for rel, text in files.items():
            m = re.match(r"^skills/([a-z0-9][a-z0-9-]{1,48})/SKILL\.md$", rel)
            if m:
                out[m.group(1)] = text
        self.builtin_skills[pid] = out

    def reload_profile(self, pid):
        self._views.pop(pid, None)
        if pid == self.active_id:
            self.active = self.view(pid)

    # -------------------------------------------------------- sessions
    def _load_sessions(self):
        p = self._p("sessions", "index.json")
        self.sessions = []
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    self.sessions = json.load(f)
            except Exception:
                self.sessions = []
        self.sessions.sort(key=lambda m: -m["updated"])

    def _save_index(self):
        self.sessions.sort(key=lambda m: -m["updated"])
        self._write(os.path.join("sessions", "index.json"), json.dumps(self.sessions, ensure_ascii=False))

    @staticmethod
    def new_session(title="Chat baru", profile=None):
        t = now_ms()
        return {
            "id": new_id(), "title": title, "created": t, "updated": t, "messages": [],
            "contextStart": 0, "summary": "", "todos": [], "userTurns": 0, "cronJobId": None, "unread": False,
            "profile": profile,
        }

    def open_session(self, sid):
        p = self._p("sessions", "%s.json" % sid)
        if not SESSION_ID_RE.match(sid or "") or not os.path.exists(p):
            return None
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)

    def save_session(self, s):
        if not s["messages"]:
            return
        with _lock:
            s["updated"] = now_ms()
            self._write(os.path.join("sessions", "%s.json" % s["id"]), json.dumps(s, ensure_ascii=False))
            meta = next((m for m in self.sessions if m["id"] == s["id"]), None)
            if meta is None:
                self.sessions.append({"id": s["id"], "title": s["title"], "updated": s["updated"],
                                      "unread": s.get("unread", False), "cron": bool(s.get("cronJobId")), "profile": s.get("profile")})
            else:
                meta.update(title=s["title"], updated=s["updated"], unread=s.get("unread", False), profile=s.get("profile"))
            self._save_index()
        self.changed("sessions")

    def save_index(self):
        self._save_index()
        self.changed("sessions")

    def delete_session(self, sid):
        if not SESSION_ID_RE.match(sid or ""):
            return
        p = self._p("sessions", "%s.json" % sid)
        if os.path.exists(p):
            os.remove(p)
        self.sessions = [m for m in self.sessions if m["id"] != sid]
        self._save_index()
        self.changed("sessions")

    def mark_read(self, sid):
        for m in self.sessions:
            if m["id"] == sid and m.get("unread"):
                m["unread"] = False
                self._save_index()
                self.changed("sessions")

    def search_sessions(self, query, exclude=None, limit=5):
        terms = [t for t in re.split(r"\s+", (query or "").lower()) if len(t) > 1]
        if not terms:
            return []
        hits = []
        for meta in list(self.sessions):
            if meta["id"] == exclude:
                continue
            s = self.open_session(meta["id"])
            if not s:
                continue
            score, snippets = 0, []
            for m in s["messages"]:
                if m["role"] in ("tool", "event") or not m.get("text"):
                    continue
                low = m["text"].lower()
                matched = [t for t in terms if t in low]
                if not matched:
                    continue
                score += len(matched) ** 2
                if len(snippets) < 3:
                    pos = low.index(matched[0])
                    a, b = max(0, pos - 120), min(len(m["text"]), pos + 200)
                    snippets.append("%s: %s%s%s" % ("User" if m["role"] == "user" else "Agent", "…" if a else "",
                                                    m["text"][a:b].replace("\n", " "), "…" if b < len(m["text"]) else ""))
            if terms[0] in s["title"].lower():
                score += 3
            if score:
                hits.append({"id": s["id"], "title": s["title"], "score": score, "snippets": snippets,
                             "date": dt.datetime.fromtimestamp(s["updated"] / 1000).strftime("%Y-%m-%d %H:%M")})
        hits.sort(key=lambda h: -h["score"])
        return hits[:limit]

    # ------------------------------------------------------------ cron
    def _load_jobs(self):
        p = self._p("cron.json")
        self.jobs = []
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    self.jobs = [CronJob(j) for j in json.load(f)]
            except Exception:
                self.jobs = []

    def save_jobs(self):
        self._write("cron.json", json.dumps(self.jobs, ensure_ascii=False, indent=1))
        self.changed("jobs")

    def job(self, prefix):
        prefix = (prefix or "").strip()
        return next((j for j in self.jobs if prefix and j["id"].startswith(prefix)), None)
