"""LLM providers (stdlib only): OpenAI-compatible + Gemini, with a fallback chain.

Messages are plain dicts:
  {"role": "user"|"assistant"|"tool"|"event", "text": str,
   "calls": [{"id","name","args"}], "callId", "name", "raw", "isError"}
"""
import json
import ssl
import time
import urllib.error
import urllib.request

from .config import cfg

_ctx = ssl.create_default_context()


class LlmError(Exception):
    pass


def _post(url, headers, body, timeout=180):
    req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_ctx) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            j = json.loads(raw)
            err = j.get("error", j) if isinstance(j, dict) else j
            msg = err.get("message", str(err)) if isinstance(err, dict) else str(err)
        except Exception:
            msg = raw[:300]
        raise LlmError("HTTP %s: %s" % (e.code, msg))
    except urllib.error.URLError as e:
        raise LlmError("Koneksi gagal: %s" % e.reason)


def _get(url, headers, timeout=30):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout, context=_ctx) as r:
        return json.loads(r.read().decode("utf-8"))


def schema(tool, upper=False):
    def fix(m):
        out = {}
        for k, v in m.items():
            if k == "type" and upper and isinstance(v, str):
                out[k] = v.upper()
            elif isinstance(v, dict):
                out[k] = fix(v)
            else:
                out[k] = v
        return out

    return {
        "type": "OBJECT" if upper else "object",
        "properties": {k: fix(v) for k, v in tool["params"].items()},
        "required": tool.get("required", []),
    }


class Reply:
    def __init__(self, text, calls, raw=None):
        self.text = text
        self.calls = calls
        self.raw = raw


class OpenAICompat:
    def __init__(self, base, key, model, name="OpenAI"):
        self.base = base.rstrip("/")
        self.key = key
        self.model = model
        self.name = name

    def chat(self, system, history, tools):
        msgs = [{"role": "system", "content": system}]
        for m in history:
            r = m["role"]
            if r == "user":
                msgs.append({"role": "user", "content": m["text"]})
            elif r == "assistant":
                o = {"role": "assistant", "content": (None if (not m["text"] and m.get("calls")) else m["text"])}
                if m.get("calls"):
                    o["tool_calls"] = [
                        {"id": c["id"], "type": "function", "function": {"name": c["name"], "arguments": json.dumps(c["args"])}}
                        for c in m["calls"]
                    ]
                msgs.append(o)
            elif r == "tool":
                msgs.append({"role": "tool", "tool_call_id": m["callId"], "content": m["text"]})
        body = {"model": self.model, "messages": msgs}
        if tools:
            body["tools"] = [
                {"type": "function", "function": {"name": t["name"], "description": t["description"], "parameters": schema(t)}}
                for t in tools
            ]
        j = _post(
            self.base + "/chat/completions",
            {"Content-Type": "application/json", "Authorization": "Bearer " + self.key, "X-Title": "satsh"},
            body,
        )
        ch = (j.get("choices") or [None])[0]
        if not ch:
            raise LlmError("Respon kosong dari provider")
        msg = ch.get("message") or {}
        calls = []
        for i, tc in enumerate(msg.get("tool_calls") or []):
            f = tc.get("function") or {}
            a = f.get("arguments")
            args = {}
            if isinstance(a, str) and a.strip():
                try:
                    args = json.loads(a)
                except Exception:
                    args = {"_raw": a}
            elif isinstance(a, dict):
                args = a
            calls.append({"id": tc.get("id") or "call_%d" % i, "name": f.get("name"), "args": args})
        content = msg.get("content")
        return Reply(content if isinstance(content, str) else "", calls)

    def models(self):
        j = _get(self.base + "/models", {"Authorization": "Bearer " + self.key})
        return sorted(m["id"] for m in j.get("data", []))


class Gemini:
    def __init__(self, key, model, name="Gemini"):
        self.key = key
        self.model = model
        self.name = name

    def chat(self, system, history, tools):
        contents = []

        def push(role, part):
            if contents and contents[-1]["role"] == role:
                contents[-1]["parts"].append(part)
            else:
                contents.append({"role": role, "parts": [part]})

        for m in history:
            r = m["role"]
            if r == "user":
                push("user", {"text": m["text"]})
            elif r == "assistant":
                if isinstance(m.get("raw"), list):
                    for p in m["raw"]:
                        push("model", p)
                else:
                    if m["text"]:
                        push("model", {"text": m["text"]})
                    for c in m.get("calls") or []:
                        push("model", {"functionCall": {"name": c["name"], "args": c["args"]}})
            elif r == "tool":
                push("user", {"functionResponse": {"name": m.get("name"), "response": {"result": m["text"]}}})
        body = {"systemInstruction": {"parts": [{"text": system}]}, "contents": contents}
        if tools:
            decls = []
            for t in tools:
                d = {"name": t["name"], "description": t["description"]}
                if t["params"]:
                    d["parameters"] = schema(t, upper=True)
                decls.append(d)
            body["tools"] = [{"functionDeclarations": decls}]
        j = _post(
            "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % self.model,
            {"Content-Type": "application/json", "x-goog-api-key": self.key},
            body,
        )
        cand = (j.get("candidates") or [None])[0]
        if not cand:
            block = (j.get("promptFeedback") or {}).get("blockReason")
            raise LlmError("Diblok Gemini: %s" % block if block else "Respon kosong dari Gemini")
        parts = (cand.get("content") or {}).get("parts") or []
        text, calls = [], []
        for p in parts:
            if p.get("thought"):
                continue
            if isinstance(p.get("text"), str):
                text.append(p["text"])
            fc = p.get("functionCall")
            if fc:
                calls.append({"id": "g%d_%d" % (len(calls), int(time.time() * 1e6)), "name": fc["name"], "args": fc.get("args") or {}})
        return Reply("".join(text), calls, raw=parts)

    def models(self):
        j = _get("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200", {"x-goog-api-key": self.key})
        return [
            m["name"].replace("models/", "")
            for m in j.get("models", [])
            if "generateContent" in (m.get("supportedGenerationMethods") or [])
        ]


def build(p):
    key = cfg.secret("key_" + p["id"])
    if not key:
        raise LlmError("API key %s belum diisi (Pengaturan)" % p.get("name", p["id"]))
    if p.get("kind") == "gemini":
        return Gemini(key, p.get("model") or "gemini-2.5-flash", p.get("name", "Gemini"))
    return OpenAICompat(p.get("base") or "https://api.openai.com/v1", key, p.get("model") or "gpt-4.1-mini", p.get("name", "OpenAI"))


class Fallback:
    """Tries providers in order; remembers which one answered last."""

    def __init__(self, providers):
        self.providers = providers
        self.last = None

    def chat(self, system, history, tools):
        errors = []
        for p in self.providers:
            try:
                r = p.chat(system, history, tools)
                self.last = p
                return r
            except Exception as e:  # noqa
                if not isinstance(e, (LlmError, OSError)):
                    from . import errlog
                    errlog.add("llm", e, {"provider": getattr(p, "name", "?")})
                errors.append("%s: %s" % (getattr(p, "name", "?"), e))
        raise LlmError(" | ".join(errors) or "Belum ada provider")


def default_provider(prefer=None):
    """All enabled providers in order (fallback chain); [prefer] (provider id) goes first."""
    built, errs = [], []
    ps = list(cfg.get("providers", []))
    if prefer:
        ps.sort(key=lambda p: 0 if p.get("id") == prefer else 1)
    for p in ps:
        if p.get("disabled"):
            continue
        try:
            built.append(build(p))
        except LlmError as e:
            errs.append(str(e))
    if not built:
        raise LlmError(errs[0] if errs else "Belum ada provider. Buka Pengaturan → Agent.")
    return Fallback(built)
