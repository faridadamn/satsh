"""Profiles + portable agent zip (desktop side). Plain asserts, runs on Python 3.8+.

    python tests/test_profiles.py                 # unit checks
    python tests/test_profiles.py export OUT.zip  # write a zip for the Android interop test
    python tests/test_profiles.py import IN.zip   # check a zip made by satsh Android
"""
import json
import os
import sys
import tempfile
import zipfile

os.environ["SATSH_HOME"] = tempfile.mkdtemp(prefix="satshprof")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from satsh import agentzip  # noqa: E402
from satsh.brain import Brain  # noqa: E402


def fresh():
    return Brain(tempfile.mkdtemp(prefix="brain"))


def ok(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print("  ✓", msg)


def seeded():
    b = fresh()
    b.memory_op("add", "user", "Adam driver ojol")
    p = b.create_profile("Payu", emoji="💼", copy_from="default")
    v = b.view(p["id"])
    v.save_soul("# soul payu")
    v.memory_op("add", "memory", "repo payu di github")
    v.save_skill("---\nname: deploy-payu\ndescription: deploy payu\n---\nlangkah")
    s = Brain.new_session("chat payu", profile=p["id"])
    s["messages"].append({"role": "user", "text": "halo"})
    b.save_session(s)
    return b, s


def unit():
    b = fresh()
    ok(b.active_id == "default" and os.path.exists(os.path.join(b.root, "SOUL.md")), "default profile keeps the old layout")
    b.memory_op("add", "memory", "server utama: vps-jkt")
    p = b.create_profile("Payu Ops", copy_from="default")
    ok(p["id"] == "payu-ops", "slug id")
    b.set_active(p["id"])
    ok(b.memory == "" and b.skill("cek-server"), "own memory, skills copied")
    b.save_soul("# Payu ops agent")
    b2 = Brain(b.root)
    ok(b2.active_id == "payu-ops" and b2.soul == "# Payu ops agent", "survives reload")
    ok("vps-jkt" in b2.view("default").memory, "default memory untouched")
    ok(b2.create_profile("Payu Ops")["id"] == "payu-ops-2", "unique ids")

    # prompt + tools follow the profile
    from satsh.agent import Agent
    a = Agent(brain=b2)
    b2.update_profile("payu-ops", desc="ngurus payu", toolsOff=["ssh"])
    pb = b2.view("payu-ops")
    pr = a.system_prompt(profile=pb)
    ok(pr.startswith("# Payu ops agent") and "ngurus payu" in pr, "system prompt uses profile soul + desc")
    ok(not any(t["group"] == "ssh" for t in a.base_tools("payu-ops")), "profile tool switches")
    ok(any(t["group"] == "ssh" for t in a.base_tools("default")), "other profile unaffected")

    # android session ids (uuid with dashes) open fine
    s = Brain.new_session("x")
    s["id"] = "3f2a9c1e-1111-4222-8333-444455556666"
    s["messages"].append({"role": "user", "text": "hai"})
    b2.save_session(s)
    ok(b2.open_session(s["id"]) is not None, "android-style session id opens")
    ok(b2.open_session("../../etc/passwd") is None, "path tricks rejected")

    # old jobs/sessions have no profile → must fall back to default (v2.0.0 crashed here)
    ok(b2.view(None).id == "default" and b2.view("ga-ada").id == "default", "missing profile falls back to default")
    from satsh.agent import CronRunner
    from satsh import agent as agent_mod, errlog
    from satsh.brain import CronJob, now_ms

    class FakeLlm:
        name = "fake"

        def chat(self, system, history, tools):
            return type("R", (), {"text": "beres", "calls": [], "raw": None})()

    agent_mod.agent.brain = b2
    agent_mod.agent.provider_override = FakeLlm()
    j = CronJob(id="oldjob1", name="loker", prompt="cek", everyMinutes=60, dailyAt=None, enabled=True, allowRisky=False,
                lastRun=None, lastResult="", sessionId=None, created=now_ms())  # no "profile" key, like pre-2.0 jobs
    b2.jobs.append(j)
    CronRunner().run(j)
    ok(not j["lastResult"].startswith("GAGAL"), "pre-2.0 cron job runs (%s)" % j["lastResult"])
    try:
        None.x  # noqa
    except Exception as e:  # noqa
        errlog.add("cron", e, {"jadwal": "tes"})
    rep = errlog.report()
    ok("AttributeError" in rep and "jadwal: tes" in rep and "test_profiles.py" in rep, "error log keeps traceback + context")

    # delete
    b2.delete_profile("payu-ops")
    ok(not b2.profile("payu-ops") and b2.active_id == "default", "delete falls back to default")

    # zip roundtrip
    src, sess = seeded()
    data = agentzip.export(src, sessions=True, jobs=True)
    names = set(zipfile.ZipFile(__import__("io").BytesIO(data)).namelist())
    ok({"satsh-agent.json", "USER.md", "profiles/default/SOUL.md", "profiles/payu/skills/deploy-payu/SKILL.md", "sessions/%s.json" % sess["id"]} <= names, "zip layout")
    dst = fresh()
    dst.memory_op("add", "user", "suka kopi")
    summary = agentzip.import_zip(dst, data)
    ok("💼 Payu" in summary, "import summary: " + summary)
    ok(set(dst.entries("user")) >= {"suka kopi", "Adam driver ojol"}, "user profile merged")
    v = dst.view("payu")
    ok(v.soul == "# soul payu" and "repo payu" in v.memory and v.skill("deploy-payu"), "profile restored")
    ok(dst.open_session(sess["id"])["profile"] == "payu", "session restored with profile")
    agentzip.import_zip(dst, data)
    ok(dst.entries("user").count("Adam driver ojol") == 1, "re-import doesn't duplicate")
    try:
        agentzip.import_zip(dst, b"nope")
        ok(False, "bad zip should fail")
    except ValueError:
        ok(True, "non-zip rejected")


def presets_test():
    from satsh import presets
    from satsh.agent import Agent, RunCtx
    ok("web-designer" in presets.ids(), "web-designer preset ships with desktop")
    f = presets.load("web-designer")
    for sk in ("antislop", "antislop-ui", "design-md", "agents-md", "web-build", "web-resources"):
        ok("skills/%s/SKILL.md" % sk in f, "preset skill " + sk)
    ok("Miqdad Badjuber" in f["skills/antislop-ui/SKILL.md"], "antislop MIT notice kept")
    b = fresh()
    a = Agent(brain=b)  # first start installs presets
    ok(b.profile("web-designer") and b.view("web-designer").skill("antislop-ui"), "preset auto-installed")
    ok(b.active_id == "default", "general agent stays active")
    b.delete_profile("web-designer")
    ok(Brain(b.root).profile("web-designer") is None and not Brain(b.root).auto_install_presets(presets.all_loaders()), "deleted preset stays deleted")
    tool = next(t for t in a.brain_tools(RunCtx(auto=True)) if t["name"] == "agent_profile")
    ok(tool["risky"], "agent_profile asks permission")
    out = tool["run"]({"action": "create", "name": "Copywriter", "emoji": "✍️", "soul": "# Kamu copywriter",
                       "skills": [{"name": "Caption IG", "description": "bikin caption", "content": "1. hook"}],
                       "memory": ["ref: github.com/miqdadbadjuber/anti-slop"], "tools_off": ["ssh"], "copy_skills_from": "preset:web-designer"})
    v = b.view("copywriter")
    ok("id=copywriter" in out and v.soul == "# Kamu copywriter" and v.skill("caption-ig") and v.skill("antislop-copywriting"), "agent_profile create")
    ok("anti-slop" in v.memory and b.profile("copywriter")["toolsOff"] == ["ssh"], "agent_profile memory + tools")


def check_android_zip(path):
    b = fresh()
    with open(path, "rb") as f:
        summary = agentzip.import_zip(b, f.read())
    print("  summary:", summary)
    ok(b.profile("payu") and b.view("payu").soul == "# soul payu", "android profile + soul imported")
    ok(b.view("payu").skill("deploy-payu"), "android skill imported")
    ok("Adam driver ojol" in b.entries("user"), "android USER.md imported")
    sid = next(m["id"] for m in b.sessions if m["title"] == "chat payu")
    s = b.open_session(sid)
    ok(s and s["profile"] == "payu" and s["messages"][0]["text"] == "halo", "android session opens on desktop")
    ok(b.jobs and b.jobs[0]["enabled"] is False and b.jobs[0].next_run(), "android cron job imported paused & schedulable")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "export":
        b, _ = seeded()
        from satsh.brain import CronJob, now_ms
        b.jobs.append(CronJob(id="jobwin1", name="cek", prompt="cek server", everyMinutes=60, dailyAt=None, enabled=True,
                              allowRisky=False, lastRun=None, lastResult="", sessionId=None, created=now_ms(), profile="payu"))
        b.save_jobs()
        with open(sys.argv[2], "wb") as f:
            f.write(agentzip.export(b, sessions=True, jobs=True))
        print("wrote", sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "import":
        check_android_zip(sys.argv[2])
        print("ANDROID ZIP OK")
    else:
        unit()
        presets_test()
        print("ALL PROFILE TESTS PASSED")
