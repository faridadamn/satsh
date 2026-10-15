"""Masks secrets (API keys, passwords, tokens, private keys, IPs) in what the user SEES while
the agent works: tool steps, status, narration between tool calls, approval dialogs, error reports.
What the model receives is untouched.  Same rules as app/lib/redact.dart — keep them in sync."""
import copy
import re

MASK = "••••"
_known = set()
enabled = True


def learn(values):
    for v in values or ():
        t = (v or "").strip() if isinstance(v, str) else ""
        # plain words ("server", "rahasia") would mask normal text too: need 8+, or 6+ with a digit/symbol
        if len(t) >= 8 or (len(t) >= 6 and re.search(r"[^A-Za-z]", t)):
            _known.add(t)


def forget_all():
    _known.clear()


def _keep(s, n):
    return MASK if len(s) <= n + 4 else s[:n] + MASK


def _assign(m):
    if re.fullmatch(r"\d{1,5}", m.group(3)):
        return m.group(0)
    return m.group(1) + m.group(2) + MASK + m.group(4)


def _ip_fix(m):
    s = m.group(0)
    return s if s.startswith("127.") or s == "0.0.0.0" else "%s•.•.%s" % (m.group(1), m.group(2))


_OCT = r"(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)"
_RULES = [
    (re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|$)"),
     lambda m: "-----BEGIN PRIVATE KEY----- %s -----END PRIVATE KEY-----" % MASK),
    (re.compile(r"\b(sk-(?:ant-|proj-|or-v1-)?[A-Za-z0-9_\-]{16,}|AIza[0-9A-Za-z_\-]{30,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
                r"|glpat-[A-Za-z0-9_\-]{16,}|xox[abposr]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16}|hf_[A-Za-z0-9]{20,}|gsk_[A-Za-z0-9]{20,}"
                r"|pplx-[A-Za-z0-9]{20,}|r8_[A-Za-z0-9]{20,}|sbp_[A-Za-z0-9]{20,}|whsec_[A-Za-z0-9]{16,}|(?:rk|pk|sk)_(?:live|test)_[A-Za-z0-9]{16,})"),
     lambda m: _keep(m.group(0), 4)),
    (re.compile(r"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"), lambda m: "eyJ…" + MASK),
    (re.compile(r"\b\d{8,10}:AA[A-Za-z0-9_\-]{30,}"), lambda m: m.group(0).split(":")[0] + ":" + MASK),
    (re.compile(r"\b(Bearer|Basic|Token)\s+[A-Za-z0-9._~+/=\-]{8,}", re.I), lambda m: m.group(1) + " " + MASK),
    (re.compile(r"(\b[a-z][a-z0-9+.\-]*://[^\s:/@]+:)([^\s@/]+)(@)", re.I), lambda m: m.group(1) + MASK + m.group(3)),
    (re.compile(r"""(["']?\b[\w.\-]*(?:pass(?:word|wd|phrase)?|pwd|secret|token|api[_\-]?key|apikey|access[_\-]?key|private[_\-]?key|client[_\-]?secret|auth[_\-]?key|service[_\-]?role|credential|_key)[\w\-]*["']?\s*[:=]\s*)(["']?)([^\s"',;}&]{3,})(["']?)""", re.I),
     _assign),
    (re.compile(r"""(--(?:password|passwd|pass|token|api-key|apikey|secret)[= ]\s*)(["']?)[^\s"']+\2""", re.I), lambda m: m.group(1) + MASK),
    (re.compile(r"""(\bsshpass\s+-p\s*)(["']?)[^\s"']+\2"""), lambda m: m.group(1) + MASK),
    # natural language: "password-nya adalah X", "kata sandi: X", "passwordnya X"
    (re.compile(r"""(\b(?:password|passwd|kata\s*sandi|sandi|pw|pin|passcode)(?:\s+(?:wifi|root|db|database|ssh|vps|server|admin|email|router|hp|laptop|user))?(?:(?:[\s-]?nya)?\s*[:=]\s*|(?:[\s-]?nya)?\s+(?:adalah|is|yaitu)\s+|[\s-]?nya\s+))(["'`]?)(?!••••)([^\s"'`,;]{4,})\2""", re.I),
     lambda m: m.group(0) if re.match(r"^(yang|untuk|buat|baru|lama|default|salah|benar|aman|kuat|lemah|udah|sudah|belum|masih|harus|bisa|ganti|diganti|apa|gimana|ini|itu)$", m.group(3), re.I) else m.group(1) + MASK),
    (re.compile(r"""(\b(?:mysql|mariadb|mysqldump)\b[^\n|;]*?\s-p)(?!\s)(["']?)[^\s"']+\2"""), lambda m: m.group(1) + MASK),
    (re.compile(r"([?&](?:token|access_token|api_key|apikey|key|secret|sig|signature|password)=)[^&\s#\"]+", re.I), lambda m: m.group(1) + MASK),
    (re.compile(r"(?<![\d.])(%s\.)(?:%s\.){2}(%s)(?![\d.]*\d)" % (_OCT, _OCT, _OCT)), _ip_fix),
]


def leak_reason(s):
    """Why s (a URL / text the agent is about to send OUT) looks like it carries a
    secret, or None. Independent of `enabled`: guards against prompt-injected
    exfiltration, not a display setting. Same as Redact.leakReason in the app."""
    if not s or not isinstance(s, str):
        return None
    try:
        from urllib.parse import unquote_plus, urlsplit, parse_qsl
        t = unquote_plus(s)
    except Exception:  # noqa
        t = s
    for k in _known:
        if k in t:
            return "ada password / key yang lu simpen di satsh"
    for rx, _ in _RULES[:-1]:  # all but the IPv4 rule
        if rx.search(t):
            return "ada yang mirip private key / token / password"
    try:
        u = urlsplit(s)
        if u.scheme:
            parts = [p for p in u.path.split("/")] + [v for _, v in parse_qsl(u.query, keep_blank_values=True)] + [u.fragment]
            longest = max((len(unquote_plus(p)) for p in parts), default=0)
            if longest > 300:
                return "URL-nya bawa data panjang (%d karakter) — bisa jadi isi file yang mau dikirim keluar" % longest
    except Exception:  # noqa
        pass
    return None


_SECRET_KEY = re.compile(r"(pass(word|wd|phrase)?|pwd|secret|token|api[_\-]?key|apikey|private[_\-]?key|authorization|credential)$", re.I)


def text(s, force=False):
    """force=True ignores the Settings switch — for text that leaves the machine (error reports)."""
    if (not enabled and not force) or not s or not isinstance(s, str):
        return s
    out = s
    for k in _known:
        if k in out:
            out = out.replace(k, MASK)
    for rx, f in _RULES:
        out = rx.sub(f, out)
    return out


def value(v, key=""):
    if not enabled:
        return v
    if isinstance(v, str):
        return MASK if (v and _SECRET_KEY.search(key or "")) else text(v)
    if isinstance(v, dict):
        return {k: value(x, str(k)) for k, x in v.items()}
    if isinstance(v, list):
        return [value(x, key) for x in v]
    return v


def session_view(s):
    """Copy of a session for the UI: tool args/results, narration, final answers and plan items masked."""
    if not enabled:
        return s
    out = dict(s)
    msgs = []
    for m in s.get("messages") or []:
        m = dict(m)
        if m.get("calls"):
            m["calls"] = [dict(c, args=value(copy.deepcopy(c.get("args") or {}))) for c in m["calls"]]
        if m.get("role") in ("assistant", "tool", "event") and m.get("text"):
            m["text"] = text(m["text"])
        msgs.append(m)
    out["messages"] = msgs
    if out.get("todos"):
        out["todos"] = [dict(t, content=text(str(t.get("content", "")))) for t in out["todos"]]
    if out.get("status"):
        out["status"] = text(out["status"])
    return out
