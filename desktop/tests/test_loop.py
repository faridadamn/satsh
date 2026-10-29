"""Agent loop limits: step cap from settings, "no limit", and the going-in-circles detector.

    python tests/test_loop.py
"""
import os
import sys
import tempfile

os.environ["SATSH_HOME"] = tempfile.mkdtemp(prefix="satshloop")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from satsh.agent import ERROR_STREAK_LIMIT, SAME_CALL_LIMIT, STEP_LIMIT_TEXT, STUCK_PREFIX, RunCtx, agent  # noqa: E402
from satsh.llm import Reply  # noqa: E402


class Fake:
    """Answers with whatever `script(n)` returns for the n-th model call."""

    def __init__(self, script):
        self.script = script
        self.n = 0

    def chat(self, system, msgs, specs):
        self.n += 1
        return self.script(self.n)


def call(name, **args):
    return Reply("", [{"id": "c%d" % id(args), "name": name, "args": args}])


def tool(name, fail=False):
    def run(args):
        if fail:
            raise RuntimeError("gagal")
        return "ok"

    return {"name": name, "description": "", "params": {"x": {"type": "string"}}, "required": [], "group": "misc", "risky": False, "run": run}


def run(script, max_steps, tools):
    llm = Fake(script)
    h = [{"role": "user", "text": "kerjain"}]
    out = agent.run_loop(llm, h, RunCtx(max_steps=max_steps), "sys", tools=tools)
    return out, llm.n, h


ok = 0


def check(cond, what):
    global ok
    assert cond, what
    ok += 1
    print("✓", what)


# different args each step: real work, not a loop -> runs until the cap
out, n, _ = run(lambda i: call("a", x=str(i)), 30, [tool("a")])
check(out == STEP_LIMIT_TEXT and n == 30, "cap: stops after exactly max_steps calls")

# no limit: keeps going until the model is done on its own
out, n, _ = run(lambda i: call("a", x=str(i)) if i < 300 else Reply("beres", []), 0, [tool("a")])
check(out == "beres" and n == 300, "max_steps=0: no cap, finishes when the model does")

# identical calls in a row -> stuck
out, n, h = run(lambda i: call("a", x="sama"), 0, [tool("a")])
check(out.startswith(STUCK_PREFIX) and n == SAME_CALL_LIMIT and "`a`" in out, "same call %dx -> stops itself" % SAME_CALL_LIMIT)
check(h[-1] == {"role": "assistant", "text": out}, "stuck message lands in history")

# a repeat that gets broken up doesn't count
seq = ["p", "p", "p", "q", "p", "p", "p"]
out, n, _ = run(lambda i: call("a", x=seq[i - 1]) if i <= len(seq) else Reply("done", []), 0, [tool("a")])
check(out == "done", "repeats interrupted by another call are fine")

# every tool erroring step after step -> stuck
out, n, _ = run(lambda i: call("b", x=str(i)), 0, [tool("b", fail=True)])
check(out.startswith(STUCK_PREFIX) and n == ERROR_STREAK_LIMIT, "errors %dx in a row -> stops itself" % ERROR_STREAK_LIMIT)

# hitting the cap and looking stuck on the same step: cap wins (missions rely on that text)
out, n, _ = run(lambda i: call("a", x="sama"), SAME_CALL_LIMIT, [tool("a")])
check(out == STEP_LIMIT_TEXT, "cap message wins when both happen on the last step")

print("OK %d" % ok)
