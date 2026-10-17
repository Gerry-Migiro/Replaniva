"""The shared Replaniva command grammar for terminal and authenticated browser use."""
import argparse;

class PlanningParser(argparse.ArgumentParser) {
    def error(self: PlanningParser, message: str) -> None {
        raise ValueError(message);
    }
}

def make_parser() -> argparse.ArgumentParser {
    parser = PlanningParser(prog="replaniva", description="Your Replaniva plan from the terminal");
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
    plan.add_argument("action", nargs="?", choices=["view", "accept", "restore", "dismiss"], `default="view");
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
