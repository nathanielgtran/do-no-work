---
name: wanderlog
description: Read, export, archive, and edit Wanderlog trips via wanderlog.com's internal JSON API. Use when the user wants to list their Wanderlog trips, pull an itinerary/places into context, export a trip to markdown, back up all trips locally, create trips, or add places/notes. Trip-planning, travel itinerary, "my Wanderlog", saved places.
---

# Wanderlog

Drives [wanderlog.com](https://wanderlog.com) through its internal JSON API
(`wanderlog.com/api/*`, an Express backend). Authentication is a `connect.sid`
session cookie cached at `~/.config/wanderlog/session`, auto-refreshed over
plain HTTP (`POST /api/user/login`) using credentials from
`pass personal/wanderlog`. No browser needed at runtime.

## CLI

Run `python3 ~/.claude/skills/wanderlog/wl.py <cmd>`:

| Command | What it does |
|---|---|
| `trips` | List your trips (key, title, place count, dates). Add `--json` for raw. |
| `export <key>` | Markdown export of a trip (flights, hotels, places w/ address, rating, notes). |
| `places <key>` | Raw `places` JSON for a trip (sections + placeMetadata). |
| `archive [--out DIR]` | Backup ALL trips to a local directory as `trip.md` + `raw.json` per trip, plus an `index.json` summary. Default: `~/Github/personal-kb/travel/wanderlog`. Idempotent — re-running overwrites. |
| `trip-create <title> [--start D] [--end D]` | Create a trip (resolves a geo from the title); prints the new key. |
| `place-add <key> "<query>"` | Resolve a place by search and append it to the trip's "Places to visit" list. |
| `note-add <key> "<text>"` | Append a free-text note block to the trip. |
| `refresh` | Force a cookie refresh via login (needs GPG unlocked for `pass`). |
| `raw <path> [--method M] [--body JSON]` | Arbitrary authenticated API call. |

`<key>` is the trip key from `trips` (e.g. `abcdefghijklmnop`), i.e. the slug in
`wanderlog.com/plan/<key>/...`.

### `archive` output layout

```
<DIR>/
  index.json          # one object per trip: {key, title, start_date, end_date, destinations, place_count}
  <key>/
    trip.md           # same markdown as `export`
    raw.json          # raw /places JSON, pretty-printed
```

`index.json` schema (contract consumed by other tools):
```json
{"key": "...", "title": "...", "start_date": "YYYY-MM-DD|null", "end_date": "YYYY-MM-DD|null",
 "destinations": ["City", ...], "place_count": 42}
```
`destinations` is derived first from trip-level `geos`, then falls back to `locality`/`administrative_area_level_1`
address components on individual places. Deduped, order-preserving.

## Auth notes

- The session cookie is long-lived; on any auth failure the CLI auto-runs
  `refresh` once and retries.
- `refresh` reads `pass personal/wanderlog` (line 1 = password,
  line 2 = `login: <email>`). `pass` needs GPG unlocked — if it times out,
  run any `pass` command in a real shell first (GPG agent caches ~1h), or have
  the user run `! cd ~/.claude/skills/wanderlog && python3 wl.py refresh`.
- For a Google-SSO account, set a password once via "Forgot password" so
  email/password login works (Google's headless-browser block does not apply
  to Wanderlog's own login form).

## API map (verified)

- `GET /api/tripPlans` — list my trips.
- `GET /api/tripPlans/{key}/places` — full itinerary content: `sections[]`
  (each with `heading`, `text` Quill-delta notes, `blocks[]`) and
  `placeMetadata[]`. Block types seen: `place` (carries inline `block.place`
  Google-place object), `flight` (`block.flightInfo` + depart/arrive), `note`.
- `POST /api/user/login` `{email,password}` — returns `Set-Cookie: connect.sid`
  and `{success, user:{id}}`.
- `GET /api/user/emails`, `/api/user/loginToken` — auth smoke-test endpoints.
- Gotcha: `GET /api/tripPlans/{key}` (single, version-gated) rejects with
  "app too old" regardless of headers — **do not use it**; `/places` is the
  ungated read path.
- Rich text everywhere is Quill-delta (`{ops:[{insert:"..."}]}`).

## Write API (verified, reverse-engineered)

**Create trip** — `POST /api/tripPlans` with body:
```json
{"geoIds":[<geoId>],"initialMapsPlaceIds":[],"initialEmailId":null,"type":"plan",
 "startDate":null,"endDate":null,"privacy":"friends","isMapEmbed":false,
 "title":"...","autogenerateItineraryOptions":null,"language":"en"}
```
A trip MUST have ≥1 geo (`{"errTypes":["noGeosForTripPlan"]}` otherwise). Resolve
the geo id from `GET /api/geo/autocomplete/{query}` (returns `[{id, name, ...}]`).
Response: `{"success":true,"data":{"key","viewKey","id","title"}}`.

**Place search** — `GET /api/placesAPI/autocomplete/v2?request=<json-url-encoded>`,
request = `{input, sessiontoken(uuid), location:{longitude,latitude}, radius, language}`.
Returns predictions each with a Google `place_id`. `location`+`radius` are required.

**Place details** — `GET /api/placesAPI/getPlaceDetails/v2?placeId=<id>&language=en`
→ `{success, data:{name, place_id, geometry, formatted_address, rating, …}}`, i.e.
the exact Google-place object a `place` block needs.

**Add place / note / any block** — there is **no REST write path** (all
`POST /api/tripPlans/{key}/...` 404). Edits go over a **ShareDB / sharejs JSONv0
collaborative websocket**:
- URL: `wss://wanderlog.com/api/tripPlans/wsOverall/{key}?X-WL-User-ID=<uid>&X-WL-Anonymous-ID=<anon>&clientSchemaVersion=2`
  (auth is the `connect.sid` cookie on the upgrade request).
- Handshake: send `{"a":"hs","id":null,"protocol":1,"protocolMinor":2}`, then
  subscribe `{"a":"s","c":"TripPlans","d":"{key}"}`. Server returns a snapshot
  `{"data":{"v":<version>,"data":{itinerary:{sections:[…]}}}}`.
- Append a block (list-insert at the end of a section):
  ```json
  {"a":"op","c":"TripPlans","d":"{key}","v":<version>,"seq":<n>,"x":{},
   "op":[{"p":["itinerary","sections",<secIdx>,"blocks",<blockCount>],"li":<block>}]}
  ```
  Ack is `{"a":"op","seq":<n>,"v":<version>,...}` (an `error` field = rejected).
- `<secIdx>` is the section index in the **websocket snapshot** (which includes the
  empty "Notes" section), NOT the filtered `/places` read. `wl.py` matches by heading.
- Block shapes:
  - place: `{"id":<rand int>,"type":"place","place":{…details…},"text":{"ops":[{"insert":"\n"}]},"addedBy":{"type":"user","userId":<uid>}}`
  - note: `{"id":<rand int>,"type":"note","text":{"ops":[{"insert":"<text>\n"}]},"addedBy":{"type":"user","userId":<uid>},"attachments":[]}`

`wl.py` implements the websocket client in pure stdlib (`socket`+`ssl`, manual WS
framing) — no third-party deps. `WL_ANON_ID` and `WL_USER_ID` come from the session
file.

**Delete trip** — `DELETE /api/tripPlans/{key}` → `{"success":true}`. (Not wired
into the CLI to avoid accidental destructive use; call via `wl raw` if needed.)
