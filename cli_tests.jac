"""Guided terminal interactions without real accounts or network mutations."""
import json;
import os;
import from unittest.mock { patch, MagicMock }
import from cli.main { guided_fields, guided_review, interactive, make_parser }

test "named CLI display handlers share the parser and never duplicate requests" {
    import from cli.main { run }
    import argparse;
    formats = {"today": "show_today", "week": "show_week", "briefing": "show_briefing", "health": "show_briefing", "next": "show_briefing", "activity": "show_activity", "goals": "show_goals", "proposals": "show_proposals"};
    for (command, formatter) in formats.items() {
        with patch("cli.main.board", return_value={}) as read {
            with patch("cli.main." + formatter) as show {
                assert run(make_parser().parse_args([command])) == 0;
                read.assert_called_once();
                show.assert_called_once();
            }
        }
    }
    with patch("urllib.request.urlopen") as network {
        assert run(argparse.Namespace(command="unknown")) == 2;
        network.assert_not_called();
    }
}

test "guided task handles invalid duration back and confirmation" {
    with patch("builtins.input", side_effect=["Read notes", "many", "45", "back", "30", "18:00", "yes"]) {
        assert guided_fields("add") == ["add", "Read notes", "--minutes", "30", "--due", "18:00"];
    }
}

test "task cancellation never reaches the server" {
    with patch.dict(os.environ, {"REPLANIVA_TOKEN": "test-only"}) {
        with patch("builtins.input", side_effect=["3", "Read notes", "30", "20:00", "no", "0"]) {
            with patch("urllib.request.urlopen") as network {
                assert interactive() == 0;
                network.assert_not_called();
            }
        }
    }
}

test "confirmed task uses the shared authenticated operation once" {
    response = MagicMock();
    response.__enter__.return_value.read.return_value = json.dumps({"ok": True, "data": {"result": {"ok": True, "message": "Saved."}}}).encode();
    with patch.dict(os.environ, {"REPLANIVA_TOKEN": "test-only"}) {
        with patch("builtins.input", side_effect=["3", "Read notes", "30", "20:00", "yes", "0"]) {
            with patch("urllib.request.urlopen", return_value=response) as network {
                assert interactive() == 0;
                network.assert_called_once();
                request = network.call_args.args[0];
                assert request.full_url.endswith("/function/create_task");
                body = json.loads(request.data);
                assert body["title"] == "Read notes" and body["duration"] == 30;
            }
        }
    }
}

test "recovery captures valid times without accepting a plan" {
    with patch("builtins.input", side_effect=["Lab", "25:00", "14:00", "13:00", "17:00"]) {
        assert guided_fields("report") == ["report", "Lab", "--start", "14:00", "--end", "17:00"];
    }
    with patch("builtins.input", side_effect=["cancel"]) { assert guided_fields("report") is None; }
}

test "onboarding and end of input exit without network calls" {
    with patch.dict(os.environ, {"REPLANIVA_TOKEN": ""}) {
        with patch("pathlib.Path.exists", return_value=False) {
            with patch("builtins.input", side_effect=["invalid", "2", "0"]) {
                with patch("urllib.request.urlopen") as network {
                    assert interactive() == 0;
                    network.assert_not_called();
                }
            }
        }
    }
    with patch("builtins.input", side_effect=EOFError()) { assert interactive() == 0; }
}

test "existing command shortcuts remain available" {
    parser = make_parser();
    assert parser.parse_args([]).command is None;
    assert parser.parse_args(["today"]).command == "today";
    args = parser.parse_args(["add", "Study", "--minutes", "45"]);
    assert args.command == "add" and args.minutes == 45;
}


test "review accepts the displayed proposal identity only after confirmation" {
    board_response = MagicMock();
    board_response.__enter__.return_value.read.return_value = json.dumps({"ok": True, "data": {"result": {"proposal": None, "command_proposals": [{"id": "displayed-proposal", "title": "Study", "details": "Study for 30 minutes"}]}}}).encode();
    action_response = MagicMock();
    action_response.__enter__.return_value.read.return_value = json.dumps({"ok": True, "data": {"result": {"ok": False, "message": "This proposal is stale. Review a fresh proposal."}}}).encode();
    with patch.dict(os.environ, {"REPLANIVA_TOKEN": "test-only"}) {
        with patch("builtins.input", side_effect=["1", "1", "yes"]) {
            with patch("urllib.request.urlopen", side_effect=[board_response, action_response]) as network {
                guided_review();
                assert network.call_count == 2;
                request = network.call_args.args[0];
                assert request.full_url.endswith("/apply_command_proposal");
                assert json.loads(request.data)["proposal_id"] == "displayed-proposal";
            }
        }
        with patch("builtins.input", side_effect=["1", "1", "no"]) {
            with patch("urllib.request.urlopen", return_value=board_response) as network {
                guided_review();
                network.assert_called_once();
            }
        }
    }
}
