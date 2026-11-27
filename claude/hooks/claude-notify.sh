#!/bin/bash
# claude-notify: Discord DM when a Claude Code session needs a human.
# Events: PermissionRequest (tool + command) and Notification idle_prompt.
# Notify-only: prints nothing on stdout, so no permission decision is made.
# `claude-notify.sh --message "<text>"` sends one arbitrary DM synchronously (exit 1 if it could not be sent).
# Always exits 0. Works on bash 3.2 (macOS) and GNU bash (WSL).

ENV_FILE="${CLAUDE_NOTIFY_ENV:-$HOME/.config/claude-notify/env}"
STATE_DIR="${CLAUDE_NOTIFY_STATE:-$HOME/.local/state/claude-notify}"
LOG="$STATE_DIR/notify.log"
CURL="${CURL:-curl}"
DEDUPE_SECS="${CLAUDE_NOTIFY_DEDUPE_SECS:-120}"

main() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  local input; input="$(cat)"
  [ -f "$ENV_FILE" ] || { log "no env file $ENV_FILE"; return 0; }

  local parsed sid msg
  parsed="$(printf '%s' "$input" | python3 -I -c "$PY" 2>>"$LOG")" || { log "parse failed"; return 0; }
  [ -n "$parsed" ] || return 0
  sid="$(printf '%s' "$parsed" | head -n1 | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)"
  msg="$(printf '%s' "$parsed" | tail -n +2)"
  [ -n "$msg" ] || return 0

  dedupe "$sid" || { log "deduped $sid"; return 0; }

  if [ -n "${CLAUDE_NOTIFY_SYNC:-}" ]; then
    send "$msg"
  else
    ( send "$msg" ) >/dev/null 2>&1 </dev/null &
  fi
  return 0
}

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" >>"$LOG" 2>/dev/null; }

dedupe() {  # one DM per session per window
  local stamp="$STATE_DIR/last-$1" now last
  now="$(date +%s)"
  last="$(cat "$stamp" 2>/dev/null)"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  [ $((now - last)) -ge "$DEDUPE_SECS" ] || return 1
  printf '%s' "$now" >"$stamp" 2>/dev/null
  return 0
}

json_id() {
  python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")' 2>/dev/null
}

bot_post() {  # bot_post <url> <payload>; token via --config stdin, never argv
  printf 'header = "Authorization: Bot %s"\n' "$DISCORD_BOT_TOKEN" \
    | "$CURL" -s --fail -X POST "$1" -H 'Content-Type: application/json' \
        -H 'User-Agent: DiscordBot (claude-notify, 1.0)' --max-time 5 \
        -d "$2" --config -
}

send() {
  local msg="$1" chan sent payload
  # shellcheck disable=SC1090
  . "$ENV_FILE" 2>/dev/null
  if [ -z "${DISCORD_BOT_TOKEN:-}" ] || [ -z "${DISCORD_OWNER_ID:-}" ]; then
    log "env file missing DISCORD_BOT_TOKEN/DISCORD_OWNER_ID"; return 1
  fi
  chan="$(bot_post "https://discord.com/api/v10/users/@me/channels" \
            "{\"recipient_id\": \"$DISCORD_OWNER_ID\"}" 2>/dev/null | json_id)"
  [ -n "$chan" ] || { log "DM channel open failed"; return 1; }
  payload="$(printf '%s' "$msg" | python3 -I -c 'import json,sys;print(json.dumps({"content":sys.stdin.read()}))')"
  sent="$(bot_post "https://discord.com/api/v10/channels/$chan/messages" "$payload" 2>/dev/null | json_id)"
  if [ -n "$sent" ]; then log "sent"; return 0; fi
  log "message send failed"
  return 1
}

message_mode() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  [ -n "${1:-}" ] || { echo "claude-notify: --message needs text" >&2; return 2; }
  [ -f "$ENV_FILE" ] || { log "no env file $ENV_FILE"; return 1; }
  send "$1"
}

PY='
import json, os, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
ev = d.get("hook_event_name", "")
sid = str(d.get("session_id", "unknown"))
cwd = d.get("cwd", "") or ""

SECRET = [
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*",  # public-safety: allow (regex literal, not a key)
    r"(?i)(authorization:\s*)(bearer|bot|basic)?\s*\S+",
    r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{8,}",
    r"://[^/\s:@]+:[^/\s@]+@",
    r"(?i)\b([A-Za-z0-9_.-]*(token|secret|passw(or)?d|pwd|api[_-]?key|apikey|credential|private[_-]?key|auth)[A-Za-z0-9_.-]*)(\s*[=:]\s*|\s+)(\"[^\"]*\"|\x27[^\x27]*\x27|\S+)",
    r"(?i)(--?(token|secret|password|passwd|api-key|apikey|auth)[= ])\S+",
    r"\b(sk|pk|rk)-[A-Za-z0-9_-]{16,}",
    r"\bgh[pousr]_[A-Za-z0-9]{20,}",
    r"\bgithub_pat_[A-Za-z0-9_]{20,}",
    r"\bxox[abprs]-[A-Za-z0-9-]{10,}",
    r"\b(AKIA|ASIA)[A-Z0-9]{16}\b",
    r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*",
    r"\b[A-Za-z0-9_-]{24,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{27,}\b",
    r"\b[A-Fa-f0-9]{32,}\b",
    r"\b[A-Za-z0-9+/_=-]{40,}\b",
]
def redact(s):
    for p in SECRET:
        if "(token|secret" in p:
            s = re.sub(p, lambda m: m.group(1) + "=[REDACTED]", s)
        elif p.startswith("(?i)(authorization"):
            s = re.sub(p, lambda m: m.group(1) + "[REDACTED]", s)
        elif p.startswith("(?i)(--?"):
            s = re.sub(p, lambda m: m.group(1) + "[REDACTED]", s)
        elif p.startswith("://"):
            s = re.sub(p, "://[REDACTED]@", s)
        else:
            s = re.sub(p, "[REDACTED]", s)
    return s
def trunc(s, n):
    s = " ".join(s.split())
    return s if len(s) <= n else s[: n - 1] + "…"

host = "macOS" if os.uname().sysname == "Darwin" else "WSL"
parts = [p for p in cwd.rstrip("/").split("/") if p]
where = "/".join(parts[-2:]) if parts else "?"
name = ""
for k in ("session_name", "name", "title"):
    if isinstance(d.get(k), str) and d[k]:
        name = d[k]; break
tag = trunc(redact(name), 40) if name else sid[:8]

if ev == "PermissionRequest":
    tool = str(d.get("tool_name", "?"))
    ti = d.get("tool_input") or {}
    detail = ""
    if isinstance(ti, dict):
        for k in ("command", "file_path", "path", "url", "pattern", "query"):
            if isinstance(ti.get(k), str) and ti[k]:
                detail = ti[k]; break
        if not detail and ti:
            detail = json.dumps(ti)
    head = "Approval needed"
    body = trunc(tool, 60) + (": " + trunc(redact(detail), 140) if detail else "")
elif ev == "Notification":
    nt = str(d.get("notification_type", ""))
    head = "Waiting for input" if nt in ("", "idle_prompt") else "Needs attention (" + trunc(nt, 30) + ")"
    body = trunc(redact(str(d.get("message", ""))), 140)
else:
    sys.exit(0)
msg = "[%s] %s - %s (%s)" % (host, head, where, tag)
if body:
    msg += "\n" + body
print(re.sub(r"[^A-Za-z0-9_-]", "_", sid))
print(msg)
'

if [ "${1:-}" = --message ]; then
  message_mode "${2:-}"
  exit $?
fi
main
exit 0
