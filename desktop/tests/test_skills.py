"""Built-in skills locked for the agent, new presets + work principles, push skill to Hermes, redaction.
Desktop side of app/test/skills_lock_push_test.dart + redact_test.dart. Plain asserts, Python 3.8+.

    python tests/test_skills.py
"""
import json
import os
import subprocess
import sys
import tempfile

os.environ["SATSH_HOME"] = tempfile.mkdtemp(prefix="satshskill")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from satsh import presets, redact, skill_push  # noqa: E402
from satsh.agent import Agent, RunCtx  # noqa: E402
from satsh.brain import WORK_PRINCIPLES, Brain  # noqa: E402


def ok(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print("  ✓", msg)


def raises(fn, needle):
    try:
        fn()
    except Exception as e:  # noqa
        return needle in str(e)
    return False


def fresh():
    return Brain(tempfile.mkdtemp(prefix="brain"))


def tools(b):
    return {t["name"]: t for t in Agent(brain=b).brain_tools(RunCtx(auto=True))}


def lock():
    b = fresh()
    pb = b.active
    t = tools(b)
    before = pb.skill("cek-server")["raw"]
    sm = t["skill_manage"]["run"]
    ok(raises(lambda: sm({"action": "edit", "name": "cek-server", "content": "---\nname: cek-server\ndescription: x\n---\nhack"}), "BAWAAN"), "agent can't edit a built-in skill")
    ok(raises(lambda: sm({"action": "patch", "name": "cek-server", "old_text": "Health check", "new_text": "Hacked"}), "BAWAAN"), "…or patch it")
    ok(raises(lambda: sm({"action": "delete", "name": "cek-server"}), "BAWAAN"), "…or delete it")
    ok(pb.skill("cek-server")["raw"] == before, "built-in untouched")
    pb.delete_skill("cek-server")
    ok(raises(lambda: sm({"action": "create", "name": "cek-server", "content": "---\nname: cek-server\ndescription: x\n---\ny"}), "BAWAAN"),
       "…or recreate it after the user deleted it")
    ok("kesimpen" in sm({"action": "create", "name": "punyaku", "content": "---\nname: punyaku\ndescription: d\n---\n1"}), "own skills still free")
    ok("[bawaan, read-only]" in pb.skills_index(), "index marks built-ins")

    pb.save_skill("---\nname: deploy-git\ndescription: versi gw\n---\nlangkah gw")
    ok(pb.is_modified(pb.skill("deploy-git")), "user can edit a built-in")
    ok(pb.missing_builtins() == ["cek-server"], "deleted built-in listed")
    pb.reset_skill("deploy-git")
    ok(not pb.is_modified(pb.skill("deploy-git")), "reset one")
    pb.save_skill("---\nname: deploy-git\ndescription: lagi\n---\nx")
    ok(pb.reset_all_builtins() == 2 and not pb.missing_builtins(), "reset all (edited + deleted)")

    b2 = fresh()
    b2.auto_install_presets(presets.all_loaders())
    b2.builtin_skills = {"default": b2.builtin_skills["default"]}  # next start
    b2.auto_install_presets(presets.all_loaders())
    v = b2.view("cybersecurity")
    ok(v.is_builtin("audit-server"), "preset skills registered again on start")
    out = tools(b2)["agent_profile"]["run"]({"action": "add_skill", "id": "cybersecurity", "skills": [
        {"name": "audit-server", "description": "palsu", "content": "x"}, {"name": "cek-cron", "description": "cek cron", "content": "1"}]})
    v = b2.view("cybersecurity")
    ok("Gagal" in out and not v.is_modified(v.skill("audit-server")) and v.skill("cek-cron"), "agent_profile can't overwrite preset skills")


def new_presets():
    ok(set(presets.ids()) >= {"web-designer", "cybersecurity", "devops", "code-reviewer"}, "4 presets ship with desktop")
    for pid, emoji in (("cybersecurity", "🛡️"), ("devops", "🚀"), ("code-reviewer", "🔍")):
        f = presets.load(pid)
        meta = json.loads(f["profile.json"])
        ok(meta["emoji"] == emoji and "control" in meta["toolsOff"] and "## Cara kerja" in f["SOUL.md"], pid + " preset ok")
        ok(presets.NAMES[pid].startswith(emoji), pid + " name")
    b = fresh()
    added = b.auto_install_presets(presets.all_loaders())
    ok(set(added) == {"web-designer", "cybersecurity", "devops", "code-reviewer"}, "auto-installed: %s" % sorted(added))
    ap = tools(b)["agent_profile"]["run"]
    ap({"action": "create", "name": "Riset Pasar", "desc": "riset kompetitor"})
    ok("## Cara kerja" in b.view("riset-pasar").soul, "agent_profile gives new agents the work principles")
    ap({"action": "create", "name": "Kedua", "soul": "# SOUL — Kedua\n\n" + WORK_PRINCIPLES})
    ok(b.view("kedua").soul.count("## Cara kerja") == 1, "…only once")


def push():
    home = tempfile.mkdtemp(prefix="home")

    def run(cmd):
        r = subprocess.run(["sh", "-c", cmd], capture_output=True, text=True, env=dict(os.environ, HOME=home))
        return r.returncode, r.stdout, r.stderr

    skill_push.exec_override = run
    h = {"id": "vps", "label": "VPS"}
    try:
        ok(skill_push.prepare("---\nname: a\ndescription: b\n---\nisi") == "---\nname: a\ndescription: b\nversion: 1.0.0\n---\nisi\n", "prepare adds version")
        ok(not skill_push.status(h)["hasAgent"], "no Hermes detected")
        os.makedirs(os.path.join(home, ".hermes"))
        b = fresh()
        sk = b.skill("cek-server")
        st = skill_push.status(h)
        ok(st["hasAgent"] and skill_push.state_of(st, sk) == "missing", "missing before push")
        ok(skill_push.push(h, sk) == "~/.hermes/skills/satsh/cek-server/SKILL.md", "pushed path")
        ok(skill_push.state_of(skill_push.status(h), sk) == "same", "same after push")
        mk = skill_push.markas_skill()
        ok(mk and skill_push.push(h, mk) == "~/.hermes/skills/markas/SKILL.md", "markas skill goes where install.sh puts it")
        d = os.path.join(home, ".hermes", "skills", "devops", "cek-log")
        os.makedirs(d)
        with open(os.path.join(d, "SKILL.md"), "w") as f:
            f.write("---\nname: cek-log\ndescription: baca log 'kutip'\n---\n1. journalctl\n")
        st = skill_push.status(h)
        only = [r for r in st["remote"] if r["name"] not in {s["name"] for s in b.skills} | {"markas"}]
        ok([r["path"] for r in only] == ["devops/cek-log/SKILL.md"], "Hermes' own skill found in a category folder")
        ok(b.save_skill(skill_push.pull(h, only[0]["path"])) == "cek-log", "pulled into satsh")
        # the same bytes as the Android app → same hash
        ok(skill_push.hash_of(skill_push.prepare(sk["raw"])) == st["remote"][[r["name"] for r in st["remote"]].index("cek-server")]["hash"], "hash matches file")
    finally:
        skill_push.exec_override = None


def redaction():
    redact.forget_all()
    redact.learn(["rahasia-vps-123", "server"])
    ok(redact.text("cek server dulu") == "cek server dulu", "plain short word isn't learned")
    s = {"id": "x", "status": "Jalanin di 103.45.67.89…", "messages": [
        {"role": "user", "text": "password gw rahasia-vps-123 ya"},
        {"role": "assistant", "text": "Oke gw coba DB_PASSWORD=hunter22", "calls": [{"id": "c1", "name": "ssh_exec", "args": {"host": "vps", "command": "mysql -u root -prahasia-vps-123", "password": "x"}}]},
        {"role": "tool", "callId": "c1", "text": "API_KEY=sk-abcdefghijklmnopqrstuvwxyz"},
        {"role": "assistant", "text": "Jawaban akhir: key lu sk-abcdefghijklmnopqrstuvwxyz"},
    ]}
    v = redact.session_view(s)
    blob = json.dumps(v["messages"][1:3])
    ok("rahasia-vps-123" not in blob and "hunter22" not in blob and "abcdefghijklmnop" not in blob, "tool args, results and narration masked")
    ok(v["messages"][1]["calls"][0]["args"]["password"] == redact.MASK and v["messages"][1]["calls"][0]["args"]["host"] == "vps", "args deep-masked")
    ok(v["messages"][0]["text"] == s["messages"][0]["text"] and v["messages"][3]["text"] == s["messages"][3]["text"], "user text & final answer untouched")
    ok(v["status"] == "Jalanin di 103.•.•.89…", "status masked")
    ok(s["messages"][1]["calls"][0]["args"]["password"] == "x", "original session not modified")
    redact.enabled = False
    ok(redact.session_view(s) is s, "switch off")
    redact.enabled = True


if __name__ == "__main__":
    lock()
    new_presets()
    push()
    redaction()
    print("ALL SKILL TESTS PASSED")
