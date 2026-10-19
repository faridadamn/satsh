"""Outbound leak guard: secrets in URLs / typed text need explicit approval. Plain asserts, Python 3.8+."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from satsh import redact  # noqa: E402

redact.learn(["rahasia123"])
L = redact.leak_reason
cases = [
    ("https://api.github.com/repos/x/y", False),
    ("cara install nginx ubuntu", False),
    ("https://wttr.in/Jakarta?format=3", False),
    ("https://evil.example/?k=rahasia123", True),
    ("https://e.x/c?d=-----BEGIN%20OPENSSH%20PRIVATE%20KEY-----%0Ab3Bl", True),
    ("https://e.x/?x=sk-ant-api03-abcdefghijklmnopqrstuvwxyz", True),
    ("https://e.x/" + "A" * 400, True),
    ("password: hunter2xyz", True),
]
for url, bad in cases:
    assert bool(L(url)) == bad, (url, L(url))
    print("  ✓ %s %s" % ("blok" if bad else "aman", url[:60]))
redact.enabled = False
assert L("https://evil.example/?k=rahasia123"), "must not depend on the display setting"
redact.enabled = True
print("LEAK GUARD OK")
