#!/usr/bin/env python3
"""Wanderlog CLI — read/export trips via wanderlog.com's internal JSON API.

Auth model: a `connect.sid` Express session cookie (stable per session) plus an
`x-wl-user-id` header. The cookie is cached in ~/.config/wanderlog/session and
refreshed over plain HTTP via POST /api/user/login using credentials from
`pass personal/wanderlog` (line 1 = password, line 2 = `login: <email>`).

No browser required at runtime. A Google-SSO account needs a password set once
("Forgot password"); this logs in with email/password, which Google's headless
block does not touch.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import secrets
import socket
import ssl
import struct
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_ARCHIVE_DIR = Path.home() / "Github" / "personal-kb" / "travel" / "wanderlog"

BASE = "https://wanderlog.com"
SESSION_FILE = Path.home() / ".config" / "wanderlog" / "session"
PASS_ENTRY = "personal/wanderlog"
UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)


class AuthError(RuntimeError):
    pass


# --- session persistence -------------------------------------------------

def load_session() -> dict:
    if not SESSION_FILE.exists():
        return {}
    out = {}
    for line in SESSION_FILE.read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip()
    return out


def save_session(s: dict) -> None:
    SESSION_FILE.parent.mkdir(parents=True, exist_ok=True)
    body = "\n".join(f"{k}={v}" for k, v in s.items()) + "\n"
    SESSION_FILE.write_text(body)
    SESSION_FILE.chmod(0o600)


def pass_creds() -> tuple[str, str]:
    """Return (email, password) from `pass personal/wanderlog`."""
    try:
        raw = subprocess.run(
            ["pass", "show", PASS_ENTRY],
            capture_output=True, text=True, timeout=20, check=True,
        ).stdout
    except subprocess.CalledProcessError as e:
        raise AuthError(f"`pass show {PASS_ENTRY}` failed: {e.stderr.strip()}")
    except subprocess.TimeoutExpired:
        raise AuthError("`pass` timed out — unlock GPG first (run a `pass` cmd in your shell).")
    lines = [ln for ln in raw.splitlines() if ln.strip()]
    if not lines:
        raise AuthError(f"`{PASS_ENTRY}` is empty")
    password = lines[0].strip()
    email = ""
    for ln in lines[1:]:
        if ln.lower().startswith("login:"):
            email = ln.split(":", 1)[1].strip()
    if not email:
        raise AuthError(f"no `login: <email>` line in `{PASS_ENTRY}`")
    return email, password


# --- HTTP ----------------------------------------------------------------

def _request(method: str, path: str, session: dict, body: dict | None) -> tuple[int, dict, bytes]:
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("accept", "application/json")
    req.add_header("user-agent", UA)
    if body is not None:
        req.add_header("content-type", "application/json")
    if session.get("CONNECT_SID"):
        req.add_header("cookie", f"connect.sid={session['CONNECT_SID']}")
    if session.get("WL_USER_ID"):
        req.add_header("x-wl-user-id", session["WL_USER_ID"])
    if session.get("WL_ANON_ID"):
        req.add_header("x-wl-anonymous-id", session["WL_ANON_ID"])
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def _looks_unauthed(status: int, raw: bytes) -> bool:
    if status in (401, 403):
        return True
    text = raw[:200].lstrip()
    if text.startswith(b"<"):  # SPA HTML instead of JSON => no session
        return True
    try:
        j = json.loads(raw)
    except Exception:
        return False
    if isinstance(j, dict) and j.get("success") is False:
        msg = " ".join(j.get("messages", [])).lower() + str(j.get("error", "")).lower()
        return "too old" in msg or "log in" in msg or "logged in" in msg
    return False


def api(method: str, path: str, session: dict, body: dict | None = None,
        *, allow_refresh: bool = True) -> dict:
    """Call the API, auto-refreshing the cookie once on auth failure."""
    status, _, raw = _request(method, path, session, body)
    if _looks_unauthed(status, raw) and allow_refresh:
        refresh(session)
        status, _, raw = _request(method, path, session, body)
    if _looks_unauthed(status, raw):
        raise AuthError(f"{method} {path}: not authenticated after refresh (HTTP {status})")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        raise RuntimeError(f"{method} {path}: non-JSON response (HTTP {status}): {raw[:120]!r}")


def refresh(session: dict) -> dict:
    """Log in via email/password, update session in place + on disk."""
    email, password = pass_creds()
    status, headers, raw = _request(
        "POST", "/api/user/login", {"WL_ANON_ID": session.get("WL_ANON_ID", "")},
        {"email": email, "password": password},
    )
    j = json.loads(raw) if raw[:1] in (b"{", b"[") else {}
    if status != 200 or j.get("success") is False:
        raise AuthError(f"login failed (HTTP {status}): {raw[:160]!r}")
    sid = _extract_sid(headers.get("Set-Cookie", ""))
    if sid:
        session["CONNECT_SID"] = sid
    data = j.get("data") or {}
    user = j.get("user", {}).get("id") or data.get("id") or (data.get("user") or {}).get("id")
    if user:
        session["WL_USER_ID"] = str(user)
    save_session(session)
    return session


def _extract_sid(set_cookie: str) -> str:
    for part in set_cookie.split(","):
        if "connect.sid=" in part:
            return part.split("connect.sid=", 1)[1].split(";", 1)[0]
    return ""


# --- Quill-delta + formatting helpers ------------------------------------

def delta_text(node: dict | None) -> str:
    if not node or "ops" not in node:
        return ""
    return "".join(op.get("insert", "") for op in node["ops"] if isinstance(op.get("insert"), str)).strip()


# --- write helpers: geo/place lookup -------------------------------------

def geo_search(query: str, session: dict) -> dict:
    """Resolve a destination name to a Wanderlog geo (needs `id` for trip create)."""
    enc = urllib.parse.quote(query)
    data = api("GET", f"/api/geo/autocomplete/{enc}", session).get("data") or []
    if not data:
        raise RuntimeError(f"no geo match for {query!r}")
    return data[0]


def place_search(query: str, session: dict, *, lat: float | None = None, lng: float | None = None) -> dict:
    """Autocomplete a place query -> first prediction (carries `place_id`).

    lat/lng bias the search; default from WL_LAT/WL_LNG env, else 0,0.
    """
    lat = float(os.environ.get("WL_LAT", 0)) if lat is None else lat
    lng = float(os.environ.get("WL_LNG", 0)) if lng is None else lng
    req = {
        "input": query, "sessiontoken": str(_uuid4()),
        "location": {"longitude": lng, "latitude": lat},
        "radius": 27116, "language": "en",
    }
    enc = urllib.parse.quote(json.dumps(req))
    data = api("GET", f"/api/placesAPI/autocomplete/v2?request={enc}", session).get("data") or []
    if not data:
        raise RuntimeError(f"no place match for {query!r}")
    return data[0]


def place_details(place_id: str, session: dict) -> dict:
    """Full Google-place object for a place_id (the shape a `place` block needs)."""
    j = api("GET", f"/api/placesAPI/getPlaceDetails/v2?placeId={place_id}&language=en", session)
    place = j.get("data")
    if not place or not place.get("place_id"):
        raise RuntimeError(f"no place details for {place_id!r}")
    return place


def _uuid4() -> str:
    b = bytearray(secrets.token_bytes(16))
    b[6] = (b[6] & 0x0F) | 0x40
    b[8] = (b[8] & 0x3F) | 0x80
    h = b.hex()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


# --- write helpers: ShareDB (sharejs JSONv0) websocket -------------------

class WSError(RuntimeError):
    pass


def _ws_connect(key: str, session: dict) -> socket.socket:
    """Open the collaborative-edit websocket for a trip and run the HTTP upgrade."""
    qs = urllib.parse.urlencode({
        "X-WL-User-ID": session.get("WL_USER_ID", ""),
        "X-WL-Anonymous-ID": session.get("WL_ANON_ID", ""),
        "clientSchemaVersion": "2",
    })
    path = f"/api/tripPlans/wsOverall/{key}?{qs}"
    raw = socket.create_connection(("wanderlog.com", 443), timeout=30)
    sock = ssl.create_default_context().wrap_socket(raw, server_hostname="wanderlog.com")
    skey = base64.b64encode(secrets.token_bytes(16)).decode()
    cookie = f"connect.sid={session['CONNECT_SID']}"
    req = (
        f"GET {path} HTTP/1.1\r\nHost: wanderlog.com\r\nUpgrade: websocket\r\n"
        f"Connection: Upgrade\r\nSec-WebSocket-Key: {skey}\r\nSec-WebSocket-Version: 13\r\n"
        f"Origin: {BASE}\r\nCookie: {cookie}\r\nUser-Agent: {UA}\r\n\r\n"
    )
    sock.sendall(req.encode())
    head = _read_until(sock, b"\r\n\r\n")
    if b" 101 " not in head.split(b"\r\n", 1)[0]:
        sock.close()
        raise WSError(f"websocket upgrade failed: {head[:120]!r}")
    return sock


def _read_until(sock: socket.socket, marker: bytes) -> bytes:
    buf = b""
    while marker not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise WSError("connection closed during handshake")
        buf += chunk
    return buf


def _ws_send(sock: socket.socket, payload: dict) -> None:
    data = json.dumps(payload).encode()
    header = bytearray([0x81])  # FIN + text frame
    mask = secrets.token_bytes(4)
    n = len(data)
    if n < 126:
        header.append(0x80 | n)
    elif n < 65536:
        header.append(0x80 | 126)
        header += struct.pack(">H", n)
    else:
        header.append(0x80 | 127)
        header += struct.pack(">Q", n)
    header += mask
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    sock.sendall(bytes(header) + masked)


def _ws_recv(sock: socket.socket) -> dict:
    """Read one server text frame (server frames are unmasked) -> parsed JSON."""
    b0, b1 = _recv_exact(sock, 2)
    length = b1 & 0x7F
    if length == 126:
        length = struct.unpack(">H", _recv_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack(">Q", _recv_exact(sock, 8))[0]
    payload = _recv_exact(sock, length) if length else b""
    if (b0 & 0x0F) == 0x8:  # close frame
        raise WSError("server closed websocket")
    return json.loads(payload) if payload else {}


def _recv_exact(sock: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise WSError("connection closed mid-frame")
        buf += chunk
    return buf


def _ws_subscribe(sock: socket.socket, key: str) -> dict:
    """Handshake + subscribe; return the trip-plan snapshot ({v, data})."""
    _ws_send(sock, {"a": "hs", "id": None, "protocol": 1, "protocolMinor": 2})
    _ws_send(sock, {"a": "s", "c": "TripPlans", "d": key})
    for _ in range(20):
        msg = _ws_recv(sock)
        if isinstance(msg.get("data"), dict) and "v" in msg["data"]:
            return msg["data"]
    raise WSError("never received trip-plan snapshot")


def _section_index(snapshot: dict, heading: str) -> tuple[int, int]:
    """Return (section index, block count) for the section with `heading`."""
    sections = (((snapshot.get("data") or {}).get("itinerary") or {}).get("sections")) or []
    for i, sec in enumerate(sections):
        if sec.get("heading") == heading:
            return i, len(sec.get("blocks") or [])
    raise WSError(f"section {heading!r} not found in trip")


def ws_append_block(key: str, block: dict, session: dict, *, heading: str = "Places to visit") -> None:
    """Open the trip socket and list-insert `block` at the end of a section."""
    sock = _ws_connect(key, session)
    try:
        snap = _ws_subscribe(sock, key)
        sec_idx, blk_idx = _section_index(snap, heading)
        op = {
            "a": "op", "c": "TripPlans", "d": key,
            "v": snap["v"], "seq": 1, "x": {},
            "op": [{"p": ["itinerary", "sections", sec_idx, "blocks", blk_idx], "li": block}],
        }
        _ws_send(sock, op)
        for _ in range(20):
            ack = _ws_recv(sock)
            if ack.get("a") == "op" and ack.get("seq") == 1:
                if ack.get("error"):
                    raise WSError(f"op rejected: {ack['error']}")
                return
            if ack.get("error"):
                raise WSError(f"op rejected: {ack['error']}")
        raise WSError("no ack for op")
    finally:
        sock.close()


def _place_block(place: dict, session: dict) -> dict:
    return {
        "id": secrets.randbelow(900_000_000) + 100_000_000,
        "type": "place", "place": place,
        "text": {"ops": [{"insert": "\n"}]},
        "addedBy": {"type": "user", "userId": int(session.get("WL_USER_ID", 0))},
    }


def _note_block(text: str, session: dict) -> dict:
    return {
        "id": secrets.randbelow(900_000_000) + 100_000_000,
        "type": "note",
        "text": {"ops": [{"insert": f"{text}\n"}]},
        "addedBy": {"type": "user", "userId": int(session.get("WL_USER_ID", 0))},
        "attachments": [],
    }


# --- commands ------------------------------------------------------------

def cmd_trips(session: dict, args) -> None:
    data = api("GET", "/api/tripPlans", session)["data"]
    if args.json:
        print(json.dumps(data, indent=2))
        return
    for t in data:
        dates = " ".join(filter(None, [t.get("startDate"), t.get("endDate")]))
        print(f"{t['key']:18}  {t.get('title') or '(untitled)':40}  "
              f"{t.get('placeCount', 0):>4} places  {dates}")


def cmd_places(session: dict, args) -> None:
    data = api("GET", f"/api/tripPlans/{args.key}/places", session)["data"]
    print(json.dumps(data, indent=2))


def _build_export_md(meta: dict, data: dict, key: str) -> str:
    """Build markdown export string from trip meta and places data."""
    pm = {p.get("placeId"): p for p in (data.get("placeMetadata") or []) if p.get("placeId")}
    lines = [f"# {meta.get('title') or key}", ""]
    dates = " – ".join(filter(None, [meta.get("startDate"), meta.get("endDate")]))
    if dates:
        lines += [f"_{dates}_", ""]
    for sec in data.get("sections", []):
        heading = sec.get("heading") or ""
        if heading:
            lines += [f"## {heading}", ""]
        notes = delta_text(sec.get("text"))
        if notes:
            lines += [notes, ""]
        for blk in sec.get("blocks", []):
            lines.append(_render_block(blk, pm))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def cmd_export(session: dict, args) -> None:
    trips = {t["key"]: t for t in api("GET", "/api/tripPlans", session)["data"]}
    meta = trips.get(args.key, {})
    data = api("GET", f"/api/tripPlans/{args.key}/places", session)["data"]
    print(_build_export_md(meta, data, args.key))


def _render_block(blk: dict, pm: dict) -> str:
    btype = blk.get("type")
    note = delta_text(blk.get("text"))
    if btype == "place":
        pl = blk.get("place", {}) or {}
        bits = [f"- **{pl.get('name') or 'Unnamed place'}**"]
        if pl.get("formatted_address"):
            bits.append(f"  {pl['formatted_address']}")
        if pl.get("rating"):
            bits.append(f"  ⭐ {pl['rating']} ({pl.get('user_ratings_total', 0)})")
        if pl.get("website"):
            bits.append(f"  {pl['website']}")
        if not note:
            extra = pm.get(pl.get("place_id"), {})
            note = (extra.get("generatedDescription") or "").strip()
        if note:
            bits.append(f"  _{note}_")
        return "\n".join(bits)
    if btype == "flight":
        fi = blk.get("flightInfo", {})
        air = fi.get("airline", {}).get("name", "")
        dep = blk.get("depart", {}).get("airport", {}).get("iata", "")
        arr = blk.get("arrive", {}).get("airport", {}).get("iata", "")
        return f"- ✈️  {air} {fi.get('number', '')}  {dep} → {arr}".rstrip()
    return f"- {note}" if note else f"- ({btype})"


def _extract_destinations(meta: dict, data: dict) -> list[str]:
    """Return a deduped ordered list of city/region names for a trip."""
    seen: dict[str, None] = {}
    # trip-level geos from the listing metadata
    for geo in meta.get("geos") or []:
        name = geo.get("name") or geo.get("city") or geo.get("region") or ""
        if name and name not in seen:
            seen[name] = None
    # fall back to place-level locality / admin-area from the places data
    for sec in data.get("sections", []):
        for blk in sec.get("blocks", []):
            pl = blk.get("place") or {}
            for comp in pl.get("address_components") or []:
                types = comp.get("types") or []
                if "locality" in types or "administrative_area_level_1" in types:
                    name = comp.get("long_name") or ""
                    if name and name not in seen:
                        seen[name] = None
    return list(seen.keys())


def cmd_archive(session: dict, args) -> None:
    """Scrape all trips and write markdown + raw JSON to a local directory."""
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    trips = api("GET", "/api/tripPlans", session)["data"]
    index = []
    failed = []
    for trip in trips:
        key = trip["key"]
        title = trip.get("title") or "(untitled)"
        try:
            data = api("GET", f"/api/tripPlans/{key}/places", session)["data"]
            trip_dir = out_dir / key
            trip_dir.mkdir(parents=True, exist_ok=True)
            (trip_dir / "trip.md").write_text(_build_export_md(trip, data, key))
            (trip_dir / "raw.json").write_text(json.dumps(data, indent=2))
            destinations = _extract_destinations(trip, data)
            place_count = sum(
                1 for sec in data.get("sections", [])
                for blk in sec.get("blocks", [])
                if blk.get("type") == "place"
            )
            index.append({
                "key": key,
                "title": title,
                "start_date": trip.get("startDate") or None,
                "end_date": trip.get("endDate") or None,
                "destinations": destinations,
                "place_count": place_count,
            })
            print(f"  {key}  {title[:40]:<40}  {place_count:>3} places")
        except Exception as exc:
            print(f"ERROR {key} ({title}): {exc}", file=sys.stderr)
            failed.append(key)
    (out_dir / "index.json").write_text(json.dumps(index, indent=2))
    total_places = sum(t["place_count"] for t in index)
    print(f"\narchived {len(index)} trips, {total_places} places -> {out_dir}")
    if failed:
        print(f"FAILED: {', '.join(failed)}", file=sys.stderr)
        sys.exit(1)


def cmd_trip_create(session: dict, args) -> None:
    geo = geo_search(args.title, session)
    body = {
        "geoIds": [geo["id"]], "initialMapsPlaceIds": [], "initialEmailId": None,
        "type": "plan", "startDate": args.start, "endDate": args.end,
        "privacy": "friends", "isMapEmbed": False, "title": args.title,
        "autogenerateItineraryOptions": None, "language": "en",
    }
    j = api("POST", "/api/tripPlans", session, body)
    if not j.get("success"):
        raise RuntimeError(f"trip create failed: {j.get('messages') or j}")
    key = (j.get("data") or {}).get("key")
    if not key:
        raise RuntimeError(f"trip created but no key returned: {j}")
    print(key)


def cmd_place_add(session: dict, args) -> None:
    pred = place_search(args.query, session)
    place = place_details(pred["place_id"], session)
    ws_append_block(args.key, _place_block(place, session), session)
    print(f"added place '{place.get('name')}' to trip {args.key}")


def cmd_note_add(session: dict, args) -> None:
    ws_append_block(args.key, _note_block(args.text, session), session)
    print(f"added note to trip {args.key}")


def cmd_refresh(session: dict, args) -> None:
    refresh(session)
    api("GET", "/api/user/emails", session)  # smoke-test the new cookie
    print(f"refreshed — session valid for user {session.get('WL_USER_ID')}")


def cmd_raw(session: dict, args) -> None:
    body = json.loads(args.body) if args.body else None
    print(json.dumps(api(args.method, args.path, session, body), indent=2))


def main() -> int:
    ap = argparse.ArgumentParser(prog="wl", description="Wanderlog CLI")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("trips", help="list your trips")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_trips)
    p = sub.add_parser("places", help="raw places JSON for a trip")
    p.add_argument("key")
    p.set_defaults(fn=cmd_places)
    p = sub.add_parser("export", help="markdown export of a trip")
    p.add_argument("key")
    p.set_defaults(fn=cmd_export)
    p = sub.add_parser("archive", help="backup all trips to a local directory")
    p.add_argument("--out", default=str(DEFAULT_ARCHIVE_DIR),
                   help="output directory (default: ~/Github/personal-kb/travel/wanderlog)")
    p.set_defaults(fn=cmd_archive)
    p = sub.add_parser("trip-create", help="create a new trip; prints its key")
    p.add_argument("title")
    p.add_argument("--start", default=None, help="start date YYYY-MM-DD")
    p.add_argument("--end", default=None, help="end date YYYY-MM-DD")
    p.set_defaults(fn=cmd_trip_create)
    p = sub.add_parser("place-add", help="resolve a place query and add it to a trip")
    p.add_argument("key")
    p.add_argument("query")
    p.set_defaults(fn=cmd_place_add)
    p = sub.add_parser("note-add", help="add a free-text note block to a trip")
    p.add_argument("key")
    p.add_argument("text")
    p.set_defaults(fn=cmd_note_add)
    p = sub.add_parser("refresh", help="force a cookie refresh via login")
    p.set_defaults(fn=cmd_refresh)
    p = sub.add_parser("raw", help="raw API call")
    p.add_argument("path")
    p.add_argument("--method", default="GET")
    p.add_argument("--body", default="")
    p.set_defaults(fn=cmd_raw)
    args = ap.parse_args()
    session = load_session()
    try:
        args.fn(session, args)
    except AuthError as e:
        print(f"auth error: {e}", file=sys.stderr)
        return 2
    except (WSError, RuntimeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
