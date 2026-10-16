"""Replaniva terminal client for the same private plan used by web and mobile."""

import argparse;
import from accounts { normalize_username }
import re;
import getpass;
import json;
import os;
import sys;
import urllib.request;
import urllib.error;
import from pathlib { Path }


def token_path() -> Path {
    return Path.home() / ".config" / "replaniva" / "token";
}

def saved_token() -> str {
    env_token = os.environ.get("REPLANIVA_TOKEN", "");
    if env_token { return env_token; }
    path = token_path();
    return path.read_text().strip() if path.exists() else "";
}

def endpoint(path: str, body: dict[str, any], token: str = "") -> dict[str, any] {
    base = os.environ.get("REPLANIVA_URL", "http://127.0.0.1:8101").rstrip("/");
    headers = {"Content-Type": "application/json"};
    if token { headers["Authorization"] = "Bearer " + token; }
    request = urllib.request.Request(base + path, data=json.dumps(body).encode(), headers=headers);
    try {
        with urllib.request.urlopen(request, timeout=15) as response {
            payload = json.loads(response.read().decode());
        }
    } except urllib.error.HTTPError as error {
        if error.code == 401 { raise RuntimeError("Sign in with `jac run cli -- login USERNAME` first."); }
        raise RuntimeError(f"Server rejected this action (HTTP {error.code}).");
    } except urllib.error.URLError {
        raise RuntimeError("Replaniva server is unreachable. Start it with `jac run` in another terminal.");
    }
    if not payload.get("ok", False) { raise RuntimeError("Replaniva could not complete the request."); }
    return payload.get("data", {}).get("result", payload.get("data", {}));
}

def call(name: str, body: dict[str, any] | None = None) -> dict[str, any] {
    body = body if body is not None else {};
    token = saved_token();
    if not token { raise RuntimeError("Sign in with `jac run cli -- login USERNAME` first."); }
    return endpoint("/function/" + name, body, token);
}

def minutes(value: str) -> int {
    parts = value.split(":");
    if len(parts) != 2 { raise ValueError("Use HH:MM, for example 14:00."); }
    hour = int(parts[0]);
    minute = int(parts[1]);
    if hour < 0 or hour > 23 or minute < 0 or minute > 59 {
        raise ValueError("Use a valid 24-hour time.");
    }
    return hour * 60 + minute;
}

def time_label(value: int) -> str {
    if value < 0 { return "unplaced"; }
    return f"{value // 60:02d}:{value % 60:02d}";
}

def board() -> dict[str, any] { return call("get_board"); }

def duration_label(value: int) -> str {
    sign = "-" if value < 0 else "";
    safe = abs(value);
    hours = safe // 60;
    remainder = safe % 60;
    if hours and remainder { return sign + str(hours) + "h " + str(remainder) + "m"; }
    if hours { return sign + str(hours) + "h"; }
    return sign + str(remainder) + "m";
}

def show_briefing(data: dict[str, any], section: str = "all") -> None {
    briefing = data["briefing"];
    health = briefing["health"];
    action = briefing["next_action"];
    if section in ["all", "health"] {
        print("Plan health: " + health["label"]);
        print("  " + briefing["headline"]);
        print("  " + briefing["summary"]);
        print("  Capacity: " + duration_label(health["available_minutes"]) +
              " available, " + duration_label(health["required_minutes"]) + " needed");
        print("  Slack: " + duration_label(health["slack_minutes"]));
        for reason in health["reasons"] { print("  - " + reason); }
    }
    if section == "all" { print(""); }
    if section in ["all", "next"] {
        timing = "";
        if action["start"] >= 0 {
            timing = " at " + time_label(action["start"]);
            if action["end"] >= 0 { timing += " to " + time_label(action["end"]); }
        }
        print("Next action: " + action["title"] + timing);
        print("  " + action["reason"]);
    }
    if section == "all" and briefing["risks"] {
        print("\nRisk radar:");
        for risk in briefing["risks"] {
            print("  " + risk["title"]);
            print("    " + risk["detail"] + " " + risk["action_label"] + ".");
        }
    }
}

def show_today(data: dict[str, any]) -> None {
    print("Replaniva · " + data["day"]);
    print("Flexible hours: " + time_label(data["day_start"]) + " to " + time_label(data["day_end"]));
    print("Fixed commitments:");
    for event in data["commitments"] {
        print(f"  {time_label(event['start'])}–{time_label(event['end'])}  {event['title']}");
    }
    if not data["commitments"] { print("  None yet"); }
    print("Tasks:");
    for (index, task) in enumerate(data["tasks"], 1) {
        state = "done" if task["done"] else time_label(task["start"]);
        print(f"  {index}. {task['title']} · {state} · due {task['due_day']} at {time_label(task['deadline'])}");
    }
    if not data["tasks"] { print("  None yet"); }
}

def show_week(data: dict[str, any]) -> None {
    print("Replaniva seven-day outlook");
    for outlook in data["horizon"] {
        pressure = duration_label(outlook["slack_minutes"]) + " slack";
        if outlook["overloaded_minutes"] > 0 {
            pressure = "+" + duration_label(outlook["overloaded_minutes"]) + " over";
        }
        print("  " + outlook["day"] + "  " + outlook["label"] + "  " + pressure);
        print("    " + duration_label(outlook["required_minutes"]) + " work, " +
              duration_label(outlook["available_minutes"]) + " available");
    }
    suggestion = data["rebalance"];
    if suggestion["available"] {
        print("\nSuggested review:");
        print("  Move " + suggestion["task_title"] + " from " + suggestion["from_day"] +
              " to " + suggestion["to_day"] + " at " + time_label(suggestion["suggested_start"]));
        print("  " + suggestion["reason"]);
    }
}

def show_plan(data: dict[str, any], guided: bool = False) -> None {
    proposal = data["proposal"];
    if proposal is None {
        print("No recovery is awaiting approval. Use `report` when plans change.");
        return;
    }
    print(f"Recovery for {proposal['title']} ({time_label(proposal['start'])}–{time_label(proposal['end'])})");
    for key in ["minimal", "deadline"] {
        choice = proposal[key];
        print("\n" + choice["label"] + " · " + choice["source"]);
        print("  " + choice["reason"]);
        for slot in choice["slots"] {
            matching = [task for task in data["tasks"] if task["id"] == slot["task_id"]];
            name = matching[0]["title"] if matching else "Task";
            print(f"  {time_label(slot['start'])}–{time_label(slot['end'])}  {name}");
        }
        for item_id in choice["unplaced"] {
            matching = [task for task in data["tasks"] if task["id"] == item_id];
            name = matching[0]["title"] if matching else "Task";
            print("  UNPLACED  " + name);
        }
    }
    if not guided { print("\nAccept with `jac run cli -- plan accept minimal` or `... deadline`."); }
}

def show_goals(data: dict[str, any]) -> None {
    goals = data.get("goals", []);
    if not goals {
        print("No goals set yet. Add one with `jac run cli -- goal add \"Title\"`.");
        return;
    }
    print("Goals:");
    for (index, goal) in enumerate(goals, 1) {
        progress = f"{goal.get('completed_tasks', 0)}/{goal.get('total_tasks', 0)} tasks done";
        target = f" · Target: {goal['target_date']}" if goal.get("target_date") else "";
        status = " [completed]" if goal.get("completed", False) else "";
        print(f"  {index}. {goal['title']}{status} · {progress}{target}");
    }
}

def show_activity(data: dict[str, any]) -> None {
    activities = data.get("activities", []);
    if not activities {
        print("No planning changes have been recorded yet.");
        return;
    }
    print("Planning activity:");
    for item in reversed(activities) {
        print("  " + item["day"] + "  " + item["title"]);
        print("    " + item["detail"]);
    }
}

def show_proposals(data: dict[str, any], guided: bool = False) -> None {
    proposals = data.get("command_proposals", []);
    if not proposals {
        print("No pending Command proposals.");
        return;
    }
    print("Pending Command proposals:");
    for (index, prop) in enumerate(proposals, 1) {
        print(f"  {index}. {prop['title']}");
        if prop.get("details") {
            print(f"     {prop['details']}");
        }
    }
    if not guided { print("\nAccept with `jac run cli -- proposal accept NUMBER` or dismiss with `... dismiss NUMBER`."); }
}

def make_parser() -> argparse.ArgumentParser {
    parser = argparse.ArgumentParser(prog="replaniva", description="Your Replaniva plan from the terminal");
    commands = parser.add_subparsers(dest="command", required=False);
    login = commands.add_parser("login", help="sign in without displaying your password or token");
    login.add_argument("username");
    commands.add_parser("logout", help="remove the saved sign-in token");
    commands.add_parser("today", help="show today's commitments and tasks");
    commands.add_parser("week", help="show seven-day workload and a safe rebalance suggestion");
    commands.add_parser("briefing", help="show plan health and the recommended next action");
    commands.add_parser("health", help="show measured plan health and its reasons");
    commands.add_parser("next", help="show the recommended next action");
    commands.add_parser("activity", help="show recent plan changes and reasons");
    commands.add_parser("notifications", help="read your private secretary inbox");
    secretary = commands.add_parser("secretary", help="investigate a planning question with the shared secretary");
    secretary.add_argument("question", nargs="?", `default="What should I do next?");
    inbox_action = commands.add_parser("notification", help="read, dismiss or snooze a notification by its displayed number");
    inbox_action.add_argument("number", `type=int);
    inbox_action.add_argument("action", choices=["read", "dismiss", "snooze"]);
    ask = commands.add_parser("ask", help="ask Replaniva a focused question about the current plan");
    ask.add_argument("question");
    add = commands.add_parser("add", help="add a task to today's plan");
    add.add_argument("title");
    add.add_argument("--minutes", `type=int, `default=60);
    add.add_argument("--due", `default="20:00");
    add.add_argument("--due-day", `default="", help="deadline date in YYYY-MM-DD (defaults to the planning day)");
    add.add_argument("--at", `default="");
    add.add_argument("--priority", `type=int, choices=[1, 2, 3], `default=2);
    done = commands.add_parser("done", help="complete a task by its number from today");
    done.add_argument("number", `type=int);
    report_cmd = commands.add_parser("report", help="preview recovery for an unexpected commitment");
    report_cmd.add_argument("title");
    report_cmd.add_argument("--start", required=True);
    report_cmd.add_argument("--end", required=True);
    report_cmd.add_argument("--with-model", action="store_true", help="request a model-assisted alternative using the configured allowance");
    plan = commands.add_parser("plan", help="view, accept, or restore a recovery");
    plan.add_argument("action", nargs="?", choices=["view", "accept", "restore"], `default="view");
    plan.add_argument("choice", nargs="?", choices=["minimal", "deadline"]);

    commands.add_parser("goals", help="list goals with progress");
    goal = commands.add_parser("goal", help="manage goals");
    goal_sub = goal.add_subparsers(dest="goal_action", required=True);
    goal_add = goal_sub.add_parser("add", help="add a goal");
    goal_add.add_argument("title");
    goal_add.add_argument("--target", `default="");
    goal_add.add_argument("--importance", choices=["low", "medium", "high"], `default="medium");
    goal_toggle = goal_sub.add_parser("toggle", help="toggle goal completion");
    goal_toggle.add_argument("number", `type=int);
    goal_delete = goal_sub.add_parser("delete", help="delete a goal");
    goal_delete.add_argument("number", `type=int);

    commands.add_parser("rebalance", help="apply active rebalance suggestion from seven-day outlook");

    breakdown_cmd = commands.add_parser("breakdown", help="preview or apply task decomposition");
    breakdown_cmd.add_argument("number", `type=int);
    breakdown_cmd.add_argument("--apply", action="store_true", `default=False);

    commands.add_parser("proposals", help="list pending Command proposals");
    proposal = commands.add_parser("proposal", help="manage Command proposals");
    proposal_sub = proposal.add_subparsers(dest="proposal_action", required=True);
    prop_accept = proposal_sub.add_parser("accept", help="accept a Command proposal");
    prop_accept.add_argument("number", `type=int);
    prop_dismiss = proposal_sub.add_parser("dismiss", help="dismiss a Command proposal");
    prop_dismiss.add_argument("number", `type=int);

    return parser;
}

def run_login(args: argparse.Namespace) -> int {
    identity = normalize_username(args.username);
    if not identity and re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", args.username.strip()) { identity = args.username.strip(); }
    if not identity { raise ValueError("Use 3 to 32 letters, numbers, underscores or hyphens for your username."); }
    password = getpass.getpass("Password: ");
    result = endpoint("/user/login", {"identity": {"type": "username", "value": identity},
                                       "credential": {"type": "password", "password": password}});
    token = result.get("token", "");
    if not token { raise RuntimeError("Sign-in failed."); }
    path = token_path();
    path.parent.mkdir(parents=True, exist_ok=True);
    path.write_text(token);
    os.chmod(path, 384);
    print("Signed in. Your token is stored privately on this device.");
    return 0;
}

def run_logout(args: argparse.Namespace) -> int {
    token_path().unlink(missing_ok=True);
    print("Signed out on this device.");
    return 0;
}

def run_today(args: argparse.Namespace) -> int {
    show_today(board());
    return 0;
}

def run_week(args: argparse.Namespace) -> int {
    show_week(board());
    return 0;
}

def run_briefing(args: argparse.Namespace) -> int {
    show_briefing(board());
    return 0;
}

def run_health(args: argparse.Namespace) -> int {
    show_briefing(board(), "health");
    return 0;
}

def run_next(args: argparse.Namespace) -> int {
    show_briefing(board(), "next");
    return 0;
}

def run_activity(args: argparse.Namespace) -> int {
    show_activity(board());
    return 0;
}

def run_notifications(args: argparse.Namespace) -> int {
    items = call("secretary_notifications", {});
    if not items { print("Your secretary inbox is clear. Enable proactive checks in Settings, Assistant."); }
    for (index, item) in enumerate(items) { print(str(index + 1) + ". " + item["title"] + "\n   " + item["message"]); }
    return 0;
}

def run_notification(args: argparse.Namespace) -> int {
    items = call("secretary_notifications", {});
    if args.number < 1 or args.number > len(items) { print("Choose a number from notifications."); return 1; }
    result = call("secretary_notification", {"notification_id": items[args.number - 1]["id"], "action": args.action});
    print(result["message"]);
    return 0 if result["ok"] else 1;
}

def run_secretary(args: argparse.Namespace) -> int {
    result = call("secretary_run", {"query": args.question});
    print(result["reply"]["title"] + "\n" + result["summary"]);
    for step in result["steps"] { print("  " + step); }
    if result["reply"].get("proposal") { print("Review it with proposals, then use proposal accept NUMBER, or open the web review."); }
    return 0 if result["reply"]["ok"] else 1;

}

def run_ask(args: argparse.Namespace) -> int {
    reply = call("secretary_run", {"query": args.question})["reply"];
    print(reply["title"]);
    print("  " + reply["message"]);
    if reply["action_label"] { print("  Suggested action: " + reply["action_label"]); }
    return 0 if reply["ok"] else 1;

}

def run_add(args: argparse.Namespace) -> int {
    result = call("create_task", {"title": args.title, "duration": args.minutes,
                "deadline": minutes(args.due), "due_day": args.due_day,
                "preferred_start": minutes(args.at) if args.at else -1,
                "priority": args.priority});
    print(result["message"]);
    return 0 if result["ok"] else 1;
}

def run_done(args: argparse.Namespace) -> int {
    data = board();
    index = args.number - 1;
    if index < 0 or index >= len(data["tasks"]) { raise ValueError("Choose a task number shown by `today`."); }
    result = call("set_task_done", {"task_id": data["tasks"][index]["id"], "done": True});
    print(result["message"]);
    return 0 if result["ok"] else 1;
}

def run_report(args: argparse.Namespace) -> int {
    result = call("preview_recovery", {"title": args.title,
                "start": minutes(args.start), "end": minutes(args.end),
                "use_model": args.with_model});
    print(result["message"]);
    if result["ok"] { show_plan(board()); }
    return 0 if result["ok"] else 1;
}

def run_plan(args: argparse.Namespace) -> int {
    data = board();
    if args.action == "view" { show_plan(data); return 0; }
    if args.action == "accept" {
        if not args.choice { raise ValueError("Choose `minimal` or `deadline`."); }
        if data["proposal"] is None { raise ValueError("No recovery is awaiting approval."); }
        result = call("accept_recovery", {"proposal_id": data["proposal"]["id"], "option": args.choice});
        print(result["message"]);
        return 0 if result["ok"] else 1;
    }
    active = [item for item in data["revisions"] if not item["restored"]];
    if not active { raise ValueError("No recovery is available to restore."); }
    result = call("restore_revision", {"revision_id": active[-1]["id"]});
    print(result["message"]);
    return 0 if result["ok"] else 1;
}

def run_goals(args: argparse.Namespace) -> int {
    show_goals(board());
    return 0;
}

def run_goal(args: argparse.Namespace) -> int {
    if args.goal_action == "add" {
        result = call("create_goal", {
            "title": args.title,
            "target_date": args.target,
            "importance": args.importance
        });
        print(result.get("message", "Goal created."));
        return 0 if result.get("ok", False) else 1;
    }
    data = board();
    goals = data.get("goals", []);
    index = args.number - 1;
    if index < 0 or index >= len(goals) {
        raise ValueError("Choose a goal number shown by `goals`.");
    }
    goal_id = goals[index]["id"];
    if args.goal_action == "toggle" {
        result = call("toggle_goal", {"goal_id": goal_id});
        print(result.get("message", "Goal updated."));
        return 0 if result.get("ok", False) else 1;
    }
    if args.goal_action == "delete" {
        result = call("delete_goal", {"goal_id": goal_id});
        print(result.get("message", "Goal removed."));
        return 0 if result.get("ok", False) else 1;
    }
    return 2;
}

def run_rebalance(args: argparse.Namespace) -> int {
    data = board();
    suggestion = data.get("rebalance", {});
    if not suggestion or not suggestion.get("available", False) {
        print("No rebalance suggestion is currently available.");
        return 0;
    }
    result = call("apply_rebalance_candidate", {
        "from_day": suggestion["from_day"],
        "to_day": suggestion["to_day"],
        "task_id": suggestion["task_id"]
    });
    print(result.get("message", "Rebalance applied."));
    return 0 if result.get("ok", False) else 1;

}

def run_breakdown(args: argparse.Namespace) -> int {
    data = board();
    index = args.number - 1;
    if index < 0 or index >= len(data["tasks"]) {
        raise ValueError("Choose a task number shown by `today`.");
    }
    task = data["tasks"][index];
    preview = call("preview_task_breakdown", {"task_id": task["id"]});
    if not preview.get("ok", False) {
        print(preview.get("message", "Task breakdown failed."));
        return 1;
    }
    subtasks = preview.get("subtasks", []);
    if args.apply {
        titles = [sub["title"] for sub in subtasks];
        durations = [sub["duration"] for sub in subtasks];
        result = call("apply_task_breakdown", {
            "task_id": task["id"],
            "titles": titles,
            "durations": durations,
            "expected_version": preview.get("base_version", -1)
        });
        print(result.get("message", "Task broken down."));
        return 0 if result.get("ok", False) else 1;
    }
    task_name = preview.get("original_title", task["title"]);
    print(f"Task breakdown preview for '{task_name}':");
    for (i, sub) in enumerate(subtasks, 1) {
        print(f"  {i}. {sub['title']} ({duration_label(sub['duration'])})");
    }
    print("\nRun with --apply to break down this task.");
    return 0;
}

def run_proposals(args: argparse.Namespace) -> int {
    show_proposals(board());
    return 0;
}

def run_proposal(args: argparse.Namespace) -> int {
    data = board();
    proposals = data.get("command_proposals", []);
    index = args.number - 1;
    if index < 0 or index >= len(proposals) {
        raise ValueError("Choose a proposal number shown by `proposals`.");
    }
    prop_id = proposals[index]["id"];
    if args.proposal_action == "accept" {
        result = call("apply_command_proposal", {"proposal_id": prop_id});
        print(result.get("message", "Proposal accepted."));
        return 0 if result.get("ok", False) else 1;
    }
    if args.proposal_action == "dismiss" {
        result = call("dismiss_command_proposal", {"proposal_id": prop_id});
        print(result.get("message", "Proposal dismissed."));
        return 0 if result.get("ok", False) else 1;
    }
    return 2;
}

def run(args: argparse.Namespace) -> int {
    handlers = {"login": run_login, "logout": run_logout, "today": run_today, "week": run_week, "briefing": run_briefing, "health": run_health, "next": run_next, "activity": run_activity, "notifications": run_notifications, "notification": run_notification, "secretary": run_secretary, "ask": run_ask, "add": run_add, "done": run_done, "report": run_report, "plan": run_plan, "goals": run_goals, "goal": run_goal, "rebalance": run_rebalance, "breakdown": run_breakdown, "proposals": run_proposals, "proposal": run_proposal};
    handler = handlers.get(args.command);
    return handler(args) if handler is not None else 2;
}

def guided_fields(command: str) -> list[str] | None {
    prompts = ["What would you like to get done?", "How many minutes? [30]", "Due by what time? [20:00]"];
    if command == "report" {
        prompts = ["What changed?", "What time does it start? (24-hour HH:MM)", "And when does it end? (24-hour HH:MM)"];
    }
    values: list[str] = [];
    print("\nLet us plan for today. Type back to revisit a step, or cancel to leave.");
    while len(values) < len(prompts) {
        value = input(prompts[len(values)] + "\n> ").strip();
        if value.lower() in ["cancel", "home", "*"] { return None; }
        if value.lower() == "back" {
            if values { values.pop(); } else { return None; }
            continue;
        }
        try {
            if len(values) == 0 {
                if not value or len(value) > 120 { raise ValueError("Use a short name, up to 120 characters."); }
            } elif command == "add" and len(values) == 1 {
                value = value or "30";
                if not value.isdecimal() or int(value) < 15 or int(value) > 600 {
                    raise ValueError("Use a number of minutes between 15 and 600.");
                }
            } else {
                value = value or ("20:00" if command == "add" else "");
                clock = minutes(value);
                if command == "report" and len(values) == 2 and clock <= minutes(values[1]) {
                    raise ValueError("The end must be after the start.");
                }
            }
        } except ValueError as error { print(str(error)); continue; }
        values.append(value);
    }
    if command == "add" {
        print("\nAdd " + values[0] + " today for " + values[1] + " minutes, due by " + values[2] + "?");
        if input("Type yes to save, or anything else to cancel: ").strip().lower() != "yes" { return None; }
        return ["add", values[0], "--minutes", values[1], "--due", values[2]];
    }
    return ["report", values[0], "--start", values[1], "--end", values[2]];
}

def guided_review -> None {
    data = board();
    proposals = data.get("command_proposals", []);
    pending = data.get("proposal");
    if pending is not None {
        show_plan(data, guided=True);
        choice = input("\n1 Move as little as possible | 2 Protect deadlines | 0 Leave unchanged\n> ").strip();
        if choice not in ["1", "2"] { print("Your plan is unchanged."); return; }
        if input("Apply this recovery? Type yes to confirm: ").strip().lower() != "yes" { return; }
        result = call("accept_recovery", {"proposal_id": pending["id"], "option": "minimal" if choice == "1" else "deadline"});
        print(result.get("message", "The server did not provide a result."));
    } elif proposals {
        show_proposals(data, guided=True);
        value = input("\nWhich proposal? Enter its number, or 0 to go back: ").strip();
        if value == "0" { return; }
        if not value.isdecimal() or int(value) < 1 or int(value) > len(proposals) { raise ValueError("Choose a proposal number from the list."); }
        proposal = proposals[int(value) - 1];
        print(proposal["details"]);
        choice = input("1 Accept | 2 Dismiss | 0 Leave unchanged\n> ").strip();
        if choice not in ["1", "2"] { return; }
        if input("Confirm this choice? Type yes: ").strip().lower() != "yes" { return; }
        result = call("apply_command_proposal" if choice == "1" else "dismiss_command_proposal", {"proposal_id": proposal["id"]});
        print(result.get("message", "The server did not provide a result."));
    } else { print("There are no suggested changes waiting for review."); }
}

def interactive -> int {
    print("\nWelcome to Replaniva. Let us make your day easier.");
    print("Keep the web server running in another terminal with jac run. Your saved plan is shared.");
    parser = make_parser();
    while True {
        try {
            if not saved_token() {
                print("\n1 Sign in | 2 Getting started | 0 Exit");
                choice = input("> ").strip();
                if choice in ["0", "exit", "quit"] { return 0; }
                if choice == "2" {
                    print("Create a username and password in the web app first. Then choose Sign in here. No email is needed.");
                    continue;
                }
                if choice != "1" { print("Choose 1, 2 or 0."); continue; }
                username = input("Username (or cancel): ").strip();
                if username.lower() == "cancel" { continue; }
                run(parser.parse_args(["login", username]));
                continue;
            }
            print("\nWhat would help right now?\n1 See today's plan\n2 Find my next step\n3 Add something to do\n4 Something changed\n5 Review suggested changes\n6 Mark a task done\n7 Ask about my plan\n8 See the week\n9 Account and help\n10 Secretary notifications\n0 Exit");
            choice = input("> ").strip();
            if choice in ["0", "exit", "quit"] { return 0; }
            shortcuts = {"1": "today", "2": "next", "8": "week"};
            if choice in shortcuts { run(parser.parse_args([shortcuts[choice]])); }
            elif choice in ["3", "4"] {
                args = guided_fields("add" if choice == "3" else "report");
                if args is None { print("Cancelled. Your saved plan is unchanged."); }
                else { run(parser.parse_args(args)); }
            } elif choice == "5" { guided_review(); }
            elif choice == "6" {
                data = board();
                show_today(data);
                value = input("Task number to finish, or 0 to go back: ").strip();
                if value == "0" { continue; }
                if not value.isdecimal() or int(value) < 1 or int(value) > len(data["tasks"]) { raise ValueError("Choose a task number from the list."); }
                task = data["tasks"][int(value) - 1];
                if input("Mark " + task["title"] + " done? Type yes: ").strip().lower() == "yes" {
                    result = call("set_task_done", {"task_id": task["id"], "done": True});
                    print(result["message"]);
                }
            } elif choice == "7" {
                print("Try: What is at risk? or What should I do next? This handles supported planning questions, not general chat.");
                question = input("Your question (or cancel): ").strip();
                if question and question.lower() != "cancel" { run(parser.parse_args(["ask", question])); }
            } elif choice == "9" {
                print("\nYou are using the same account and plan as the web app. Use its Settings page for connections.");
                print("Capture supports back and cancel. Changes need confirmation. Shortcuts remain available with jac run cli -- --help.");
                if input("Type logout to sign out, or press Enter to return: ").strip().lower() == "logout" {
                    if os.environ.get("REPLANIVA_TOKEN", "") { print("This session uses REPLANIVA_TOKEN. Unset it in your terminal to sign out."); }
                    else { run(parser.parse_args(["logout"])); }
                }
            } else { print("Choose a number from the menu, or 0 to exit."); }
        } except (EOFError, KeyboardInterrupt) {
            print("\nGoodbye. Any unfinished input was not submitted.");
            return 0;
        } except (RuntimeError, ValueError) as error {
            print(str(error));
            print("You can try again or choose 0 to exit.");
        }
    }
}

def main(argv: list[str]) -> int {
    if not argv { return interactive(); }
    parser = make_parser();
    try { return run(parser.parse_args(argv)); }
    except (RuntimeError, ValueError) as error {
        print("replaniva: " + str(error), file=sys.stderr);
        return 1;
    }
}

with entry:__main__ {
    sys.`exit(main(sys.argv[1:]));
}
