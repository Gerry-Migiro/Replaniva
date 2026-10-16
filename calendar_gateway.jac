"""Google Calendar transport and encrypted OAuth vault, never a planning backend."""
import base64;
import contextlib;
import hashlib;
import fcntl;
import functools;
import threading;
import json;
import os;
import secrets;
import sqlite3;
import time;
import urllib.error;
import urllib.parse;
import urllib.request;
import from datetime { date, datetime, time as daytime, timedelta, timezone }
import from pathlib { Path }
import from zoneinfo { ZoneInfo }
import from cryptography.fernet { Fernet, InvalidToken }
with entry {
    CALLBACK_PATH = "/integrations/google-calendar/callback";
    SCOPES = `tuple(
        ("https://www.googleapis.com/auth/" + scope)
        for scope in (
            "calendar.events.readonly",
            "calendar.calendarlist.readonly",
            "calendar.app.created"
        )
    );
    API = "https://www.googleapis.com/calendar/v3";
}
"""Safe owner-facing error with no upstream response or credentials."""
class CalendarError(ValueError) {}
def configuration() -> any {
    redirect = os.environ.get(
        "GOOGLE_CALENDAR_REDIRECT_URI", ("http://localhost:8100" + CALLBACK_PATH)
    );
    parsed = urllib.parse.urlsplit(redirect);
    if (
        (parsed.path != CALLBACK_PATH)
        or parsed.query
        or parsed.fragment
        or parsed.username
        or parsed.password
        or not parsed.hostname
        or (
            (parsed.scheme != "https")
            and not (
                (parsed.scheme == "http")
                and (parsed.hostname in ("localhost", "127.0.0.1"))
            )
        )
    ) {
        raise CalendarError(
            "Calendar redirect must use the dedicated callback path and HTTPS outside localhost."
        );
    }
    client = os.environ.get("GOOGLE_CALENDAR_CLIENT_ID", "");
    secret = os.environ.get("GOOGLE_CALENDAR_CLIENT_SECRET", "");
    try {
        cipher = Fernet(os.environ.get("REPLANIVA_CALENDAR_KEY", "").encode());
        ZoneInfo(os.environ.get("GOOGLE_CALENDAR_TIMEZONE", "Africa/Nairobi"));
    } except (ValueError, KeyError) {
        raise CalendarError(
            "Configure a valid calendar encryption key and timezone on the server."
        ) from None;
    }
    if (not client or not secret) {
        raise CalendarError(
            "The owner must configure the Google Calendar web client ID and secret on the server."
        );
    }
    return (client, secret, redirect, cipher);
}
def digest(value: any) -> any {
    return hashlib.sha256(value.encode()).hexdigest();
}
class Vault {
    def init(self: Vault) -> any {
        self.path = Path(
            os.environ.get("REPLANIVA_CALENDAR_PATH", ".jac/calendar.sqlite3")
        );
    }
    def connect(self: Vault) -> any {
        self.path.parent.mkdir(parents=True, exist_ok=True);
        fd = os.open(self.path, (os.O_CREAT | os.O_RDWR), 384);
        os.close(fd);
        os.chmod(self.path, 384);
        conn = sqlite3.connect(self.path, timeout=20);
        conn.execute("PRAGMA secure_delete=ON");
        conn.execute(
            "CREATE TABLE IF NOT EXISTS connections(account TEXT PRIMARY KEY, payload BLOB NOT NULL)"
        );
        conn.execute(
            "CREATE TABLE IF NOT EXISTS flows(state TEXT PRIMARY KEY, account TEXT, proof TEXT, expires REAL, phase TEXT, payload BLOB)"
        );
        conn.execute(
            "CREATE TABLE IF NOT EXISTS destinations(account TEXT, identity TEXT, payload BLOB, PRIMARY KEY(account,identity))"
        );
        conn.execute("DELETE FROM flows WHERE expires < ?", (time.time(), ));
        conn.commit();
        return conn;
    }
    def encrypt(self: Vault, value: any) -> any {
        return configuration()[3].encrypt(json.dumps(value).encode());
    }
    def decrypt(self: Vault, value: any) -> any {
        try {
            return json.loads(configuration()[3].decrypt(value));
        } except (InvalidToken, ValueError) {
            raise CalendarError(
                "Calendar storage cannot be opened. Restore the original encryption key or reconnect."
            ) from None;
        }
    }
    def get(self: Vault, account: any) -> any {
        with contextlib.closing(self.connect()) as conn {
            row = conn.execute(
                "SELECT payload FROM connections WHERE account=?", (account, )
            ).fetchone();
        }
        if not row {
            raise CalendarError("Connect Google Calendar first.");
        }
        return self.decrypt(row[0]);
    }
    def put(self: Vault, account: any, data: any) -> any {
        encrypted = self.encrypt(data);
        with contextlib.closing(self.connect()) as conn, conn {
            conn.execute(
                "INSERT OR REPLACE INTO connections VALUES (?,?)", (account, encrypted)
            );
        }
    }
}
with entry {
    _LOCK = threading.RLock();
    _LOCAL = threading.local();
}
def serialized(operation: any) -> any {
    @functools.wraps(operation)
    def wrapper(account: any, *args: any, **kwargs: any) -> any {
        with _LOCK {
            if getattr(_LOCAL, "depth", 0) {
                return operation(account, *args, **kwargs);
            }
            path = Vault().path;
            path.parent.mkdir(parents=True, exist_ok=True);
            fd = os.open((str(path) + ".lock"), (os.O_CREAT | os.O_RDWR), 384);
            try {
                fcntl.flock(fd, fcntl.LOCK_EX);
                _LOCAL.depth = 1;
                return operation(account, *args, **kwargs);
            } finally {
                _LOCAL.depth = 0;
                os.close(fd);
            }
        }
    }
    return wrapper;
}
class NoRedirect(urllib.request.HTTPRedirectHandler) {
    def redirect_request(
        self: NoRedirect,
        req: any,
        fp: any,
        code: any,
        msg: any,
        headers: any,
        newurl: any
    ) -> any {
        return None;
    }
}
def http_json(
    url: any,
    method: any = "GET",
    body: any = None,
    token: any = "",
    form: any = False,
    etag: any = ""
) -> any {
    if not url.startswith(((API + "/"), "https://oauth2.googleapis.com/")) {
        raise CalendarError("Unsupported calendar destination.");
    }
    headers = {"Accept": "application/json"};
    data = None;
    if (body is not None) {
        data = urllib.parse.urlencode(body).encode()
            if form
            else json.dumps(body).encode();
        headers["Content-Type"] = "application/x-www-form-urlencoded"
            if form
            else "application/json";
    }
    if token {
        headers["Authorization"] = "Bearer " + token;
    }
    if etag {
        headers["If-Match"] = etag;
    }
    req = urllib.request.Request(url, data=data, headers=headers, method=method);
    try {
        with urllib.request.build_opener(NoRedirect()).open(
            req, timeout=20
        ) as response {
            raw = response.read(((4 * 1024 * 1024) + 1));
            if (len(raw) > (4 * 1024 * 1024)) {
                raise CalendarError(
                    "Google returned too much data. Use a smaller date window."
                );
            }
            return json.loads(raw) if raw else {};
        }
    } except urllib.error.HTTPError as error {
        if (error.code in (400, 401)) {
            raise CalendarError(
                "Google authorization expired or was revoked. Reconnect Google Calendar."
            ) from None;
        }
        if (error.code == 403) {
            raise CalendarError(
                "Google did not allow this action. Check Calendar permissions and reconnect."
            ) from None;
        }
        if (error.code in (409, 412)) {
            raise CalendarError(
                "Google Calendar changed during review. Preview synchronization again."
            ) from None;
        }
        if (error.code in (404, 410)) {
            raise CalendarError(
                "The calendar item is no longer available. Preview again or reconnect."
            ) from None;
        }
        raise CalendarError(
            "Google Calendar is temporarily unavailable. Try again later."
        ) from None;
    } except (urllib.error.URLError, TimeoutError, OSError, ValueError) {
        raise CalendarError(
            "Google Calendar could not be reached. Your approval can be retried safely."
        ) from None;
    }
}
@serialized
def begin(account: any) -> dict[(str, str)] {
    (client, _, redirect, _) = configuration();
    vault = Vault();
    (state, proof, verifier) = (
        secrets.token_urlsafe(32),
        secrets.token_urlsafe(32),
        secrets.token_urlsafe(64)
    );
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()
    ).rstrip(
        b'='
    ).decode();
    with contextlib.closing(vault.connect()) as conn, conn {
        conn.execute("DELETE FROM flows WHERE account=?", (account, ));
        conn.execute(
            "INSERT INTO flows VALUES (?,?,?,?,?,?)",
            (
                digest(state),
                account,
                digest(proof),
                (time.time() + 600),
                "started",
                vault.encrypt({"verifier": verifier})
            )
        );
    }
    params = {
        "client_id": client,
        "redirect_uri": redirect,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "state": state,
        "access_type": "offline",
        "prompt": "consent",
        "include_granted_scopes": "false",
        "code_challenge": challenge,
        "code_challenge_method": "S256"
    };
    return {
        "url": (
            "https://accounts.google.com/o/oauth2/v2/auth?"
            + urllib.parse.urlencode(params)
        ),
        "flow": state,
        "proof": proof,
        "origin": (
            urllib.parse.urlsplit(redirect).scheme
            + "://"
            + urllib.parse.urlsplit(redirect).netloc
        )
    };
}
def callback(code: any, state: any, error: any = "") -> any {
    vault = Vault();
    with contextlib.closing(vault.connect()) as conn, conn {
        conn.execute("BEGIN IMMEDIATE");
        row = conn.execute(
            "SELECT payload FROM flows WHERE state=? AND phase='started' AND expires>?",
            (digest(state), time.time())
        ).fetchone();
        if (not state or not row) {
            return False;
        }
        conn.execute("UPDATE flows SET phase='used' WHERE state=?", (digest(state), ));
    }
    if (error or not code or (len(code) > 4096)) {
        return False;
    }
    try {
        (client, secret, redirect, _) = configuration();
        tokens = http_json(
            "https://oauth2.googleapis.com/token",
            "POST",
            {
                "client_id": client,
                "client_secret": secret,
                "redirect_uri": redirect,
                "grant_type": "authorization_code",
                "code": code,
                "code_verifier": vault.decrypt(row[0])["verifier"]
            },
            form=True
        );
        if (
            not `set(SCOPES).issubset(`set(tokens.get("scope", "").split()))
            or not tokens.get("refresh_token")
            or not tokens.get("access_token")
        ) {
            raise CalendarError("Grant all three Calendar permissions and reconnect.");
        }
        calendars = http_json(
            (API + "/users/me/calendarList?maxResults=100"),
            token=tokens["access_token"]
        );
        primary = next(
            (
                c
                for c in calendars.get("items", [])
                if c.get("primary")
            ),
            None
        );
        if not primary {
            raise CalendarError("Google did not return the primary calendar.");
        }
        data = {
            "access_token": tokens["access_token"],
            "refresh_token": tokens["refresh_token"],
            "expires": (time.time() + int(tokens.get("expires_in", 3600))),
            "identity": primary["id"],
            "label": primary.get("summary", "Google Calendar"),
            "selected": [],
            "app_calendar": "",
            "exports": {},
            "generation": secrets.token_hex(16),
            "last_sync": ""
        };
        with contextlib.closing(vault.connect()) as conn, conn {
            conn.execute(
                "UPDATE flows SET phase='ready',payload=? WHERE state=?",
                (vault.encrypt(data), digest(state))
            );
        }
        return True;
    } except (CalendarError, KeyError, TypeError, ValueError) {
        return False;
    }
}
@serialized
def finish(account: any, `flow: any, proof: any) -> dict[(str, any)] {
    vault = Vault();
    with contextlib.closing(vault.connect()) as conn, conn {
        conn.execute("BEGIN IMMEDIATE");
        row = conn.execute(
            "SELECT payload FROM flows WHERE state=? AND account=? AND proof=? AND phase='ready' AND expires>?",
            (digest(`flow), account, digest(proof), time.time())
        ).fetchone();
        if not row {
            raise CalendarError(
                "Calendar connection was cancelled, expired or belongs to another signed-in account. Start again."
            );
        }
        data = vault.decrypt(row[0]);
        old = conn.execute(
            "SELECT payload FROM connections WHERE account=?", (account, )
        ).fetchone();
        if old {
            previous = vault.decrypt(old[0]);
            if (previous.get("identity") == data["identity"]) {
                for key in ("selected", "app_calendar", "exports", "last_sync") {
                    data[key] = previous.get(key, data[key]);
                }
            }
        }
        destination = conn.execute(
            "SELECT payload FROM destinations WHERE account=? AND identity=?",
            (account, digest(data["identity"]))
        ).fetchone();
        if destination {
            saved = vault.decrypt(destination[0]);
            data.update(saved);
        }
        conn.execute(
            "INSERT OR REPLACE INTO connections VALUES (?,?)",
            (account, vault.encrypt(data))
        );
        conn.execute("DELETE FROM flows WHERE state=?", (digest(`flow), ));
    }
    return status(account);
}
@serialized
def access(account: any) -> any {
    vault = Vault();
    data = vault.get(account);
    if (data["expires"] < (time.time() + 60)) {
        (client, secret, _, _) = configuration();
        result = http_json(
            "https://oauth2.googleapis.com/token",
            "POST",
            {
                "client_id": client,
                "client_secret": secret,
                "refresh_token": data["refresh_token"],
                "grant_type": "refresh_token"
            },
            form=True
        );
        if not result.get("access_token") {
            raise CalendarError("Reconnect Google Calendar to restore access.");
        }
        data["access_token"] = result["access_token"];
        data["expires"] = time.time() + int(result.get("expires_in", 3600));
        vault.put(account, data);
    }
    return data;
}
def api(
    account: any, path: any, method: any = "GET", body: any = None, etag: any = ""
) -> any {
    return http_json(
        (API + path), method, body, access(account)["access_token"], etag=etag
    );
}
@serialized
def calendars(account: any) -> any {
    (items, page) = ([], "");
    for _ in range(10) {
        result = api(
            account,
            (
                "/users/me/calendarList?"
                + urllib.parse.urlencode({"maxResults": 100, "pageToken": page})
            )
        );
        items.extend(
            {
                "id": c["id"],
                "label": c.get("summary", "Calendar"),
                "primary": bool(c.get("primary"))
            }
            for c in result.get("items", [])
            if not c.get("deleted")
        );
        page = result.get("nextPageToken", "");
        if not page {
            return items;
        }
    }
    raise CalendarError("Too many calendars to list safely.");
}
@serialized
def status(account: any) -> dict[(str, any)] {
    try {
        configuration();
    } except CalendarError as error {
        return {
            "configured": False,
            "connected": False,
            "message": str(error),
            "calendars": [],
            "selected": [],
            "app_calendar": "",
            "last_sync": "",
            "label": ""
        };
    }
    try {
        data = Vault().get(account);
    } except CalendarError {
        return {
            "configured": True,
            "connected": False,
            "message": "Connect to choose the calendars to read.",
            "calendars": [],
            "selected": [],
            "app_calendar": "",
            "last_sync": "",
            "label": ""
        };
    }
    try {
        items = calendars(account);
        return {
            "configured": True,
            "connected": True,
            "message": "Google Calendar access verified.",
            "calendars": items,
            "selected": data["selected"],
            "app_calendar": data["app_calendar"],
            "last_sync": data["last_sync"],
            "label": data["label"]
        };
    } except CalendarError as error {
        return {
            "configured": True,
            "connected": False,
            "message": str(error),
            "calendars": [],
            "selected": [],
            "app_calendar": "",
            "last_sync": data["last_sync"],
            "label": data["label"]
        };
    }
}
@serialized
def select_calendars(account: any, selected: any) -> any {
    if ((len(selected) > 10) or (len(selected) != len(`set(selected)))) {
        raise CalendarError("Choose up to ten different calendars.");
    }
    allowed = {c["id"] for c in calendars(account)};
    data = Vault().get(account);
    if `any(((c not in allowed) or (c == data["app_calendar"])) for c in selected) {
        raise CalendarError(
            "Choose existing readable calendars, excluding the Replaniva export calendar."
        );
    }
    data["selected"] = selected;
    data["generation"] = secrets.token_hex(16);
    Vault().put(account, data);
}
def normalize_events(
    calendar: any, events: any, first: any, last: any, zone: any
) -> any {
    tz = ZoneInfo(zone);
    lower = datetime.combine(date.fromisoformat(first), daytime.min, tzinfo=tz);
    upper = datetime.combine(date.fromisoformat(last), daytime.min, tzinfo=tz);
    output = [];
    for event in events {
        if (
            (event.get("status") == "cancelled")
            or (event.get("transparency") == "transparent")
            or (event.get("eventType") == "workingLocation")
        ) {
            continue;
        }
        if `any(
            (a.get("self") and (a.get("responseStatus") == "declined"))
            for a in event.get("attendees", [])
        ) {
            continue;
        }
        if not event.get("id") {
            raise CalendarError("Google returned an event without an identifier.");
        }
        def boundary(value: any) -> any {
            if ("date" in value) {
                return datetime.combine(
                    date.fromisoformat(value["date"]), daytime.min, tzinfo=tz
                );
            }
            timestamp = datetime.fromisoformat(
                value["dateTime"].replace("Z", "+00:00")
            );
            if (timestamp.tzinfo is None) {
                timestamp = timestamp.replace(
                    tzinfo=ZoneInfo(value.get("timeZone", zone))
                );
            }
            return timestamp.astimezone(tz);
        }
        try {
            (start, end) = (boundary(event["start"]), boundary(event["end"]));
        } except (KeyError, ValueError, TypeError) {
            raise CalendarError(
                "An event has invalid dates. No import was prepared."
            ) from None;
        }
        if (end <= start) {
            raise CalendarError("An event ends before it starts.");
        }
        cursor = max(start, lower);
        stop = min(end, upper);
        while (cursor < stop) {
            midnight = datetime.combine(
                (cursor.date() + timedelta(days=1)), daytime.min, tzinfo=tz
            );
            segment_end = min(stop, midnight);
            end_minute = 1440 if segment_end == midnight else segment_end.hour * 60 + segment_end.minute;
            if segment_end != midnight and (segment_end.second or segment_end.microsecond) { end_minute += 1; }
            day = cursor.date().isoformat();
            output.append(
                {
                    "key": digest((calendar + "\0" + event["id"] + "\0" + day)),
                    "calendar": calendar,
                    "event": event["id"],
                    "title": (str(event.get("summary", "Busy"))[:120] or "Busy"),
                    "day": day,
                    "start": ((cursor.hour * 60) + cursor.minute),
                    "end": end_minute
                }
            );
            cursor = segment_end;
        }
    }
    return output;
}
@serialized
def snapshot(account: any, first: any, last: any) -> dict[(str, any)] {
    (lower, upper) = (date.fromisoformat(first), date.fromisoformat(last));
    if not (0 < (upper - lower).days <= 31) {
        raise CalendarError("Choose a synchronization window of 1 to 31 days.");
    }
    data = access(account);
    zone = os.environ.get("GOOGLE_CALENDAR_TIMEZONE", "Africa/Nairobi");
    tz = ZoneInfo(zone);
    events = [];
    for calendar in data["selected"] {
        page = "";
        for _ in range(10) {
            query = {
                "timeMin": datetime.combine(lower, daytime.min, tzinfo=tz).isoformat(),
                "timeMax": datetime.combine(upper, daytime.min, tzinfo=tz).isoformat(),
                "singleEvents": "true",
                "showDeleted": "true",
                "maxResults": 250,
                "timeZone": zone,
                "pageToken": page
            };
            result = api(
                account,
                (
                    "/calendars/"
                    + urllib.parse.quote(calendar, safe="")
                    + "/events?"
                    + urllib.parse.urlencode(query)
                )
            );
            events.extend(
                normalize_events(calendar, result.get("items", []), first, last, zone)
            );
            if (len(events) > 1000) {
                raise CalendarError("Too many busy periods. Preview a shorter window.");
            }
            page = result.get("nextPageToken", "");
            if not page {
                break;
            }
        }
        if page {
            raise CalendarError(
                "The event list was incomplete. Preview a shorter window."
            );
        }
    }
    unique = {e["key"]: e for e in events};
    return {
        "generation": data["generation"],
        "identity": data["identity"],
        "selected": data["selected"],
        "events": sorted(unique.values(), key=lambda (e: any) { e["key"]; })
    };
}
def fingerprint(value: any) -> any {
    return digest(json.dumps(value, sort_keys=True, separators=(",", ":")));
}
@serialized
def ensure_app_calendar(account: any) -> any {
    data = access(account);
    if data["app_calendar"] {
        api(
            account, ("/calendars/" + urllib.parse.quote(data["app_calendar"], safe=""))
        );
        return data["app_calendar"];
    }
    vault = Vault();
    with contextlib.closing(vault.connect()) as conn, conn {
        row = conn.execute(
            "SELECT payload FROM destinations WHERE account=? AND identity=?",
            (account, digest(data["identity"]))
        ).fetchone();
        saved: dict[str, any] = vault.decrypt(row[0])
            if row
            else {
                "marker": ("Replaniva managed " + secrets.token_hex(32)),
                "app_calendar": "",
                "exports": {}
            };
        if ("marker" not in saved) {
            saved["marker"] = "Replaniva managed " + secrets.token_hex(32);
        }
        conn.execute(
            "INSERT OR REPLACE INTO destinations VALUES (?,?,?)",
            (account, digest(data["identity"]), vault.encrypt(saved))
        );
    }
    (result, page) = (None, "");
    for _ in range(10) {
        listing = api(
            account,
            (
                "/users/me/calendarList?"
                + urllib.parse.urlencode({"maxResults": 100, "pageToken": page})
            )
        );
        matches = [
            c
            for c in listing.get("items", [])
            if ((c.get("description") == saved["marker"]) and not c.get("primary"))
        ];
        if matches {
            result = matches[0];
            break;
        }
        page = listing.get("nextPageToken", "");
        if not page {
            break;
        }
    }
    if (page and (result is None)) {
        raise CalendarError(
            "Calendar discovery was incomplete. Try again before creating a destination."
        );
    }
    if (result is None) {
        if saved.get("creation_started") {
            raise CalendarError(
                "A previous calendar creation was not confirmed. Check Google Calendar and retry discovery; another calendar will not be created automatically."
            );
        }
        saved["creation_started"] = True;
        with contextlib.closing(vault.connect()) as conn, conn {
            conn.execute(
                "UPDATE destinations SET payload=? WHERE account=? AND identity=?",
                (vault.encrypt(saved), account, digest(data["identity"]))
            );
        }
        result = api(
            account,
            "/calendars",
            "POST",
            {
                "summary": "Replaniva",
                "description": saved["marker"],
                "timeZone": os.environ.get("GOOGLE_CALENDAR_TIMEZONE", "Africa/Nairobi")
            }
        );
    }
    if not result.get("id") {
        raise CalendarError(
            "Google did not confirm creation of the Replaniva calendar."
        );
    }
    data = vault.get(account);
    data["app_calendar"] = result["id"];
    saved["app_calendar"] = result["id"];
    with contextlib.closing(vault.connect()) as conn, conn {
        conn.execute(
            "INSERT OR REPLACE INTO destinations VALUES (?,?,?)",
            (account, digest(data["identity"]), vault.encrypt(saved))
        );
    }
    vault.put(account, data);
    return result["id"];
}
def same_export(remote: any, body: any) -> any {
    try {
        return (
            (remote.get("summary") == body["summary"])
            and (
                remote.get("extendedProperties", {}).get("private", {}).get(
                    "replanivaTask"
                )
                == body["extendedProperties"]["private"]["replanivaTask"]
            )
            and all(
                (
                    datetime.fromisoformat(
                        remote[key]["dateTime"].replace("Z", "+00:00")
                    )
                    == datetime.fromisoformat(
                        body[key]["dateTime"].replace("Z", "+00:00")
                    )
                ) for key in ("start", "end")
            )
        );
    } except (KeyError, ValueError, TypeError) {
        return False;
    }
}
@serialized
def export_preview(account: any, tasks: any) -> dict[(str, any)] {
    data = access(account);
    if not data["app_calendar"] {
        raise CalendarError("Create the dedicated Replaniva export calendar first.");
    }
    changes = [];
    zone = os.environ.get("GOOGLE_CALENDAR_TIMEZONE", "Africa/Nairobi");
    for task in tasks {
        start = (
            datetime.combine(
                date.fromisoformat(task["day"]), daytime.min, tzinfo=ZoneInfo(zone)
            )
            + timedelta(minutes=task["start"])
        );
        end = start + timedelta(minutes=task["duration"]);
        event_id = digest((data["identity"] + "\0" + task["id"]));
        body: dict[str, any] = {
            "id": event_id,
            "summary": task["title"],
            "start": {"dateTime": start.isoformat(), "timeZone": zone},
            "end": {"dateTime": end.isoformat(), "timeZone": zone},
            "extendedProperties": {"private": {"replanivaTask": task["id"]}}
        };
        old = data["exports"].get(task["id"]);
        if (old and (old["fingerprint"] == fingerprint(body))) {
            continue;
        }
        remote = api(
            account,
            (
                "/calendars/"
                + urllib.parse.quote(data["app_calendar"], safe="")
                + "/events/"
                + body["id"]
            )
        )
            if old
            else None;
        if ((remote is not None) and not remote.get("etag")) {
            raise CalendarError(
                "Google did not return an event version. Preview again."
            );
        }
        changes.append(
            {
                "task": task["id"],
                "body": body,
                "old": old,
                "etag": remote["etag"] if remote else "",
                "before": {key: remote.get(key) for key in ("summary", "start", "end")}
                    if remote
                    else None,
                "label": task["title"],
                "kind": "update" if old else "create"
            }
        );
    }
    return {
        "generation": data["generation"],
        "calendar": data["app_calendar"],
        "changes": changes
    };
}
@serialized
def write_export(account: any, preview: any) -> any {
    data = access(account);
    if (
        not data["app_calendar"]
        or (preview["calendar"] != data["app_calendar"])
        or (preview["generation"] != data["generation"])
    ) {
        raise CalendarError("Calendar connection changed. Preview exports again.");
    }
    for change in preview["changes"] {
        body = change["body"];
        current = Vault().get(account);
        if (
            current["exports"].get(change["task"], {}).get("fingerprint")
            == fingerprint(body)
        ) {
            continue;
        }
        path = (
            "/calendars/"
            + urllib.parse.quote(data["app_calendar"], safe="")
            + "/events"
        );
        if change["old"] {
            if (current["exports"].get(change["task"]) != change["old"]) {
                raise CalendarError("Export changed during review. Preview again.");
            }
            remote = api(account, (path + "/" + body["id"]));
            if same_export(remote, body) {
                result = remote;
            } else {
                if (remote.get("etag") != change["etag"]) {
                    raise CalendarError(
                        "An exported event changed after review. Preview again."
                    );
                }
                result = api(
                    account,
                    (path + "/" + body["id"]),
                    "PATCH",
                    {
                        key: value
                        for (key, value) in body.items()
                        if (key != "id")
                    },
                    etag=change["etag"]
                );
            }
        } else {
            existing = api(
                account,
                (
                    path
                    + "?"
                    + urllib.parse.urlencode(
                        {
                            "privateExtendedProperty": (
                                "replanivaTask=" + change["task"]
                            ),
                            "showDeleted": "false"
                        }
                    )
                )
            );
            matches = [
                e
                for e in existing.get("items", [])
                if (e.get("id") == body["id"])
            ];
            if matches {
                result = matches[0];
                if not same_export(result, body) {
                    raise CalendarError(
                        "An existing exported event differs. Review it before retrying."
                    );
                }
            } else {
                result = api(account, path, "POST", body);
            }
        }
        if (not result.get("etag") or (result.get("id") != body["id"])) {
            raise CalendarError(
                "Google did not confirm this export. Preview again before retrying."
            );
        }
        current["exports"][change["task"]] = {
            "id": body["id"],
            "etag": result["etag"],
            "fingerprint": fingerprint(body)
        };
        Vault().put(account, current);
    }
    current = Vault().get(account);
    vault = Vault();
    with contextlib.closing(vault.connect()) as conn, conn {
        row = conn.execute(
            "SELECT payload FROM destinations WHERE account=? AND identity=?",
            (account, digest(current["identity"]))
        ).fetchone();
        if row {
            saved: dict[str, any] = vault.decrypt(row[0]);
            saved["exports"] = current["exports"];
            conn.execute(
                "UPDATE destinations SET payload=? WHERE account=? AND identity=?",
                (vault.encrypt(saved), account, digest(current["identity"]))
            );
        }
    }
    mark_synced(account);
}
@serialized
def mark_synced(account: any) -> any {
    data = Vault().get(account);
    data["last_sync"] = datetime.now(timezone.utc).isoformat(timespec="seconds");
    Vault().put(account, data);
}
@serialized
def disconnect(account: any) -> str {
    vault = Vault();
    revoked = True;
    try {
        data = vault.get(account);
        http_json(
            "https://oauth2.googleapis.com/revoke",
            "POST",
            {"token": data["refresh_token"]},
            form=True
        );
    } except CalendarError {
        revoked = False;
    }
    with contextlib.closing(vault.connect()) as conn, conn {
        conn.execute("DELETE FROM connections WHERE account=?", (account, ));
        conn.execute("DELETE FROM flows WHERE account=?", (account, ));
    }
    message = "Disconnected. Saved planning data and exported events were kept.";
    if not revoked { message += " Remove Replaniva in your Google account permissions too, because remote revocation could not be confirmed."; }
    return message;
}
