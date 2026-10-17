"""Private graph relationships and the bounded planning secretary."""

import time;
import from .investigation_types { InvestigatedTask, InvestigatedGoal, InvestigationContext }
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from .account_clock { AccountClock, local_clock }
import from collections { deque }
import from planning { Work, Busy }
import from intelligence { build_briefing }
import from .assistant { CommandReply, answer_command }
import from .secretary_ai { secretary_advice }

node PlanningSettings {
    has version: int = 0, day_start: int = 480, day_end: int = 1320,
        tour_completed: bool = False, light_mode: bool = False;
}
node PlanningTask {
    has title: str, day: str, duration: int, deadline: int,
        priority: int = 2, start: int = -1, done: bool = False,
        depends_on: list[str] = [], goal_id: str = "", due_day: str = "",
        relationships_migrated: bool = False;
}
node PlanningGoal {
    has title: str, target_date: str = "", importance: str = "medium", completed: bool = False;
}
edge DependsOn: PlanningTask --> PlanningTask {}
edge SupportsGoal: PlanningTask --> PlanningGoal {}

obj SecretaryAction { has ok: bool, message: str; }
obj SecretaryLiveConnection { has ticket: str, api_port: int = 0; }
obj SecretaryPreferences {
    has enabled: bool = False, timezone: str = "Africa/Nairobi", morning: int = 480,
        quiet_start: int = 1320, quiet_end: int = 480, lead: int = 15,
        focus_period: str = "", job_id: str = "";
}
@archetype_alias("_jac_app_9919b86551cad1e0.secretary.SecretaryConfig")
node SecretaryConfig {
    has enabled: bool = False, timezone: str = "Africa/Nairobi", morning: int = 480,
        quiet_start: int = 1320, quiet_end: int = 480, lead: int = 15,
        focus_period: str = "", job_id: str = "", last_tick: float = 0.0;
    def view -> SecretaryPreferences {
        return SecretaryPreferences(enabled=self.enabled, timezone=self.timezone, morning=self.morning,
            quiet_start=self.quiet_start, quiet_end=self.quiet_end, lead=self.lead,
            focus_period=self.focus_period, job_id=self.job_id);
    }
}
obj NotificationView {
    has id: str, kind: str, title: str, message: str, day: str, task_id: str,
        created_at: float, read: bool, dismissed: bool, snoozed_until: float,
        resolved: bool, revision: int, browser_allowed: bool = True;
}
node SecretaryNotification {
    has key: str, kind: str, title: str, message: str, day: str, task_id: str = "",
        created_at: float = 0.0, read: bool = False, dismissed: bool = False,
        snoozed_until: float = 0.0, resolved: bool = False, revision: int = 1;
    def view -> NotificationView {
        return NotificationView(id=jid(self), kind=self.kind, title=self.title, message=self.message,
            day=self.day, task_id=self.task_id, created_at=self.created_at, read=self.read,
            dismissed=self.dismissed, snoozed_until=self.snoozed_until, resolved=self.resolved, revision=self.revision);
    }
}
obj PreferenceView { has id: str, period: str, message: str; }
node PreferenceSuggestion { has period: str, active: bool = True; }
obj SecretaryRunView {
    has id: str, day: str, status: str, summary: str, steps: list[str],
        visited_tasks: list[str], visited_goals: list[str], reply: CommandReply,
        created_at: float, source: str = "Deterministic Jac", context: InvestigationContext = InvestigationContext();
}
node SecretaryRunRecord {
    has day: str, status: str, summary: str, steps: list[str], visited_tasks: list[str],
        visited_goals: list[str], reply: CommandReply, created_at: float, source: str = "Deterministic Jac", context: InvestigationContext = InvestigationContext();
    def view -> SecretaryRunView {
        return SecretaryRunView(id=jid(self), day=self.day, status=self.status, summary=self.summary,
            steps=self.steps, visited_tasks=self.visited_tasks, visited_goals=self.visited_goals,
            reply=self.reply, created_at=self.created_at, source=self.source, context=getattr(self, "context", InvestigationContext()));
    }
}

def private_account() -> None {
    if jid(root) == jid(root.shared) { raise PermissionError("Sign in to access the secretary."); }
}
def secretary_config() -> SecretaryConfig {
    private_account();
    found = [root -->][?:SecretaryConfig];
    return found[0] if found else root ++> SecretaryConfig();
}
def account_clock(stamp: float | None = None) -> AccountClock {
    return local_clock("Africa/Nairobi" if jid(root) == jid(root.shared) else secretary_config().timezone, stamp);
}
def graph_errors(tasks: list[PlanningTask], goals: list[PlanningGoal]) -> list[str] {
    ids = {jid(task) for task in tasks};
    goal_ids = {jid(goal) for goal in goals};
    errors: list[str] = [];
    for task in tasks {
        dependency_ids = [jid(node) for node in [node for node in list([task ->:DependsOn:->]) if isinstance(node, PlanningTask)]] if task.relationships_migrated else task.depends_on;
        linked = [jid(node) for node in [node for node in list([task ->:SupportsGoal:->]) if isinstance(node, PlanningGoal)]] if task.relationships_migrated else ([task.goal_id] if task.goal_id else []);
        if len(dependency_ids) != len(set(dependency_ids)) or any(dependency not in ids for dependency in dependency_ids) {
            errors.append("A task has a missing, duplicate or foreign prerequisite.");
        }
        if len(linked) > 1 or any(goal not in goal_ids for goal in linked) { errors.append("A task has a missing or foreign goal."); }
    }
    if errors { return errors; }
    dependencies = {jid(task): [jid(node) for node in [node for node in list([task ->:DependsOn:->]) if isinstance(node, PlanningTask)]] if task.relationships_migrated else task.depends_on for task in tasks};
    remaining = {key: len(set(values)) for (key, values) in dependencies.items()};
    dependents: dict[str, list[str]] = {key: [] for key in ids};
    for (key, values) in dependencies.items() {
        for dependency in set(values) { dependents[dependency].append(key); }
    }
    ready = deque([key for key in ids if remaining[key] == 0]);
    visited = 0;
    while ready {
        key = ready.popleft();
        visited += 1;
        for dependent in dependents[key] {
            remaining[dependent] -= 1;
            if remaining[dependent] == 0 { ready.append(dependent); }
        }
    }
    if visited != len(ids) { errors.append("A task dependency cycle needs attention before investigation."); }
    return errors;
}
def sync_planning_graph() -> list[str] {
    private_account();
    tasks = [node for node in list([root -->]) if isinstance(node, PlanningTask)];
    goals = [node for node in list([root -->]) if isinstance(node, PlanningGoal)];
    errors = graph_errors(tasks, goals);
    if errors { return errors; }
    for task in tasks {
        if not task.relationships_migrated {
            for linked_task in list([task ->:DependsOn:->]) { task del --> linked_task; }
            for linked_goal in list([task ->:SupportsGoal:->]) { task del --> linked_goal; }
            for dependency in tasks {
                if jid(dependency) in task.depends_on { task +>: DependsOn :+> dependency; }
            }
            for goal in goals {
                if jid(goal) == task.goal_id { task +>: SupportsGoal :+> goal; }
            }
            task.relationships_migrated = True;
        }
        dependency_ids = [jid(node) for node in [node for node in list([task ->:DependsOn:->]) if isinstance(node, PlanningTask)]];
        if task.depends_on != dependency_ids { task.depends_on = dependency_ids; }
        linked = [node for node in list([task ->:SupportsGoal:->]) if isinstance(node, PlanningGoal)];
        goal_id = jid(linked[0]) if linked else "";
        if task.goal_id != goal_id { task.goal_id = goal_id; }
    }
    return [];
}
def secretary_work(task: PlanningTask, day: str) -> Work {
    return Work(id=jid(task), title=task.title, duration=task.duration, priority=task.priority,
        start=task.start, deadline=task.deadline if (task.due_day or task.day) <= day else 1440,
        depends_on=task.depends_on, due_day=task.due_day or task.day, due_time=task.deadline);
}


walker SecretaryRun {
    has query: str, day: str, fixed: list[Busy], day_start: int, day_end: int,
        version: int, completed: int = 0, use_model: bool = False, source: str = "Deterministic Jac", owned: list[str] = [], goal_ids: list[str] = [],
        visited_tasks: list[str] = [], visited_goals: list[str] = [],
        work: list[Work] = [], steps: list[str] = [], incomplete: bool = False,
        deadline: float = 0.0, reply: CommandReply | None = None, context: InvestigationContext = InvestigationContext();
    can begin with Root entry {
        private_account();
        if not self.deadline { self.deadline = time.monotonic() + 45; }
        tasks = [node for node in list([root -->]) if isinstance(node, PlanningTask)];
        self.owned = [jid(task) for task in tasks];
        self.completed = len([task for task in tasks if task.day == self.day and task.done]);
        self.goal_ids = [jid(goal) for goal in [node for node in list([root -->]) if isinstance(node, PlanningGoal)]];
        self.steps.append("Read " + str(len(tasks)) + " owned tasks and this account's planning boundaries.");
        visit [task for task in tasks if task.day == self.day];
        if "goal" in self.query.lower() { visit [node for node in list([root -->]) if isinstance(node, PlanningGoal)]; }
    }
    can task_entry with PlanningTask entry { self.inspect_task(here); }
    can goal_entry with PlanningGoal entry { self.inspect_goal(here); }
    def inspect_task(task: PlanningTask) -> None {
        if jid(task) not in self.owned { self.incomplete = True; disengage; }
        if jid(task) in self.visited_tasks { return; }
        if len(self.visited_tasks) + len(self.visited_goals) >= 200 or time.monotonic() > self.deadline {
            self.incomplete = True;
            disengage;
        }
        self.visited_tasks.append(jid(task));
        self.context.tasks.append(InvestigatedTask(id=jid(task), title=task.title, day=task.day, done=task.done, depends_on=task.depends_on, goal_id=task.goal_id));
        if task.day == self.day and not task.done { self.work.append(secretary_work(task, self.day)); }
        visit [node for node in list([task ->:DependsOn:->]) if isinstance(node, PlanningTask)];
        visit [node for node in list([task <-:DependsOn:<-]) if isinstance(node, PlanningTask)];
        visit [node for node in list([task ->:SupportsGoal:->]) if isinstance(node, PlanningGoal)];
    }
    def inspect_goal(goal: PlanningGoal) -> None {
        if jid(goal) not in self.goal_ids { self.incomplete = True; disengage; }
        if jid(goal) in self.visited_goals { return; }
        if len(self.visited_tasks) + len(self.visited_goals) >= 200 or time.monotonic() > self.deadline { self.incomplete = True; disengage; }
        self.visited_goals.append(jid(goal));
        self.context.goals.append(InvestigatedGoal(id=jid(goal), title=goal.title, target_date=goal.target_date));
        visit [node for node in list([goal <-:SupportsGoal:<-]) if isinstance(node, PlanningTask)];
    }
    can finish with Root exit {
        self.context.complete = not self.incomplete;
        for goal in self.context.goals {
            linked = [task for task in self.context.tasks if task.goal_id == goal.id];
            goal.total = len(linked);
            goal.completed = len([task for task in linked if task.done]);
        }
        self.steps.append("Traversed " + str(len(self.visited_tasks)) + " tasks and " + str(len(self.visited_goals)) + " related goals.");
        if self.incomplete {
            self.reply = CommandReply(ok=False, kind="help", title="Narrow this investigation",
                message="The graph could not be fully inspected within the safe limit. Choose a smaller day or resolve invalid links.");
        } else {
            briefing = build_briefing(self.work, self.fixed, self.completed, self.day_start, self.day_end, self.day_start);
            self.steps.append("Checked capacity, deadlines and dependency risks using deterministic Jac.");
            self.reply = answer_command(self.query, briefing, self.work, self.fixed,
                self.day_start, self.day_end, self.version, self.day);
            evidence = relationship_answer(self.query, self.context);
            if evidence is not None { self.reply = evidence; }
            if self.use_model and self.reply.kind == "help" {
                advice = secretary_advice(self.query, jid(root), self.work, self.fixed, self.day_start, self.day_end, secretary_config().focus_period, self.deadline, self.context);
                self.steps.extend(advice.steps);
                if advice.message {
                    self.reply = CommandReply(ok=True, kind="secretary", title="Your planning secretary", message=advice.message);
                    self.source = advice.source;
                } else {
                    self.reply = CommandReply(ok=False, kind="help", title="Verified plan findings",
                        message="I could not interpret that request confidently. Here is what I can verify: " + briefing.summary + " Next: " + briefing.next_action.title + ". You can ask about risks, your next task, or an explicit schedule change.");
                }
            }
            self.steps.append("Prepared a reviewable proposal; no plan was applied." if self.reply.proposal else "Returned findings without changing the saved plan.");
        }
    }
}


def relationship_answer(query: str, context: InvestigationContext) -> CommandReply | None {
    normalized = query.lower();
    if "goal" in normalized and ("progress" in normalized or "how are" in normalized or "my goals" in normalized or normalized.strip() == "goals") {
        progress = [goal.title + ": " + str(goal.completed) + " of " + str(goal.total) + " linked tasks complete" + ("; target " + goal.target_date if goal.target_date else "") + "." for goal in context.goals];
        return CommandReply(ok=True, kind="goals", title="Goal progress" if progress else "No goals yet", message=" ".join(progress) if progress else "Add a goal in Today, then link tasks to see progress here.");
    }
    if any(word in normalized for word in ["dependenc", "prerequisite", "blocked", "blocker", "related work"]) {
        titles = {task.id: task.title + " (" + task.day + (", done" if task.done else ", unfinished") + ")" for task in context.tasks};
        findings = [task.title + " depends on " + ", ".join([titles[dependency] for dependency in task.depends_on if dependency in titles]) + "." for task in context.tasks if task.depends_on];
        return CommandReply(ok=True, kind="dependencies", title="Your task relationships", message=" ".join(findings) if findings else "The inspected work has no linked prerequisites. No tasks were changed.");
    }
    return None;
}

def investigate(query: str, day: str, fixed: list[Busy], day_start: int, day_end: int, version: int, use_model: bool = False) -> SecretaryRunView {
    private_account();
    until = time.monotonic() + 45;
    errors = sync_planning_graph();
    runner = SecretaryRun(query=query, day=day, fixed=fixed, day_start=day_start, day_end=day_end, version=version, use_model=use_model, deadline=until);
    if not errors { root spawn runner; }
    runner.context.complete = not runner.incomplete and runner.reply is not None;
    reply = runner.reply if runner.reply is not None else CommandReply(ok=False, kind="help", title="Planning relationships need attention", message=" ".join(errors) or "Investigation stopped before completion.");
    record = root ++> SecretaryRunRecord(day=day, status="complete" if reply.ok else "needs_attention",
        summary=reply.message, steps=runner.steps if not errors else errors,
        visited_tasks=runner.visited_tasks, visited_goals=runner.visited_goals,
        reply=reply, created_at=time.time(), source=runner.source, context=runner.context);
    record.context.integrity_ok = not errors;
    previous = [root -->][?:SecretaryRunRecord];
    for old in previous[:-30] { del old; }
    return record.view();
}

node PlanningCommitment { has title: str, day: str, start: int, end: int, source: str = "manual"; }

def quiet_at(minute: int, start: int, end: int) -> bool {
    if start == end { return False; }
    return start <= minute < end if start < end else minute >= start or minute < end;
}
def notification_upsert(key: str, kind: str, title: str, message: str, day: str, task_id: str, stamp: float) -> bool {
    found = [item for item in [root -->][?:SecretaryNotification] if item.key == key];
    if found {
        item = found[0];
        changed = item.message != message or item.resolved;
        item.message = message;
        item.resolved = False;
        if changed { item.revision += 1; }
        return changed;
    }
    root ++> SecretaryNotification(key=key, kind=kind, title=title, message=message,
        day=day, task_id=task_id, created_at=stamp);
    return True;
}
def secretary_tick(stamp: float = 0.0) -> int {
    cfg = secretary_config();
    if not cfg.enabled { return 0; }
    stamp = stamp or time.time();
    local = datetime.fromtimestamp(stamp, ZoneInfo(cfg.timezone));
    day = local.date().isoformat();
    minute = local.hour * 60 + local.minute;
    tasks = [node for node in list([root -->]) if isinstance(node, PlanningTask)];
    fixed = [Busy(title=item.title, start=item.start, end=item.end)
        for item in [node for node in list([root -->]) if isinstance(node, PlanningCommitment)] if item.day == day];
    prefs = [node for node in list([root -->]) if isinstance(node, PlanningSettings)];
    day_start = prefs[0].day_start if prefs else 480;
    day_end = prefs[0].day_end if prefs else 1320;
    work = [secretary_work(item, day) for item in tasks if item.day == day and not item.done];
    briefing = build_briefing(work, fixed, len([item for item in tasks if item.day == day and item.done]), day_start, day_end, minute);
    active: list[str] = [];
    changed = 0;
    quiet = quiet_at(minute, cfg.quiet_start, cfg.quiet_end);
    if minute >= cfg.morning {
        key = "briefing:" + day;
        active.append(key);
        if not quiet {
            changed += int(notification_upsert(key, "briefing", "Your morning briefing", briefing.summary + " Next: " + briefing.next_action.title, day, "", stamp));
        }
    }
    for task in tasks {
        if task.done { continue; }
        if task.day == day and task.start >= 0 and task.start - cfg.lead <= minute < task.start {
            key = "start:" + jid(task) + ":" + day + ":" + str(task.start);
            active.append(key);
            if not quiet { changed += int(notification_upsert(key, "reminder", "Coming up: " + task.title, "This task starts at " + str(task.start // 60).zfill(2) + ":" + str(task.start % 60).zfill(2) + ".", day, jid(task), stamp)); }
        }
        if task.day == day and task.start >= 0 and minute >= task.start + task.duration + 15 {
            key = "followup:" + jid(task) + ":" + day + ":" + str(task.start);
            active.append(key);
            if not quiet { changed += int(notification_upsert(key, "followup", "How did " + task.title + " go?", "It is still marked unfinished. Are you done, still working, or would you like help adjusting the plan?", day, jid(task), stamp)); }
        }
        due_day = task.due_day or task.day;
        due = datetime.fromisoformat(due_day).replace(tzinfo=ZoneInfo(cfg.timezone)) + timedelta(minutes=task.deadline);
        remaining = due.timestamp() - stamp;
        if remaining <= 86400 {
            key = "deadline:" + jid(task) + ":" + due_day;
            active.append(key);
            if not quiet { changed += int(notification_upsert(key, "deadline", "Deadline: " + task.title, "This unfinished task is overdue." if remaining < 0 else "This unfinished task is due within 24 hours.", task.day, jid(task), stamp)); }
        }
    }
    for risk in briefing.risks {
        key = "risk:" + day + ":" + risk.code + ":" + risk.task_id;
        active.append(key);
        if not quiet { changed += int(notification_upsert(key, "risk", risk.title, risk.detail, day, risk.task_id, stamp)); }
    }
    for item in [root -->][?:SecretaryNotification] {
        if not item.resolved and item.key not in active {
            item.resolved = True;
            item.revision += 1;
            changed += 1;
        }
    }
    cfg.last_tick = stamp;
    old = [item for item in [root -->][?:SecretaryNotification] if item.created_at < stamp - 30 * 86400 and (item.dismissed or item.resolved)];
    for item in old { del item; }
    return changed;
}
def notifications() -> list[NotificationView] {
    private_account();
    items = [item.view() for item in [root -->][?:SecretaryNotification]
        if not item.dismissed and not item.resolved and item.snoozed_until <= time.time()];
    cfg = secretary_config();
    now = datetime.now(ZoneInfo(cfg.timezone));
    browser_allowed = not quiet_at(now.hour * 60 + now.minute, cfg.quiet_start, cfg.quiet_end);
    for item in items { item.browser_allowed = browser_allowed; }
    items.sort(key=lambda (item: NotificationView) { -item.created_at; });
    return items[:100];
}
def change_notification(notification_id: str, action: str, minutes: int = 15) -> SecretaryAction {
    private_account();
    for item in [root -->][?:SecretaryNotification] {
        if jid(item) == notification_id {
            if action == "read" { item.read = True; }
            elif action == "dismiss" { item.dismissed = True; }
            elif action == "snooze" and minutes in [15, 30, 60] { item.snoozed_until = time.time() + minutes * 60; }
            else { return SecretaryAction(ok=False, message="Choose read, dismiss, or a 15, 30 or 60 minute snooze."); }
            item.revision += 1;
            return SecretaryAction(ok=True, message="Notification updated.");
        }
    }
    return SecretaryAction(ok=False, message="Notification not found in this account.");
}
def suggest_focus(query: str) -> PreferenceView | None {
    private_account();
    note = query.lower().strip();
    if not any(phrase in note for phrase in ["i prefer", "i focus better", "i study better", "i work better"]) { return None; }
    periods = [period for period in ["morning", "afternoon", "evening"] if period in note];
    if len(periods) != 1 { return None; }
    cfg = secretary_config();
    period = periods[0];
    if cfg.focus_period == period { return None; }
    found = [item for item in [root -->][?:PreferenceSuggestion] if item.active and item.period == period];
    item = found[0] if found else root ++> PreferenceSuggestion(period=period);
    return PreferenceView(id=jid(item), period=period, message="Remember that you prefer focused work in the " + period + "? Existing tasks will not move.");
}
def preference_suggestions() -> list[PreferenceView] {
    private_account();
    return [PreferenceView(id=jid(item), period=item.period, message="Remember focused work in the " + item.period + "?") for item in [root -->][?:PreferenceSuggestion] if item.active];
}
def propose_focus_period(period: str) -> SecretaryAction {
    private_account();
    if period not in ["morning", "afternoon", "evening"] {
        return SecretaryAction(ok=False, message="Choose morning, afternoon or evening.");
    }
    suggestion = suggest_focus("I focus better in the " + period);
    return SecretaryAction(ok=True, message="Review the preference below before remembering it. Your plan has not moved." if suggestion else "That focus period is already approved.");
}
def decide_preference(suggestion_id: str, accept: bool) -> SecretaryAction {
    private_account();
    for item in [root -->][?:PreferenceSuggestion] {
        if jid(item) == suggestion_id and item.active {
            if accept { secretary_config().focus_period = item.period; }
            item.active = False;
            return SecretaryAction(ok=True, message="Preference saved. Your current plan was not moved." if accept else "Preference suggestion dismissed.");
        }
    }
    return SecretaryAction(ok=False, message="That preference suggestion is no longer active.");
}
