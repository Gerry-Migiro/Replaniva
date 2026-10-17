"""Quota safety tests using temporary storage and no provider requests."""
import os;
import tempfile;
import threading;
import unittest;
import from concurrent.futures { ThreadPoolExecutor }
import from email.utils { formatdate }
import from pathlib { Path }
import from unittest.mock { patch }
import from model_usage { UsageGuard, configured_models }
class UsageTests(unittest.TestCase) {
    def setUp(self: UsageTests) -> any {
        self.temp = tempfile.TemporaryDirectory();
        self.addCleanup(self.temp.cleanup);
        self.env = patch.dict(os.environ, {}, clear=True);
        self.env.start();
        self.addCleanup(self.env.stop);
        self.now = 1000000.0;
        self.path = Path(self.temp.name) / "usage.sqlite3";
        self.guard = UsageGuard(self.path, lambda() { self.now; });
    }
    def call(
        self: UsageTests,
        payload: any = "request",
        scope: any = "alice",
        operation: any = lambda() { "answer"; }
    ) -> any {
        return self.guard.run(scope, "gemini/test", payload, operation);
    }
    def test_cache_is_private_and_invalidated_by_context(self: UsageTests) -> any {
        calls = [];
        operation = lambda() { (calls.append(1) or "answer"); };
        self.call(operation=operation);
        self.call(operation=operation);
        self.call(scope="bob", operation=operation);
        self.call(payload="changed plan", operation=operation);
        self.assertEqual(len(calls), 3);
        self.assertEqual(self.guard.status("alice")["calls"], 2);
        self.assertEqual(self.guard.status("bob")["calls"], 1);
    }
    def test_cache_expires(self: UsageTests) -> any {
        self.call();
        self.now += 301;
        self.call();
        self.assertEqual(self.guard.status("alice")["calls"], 2);
    }
    def test_daily_limits_survive_restart_and_reset_at_utc_midnight(
        self: UsageTests
    ) -> any {
        os.environ["REPLANIVA_AI_DAILY_CALLS"] = "1";
        self.assertEqual(self.call(), "answer");
        restarted = UsageGuard(self.path, lambda() { self.now; });
        self.assertIsNone(
            restarted.run(
                "alice", "gemini/test", "new", lambda() { self.fail("unmetered call"); }
            )
        );
        self.now = (int((self.now // 86400)) + 1) * 86400;
        self.assertEqual(
            restarted.run("alice", "gemini/test", "new", lambda() { "new"; }), "new"
        );
    }
    def test_server_budget_cannot_be_bypassed_with_another_account(
        self: UsageTests
    ) -> any {
        os.environ["REPLANIVA_AI_SERVER_DAILY_CALLS"] = "1";
        self.call();
        self.assertIsNone(
            self.call(
                scope="bob", operation=lambda() { self.fail("server budget bypass"); }
            )
        );
    }
    def test_context_and_allowance_bounds_skip_provider(self: UsageTests) -> any {
        self.assertIsNone(
            self.call(
                payload=("x" * 8001),
                operation=lambda() { self.fail("oversized request"); }
            )
        );
        os.environ["REPLANIVA_AI_DAILY_UNITS"] = "1";
        self.assertIsNone(
            self.call(operation=lambda() { self.fail("allowance bypass"); })
        );
        self.assertEqual(self.guard.status("alice")["calls"], 0);
    }
    def test_rate_window_and_recovery(self: UsageTests) -> any {
        os.environ["REPLANIVA_AI_RPM"] = "1";
        self.call();
        self.assertIsNone(self.call(payload="second"));
        self.now += 61;
        self.assertEqual(self.call(payload="second"), "answer");
    }
    def test_minute_allowance_limits_large_requests(self: UsageTests) -> any {
        os.environ["REPLANIVA_AI_MINUTE_UNITS"] = "3000";
        self.assertEqual(self.call(), "answer");
        self.assertIsNone(
            self.call(
                payload="second",
                operation=lambda() { self.fail("minute allowance bypass"); }
            )
        );
        self.now += 61;
        self.assertEqual(self.call(payload="second"), "answer");
    }
    def test_default_allowance_completes_bounded_tool_sequence(self: UsageTests) -> any {
        for step in range(4) {
            self.assertEqual(self.call(payload=("x" * 7999) + str(step)), "answer");
        }
        self.assertIsNone(self.call(payload="extra", operation=lambda() { self.fail("RPM limit bypass"); }));
        self.assertEqual(self.guard.status("alice")["calls"], 4);
    }
    def test_failure_is_counted_and_cooldown_survives_restart(
        self: UsageTests
    ) -> any {
        class RateLimitError(Exception) {
            with entry {
                response = `type("Response", (), {"headers": {"retry-after": "120"}})();
            }
        }
        def failed() -> any {
            raise RateLimitError("secret must never be stored");
        }
        self.assertIsNone(self.call(operation=failed));
        second = UsageGuard(self.path, lambda() { self.now; });
        self.assertIsNone(
            second.run(
                "bob", "gemini/test", "new", lambda() { self.fail("cooldown ignored"); }
            )
        );
        self.assertEqual(
            second.run("alice", "groq/test", "new", lambda() { "backup"; }), "backup"
        );
        self.now += 121;
        self.assertEqual(self.call(), "answer");
        self.assertNotIn(b'secret', self.path.read_bytes());
    }
    def test_http_date_retry_after_is_respected(self: UsageTests) -> any {
        class RateLimitError(Exception) {}
        error = RateLimitError();
        setattr(error, "response", `type(
            "Response",
            (),
            {"headers": {"retry-after": formatdate((self.now + 120), usegmt=True)}}
        )());
        def failed() -> any {
            raise error;
        }
        self.assertIsNone(self.call(operation=failed));
        self.now += 61;
        self.assertIsNone(self.call());
        self.now += 60;
        self.assertEqual(self.call(), "answer");
    }
    def test_separate_guard_instances_share_concurrency_guard(
        self: UsageTests
    ) -> any {
        (started, release) = (threading.Event(), threading.Event());
        second = UsageGuard(self.path, lambda() { self.now; });
        def slow() -> any {
            started.set();
            self.assertTrue(release.wait(3));
            return "answer";
        }
        with ThreadPoolExecutor(max_workers=1) as pool {
            pending = pool.submit(self.call, operation=slow);
            try {
                self.assertTrue(started.wait(3));
                self.assertIsNone(
                    second.run(
                        "bob",
                        "groq/test",
                        "other",
                        lambda() { self.fail("concurrent call"); }
                    )
                );
            } finally {
                release.set();
            }
            self.assertEqual(pending.result(), "answer");
        }
    }
    def test_disabled_and_unconfigured_providers(self: UsageTests) -> any {
        self.assertEqual(configured_models(), []);
        os.environ["GOOGLE_API_KEY"] = "mock";
        self.assertEqual(configured_models(), ["gemini/gemini-2.5-flash"]);
        os.environ.update(
            REPLANIVA_AI_BACKUP_MODEL="groq/example", GROQ_API_KEY="mock"
        );
        self.assertEqual(len(configured_models()), 2);
        os.environ["REPLANIVA_AI_ENABLED"] = "0";
        self.assertEqual(configured_models(), []);
    }
    def test_local_model_requires_no_hosted_key(self: UsageTests) -> any {
        os.environ["BYLLM_DEFAULT_MODEL"] = "ollama/example";
        self.assertEqual(configured_models(), ["ollama/example"]);
    }
}
with entry {
    if (__name__ == "__main__") {
        unittest.main();
    }
}



test "model allowance regression suite" {
    import io;
    output = io.StringIO();
    suite = unittest.TestLoader().loadTestsFromTestCase(UsageTests);
    result = unittest.TextTestRunner(stream=output).run(suite);
    assert result.testsRun > 0 and result.wasSuccessful(), output.getvalue();
    print("MODEL_ALLOWANCE_CHECKS", result.testsRun);
}
