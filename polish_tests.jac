"""Model-independent planning suggestions use the shared private graph."""
import from .secretary_tests { SecretaryFixture }
import from .endpoints { secretary_run, get_board }
import from . { secretary }
import from unittest.mock { patch }

test "all suggested planning questions work when model calls are unavailable" {
    fixture = SecretaryFixture(); fixture.start();
    try {
        day = "2099-03-01";
        before = get_board(day);
        with patch.object(secretary, "secretary_advice", side_effect=RuntimeError("Provider is offline")) as model {
            for query in ["What should I do next?", "What is at risk?", "Can I finish everything today?", "Help me adjust my plan", "Explain my plan", "Show my dependencies", "Show my goal progress"] {
                result = secretary_run(query=query, day=day, use_model=True);
                assert result.reply.ok and result.source == "Deterministic Jac";
                assert result.reply.proposal is None;
            }
            assert model.call_count == 0;
        }
        after = get_board(day);
        assert after.version == before.version and not after.tasks and not after.commitments;
    } finally { fixture.close(); }
}
