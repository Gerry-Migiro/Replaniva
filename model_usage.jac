"""Local model admission control. Stores counters, never prompts or credentials."""
import hashlib;
import os;
import sqlite3;
import threading;
import time;
import from collections { OrderedDict }
import from contextlib { contextmanager }
import from email.utils { parsedate_to_datetime }
import from pathlib { Path }
def limit(name: str, `default: int) -> int {
    try {
        return max(0, int(os.environ.get(name, str(`default))));
    } except ValueError {
        return `default;
    }
}
def configured_models() -> list[str] {
    if (os.environ.get("REPLANIVA_AI_ENABLED", "1") == "0") {
        return [];
    }
    primary = os.environ.get("BYLLM_DEFAULT_MODEL", "gemini/gemini-2.5-flash");
    backup = os.environ.get("REPLANIVA_AI_BACKUP_MODEL", "");
    models = [];
    for model in (primary, backup) {
        prefix = model.split("/", 1)[0];
        credential = {
            "gemini": "GOOGLE_API_KEY",
            "groq": "GROQ_API_KEY",
            "openrouter": "OPENROUTER_API_KEY"
        }.get(
            prefix
        );
        if (
            model
            and (model not in models)
            and ((credential and os.environ.get(credential)) or (prefix == "ollama"))
        ) {
            models.append(model);
        }
    }
    return models;
}
class UsageGuard {
    def init(
        self: UsageGuard, path: Path, clock: Callable[([], float)] = time.time
    ) -> any {
        self.path = path;
        self.clock = clock;
        self.lock = threading.RLock();
        self.cache: OrderedDict[(str, tuple[(float, any)])] = OrderedDict();
    }
    @contextmanager
    def connect(self: UsageGuard) -> any {
        self.path.parent.mkdir(parents=True, exist_ok=True);
        db = sqlite3.connect(self.path, timeout=3, isolation_level=None);
        os.chmod(self.path, 384);
        db.execute(
            "CREATE TABLE IF NOT EXISTS calls (scope TEXT, model TEXT, stamp REAL, units INTEGER, active INTEGER)"
        );
        db.execute(
            "CREATE TABLE IF NOT EXISTS pauses (model TEXT PRIMARY KEY, until REAL)"
        );
        try {
            yield db;
        } finally {
            db.close();
        }
    }
    def status(self: UsageGuard, scope: str) -> dict[(str, any)] {
        now = self.clock();
        with self.lock, self.connect() as db {
            row = db.execute(
                "SELECT COUNT(*), COALESCE(SUM(units),0) FROM calls WHERE scope=? AND stamp>=?",
                (scope, (int((now // 86400)) * 86400))
            ).fetchone();
            paused = db.execute(
                "SELECT COUNT(*) FROM pauses WHERE until>?", (now, )
            ).fetchone()[0];
        }
        (calls, units) = row;
        return {
            "calls": calls,
            "remaining": max(0, (limit("REPLANIVA_AI_DAILY_CALLS", 30) - calls)),
            "units": units,
            "unit_limit": limit("REPLANIVA_AI_DAILY_UNITS", 120000),
            "paused": bool(paused),
            "models": (", ".join(configured_models()) or "Deterministic planning")
        };
    }
    def run(
        self: UsageGuard,
        scope: str,
        model: str,
        payload: str,
        operation: Callable[([], any)]
    ) -> any {
        key = hashlib.sha256(
            (scope + "\0" + model + "\0" + payload).encode()
        ).hexdigest();
        now = self.clock();
        with self.lock {
            cached = self.cache.get(key);
            if (cached and ((now - cached[0]) < 300)) {
                self.cache.move_to_end(key);
                return cached[1];
            }
            if (len(payload.encode()) > 8000) {
                return None;
            }
            units = len(payload.encode()) + 2048 + 700;
            with self.connect() as db {
                db.execute("BEGIN IMMEDIATE");
                db.execute("DELETE FROM calls WHERE stamp<?", ((now - 172800), ));
                pause = db.execute(
                    "SELECT until FROM pauses WHERE model=?", (model, )
                ).fetchone();
                day = int((now // 86400)) * 86400;
                counts = db.execute(
                    "SELECT COUNT(*), COALESCE(SUM(units),0) FROM calls WHERE scope=? AND stamp>=?",
                    (scope, day)
                ).fetchone();
                global_calls = db.execute(
                    "SELECT COUNT(*) FROM calls WHERE stamp>=?", (day, )
                ).fetchone()[0];
                (recent, recent_units) = db.execute(
                    "SELECT COUNT(*), COALESCE(SUM(units),0) FROM calls WHERE stamp>?",
                    ((now - 60), )
                ).fetchone();
                active = db.execute(
                    "SELECT COUNT(*) FROM calls WHERE active=1 AND stamp>?",
                    ((now - 120), )
                ).fetchone()[0];
                if (
                    (pause and (pause[0] > now))
                    or (counts[0] >= limit("REPLANIVA_AI_DAILY_CALLS", 30))
                    or ((counts[1] + units) > limit("REPLANIVA_AI_DAILY_UNITS", 120000))
                    or (global_calls >= limit("REPLANIVA_AI_SERVER_DAILY_CALLS", 60))
                    or (recent >= limit("REPLANIVA_AI_RPM", 4))
                    or (
                        (recent_units + units)
                        > limit("REPLANIVA_AI_MINUTE_UNITS", 12000)
                    )
                    or (active >= 1)
                ) {
                    db.commit();
                    return None;
                }
                cursor = db.execute(
                    "INSERT INTO calls VALUES (?,?,?,?,1)", (scope, model, now, units)
                );
                call_id = cursor.lastrowid;
                db.commit();
            }
        }
        result = None;
        try {
            result = operation();
        } except Exception as error {
            response = getattr(error, "response", None);
            headers = getattr(response, "headers", {}) or {};
            try {
                delay = float(headers.get("retry-after", "60"));
            } except (TypeError, ValueError) {
                try {
                    retry_at: any = parsedate_to_datetime(headers.get("retry-after", ""));
                    if retry_at is None { raise ValueError("Invalid retry time."); }
                    delay = retry_at.timestamp() - self.clock();
                } except (TypeError, ValueError, OverflowError) {
                    delay = 60;
                }
            }
            if (
                ("RateLimit" in `type(error).__name__)
                or (getattr(error, "status_code", 0) == 429)
            ) {
                delay = max(60.0, delay);
            } else {
                delay = max(15.0, delay);
            }
            with self.lock, self.connect() as db {
                db.execute(
                    "INSERT OR REPLACE INTO pauses VALUES (?,?)",
                    (model, (self.clock() + delay))
                );
            }
        } finally {
            with self.lock, self.connect() as db {
                db.execute("UPDATE calls SET active=0 WHERE rowid=?", (call_id, ));
            }
        }
        if (result is not None) {
            with self.lock {
                self.cache[key] = (self.clock(), result);
                while (len(self.cache) > 128) {
                    self.cache.popitem(last=False);
                }
            }
        }
        return result;
    }
}
with entry {
    guard = UsageGuard(
        Path(
            os.environ.get(
                "REPLANIVA_AI_USAGE_PATH",
                str((Path(__file__).parent / ".jac" / "model-usage.sqlite3"))
            )
        )
    );
}
def guarded_call(
    scope: str, model: str, payload: str, operation: Callable[([], any)]
) -> any {
    try {
        return guard.run(scope, model, payload, operation);
    } except (OSError, sqlite3.Error) {
        return None;
    }
}
def usage_status(scope: str) -> dict[(str, any)] {
    try {
        return guard.status(scope);
    } except (OSError, sqlite3.Error) {
        return {
            "calls": 0,
            "remaining": 0,
            "units": 0,
            "unit_limit": 0,
            "paused": True,
            "models": "Usage storage unavailable"
        };
    }
}
