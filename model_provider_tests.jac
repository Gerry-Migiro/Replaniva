"""Real ByLLM request construction with mock replies, never cloud calls."""
import ai;
import model_usage;
import from ai { PlanningModel, SuggestedPlan, SuggestedStart, InterpretedDisruption, optional_model_choice, optional_interpret_note }
import from planning { Work, Busy, validate }
import from jaclang.byllm.lib { MockLLM }
import from model_usage { UsageGuard }
import from os { environ }
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from unittest.mock { patch }

test "invalid model schedule is revised and validated with a bounded loop" {
    work = [Work(id="study", title="Study", duration=60, deadline=1080)];
    busy = [Busy(title="Lab", start=840, end=1020)];
    rejected = SuggestedPlan(starts=[SuggestedStart(task_id="study", start=900)], explanation="Invalid overlap");
    accepted = SuggestedPlan(starts=[SuggestedStart(task_id="study", start=1020)], explanation="Study after the lab");
    mock = MockLLM(outputs=[rejected, accepted]);
    runner = PlanningModel(model=mock);
    assert str(runner) == "Replaniva planning model";
    with TemporaryDirectory() as directory {
      with patch.dict(environ, {"GOOGLE_API_KEY": "mock"}, clear=True) {
        with patch.object(model_usage, "guard", UsageGuard(Path(directory) / "usage.sqlite3")) {
          with patch.object(ai, "model_runner", return_value=runner) {
            choice = optional_model_choice(work, busy, 480, 1320, "test");
            assert choice is not None;
            assert validate(choice.slots, work, busy, 480, 1320);
            assert choice.slots[0].start == 1020;
            assert model_usage.usage_status("test")["calls"] == 2;
            assert "Invalid overlap" not in str(mock.sent("messages")[0]);
            assert "overlaps" in str(mock.sent("messages")[1]);
          }
        }
      }
    }
}

test "configured backup can supply a validated choice" {
    work = [Work(id="study", title="Study", duration=60, deadline=1080)];
    invalid = PlanningModel(model=MockLLM(outputs=[SuggestedPlan(starts=[], explanation="Missing task")]));
    backup = PlanningModel(model=MockLLM(outputs=[SuggestedPlan(starts=[SuggestedStart(task_id="study", start=600)], explanation="Fits")]));
    with TemporaryDirectory() as directory {
      with patch.dict(environ, {"GOOGLE_API_KEY": "mock", "GROQ_API_KEY": "mock", "REPLANIVA_AI_BACKUP_MODEL": "groq/example"}, clear=True) {
        with patch.object(model_usage, "guard", UsageGuard(Path(directory) / "usage.sqlite3")) {
          with patch.object(ai, "model_runner", side_effect=[invalid, backup]) {
            choice = optional_model_choice(work, [], 480, 1320, "test");
            assert choice is not None;
            assert choice.source == "groq/example suggested · Jac validated";
          }
        }
      }
    }
}

test "no key and exhausted budgets preserve the deterministic fallback" {
    work = [Work(id="study", title="Study", duration=60, deadline=1080)];
    with patch.dict(environ, {}, clear=True) {
        assert optional_model_choice(work, [], 480, 1320, "test") is None;
        assert optional_interpret_note("Lab 2 to 5", "2026-10-14", "test") is None;
    }
    with TemporaryDirectory() as directory {
      with patch.dict(environ, {"GOOGLE_API_KEY": "mock", "REPLANIVA_AI_DAILY_CALLS": "0"}, clear=True) {
        with patch.object(model_usage, "guard", UsageGuard(Path(directory) / "usage.sqlite3")) {
          with patch.object(ai, "model_runner", return_value=PlanningModel(model=MockLLM(outputs=[]))) {
            assert optional_model_choice(work, [], 480, 1320, "test") is None;
            assert model_usage.usage_status("test")["calls"] == 0;
          }
        }
      }
    }
}

test "interpretation reuses an account's unchanged note without another call" {
    runner = PlanningModel(model=MockLLM(outputs=[InterpretedDisruption(title="Lab", start=840, end=1020)]));
    with TemporaryDirectory() as directory {
      with patch.dict(environ, {"GOOGLE_API_KEY": "mock"}, clear=True) {
        with patch.object(model_usage, "guard", UsageGuard(Path(directory) / "usage.sqlite3")) {
          with patch.object(ai, "model_runner", return_value=runner) {
            first = optional_interpret_note("Lab 2 to 5 pm", "2026-10-14", "test");
            repeated = optional_interpret_note("Lab 2 to 5 pm", "2026-10-14", "test");
            assert first is not None and repeated is not None;
            assert repeated.start == 840 and repeated.end == 1020;
            assert model_usage.usage_status("test")["calls"] == 1;
          }
        }
      }
    }
}
