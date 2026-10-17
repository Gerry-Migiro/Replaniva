"""An account-owned command console over the shared planner, with no process execution."""
import shlex;
import secrets;
import time;
import threading;
import from .command_parser { make_parser }
import from .endpoints {
    Board, Action, require_account, settings, resolved_day, get_board, create_task,
    set_task_done, preview_recovery, accept_recovery, dismiss_recovery, restore_revision,
    create_goal, toggle_goal, delete_goal, secretary_run, secretary_notifications,
    secretary_notification, apply_command_proposal, dismiss_command_proposal,
    apply_rebalance_candidate, preview_task_breakdown, apply_task_breakdown
}
import from .intelligence { clock_label }
import from .date_labels { day_label }

obj ConsoleReply {
    has ok: bool, output: str, review_id: str = "", changed: bool = False;
}
obj ConsoleReview {
    has owner: str, day: str, version: int, operation: str,
        arguments: dict[str, any], summary: str, expires: float;
}
glob console_reviews: dict[str, ConsoleReview] = {};
glob console_lock: any = threading.RLock();
glob console_commands: list[str] = ["today", "briefing", "next", "week", "health", "goals", "activity", "notifications", "ask", "secretary", "add", "done", "report", "plan", "goal", "rebalance", "breakdown", "proposals", "proposal", "notification"];

def console_help() -> str {
    return "Replaniva account command console\n" +
        "today | briefing | next | week | health | goals | activity | notifications\n" +
        "ask \"What should I do next?\" | secretary \"Check my dependencies\"\n" +
        "add \"Task title\" --minutes 30 --due 18:00 [--priority 1|2|3]\n" +
        "done NUMBER | report \"Change\" --start 14:00 --end 15:00\n" +
        "plan [view|accept minimal|accept deadline|restore|dismiss]\n" +
        "proposals | proposal accept NUMBER | proposal dismiss NUMBER\n" +
        "goal add \"Title\" [--target YYYY-MM-DD] | goal toggle NUMBER | goal delete NUMBER\n" +
        "rebalance | breakdown NUMBER [--apply] | notification NUMBER read|dismiss|snooze\n" +
        "confirm REVIEW_ID | cancel REVIEW_ID | clear | help\n" +
        "Saved-plan changes require a separate confirmation. No shell commands are available.";
}
def console_minutes(value: str) -> int {
    parts = value.split(":");
    if len(parts) != 2 { raise ValueError("Use a valid HH:MM time."); }
    hour = int(parts[0]); minute = int(parts[1]);
    if hour < 0 or hour > 23 or minute < 0 or minute > 59 { raise ValueError("Use a valid HH:MM time."); }
    return hour * 60 + minute;
}
def console_board(board: Board, kind: str = "today") -> str {
    lines: list[str] = ["PLAN  " + day_label(board.day), "Version " + str(board.version), "─" * 48];
    if kind in ["today", "briefing", "health", "next"] {
        lines.extend([board.briefing.headline, "", "NEXT ACTION", "  " + board.briefing.next_action.title,
            "", "CAPACITY", "  Available  " + str(board.briefing.health.available_minutes) + " min",
            "  Required   " + str(board.briefing.health.required_minutes) + " min",
            "  Slack      " + str(board.briefing.health.slack_minutes) + " min"]);
    }
    if kind == "today" {
        lines.extend(["", "FIXED COMMITMENTS"]);
        if not board.commitments { lines.append("  None on this day."); }
        for item in board.commitments { lines.append("  " + clock_label(item.start) + "–" + clock_label(item.end) + "  " + item.title); }
        lines.extend(["", "TASKS  (" + str(len(board.tasks)) + ")"]);
        for (index, task) in enumerate(board.tasks, 1) {
            state = "Done" if task.done else "Unplaced" if task.start < 0 else clock_label(task.start) + "–" + clock_label(task.start + task.duration);
            lines.extend(["", "  " + str(index) + ". " + task.title,
                "     " + state + "  ·  " + str(task.duration) + " min",
                "     Due  " + day_label(task.due_day or board.day) + " at " + clock_label(task.deadline)]);
            if task.depends_on {
                names = [item.title for item in board.tasks if item.id in task.depends_on];
                lines.append("     Depends on  " + ", ".join(names));
            }
        }
        if not board.tasks { lines.append("  No tasks on this day."); }
    }
    if kind == "week" {
        lines.append("SEVEN-DAY OUTLOOK");
        for item in board.horizon { lines.extend(["", day_label(item.day) + "  ·  " + item.label,
            "  Work " + str(item.required_minutes) + " min  /  Available " + str(item.available_minutes) + " min"]); }
    }
    if kind == "goals" {
        lines.append("GOALS");
        for (index, goal) in enumerate(board.goals, 1) { lines.extend(["", str(index) + ". " + goal.title,
            "  " + str(goal.completed_tasks) + "/" + str(goal.total_tasks) + " tasks complete" + ("  ·  Target " + day_label(goal.target_date) if goal.target_date else "")]); }
        if not board.goals { lines.append("  No goals yet."); }
    }
    if kind == "activity" {
        lines.append("RECENT ACTIVITY");
        for item in board.activities { lines.extend(["", day_label(item.day) + "  ·  " + item.title, "  " + item.detail]); }
        if not board.activities { lines.append("  No recent planning activity."); }
    }
    if kind == "proposals" {
        lines.append("PENDING PROPOSALS");
        for (index, item) in enumerate(board.command_proposals, 1) { lines.extend(["", str(index) + ". " + item.title, "  " + item.details]); }
        if not board.command_proposals { lines.append("  No pending Command proposals."); }
    }
    if kind == "plan" {
        if board.proposal is not None {
            proposal = board.proposal;
            lines.extend(["RECOVERY PREVIEW", proposal.title + "  " + clock_label(proposal.start) + "–" + clock_label(proposal.end)]);
            for choice in [proposal.minimal, proposal.deadline] {
                lines.extend(["", choice.key.upper() + "  " + choice.label, "  " + str(choice.moved) + " moved  ·  " + str(len(choice.unplaced)) + " unplaced"]);
                for slot in choice.slots {
                    names = [task.title for task in board.tasks if task.id == slot.task_id];
                    lines.append("  " + clock_label(slot.start) + "–" + clock_label(slot.end) + "  " + (names[0] if names else "Task"));
                }
            }
            lines.extend(["", "Saved plan unchanged.", "Use plan accept minimal or plan accept deadline to request approval."]);
        } else { lines.append("No recovery awaiting approval."); }
        for revision in board.revisions { lines.append(("Restored: " if revision.restored else "Accepted: ") + revision.title); }
    }
    return "\n".join(lines);
}

def console_stage(board: Board, operation: str, arguments: dict[str, any], summary: str) -> ConsoleReply {
    with console_lock {
        now = time.time();
        for key in list(console_reviews) {
            if console_reviews[key].expires < now { console_reviews.pop(key); }
        }
        if len(console_reviews) >= 500 { return ConsoleReply(ok=False, output="Too many pending reviews. Try again later."); }
        ticket = secrets.token_urlsafe(24);
        console_reviews[ticket] = ConsoleReview(owner=jid(root), day=board.day, version=board.version,
            operation=operation, arguments=arguments, summary=summary, expires=now + 300.0);
    }
    return ConsoleReply(ok=True, output="Review proposed change:\n" + summary + "\nYour plan has not changed. Review expires in five minutes.\nconfirm " + ticket + "\ncancel " + ticket, review_id=ticket);
}
def console_apply(operation: str, arguments: dict[str, any]) -> Action {
    if operation == "create_task" { return create_task(**arguments); }
    if operation == "set_task_done" { return set_task_done(**arguments); }
    if operation == "accept_recovery" { return accept_recovery(**arguments); }
    if operation == "restore_revision" { return restore_revision(**arguments); }
    if operation == "create_goal" { return create_goal(**arguments); }
    if operation == "toggle_goal" { return toggle_goal(**arguments); }
    if operation == "delete_goal" { return delete_goal(**arguments); }
    if operation == "apply_command_proposal" { return apply_command_proposal(**arguments); }
    if operation == "apply_rebalance_candidate" { return apply_rebalance_candidate(**arguments); }
    if operation == "apply_task_breakdown" { return apply_task_breakdown(**arguments); }
    return Action(ok=False, message="That operation is not available in this console.");
}

def console_confirm(ticket: str, cancel: bool = False) -> ConsoleReply {
    require_account();
    with console_lock {
        review = console_reviews.get(ticket);
        if review is None or review.owner != jid(root) { return ConsoleReply(ok=False, output="Review unavailable. It may have expired or already been used."); }
    }
    assert review is not None;
    if cancel {
        console_forget(ticket);
        return ConsoleReply(ok=True, output="Review cancelled. Your plan was not changed.");
    }
    if review.expires < time.time() { console_forget(ticket); return ConsoleReply(ok=False, output="Review expired. Request a new review."); }
    if settings().version != review.version { console_forget(ticket); return ConsoleReply(ok=False, output="Your plan changed. Request a fresh review before confirming."); }
    result = console_apply(review.operation, review.arguments);
    # Keep the review until persistence succeeds, including Jac's transaction retries.
    # A repeated request also has to pass the saved planning version check.
    if result.ok { on_commit(lambda -> None { console_forget(ticket); }); }
    return ConsoleReply(ok=result.ok, output=result.message, changed=result.ok);
}

def console_forget(ticket: str) -> None {
    with console_lock { console_reviews.pop(ticket, None); }
}

def:protect console_execute(command: str, day: str = "") -> ConsoleReply {
    require_account();
    if not command.strip() or len(command) > 600 { return ConsoleReply(ok=False, output="Enter a planning command of 600 characters or fewer."); }
    try {
        words = shlex.split(command);
        if not words { return ConsoleReply(ok=False, output="Enter a planning command."); }
        name = words[0];
        if name == "help" or (name in console_commands and any(w in ["--help", "-h"] for w in words[1:])) { return ConsoleReply(ok=True, output=console_help()); }
        if name == "clear" and len(words) == 1 { return ConsoleReply(ok=True, output=""); }
        if name in ["confirm", "cancel"] {
            if len(words) != 2 { return ConsoleReply(ok=False, output="Use " + name + " REVIEW_ID."); }
            return console_confirm(words[1], name == "cancel");
        }
        if name not in console_commands { return ConsoleReply(ok=False, output="Unknown planning command. Type help for supported commands. This console cannot run shell commands."); }
        args: any = make_parser().parse_args(words);
        current_day = resolved_day(day);
        board = get_board(current_day);
        if name in ["today", "briefing", "health", "next", "week", "goals", "activity", "proposals"] { return ConsoleReply(ok=True, output=console_board(board, name)); }
        if name in ["ask", "secretary"] {
            run = secretary_run(query=args.question, day=current_day, use_model=True);
            return ConsoleReply(ok=run.reply.ok, output=run.reply.title + "\n" + run.reply.message + "\n" + "\n".join(run.steps));
        }
        if name == "notifications" {
            items = secretary_notifications();
            return ConsoleReply(ok=True, output="\n".join([str(i + 1) + ". " + item.title + " | " + item.message for (i, item) in enumerate(items)]) if items else "Your secretary inbox is clear.");
        }
        if name == "notification" {
            items = secretary_notifications();
            if args.number < 1 or args.number > len(items) { raise ValueError("Choose a number from notifications."); }
            notification_result = secretary_notification(items[args.number - 1].id, args.action);
            return ConsoleReply(ok=notification_result.ok, output=notification_result.message, changed=notification_result.ok);
        }
        if name == "add" {
            values: dict[str, any] = {"title": args.title, "day": current_day, "duration": args.minutes, "deadline": console_minutes(args.due), "due_day": args.due_day, "preferred_start": console_minutes(args.at) if args.at else -1, "priority": args.priority};
            return console_stage(board, "create_task", values, "Add " + args.title + " on " + current_day + ", " + str(args.minutes) + " minutes, due " + args.due + ". The shared planner validates and arranges the day on confirmation.");
        }
        if name == "done" {
            if args.number < 1 or args.number > len(board.tasks) { raise ValueError("Choose a task number shown by today."); }
            task = board.tasks[args.number - 1];
            return console_stage(board, "set_task_done", {"task_id": task.id, "done": True}, "Mark " + task.title + " complete.");
        }
        if name == "report" {
            result = preview_recovery(args.title, current_day, console_minutes(args.start), console_minutes(args.end), args.with_model);
            return ConsoleReply(ok=result.ok, output=result.message + "\n" + console_board(get_board(current_day), "plan"));
        }
        if name == "plan" {
            if args.action == "view" { return ConsoleReply(ok=True, output=console_board(board, "plan")); }
            if args.action == "restore" {
                active = [r for r in board.revisions if not r.restored];
                if not active { raise ValueError("No recovery is available to restore."); }
                return console_stage(board, "restore_revision", {"revision_id": active[-1].id}, "Restore the plan before " + active[-1].title + ".");
            }
            if board.proposal is None { raise ValueError("No recovery is awaiting approval."); }
            if args.action == "dismiss" {
                result = dismiss_recovery(board.proposal.id); return ConsoleReply(ok=result.ok, output=result.message);
            }
            if not args.choice { raise ValueError("Choose minimal or deadline."); }
            return console_stage(board, "accept_recovery", {"proposal_id": board.proposal.id, "option": args.choice}, "Apply " + args.choice + " recovery for " + board.proposal.title + ".\n" + console_board(board, "plan"));
        }
        if name == "proposal" {
            if args.number < 1 or args.number > len(board.command_proposals) { raise ValueError("Choose a number from proposals."); }
            proposal = board.command_proposals[args.number - 1];
            if args.proposal_action == "dismiss" {
                result = dismiss_command_proposal(proposal.id); return ConsoleReply(ok=result.ok, output=result.message);
            }
            return console_stage(board, "apply_command_proposal", {"proposal_id": proposal.id}, proposal.title + "\n" + proposal.details);
        }
        if name == "goal" {
            if args.goal_action == "add" { return console_stage(board, "create_goal", {"title": args.title, "target_date": args.target, "importance": args.importance}, "Add goal " + args.title + "."); }
            if args.number < 1 or args.number > len(board.goals) { raise ValueError("Choose a number from goals."); }
            goal = board.goals[args.number - 1];
            return console_stage(board, "toggle_goal" if args.goal_action == "toggle" else "delete_goal", {"goal_id": goal.id}, args.goal_action + " goal " + goal.title + ".");
        }
        if name == "rebalance" {
            candidate = board.rebalance;
            if not candidate.available { raise ValueError("No safe rebalance is currently available."); }
            return console_stage(board, "apply_rebalance_candidate", {"from_day": candidate.from_day, "to_day": candidate.to_day, "task_id": candidate.task_id}, "Move " + candidate.task_title + " from " + candidate.from_day + " to " + candidate.to_day + ".");
        }
        if name == "breakdown" {
            if args.number < 1 or args.number > len(board.tasks) { raise ValueError("Choose a task number shown by today."); }
            draft = preview_task_breakdown(board.tasks[args.number - 1].id);
            if not draft.ok { return ConsoleReply(ok=False, output=draft.message); }
            summary = "\n".join([step.title + " | " + str(step.duration) + "m" for step in draft.subtasks]);
            if not args.apply { return ConsoleReply(ok=True, output=summary + "\nUse breakdown NUMBER --apply to request confirmation."); }
            return console_stage(board, "apply_task_breakdown", {"task_id": draft.task_id, "titles": [step.title for step in draft.subtasks], "durations": [step.duration for step in draft.subtasks], "expected_version": draft.base_version}, summary);
        }
        return ConsoleReply(ok=False, output="Use help to choose a supported planning command.");
    } except (ValueError, TypeError, IndexError) as error {
        return ConsoleReply(ok=False, output="Check the command: " + str(error));
    }
}
