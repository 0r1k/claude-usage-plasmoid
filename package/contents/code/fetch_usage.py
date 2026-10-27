#!/usr/bin/env python3
"""Fetch Claude plan usage (the data behind Claude Code's /usage) and print one JSON line.

Reads the OAuth token Claude Code keeps in ~/.claude/.credentials.json. The token is
never refreshed here: refresh tokens rotate, and refreshing behind Claude Code's back
would log it out. When the token is expired we return the last cached result instead.
"""
import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.request

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                     "claude-usage-plasmoid", "usage.json")

LABELS = {
    "session": "Current session",
    "weekly_all": "Current week (all models)",
    "weekly_opus": "Current week (Opus)",
    "weekly_sonnet": "Current week (Sonnet)",
}
# Old response shape, used when "limits" is missing.
LEGACY = [
    ("five_hour", "session", "session"),
    ("seven_day", "weekly_all", "weekly"),
    ("seven_day_opus", "weekly_opus", "weekly"),
    ("seven_day_sonnet", "weekly_sonnet", "weekly"),
]


def ms(iso):
    if not iso:
        return None
    try:
        return int(datetime.datetime.fromisoformat(iso).timestamp() * 1000)
    except ValueError:
        return None


def label(kind, scope):
    text = LABELS.get(kind) or kind.replace("_", " ").capitalize()
    if scope:
        text += " (%s)" % (scope if isinstance(scope, str) else scope.get("display_name") or scope)
    return text


def normalize(raw):
    limits = []
    if isinstance(raw.get("limits"), list):
        for l in raw["limits"]:
            limits.append({
                "kind": l.get("kind", ""),
                "group": l.get("group", ""),
                "label": label(l.get("kind", ""), l.get("scope")),
                "percent": float(l.get("percent") or 0),
                "resetsAt": ms(l.get("resets_at")),
                "severity": l.get("severity") or "normal",
            })
    else:
        for key, kind, group in LEGACY:
            w = raw.get(key)
            if w:
                limits.append({
                    "kind": kind, "group": group, "label": label(kind, None),
                    "percent": float(w.get("utilization") or 0),
                    "resetsAt": ms(w.get("resets_at")), "severity": "normal",
                })

    extra = None
    eu = raw.get("extra_usage") or {}
    if eu.get("is_enabled"):
        extra = {
            "used": eu.get("used_credits"),
            "limit": eu.get("monthly_limit"),
            "percent": eu.get("utilization"),
            "currency": eu.get("currency") or "USD",
        }

    breakdown = [{"name": r.get("display_name") or r.get("key"), "percent": r.get("percent") or 0}
                 for r in ((raw.get("seven_day_breakdown") or {}).get("rows") or [])]
    return {"limits": limits, "extra": extra, "breakdown": breakdown}


def read_cache():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def write_cache(obj):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, CACHE)


def fail(error, message, meta):
    out = {"ok": False, "error": error, "message": message, **meta}
    cached = read_cache()
    if cached:
        out["fetchedAt"] = cached.get("fetchedAt")
        out["usage"] = cached.get("usage")
    print(json.dumps(out))
    sys.exit(0)


def main():
    cred_path = (sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else
                 os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"),
                              ".credentials.json"))
    meta = {}
    try:
        with open(os.path.expanduser(cred_path)) as f:
            oauth = json.load(f)["claudeAiOauth"]
        token = oauth["accessToken"]
    except (OSError, ValueError, KeyError) as e:
        fail("no_credentials", "Cannot read %s: %s" % (cred_path, e), meta)

    meta = {"plan": oauth.get("subscriptionType"), "tokenExpiresAt": oauth.get("expiresAt")}
    if meta["tokenExpiresAt"] and meta["tokenExpiresAt"] <= time.time() * 1000:
        fail("token_expired", "OAuth token expired; run claude to refresh it", meta)

    req = urllib.request.Request(USAGE_URL, headers={
        "Authorization": "Bearer " + token,
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-usage-plasmoid/1.0",
    })
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 401:
            fail("unauthorized", "HTTP 401: token rejected; run claude to re-login", meta)
        if e.code == 429:
            fail("rate_limited", "HTTP 429: rate limited, backing off", meta)
        fail("http", "HTTP %d" % e.code, meta)
    except (urllib.error.URLError, OSError, ValueError) as e:
        fail("network", str(getattr(e, "reason", e)), meta)

    cached = {"fetchedAt": int(time.time() * 1000), "usage": normalize(raw)}
    write_cache(cached)
    print(json.dumps({"ok": True, "error": None, "message": "", **meta, **cached}))


if __name__ == "__main__":
    main()
