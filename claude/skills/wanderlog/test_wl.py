"""Unit tests for wl.py. Run: python3 -m unittest test_wl"""
import importlib.util
import json
import unittest
from pathlib import Path
from unittest import mock

_spec = importlib.util.spec_from_file_location("wl", Path(__file__).parent / "wl.py")
wl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wl)


class DeltaText(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(wl.delta_text({"ops": [{"insert": "hello\n"}]}), "hello")

    def test_none_and_empty(self):
        self.assertEqual(wl.delta_text(None), "")
        self.assertEqual(wl.delta_text({}), "")

    def test_skips_non_string_inserts(self):
        node = {"ops": [{"insert": "a"}, {"insert": {"image": 1}}, {"insert": "b\n"}]}
        self.assertEqual(wl.delta_text(node), "ab")


class ExtractSid(unittest.TestCase):
    def test_single(self):
        self.assertEqual(wl._extract_sid("connect.sid=abc123; Path=/; HttpOnly"), "abc123")

    def test_comma_joined_cookies(self):
        sc = "other=1; Path=/, connect.sid=s%3Axyz; Path=/; HttpOnly"
        self.assertEqual(wl._extract_sid(sc), "s%3Axyz")

    def test_absent(self):
        self.assertEqual(wl._extract_sid("foo=bar; Path=/"), "")


class LooksUnauthed(unittest.TestCase):
    def test_http_codes(self):
        self.assertTrue(wl._looks_unauthed(401, b"{}"))
        self.assertTrue(wl._looks_unauthed(403, b"{}"))

    def test_html_body(self):
        self.assertTrue(wl._looks_unauthed(200, b"  <!DOCTYPE html><html>"))

    def test_version_gate_and_login_msgs(self):
        self.assertTrue(wl._looks_unauthed(200, b'{"success":false,"error":"app too old"}'))
        self.assertTrue(wl._looks_unauthed(200, b'{"success":false,"messages":["Please log in"]}'))

    def test_ok_and_non_auth_failure(self):
        self.assertFalse(wl._looks_unauthed(200, b'{"success":true,"data":[]}'))
        self.assertFalse(wl._looks_unauthed(200, b'{"success":false,"messages":["not found"]}'))


class RenderBlock(unittest.TestCase):
    def test_place(self):
        blk = {"type": "place", "place": {
            "name": "Lau Pa Sat", "formatted_address": "18 Raffles Quay",
            "rating": 4.3, "user_ratings_total": 29848, "website": "https://laupasat.sg/"}}
        out = wl._render_block(blk, {})
        self.assertIn("**Lau Pa Sat**", out)
        self.assertIn("18 Raffles Quay", out)
        self.assertIn("⭐ 4.3 (29848)", out)
        self.assertIn("laupasat.sg", out)

    def test_place_falls_back_to_generated_description(self):
        blk = {"type": "place", "place": {"name": "X", "place_id": "PID"}}
        pm = {"PID": {"generatedDescription": "A nice spot."}}
        self.assertIn("_A nice spot._", wl._render_block(blk, pm))

    def test_flight(self):
        blk = {"type": "flight", "flightInfo": {"airline": {"name": "Singapore Airlines"}, "number": 1},
               "depart": {"airport": {"iata": "SYD"}}, "arrive": {"airport": {"iata": "SIN"}}}
        self.assertEqual(wl._render_block(blk, {}), "- ✈️  Singapore Airlines 1  SYD → SIN")

    def test_note(self):
        blk = {"type": "note", "text": {"ops": [{"insert": "remember sunscreen\n"}]}}
        self.assertEqual(wl._render_block(blk, {}), "- remember sunscreen")


class SessionRoundtrip(unittest.TestCase):
    def test_save_load(self):
        with mock.patch.object(wl, "SESSION_FILE", Path("/tmp/wl_test_session")):
            wl.save_session({"CONNECT_SID": "abc", "WL_USER_ID": "42"})
            self.assertEqual(wl.SESSION_FILE.stat().st_mode & 0o777, 0o600)
            self.assertEqual(wl.load_session(), {"CONNECT_SID": "abc", "WL_USER_ID": "42"})
            wl.SESSION_FILE.unlink()

    def test_load_missing(self):
        with mock.patch.object(wl, "SESSION_FILE", Path("/tmp/wl_does_not_exist")):
            self.assertEqual(wl.load_session(), {})


class PassCreds(unittest.TestCase):
    def _run(self, stdout):
        return mock.patch("subprocess.run", return_value=mock.Mock(stdout=stdout))

    def test_ok(self):
        with self._run("secretpw\nlogin: a@b.com\n"):
            self.assertEqual(wl.pass_creds(), ("a@b.com", "secretpw"))

    def test_missing_login_raises(self):
        with self._run("secretpw\n"):
            with self.assertRaises(wl.AuthError):
                wl.pass_creds()

    def test_empty_raises(self):
        with self._run("\n  \n"):
            with self.assertRaises(wl.AuthError):
                wl.pass_creds()


class ApiRefresh(unittest.TestCase):
    def test_retries_once_on_unauth(self):
        calls = []

        def fake_request(method, path, session, body):
            calls.append(1)
            if len(calls) == 1:
                return 200, {}, b"<!DOCTYPE html>"  # unauthed
            return 200, {}, b'{"success":true,"data":[1]}'

        refreshed = []
        with mock.patch.object(wl, "_request", side_effect=fake_request), \
             mock.patch.object(wl, "refresh", side_effect=lambda s: refreshed.append(1)):
            out = wl.api("GET", "/api/tripPlans", {})
        self.assertEqual(out, {"success": True, "data": [1]})
        self.assertEqual(len(calls), 2)
        self.assertEqual(len(refreshed), 1)

    def test_raises_if_still_unauthed(self):
        with mock.patch.object(wl, "_request", return_value=(200, {}, b"<!DOCTYPE html>")), \
             mock.patch.object(wl, "refresh", side_effect=lambda s: None):
            with self.assertRaises(wl.AuthError):
                wl.api("GET", "/api/tripPlans", {})


class Refresh(unittest.TestCase):
    def test_updates_session_from_login(self):
        headers = {"Set-Cookie": "connect.sid=NEWSID; Path=/; HttpOnly"}
        body = b'{"success":true,"user":{"id":42}}'
        session = {"WL_ANON_ID": "anon"}
        with mock.patch.object(wl, "pass_creds", return_value=("a@b.com", "pw")), \
             mock.patch.object(wl, "_request", return_value=(200, headers, body)), \
             mock.patch.object(wl, "save_session"):
            wl.refresh(session)
        self.assertEqual(session["CONNECT_SID"], "NEWSID")
        self.assertEqual(session["WL_USER_ID"], "42")

    def test_login_failure_raises(self):
        with mock.patch.object(wl, "pass_creds", return_value=("a@b.com", "pw")), \
             mock.patch.object(wl, "_request", return_value=(401, {}, b'{"success":false}')):
            with self.assertRaises(wl.AuthError):
                wl.refresh({})


class Export(unittest.TestCase):
    def test_renders_markdown(self):
        trips = {"success": True, "data": [
            {"key": "k1", "title": "Trip to Lisbon", "startDate": "2030-01-10", "endDate": "2030-01-20"}]}
        places = {"success": True, "data": {"sections": [
            {"heading": "Flights", "text": {"ops": [{"insert": "\n"}]}, "blocks": [
                {"type": "flight", "flightInfo": {"airline": {"name": "SQ"}, "number": 1},
                 "depart": {"airport": {"iata": "SYD"}}, "arrive": {"airport": {"iata": "SIN"}}}]},
            {"heading": "Food", "text": {"ops": [{"insert": "eat well\n"}]}, "blocks": [
                {"type": "place", "place": {"name": "Lau Pa Sat", "formatted_address": "18 Raffles Quay"}}]}],
            "placeMetadata": []}}

        def fake_api(method, path, session, body=None, **kw):
            return trips if path == "/api/tripPlans" else places

        args = mock.Mock(key="k1")
        with mock.patch.object(wl, "api", side_effect=fake_api), \
             mock.patch("builtins.print") as p:
            wl.cmd_export({}, args)
        out = "\n".join(str(c.args[0]) for c in p.call_args_list)
        self.assertIn("# Trip to Lisbon", out)
        self.assertIn("2030-01-10 – 2030-01-20", out)
        self.assertIn("## Flights", out)
        self.assertIn("SQ 1  SYD → SIN", out)
        self.assertIn("## Food", out)
        self.assertIn("eat well", out)
        self.assertIn("**Lau Pa Sat**", out)


class TripCreate(unittest.TestCase):
    def test_builds_request_and_prints_key(self):
        calls = {}

        def fake_api(method, path, session, body=None, **kw):
            if path.startswith("/api/geo/autocomplete/"):
                return {"data": [{"id": 7, "name": "Singapore"}]}
            calls["create"] = (method, path, body)
            return {"success": True, "data": {"key": "newkey123"}}

        args = mock.Mock(title="Trip X", start="2026-07-01", end="2026-07-05")
        with mock.patch.object(wl, "api", side_effect=fake_api), \
             mock.patch("builtins.print") as p:
            wl.cmd_trip_create({}, args)
        method, path, body = calls["create"]
        self.assertEqual((method, path), ("POST", "/api/tripPlans"))
        self.assertEqual(body["geoIds"], [7])
        self.assertEqual(body["title"], "Trip X")
        self.assertEqual(body["startDate"], "2026-07-01")
        self.assertEqual(body["endDate"], "2026-07-05")
        self.assertEqual(body["type"], "plan")
        p.assert_called_once_with("newkey123")

    def test_failure_raises(self):
        def fake_api(method, path, session, body=None, **kw):
            if path.startswith("/api/geo/"):
                return {"data": [{"id": 7}]}
            return {"success": False, "messages": ["nope"]}

        args = mock.Mock(title="T", start=None, end=None)
        with mock.patch.object(wl, "api", side_effect=fake_api):
            with self.assertRaises(RuntimeError):
                wl.cmd_trip_create({}, args)

    def test_no_geo_match_raises(self):
        with mock.patch.object(wl, "api", return_value={"data": []}):
            with self.assertRaises(RuntimeError):
                wl.geo_search("zzz", {})


class PlaceLookup(unittest.TestCase):
    def test_place_search_returns_first(self):
        resp = {"data": [{"place_id": "P1"}, {"place_id": "P2"}]}
        with mock.patch.object(wl, "api", return_value=resp):
            self.assertEqual(wl.place_search("zoo", {})["place_id"], "P1")

    def test_place_search_empty_raises(self):
        with mock.patch.object(wl, "api", return_value={"data": []}):
            with self.assertRaises(RuntimeError):
                wl.place_search("zoo", {})

    def test_place_details_validates_place_id(self):
        with mock.patch.object(wl, "api", return_value={"data": {"name": "X"}}):
            with self.assertRaises(RuntimeError):
                wl.place_details("P1", {})

    def test_uuid4_format(self):
        u = wl._uuid4()
        parts = u.split("-")
        self.assertEqual([len(p) for p in parts], [8, 4, 4, 4, 12])
        self.assertEqual(u[14], "4")  # version nibble


class BlockBuilders(unittest.TestCase):
    def test_place_block(self):
        blk = wl._place_block({"name": "Zoo", "place_id": "P1"}, {"WL_USER_ID": "42"})
        self.assertEqual(blk["type"], "place")
        self.assertEqual(blk["place"]["name"], "Zoo")
        self.assertEqual(blk["addedBy"], {"type": "user", "userId": 42})
        self.assertEqual(blk["text"], {"ops": [{"insert": "\n"}]})
        self.assertIsInstance(blk["id"], int)

    def test_note_block(self):
        blk = wl._note_block("hi there", {"WL_USER_ID": "42"})
        self.assertEqual(blk["type"], "note")
        self.assertEqual(blk["text"], {"ops": [{"insert": "hi there\n"}]})
        self.assertEqual(blk["attachments"], [])
        self.assertEqual(blk["addedBy"]["userId"], 42)


class SectionIndex(unittest.TestCase):
    SNAP = {"v": 4, "data": {"itinerary": {"sections": [
        {"heading": "Notes", "blocks": []},
        {"heading": "Places to visit", "blocks": [{"id": 1}, {"id": 2}]},
    ]}}}

    def test_finds_section_and_block_count(self):
        self.assertEqual(wl._section_index(self.SNAP, "Places to visit"), (1, 2))
        self.assertEqual(wl._section_index(self.SNAP, "Notes"), (0, 0))

    def test_missing_section_raises(self):
        with self.assertRaises(wl.WSError):
            wl._section_index(self.SNAP, "Nonexistent")


class WSFraming(unittest.TestCase):
    def test_send_then_recv_roundtrip(self):
        sent = bytearray()
        sock = mock.Mock()
        sock.sendall.side_effect = sent.extend
        wl._ws_send(sock, {"a": "op", "n": 1})
        # client frame is masked; decode it as the server would, then re-emit unmasked
        self.assertEqual(sent[0], 0x81)
        masklen = sent[1] & 0x7F
        self.assertTrue(sent[1] & 0x80)  # mask bit set
        mask = sent[2:6]
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(sent[6:6 + masklen]))
        self.assertEqual(json.loads(payload), {"a": "op", "n": 1})

    def test_recv_parses_unmasked_text_frame(self):
        body = json.dumps({"a": "op", "seq": 1, "v": 4}).encode()
        frame = bytes([0x81, len(body)]) + body
        chunks = [frame[:2], frame[2:]]
        sock = mock.Mock()
        sock.recv.side_effect = lambda n: chunks.pop(0)
        self.assertEqual(wl._ws_recv(sock), {"a": "op", "seq": 1, "v": 4})

    def test_recv_close_frame_raises(self):
        sock = mock.Mock()
        sock.recv.side_effect = [bytes([0x88, 0])]
        with self.assertRaises(wl.WSError):
            wl._ws_recv(sock)


class WSAppendBlock(unittest.TestCase):
    def test_builds_op_at_section_end(self):
        snap = {"v": 7, "data": {"itinerary": {"sections": [
            {"heading": "Places to visit", "blocks": [{"id": 1}]}]}}}
        captured = {}

        def fake_subscribe(sock, key):
            return snap

        def fake_send(sock, payload):
            if payload.get("a") == "op":
                captured["op"] = payload

        recvs = iter([{"a": "op", "seq": 1, "v": 7, "d": "k"}])

        with mock.patch.object(wl, "_ws_connect", return_value=mock.Mock()), \
             mock.patch.object(wl, "_ws_subscribe", side_effect=fake_subscribe), \
             mock.patch.object(wl, "_ws_send", side_effect=fake_send), \
             mock.patch.object(wl, "_ws_recv", side_effect=lambda s: next(recvs)):
            wl.ws_append_block("k", {"id": 99, "type": "note"}, {"WL_USER_ID": "1"})

        op = captured["op"]
        self.assertEqual(op["v"], 7)
        self.assertEqual(op["d"], "k")
        self.assertEqual(op["op"][0]["p"], ["itinerary", "sections", 0, "blocks", 1])
        self.assertEqual(op["op"][0]["li"], {"id": 99, "type": "note"})

    def test_rejected_op_raises(self):
        snap = {"v": 1, "data": {"itinerary": {"sections": [
            {"heading": "Places to visit", "blocks": []}]}}}
        with mock.patch.object(wl, "_ws_connect", return_value=mock.Mock()), \
             mock.patch.object(wl, "_ws_subscribe", return_value=snap), \
             mock.patch.object(wl, "_ws_send"), \
             mock.patch.object(wl, "_ws_recv", return_value={"a": "op", "seq": 1, "error": "boom"}):
            with self.assertRaises(wl.WSError):
                wl.ws_append_block("k", {"id": 1}, {})


class PlaceAddCommand(unittest.TestCase):
    def test_resolves_and_appends(self):
        flow = {}
        with mock.patch.object(wl, "place_search", return_value={"place_id": "P1"}), \
             mock.patch.object(wl, "place_details", return_value={"name": "Zoo", "place_id": "P1"}), \
             mock.patch.object(wl, "ws_append_block",
                               side_effect=lambda k, b, s, **kw: flow.update(key=k, block=b)), \
             mock.patch("builtins.print"):
            wl.cmd_place_add({"WL_USER_ID": "42"}, mock.Mock(key="trip1", query="zoo"))
        self.assertEqual(flow["key"], "trip1")
        self.assertEqual(flow["block"]["type"], "place")
        self.assertEqual(flow["block"]["place"]["name"], "Zoo")

    def test_note_add_command(self):
        flow = {}
        with mock.patch.object(wl, "ws_append_block",
                               side_effect=lambda k, b, s, **kw: flow.update(key=k, block=b)), \
             mock.patch("builtins.print"):
            wl.cmd_note_add({"WL_USER_ID": "42"}, mock.Mock(key="trip1", text="hi"))
        self.assertEqual(flow["block"]["type"], "note")
        self.assertEqual(flow["block"]["text"], {"ops": [{"insert": "hi\n"}]})


class BuildExportMd(unittest.TestCase):
    TRIP_META = {"key": "k1", "title": "Tokyo Trip", "startDate": "2025-03-01", "endDate": "2025-03-10"}
    PLACES_DATA = {
        "sections": [
            {"heading": "Food", "text": None, "blocks": [
                {"type": "place", "place": {"name": "Sushi Saito", "formatted_address": "1-1 Minato"}}
            ]}
        ],
        "placeMetadata": [],
    }

    def test_produces_markdown(self):
        md = wl._build_export_md(self.TRIP_META, self.PLACES_DATA, "k1")
        self.assertIn("# Tokyo Trip", md)
        self.assertIn("2025-03-01 – 2025-03-10", md)
        self.assertIn("## Food", md)
        self.assertIn("**Sushi Saito**", md)

    def test_export_cmd_uses_helper(self):
        trips_resp = {"data": [self.TRIP_META]}
        places_resp = {"data": self.PLACES_DATA}

        def fake_api(method, path, session, body=None, **kw):
            return trips_resp if path == "/api/tripPlans" else places_resp

        args = mock.Mock(key="k1")
        with mock.patch.object(wl, "api", side_effect=fake_api), \
             mock.patch("builtins.print") as p:
            wl.cmd_export({}, args)
        out = "".join(str(c.args[0]) for c in p.call_args_list)
        self.assertIn("# Tokyo Trip", out)


class ExtractDestinations(unittest.TestCase):
    def test_geos_from_meta(self):
        meta = {"geos": [{"name": "Tokyo"}, {"name": "Kyoto"}]}
        result = wl._extract_destinations(meta, {"sections": []})
        self.assertEqual(result, ["Tokyo", "Kyoto"])

    def test_dedupes_preserves_order(self):
        meta = {"geos": [{"name": "Paris"}, {"name": "Paris"}]}
        result = wl._extract_destinations(meta, {"sections": []})
        self.assertEqual(result, ["Paris"])

    def test_falls_back_to_address_components(self):
        meta = {}
        data = {"sections": [{"blocks": [
            {"type": "place", "place": {"name": "Eiffel Tower", "address_components": [
                {"long_name": "Paris", "types": ["locality"]},
                {"long_name": "Île-de-France", "types": ["administrative_area_level_1"]},
            ]}}
        ]}]}
        result = wl._extract_destinations(meta, data)
        self.assertIn("Paris", result)

    def test_empty_meta_and_data(self):
        self.assertEqual(wl._extract_destinations({}, {"sections": []}), [])


class CmdArchive(unittest.TestCase):
    TRIPS = [
        {"key": "abc", "title": "Singapore", "startDate": "2025-01-01", "endDate": "2025-01-07",
         "geos": [{"name": "Singapore"}], "placeCount": 2},
        {"key": "xyz", "title": "Bali", "startDate": None, "endDate": None,
         "geos": [{"name": "Bali"}], "placeCount": 0},
    ]
    PLACES_DATA = {
        "sections": [
            {"heading": "Eats", "text": None, "blocks": [
                {"type": "place", "place": {"name": "Hawker Chan", "formatted_address": "78 Smith St"}},
                {"type": "place", "place": {"name": "Satay by the Bay", "formatted_address": "18 Marina"}},
            ]}
        ],
        "placeMetadata": [],
    }
    BALI_DATA = {"sections": [], "placeMetadata": []}

    def _fake_api(self, method, path, session, body=None, **kw):
        if path == "/api/tripPlans":
            return {"data": self.TRIPS}
        if "abc" in path:
            return {"data": self.PLACES_DATA}
        return {"data": self.BALI_DATA}

    def test_creates_per_trip_files(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            args = mock.Mock(out=tmp)
            with mock.patch.object(wl, "api", side_effect=self._fake_api), \
                 mock.patch("builtins.print"):
                wl.cmd_archive({}, args)
            self.assertTrue(Path(tmp, "abc", "trip.md").exists())
            self.assertTrue(Path(tmp, "abc", "raw.json").exists())
            self.assertTrue(Path(tmp, "xyz", "trip.md").exists())
            self.assertTrue(Path(tmp, "xyz", "raw.json").exists())

    def test_index_json_schema(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            args = mock.Mock(out=tmp)
            with mock.patch.object(wl, "api", side_effect=self._fake_api), \
                 mock.patch("builtins.print"):
                wl.cmd_archive({}, args)
            index = json.loads(Path(tmp, "index.json").read_text())
            self.assertIsInstance(index, list)
            self.assertEqual(len(index), 2)
            for entry in index:
                for field in ("key", "title", "start_date", "end_date", "destinations", "place_count"):
                    self.assertIn(field, entry)
                self.assertIsInstance(entry["destinations"], list)
                self.assertIsInstance(entry["place_count"], int)

    def test_index_dates_and_destinations(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            args = mock.Mock(out=tmp)
            with mock.patch.object(wl, "api", side_effect=self._fake_api), \
                 mock.patch("builtins.print"):
                wl.cmd_archive({}, args)
            index = {e["key"]: e for e in json.loads(Path(tmp, "index.json").read_text())}
            self.assertEqual(index["abc"]["start_date"], "2025-01-01")
            self.assertEqual(index["abc"]["end_date"], "2025-01-07")
            self.assertIsNone(index["xyz"]["start_date"])
            self.assertIsNone(index["xyz"]["end_date"])
            self.assertIn("Singapore", index["abc"]["destinations"])
            self.assertEqual(index["abc"]["place_count"], 2)
            self.assertEqual(index["xyz"]["place_count"], 0)

    def test_partial_failure_continues_and_exits_nonzero(self):
        import tempfile

        def flaky_api(method, path, session, body=None, **kw):
            if path == "/api/tripPlans":
                return {"data": self.TRIPS}
            if "abc" in path:
                raise RuntimeError("network error")
            return {"data": self.BALI_DATA}

        with tempfile.TemporaryDirectory() as tmp:
            args = mock.Mock(out=tmp)
            with mock.patch.object(wl, "api", side_effect=flaky_api), \
                 mock.patch("builtins.print"), \
                 mock.patch("sys.exit") as mock_exit:
                wl.cmd_archive({}, args)
            mock_exit.assert_called_once_with(1)
            # successful trip still written
            self.assertTrue(Path(tmp, "xyz", "trip.md").exists())
            # failed trip not written
            self.assertFalse(Path(tmp, "abc", "trip.md").exists())

    def test_index_excludes_failed_trips(self):
        import tempfile

        def flaky_api(method, path, session, body=None, **kw):
            if path == "/api/tripPlans":
                return {"data": self.TRIPS}
            if "abc" in path:
                raise RuntimeError("boom")
            return {"data": self.BALI_DATA}

        with tempfile.TemporaryDirectory() as tmp:
            args = mock.Mock(out=tmp)
            with mock.patch.object(wl, "api", side_effect=flaky_api), \
                 mock.patch("builtins.print"), \
                 mock.patch("sys.exit"):
                wl.cmd_archive({}, args)
            index = json.loads(Path(tmp, "index.json").read_text())
            keys = [e["key"] for e in index]
            self.assertNotIn("abc", keys)
            self.assertIn("xyz", keys)


if __name__ == "__main__":
    unittest.main()
