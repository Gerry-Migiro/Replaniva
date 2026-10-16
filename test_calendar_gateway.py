"""Calendar transport tests use synthetic events and mocked Google responses only."""
import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit
from cryptography.fernet import Fernet
import calendar_gateway as g


class CalendarTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {
            "GOOGLE_CALENDAR_CLIENT_ID": "test-client", "GOOGLE_CALENDAR_CLIENT_SECRET": "test-secret",
            "GOOGLE_CALENDAR_REDIRECT_URI": "http://localhost:8000"+g.CALLBACK_PATH,
            "REPLANIVA_CALENDAR_KEY": Fernet.generate_key().decode(),
            "GOOGLE_CALENDAR_TIMEZONE": "Africa/Nairobi",
            "REPLANIVA_CALENDAR_PATH": self.tmp.name+"/calendar.sqlite3"})
        self.env.start()
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(self.env.stop)
        self.account = "account-a"

    def seed(self, **changes):
        data = {"access_token": "secret-access", "refresh_token": "secret-refresh", "expires": time.time()+3600,
                "identity": "primary@example.invalid", "label": "My calendar", "selected": ["personal"],
                "app_calendar": "app-owned", "exports": {}, "generation": "connection-a", "last_sync": ""}
        data.update(changes)
        g.Vault().put(self.account, data)
        return data

    def tokens(self):
        return {"access_token": "secret-access", "refresh_token": "secret-refresh", "expires_in": 3600, "scope": " ".join(g.SCOPES)}

    def connect(self):
        flow = g.begin(self.account)
        with patch.object(g, "http_json", side_effect=[self.tokens(), {"items": [{"id": "primary@example.invalid", "primary": True}]}]):
            self.assertTrue(g.callback("synthetic-code", flow["flow"]))
        return flow

    def test_oauth_exact_scopes_and_pkce(self):
        flow = g.begin(self.account)
        query = parse_qs(urlsplit(flow["url"]).query)
        self.assertEqual(set(query["scope"][0].split()), set(g.SCOPES))
        self.assertEqual(query["code_challenge_method"], ["S256"])
        self.assertEqual(query["access_type"], ["offline"])
        self.assertNotIn("test-secret", flow["url"])
        self.assertNotIn("verifier", flow)

    def test_callback_invalid_state_does_not_contact_google(self):
        with patch.object(g, "http_json") as http:
            self.assertFalse(g.callback("code", "wrong-state"))
            http.assert_not_called()

    def test_oauth_state_expiry_denial_and_replay(self):
        flow = g.begin(self.account)
        with g.Vault().connect() as conn:
            conn.execute("UPDATE flows SET expires=0")
        self.assertFalse(g.callback("code", flow["flow"]))
        flow = g.begin(self.account)
        self.assertFalse(g.callback("", flow["flow"], "access_denied"))
        self.assertFalse(g.callback("code", flow["flow"]))
        flow = self.connect()
        with patch.object(g, "http_json") as http:
            self.assertFalse(g.callback("code", flow["flow"]))
            http.assert_not_called()

    def test_finish_requires_original_account_and_browser_proof(self):
        flow = self.connect()
        with self.assertRaises(g.CalendarError):
            g.finish("account-b", flow["flow"], flow["proof"])
        with self.assertRaises(g.CalendarError):
            g.finish(self.account, flow["flow"], "wrong")
        with patch.object(g, "calendars", return_value=[]):
            status = g.finish(self.account, flow["flow"], flow["proof"])
        self.assertTrue(status["connected"])
        with self.assertRaises(g.CalendarError):
            g.finish(self.account, flow["flow"], flow["proof"])

    def test_missing_permission_does_not_connect(self):
        flow = g.begin(self.account)
        tokens = self.tokens()
        tokens["scope"] = g.SCOPES[0]
        with patch.object(g, "http_json", return_value=tokens):
            self.assertFalse(g.callback("code", flow["flow"]))
        with self.assertRaises(g.CalendarError):
            g.Vault().get(self.account)

    def test_connection_not_ready_until_real_api_success(self):
        flow = g.begin(self.account)
        with patch.object(g, "http_json", side_effect=[self.tokens(), g.CalendarError("Unavailable")]):
            self.assertFalse(g.callback("code", flow["flow"]))
        with self.assertRaises(g.CalendarError):
            g.finish(self.account, flow["flow"], flow["proof"])

    def test_encrypted_tokens_private_permissions_and_isolation(self):
        self.seed()
        path = Path(os.environ["REPLANIVA_CALENDAR_PATH"])
        self.assertNotIn(b"secret-access", path.read_bytes())
        self.assertNotIn(b"secret-refresh", path.read_bytes())
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        with self.assertRaises(g.CalendarError):
            g.Vault().get("account-b")
        with patch.dict(os.environ, {"REPLANIVA_CALENDAR_KEY": Fernet.generate_key().decode()}):
            with self.assertRaises(g.CalendarError):
                g.Vault().get(self.account)

    def test_refresh_and_revocation(self):
        self.seed(expires=0)
        with patch.object(g, "http_json", return_value={"access_token": "new-private-access", "expires_in":3600}) as http:
            self.assertEqual(g.access(self.account)["access_token"], "new-private-access")
            self.assertEqual(http.call_count, 1)
        self.seed(expires=0)
        with patch.object(g, "http_json", side_effect=g.CalendarError("Reconnect")):
            self.assertFalse(g.status(self.account)["connected"])

    def test_https_and_dedicated_path(self):
        for uri in ["http://example.com"+g.CALLBACK_PATH, "http://localhost:8000/", "https://example.com"+g.CALLBACK_PATH+"?secret=bad"]:
            with patch.dict(os.environ, {"GOOGLE_CALENDAR_REDIRECT_URI":uri}):
                with self.assertRaises(g.CalendarError):
                    g.configuration()

    def event(self, **extra):
        return {"id":"class-a", "summary":"Class", "start":{"dateTime":"2099-01-01T14:00:00+03:00"},
                "end":{"dateTime":"2099-01-01T15:00:00+03:00"}, **extra}

    def test_timezone_all_day_multiday_cancelled_and_free(self):
        events = [self.event(), self.event(id="cancelled", status="cancelled"), self.event(id="free", transparency="transparent"),
                  self.event(id="all-day", start={"date":"2099-01-02"}, end={"date":"2099-01-04"}),
                  self.event(id="utc", start={"dateTime":"2099-01-04T22:00:00Z"}, end={"dateTime":"2099-01-04T23:00:00Z"})]
        rows = g.normalize_events("personal",events,"2099-01-01","2099-01-08","Africa/Nairobi")
        self.assertEqual(len(rows),4)
        self.assertEqual((rows[0]["start"],rows[0]["end"]),(840,900))
        self.assertEqual((rows[1]["day"],rows[1]["start"],rows[1]["end"]),("2099-01-02",0,1440))
        self.assertEqual(rows[-1]["day"],"2099-01-05")
        self.assertEqual(rows[-1]["start"],60)

    def test_recurring_instances_and_duplicates(self):
        self.seed()
        events = [self.event(), self.event(), self.event(id="instance-b", recurringEventId="series-a")]
        with patch.object(g,"api",return_value={"items":events}) as api:
            snapshot = g.snapshot(self.account,"2099-01-01","2099-01-08")
        self.assertEqual(len(snapshot["events"]),2)
        self.assertIn("singleEvents=true",api.call_args.args[1])

    def test_event_pagination_never_silently_truncates(self):
        self.seed()
        with patch.object(g,"api",return_value={"items":[],"nextPageToken":"more"}):
            with self.assertRaises(g.CalendarError):
                g.snapshot(self.account,"2099-01-01","2099-01-08")

    def test_selection_does_not_allow_export_calendar_or_foreign_ids(self):
        self.seed()
        with patch.object(g,"calendars",return_value=[{"id":"personal"},{"id":"app-owned"}]):
            for selected in [["unknown"],["app-owned"],["personal","personal"]]:
                with self.assertRaises(g.CalendarError):
                    g.select_calendars(self.account,selected)

    def task(self):
        return {"id":"saved-task", "day":"2099-01-01", "title":"Study", "start":600, "duration":30}

    def test_export_preview_no_writes_and_idempotent_approval(self):
        self.seed()
        with patch.object(g,"api") as api:
            preview = g.export_preview(self.account,[self.task()])
            api.assert_not_called()
        body = preview["changes"][0]["body"]
        with patch.object(g,"api",side_effect=[{"items":[]},{**body,"etag":"version-1"}]) as api:
            g.write_export(self.account,preview)
            self.assertEqual(api.call_count,2)
            self.assertEqual(api.call_args.args[2],"POST")
            self.assertIn("/calendars/app-owned/events",api.call_args.args[1])
        with patch.object(g,"api") as api:
            g.write_export(self.account,preview)
            api.assert_not_called()
        self.assertEqual(g.export_preview(self.account,[self.task()])["changes"],[])

    def test_export_destination_and_generation_cannot_change(self):
        self.seed()
        preview = g.export_preview(self.account,[self.task()])
        for field,value in [("calendar","personal"),("generation","another-connection")]:
            invalid = {**preview,field:value}
            with patch.object(g,"api") as api:
                with self.assertRaises(g.CalendarError):
                    g.write_export(self.account,invalid)
                api.assert_not_called()

    def test_changed_export_uses_reviewed_etag_and_only_owned_calendar(self):
        self.seed(exports={"saved-task":{"id":"old", "etag":"v1", "fingerprint":"old"}})
        remote = {"etag":"v1", "summary":"Old title", "start":{"dateTime":"2099-01-01T09:00:00+03:00"}, "end":{"dateTime":"2099-01-01T09:30:00+03:00"}}
        with patch.object(g,"api",return_value=remote):
            preview = g.export_preview(self.account,[self.task()])
        body = preview["changes"][0]["body"]
        with patch.object(g,"api",side_effect=[remote,{**body,"etag":"v2"}]) as api:
            g.write_export(self.account,preview)
        self.assertEqual(api.call_args.kwargs["etag"],"v1")
        self.assertEqual(api.call_args.args[2],"PATCH")
        self.assertIn("/calendars/app-owned/events/",api.call_args.args[1])

    def test_existing_destination_is_reused(self):
        self.seed()
        with patch.object(g,"api",return_value={"id":"app-owned"}) as api:
            self.assertEqual(g.ensure_app_calendar(self.account),"app-owned")
            self.assertEqual(api.call_count,1)
            self.assertEqual(len(api.call_args.args),2)

    def test_disconnection_preserves_plans_and_clears_secrets(self):
        self.seed()
        with patch.object(g,"http_json",return_value={}):
            self.assertIn("kept",g.disconnect(self.account))
        with self.assertRaises(g.CalendarError):
            g.Vault().get(self.account)
        self.assertNotIn(b"secret-refresh",Path(os.environ["REPLANIVA_CALENDAR_PATH"]).read_bytes())

    def test_uncertain_calendar_creation_is_discovered_not_repeated(self):
        self.seed(app_calendar="")
        with patch.object(g,"api",side_effect=[{"items":[]},g.CalendarError("Lost response")]):
            with self.assertRaises(g.CalendarError):
                g.ensure_app_calendar(self.account)
        with patch.object(g,"api",return_value={"items":[]}) as api:
            with self.assertRaises(g.CalendarError):
                g.ensure_app_calendar(self.account)
            self.assertEqual(api.call_count,1)
        vault = g.Vault()
        with vault.connect() as conn:
            row = conn.execute("SELECT payload FROM destinations").fetchone()
        marker = vault.decrypt(row[0])["marker"]
        with patch.object(g,"api",return_value={"items":[{"id":"created-once","description":marker}]}) as api:
            self.assertEqual(g.ensure_app_calendar(self.account),"created-once")
            self.assertEqual(api.call_count,1)

    def test_reconnect_reuses_created_destination_after_disconnect(self):
        self.seed(app_calendar="")
        with patch.object(g,"api",side_effect=[{"items":[]},{"id":"created-once"}]):
            g.ensure_app_calendar(self.account)
        with patch.object(g,"http_json",return_value={}):
            g.disconnect(self.account)
        flow = self.connect()
        with patch.object(g,"calendars",return_value=[]):
            g.finish(self.account,flow["flow"],flow["proof"])
        self.assertEqual(g.Vault().get(self.account)["app_calendar"],"created-once")

    def test_lost_export_response_does_not_create_duplicate(self):
        self.seed()
        preview = g.export_preview(self.account,[self.task()])
        body = preview["changes"][0]["body"]
        with patch.object(g,"api",return_value={"items":[{**body,"etag":"saved-version"}]}) as api:
            g.write_export(self.account,preview)
            self.assertEqual(api.call_count,1)
            self.assertEqual(len(api.call_args.args),2)

    def test_remote_export_change_after_review_is_rejected(self):
        self.seed(exports={"saved-task":{"id":"old","etag":"v1","fingerprint":"old"}})
        remote = {"etag":"v1","summary":"Before","start":{"dateTime":"2099-01-01T09:00:00+03:00"},"end":{"dateTime":"2099-01-01T09:30:00+03:00"}}
        with patch.object(g,"api",return_value=remote):
            preview = g.export_preview(self.account,[self.task()])
        with patch.object(g,"api",return_value={**remote,"etag":"v2"}) as api:
            with self.assertRaises(g.CalendarError):
                g.write_export(self.account,preview)
            self.assertEqual(api.call_count,1)



if __name__ == "__main__":
    unittest.main()
