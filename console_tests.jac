"""Real private-graph command reviews, without providers or shell processes."""
import from .secretary_tests { SecretaryFixture }
import from .console_api { console_execute, console_reviews, console_confirm, console_apply }
import from .endpoints { get_board, create_task, settings }
import from .command_parser { make_parser }
import from jaclang { JacRuntime as Jac }
import from jaclang.runtime.archetype { Root }
import from unittest.mock { patch }
import time;

test "shared grammar preserves task and recovery command options" {
    task = make_parser().parse_args(["add", "Project brief", "--minutes", "45", "--due", "18:00", "--priority", "3"]);
    assert task.title == "Project brief" and task.minutes == 45 and task.priority == 3;
    assert make_parser().parse_args(["plan", "dismiss"]).action == "dismiss";
}

test "browser console rejects shell and execution commands before any operation" {
    fixture = SecretaryFixture(); fixture.start();
    try {
        for text in ["sh", "bash -c env", "python -c print(1)", "jac run main.jac", "cat .env", "ls", "env", "login somebody", "today ; env", "add", "ask \"unterminated"] {
            reply = console_execute(text, "2099-03-01");
            assert not reply.ok;
        }
        assert console_execute("help").ok;
        assert len(get_board("2099-03-01").tasks) == 0;
        assert not console_apply("__import__", {}).ok;
    } finally { fixture.close(); }
}

test "task capture requires separate single use confirmation and shares saved graph" {
    fixture = SecretaryFixture(); fixture.start();
    try {
        day = "2099-03-01";
        preview = console_execute('add "Project brief" --minutes 45 --due 18:00', day);
        assert preview.ok and preview.review_id;
        assert not get_board(day).tasks;
        confirmed = console_execute("confirm " + preview.review_id, day);
        assert confirmed.ok and confirmed.changed;
        board = get_board(day);
        assert len(board.tasks) == 1 and board.tasks[0].title == "Project brief";
        assert board.tasks[0].duration == 45;
        assert not console_execute("confirm " + preview.review_id, day).ok;
        assert len(get_board(day).tasks) == 1;
        output = console_execute("today", day).output;
        assert "Project brief" in output and "TASKS" in output;
        assert "Due" in output and "min" in output;
        done = console_execute("done 1", day);
        assert not get_board(day).tasks[0].done;
        assert console_execute("confirm " + done.review_id, day).ok;
        assert get_board(day).tasks[0].done;
    } finally { fixture.close(); }
}

test "stale expired cancelled and foreign reviews never mutate a plan" {
    fixture = SecretaryFixture(); fixture.start();
    try {
        day = "2099-03-01";
        stale = console_execute('add "Stale task"', day);
        assert create_task("Another change", day).ok;
        assert not console_confirm(stale.review_id).ok;
        expired = console_execute('add "Expired task"', day);
        console_reviews[expired.review_id].expires = time.time() - 1.0;
        assert not console_confirm(expired.review_id).ok;
        cancelled = console_execute('add "Cancelled task"', day);
        assert console_confirm(cancelled.review_id, True).ok;
        assert not console_confirm(cancelled.review_id).ok;
        foreign = console_execute('add "Owned task"', day);
        owner = jid(root);
        other = root ++> Root(); Jac.save(other); Jac.commit();
        Jac.get_context().set_user_root(jid(other));
        assert not console_confirm(foreign.review_id).ok;
        assert not console_confirm(foreign.review_id, True).ok;
        assert not get_board(day).tasks;
        Jac.get_context().set_user_root(owner);
        assert console_confirm(foreign.review_id).ok;
        assert len(get_board(day).tasks) == 2;
    } finally { fixture.close(); }
}

test "recovery console previews without mutations and applies one validated choice" {
    fixture = SecretaryFixture(); fixture.start();
    try {
        day = "2099-03-01";
        assert create_task("Prepare project brief", day, 60, 1200).ok;
        before = get_board(day);
        preview = console_execute('report "Team meeting" --start 08:00 --end 09:00', day);
        assert preview.ok and "minimal" in preview.output and "deadline" in preview.output;
        reviewed = get_board(day);
        assert reviewed.version == before.version;
        assert reviewed.tasks[0].start == before.tasks[0].start and not reviewed.commitments;
        approval = console_execute("plan accept deadline", day);
        assert approval.review_id and not get_board(day).commitments;
        assert console_confirm(approval.review_id).ok;
        assert len(get_board(day).commitments) == 1;
        assert get_board(day).tasks[0].start >= 540;
        restore = console_execute("plan restore", day);
        assert console_confirm(restore.review_id).ok;
        assert not get_board(day).commitments;
    } finally { fixture.close(); }
}
