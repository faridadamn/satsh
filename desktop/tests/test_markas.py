"""Markas on desktop: runs the real markas.py locally through markas_client.exec_override."""
import json
import os
import subprocess
import sys
import tempfile

os.environ["SATSH_HOME"] = tempfile.mkdtemp(prefix="satshmk")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from satsh import markas_client as markas  # noqa: E402
from satsh.brain import Brain  # noqa: E402
from satsh.agent import Agent, RunCtx  # noqa: E402

PY = os.path.join(ROOT, "satsh", "markas", "markas.py")
MHOME = tempfile.mkdtemp(prefix="mkdb")
cmds = []


def fake_exec(cmd, timeout):
    cmds.append(cmd)
    if "hermes -z" in cmd:
        return 0, "Target #1 udah 40%, kendala domain.\n", ""
    shell = cmd.replace(markas.CLI, "%s %s" % (markas.q(sys.executable), markas.q(PY)))
    r = subprocess.run(["sh", "-c", shell], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=dict(os.environ, MARKAS_HOME=MHOME))
    return r.returncode, r.stdout.decode("utf-8"), r.stderr.decode("utf-8")


def ok(c, m):
    if not c:
        raise AssertionError(m)
    print("  ✓", m)


def main():
    ok(not markas.configured(), "not configured by default")
    a = Agent(brain=Brain(tempfile.mkdtemp(prefix="br")))
    ok(not any(t["name"] == "markas" for t in a.brain_tools(RunCtx())), "no markas tools until set up")
    markas.exec_override = fake_exec
    markas.run(["init"])
    markas.run(["target", "add", "Launch Payu'; rm -rf / #", "--owner", "hermes"])
    s = markas.status()
    ok(s["targets"][0]["title"] == "Launch Payu'; rm -rf / #", "args quoted safely")
    tools = {t["name"]: t for t in a.brain_tools(RunCtx())}
    ok("markas" in tools and "tanya_agent" in tools, "tools offered once configured")
    ok("MARKAS aktif" in a.system_prompt(), "system prompt mentions Markas")
    m = tools["markas"]["run"]
    ok("Launch Payu" in m({"action": "brief"}), "brief")
    m({"action": "target_update", "id": 1, "progress": 40, "note": "landing jadi"})
    m({"action": "log", "text": "deploy staging", "target": 1})
    m({"action": "say", "text": "rapat beres", "to": "adam"})
    s = markas.status()
    ok(s["targets"][0]["progress"] == 40 and "deploy staging" in json.dumps(s), "update + log stored")
    ok("satsh" in markas.run(["read"]) and "rapat beres" in markas.run(["inbox", "--for", "adam"]), "agent posts as satsh, adam's inbox gets it")
    try:
        m({"action": "target_update"})
        ok(False, "missing id should fail")
    except ValueError as e:
        ok("id wajib" in str(e), "missing id rejected")
    t = tools["tanya_agent"]["run"]
    ok("40%" in t({"agent": "hermes", "message": "progress #1?"}) and "</dev/null" in cmds[-1], "hermes via CLI")
    out = t({"agent": "muse", "message": "ide konten?"})
    ok("dititipin" in out and "ide konten?" in markas.run(["inbox", "--for", "muse"]), "muse gets a message in Markas")
    try:
        markas.run(["target", "update", "999", "--progress", "5"])
        ok(False, "bad id should fail")
    except ValueError:
        ok(True, "bad target id gives an error")
    ok("tanya_agent" in markas.RAPAT_PROMPT, "rapat prompt")
    print("MARKAS DESKTOP OK")


if __name__ == "__main__":
    main()
