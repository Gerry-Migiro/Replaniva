"""Private planning operations shared by every Replaniva interface."""

import json;
import time;
import calendar_gateway as google;

import from datetime { date, datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from os { environ }
import from planning { Work, Busy, Slot, Choice, make_choice, validate, overlaps }
import from intelligence {
    DailyBriefing, DayOutlook, RebalanceCandidate, build_briefing,
    build_outlook, suggest_rebalance, clock_label
}
import from .assistant {
    CommandReply, CommandProposal, SubtaskDraft,
    generate_subtasks, resolve_command_day
}
import from .ai { optional_model_choice, optional_interpret_note }
import from model_usage { usage_status }

import from .secretary {
    SecretaryRun,
    PlanningSettings, PlanningTask, PlanningGoal, investigate, account_clock,
    SecretaryRunView, SecretaryRunRecord, SecretaryAction, SecretaryLiveConnection, secretary_config, PlanningCommitment,
    SecretaryPreferences, NotificationView, PreferenceView, secretary_tick, notifications,
    change_notification, suggest_focus, preference_suggestions, decide_preference, propose_focus_period
}

import from .planning_context { PlanningSnapshot, prepare_planning }

obj TaskView {
    has id: str, title: str, day: str, due_day: str, duration: int, deadline: int,
        priority: int, start: int, done: bool, depends_on: list[str] = [],
        goal_id: str = "";
}
obj GoalView {
    has id: str, title: str, target_date: str = "", importance: str = "medium",
        completed: bool = False, total_tasks: int = 0, completed_tasks: int = 0;
}
obj CommitmentView {
    has id: str, title: str, day: str, start: int, end: int, source: str;
}
obj ProposalView {
    has id: str, day: str, title: str, start: int, end: int,
        base_version: int, minimal: Choice, deadline: Choice;
}
obj RevisionView {
    has id: str, day: str, version: int, title: str, restored: bool;
}
obj ActivityView {
    has id: str, day: str, title: str, detail: str, created_at: str;
}
obj CommandProposalView {
    has id: str, kind: str, title: str, day: str, details: str, base_version: int,
        active: bool, task_title: str, task_duration: int,
        task_deadline: int, commitment_start: int, commitment_end: int,
        commitment_title: str, affected_tasks: list[str], unplaced_count: int, slack_change: int,
        action_type: str, target_task_id: str = "", target_day: str = "",
        proposed_duration: int = 0;
}
obj ServerConnectionView {
    has gemini_configured: bool = False,
        model_label: str = "Deterministic planning", model_calls: int = 0,
        model_remaining: int = 0, model_units: int = 0, model_unit_limit: int = 0,
        model_paused: bool = False;
}
obj Board {
    has day: str, version: int, day_start: int, day_end: int, tasks: list[TaskView],
        commitments: list[CommitmentView], proposal: ProposalView | None,
        revisions: list[RevisionView], briefing: DailyBriefing,
        horizon: list[DayOutlook], rebalance: RebalanceCandidate,
        command_proposals: list[CommandProposalView] = [],
        goals: list[GoalView] = [],
        activities: list[ActivityView] = [],
        tour_completed: bool = False,
        light_mode: bool = False, connections: ServerConnectionView = ServerConnectionView();
}
obj PlannerDate {
    has day: str, number: int, in_month: bool, tasks: int = 0,
        commitments: int = 0, deadlines: int = 0;
}
obj PlannerMonth {
    has month: str, label: str, today: str, previous: str, following: str,
        days: list[PlannerDate];
}

def build_planner_month(month: str, tasks: list[TaskView], commitments: list[CommitmentView]) -> PlannerMonth {
    first = date.fromisoformat(month).replace(day=1);
    previous = (first - timedelta(days=1)).replace(day=1);
    following = (first + timedelta(days=32)).replace(day=1);
    start = first - timedelta(days=first.weekday());
    counts: dict[str, list[int]] = {};
    for task in tasks {
        if task.day not in counts { counts[task.day] = [0, 0, 0]; }
        counts[task.day][0] += 1;
        if not task.done {
            due = task.due_day if task.due_day else task.day;
            if due not in counts { counts[due] = [0, 0, 0]; }
            counts[due][2] += 1;
        }
    }
    for commitment in commitments {
        if commitment.day not in counts { counts[commitment.day] = [0, 0, 0]; }
        counts[commitment.day][1] += 1;
    }
    days: list[PlannerDate] = [];
    for index in range(42) {
        day = start + timedelta(days=index);
        values = counts.get(day.isoformat(), [0, 0, 0]);
        days.append(PlannerDate(day=day.isoformat(), number=day.day,
            in_month=day.month == first.month, tasks=values[0],
            commitments=values[1], deadlines=values[2]));
    }
    return PlannerMonth(month=first.isoformat(), label=first.strftime("%B %Y"),
        today=account_clock().day, previous=previous.isoformat(),
        following=following.isoformat(), days=days);
}

def:protect get_planner_month(month: str = "") -> PlannerMonth {
    require_account();
    return build_planner_month(resolved_day(month),
        [task.view() for task in [root -->][?:Task]],
        [commitment.view() for commitment in [root -->][?:Commitment]]);
}

obj Action { has ok: bool, message: str; }
obj DisruptionDraft {
    has ok: bool, title: str = "", start: int = -1, end: int = -1,
        message: str = "";
}
obj BreakdownProposal {
    has ok: bool, task_id: str = "", original_title: str = "", day: str = "",
        base_version: int = 0, subtasks: list[SubtaskDraft] = [], message: str = "";
}

@archetype_alias('jac:["Replaniva","endpoints"].PlanningSettings')
node Settings(PlanningSettings) {
    has timezone: str = "", migration_complete: bool = False;
    static def __jac_schema__ -> None;
}
impl Settings.__jac_schema__ -> None {
    schema_alias("day_start", stored="start");
    schema_alias("day_end", stored="end");
}
node Task(PlanningTask) {
    can secretary_visit with SecretaryRun entry { visitor.inspect_task(self); }
    def view() -> TaskView {
        return TaskView(id=jid(self), title=self.title, day=self.day,
                        due_day=self.due_day if self.due_day else self.day,
                        duration=self.duration, deadline=self.deadline,
                        priority=self.priority, start=self.start, done=self.done,
                        depends_on=self.depends_on, goal_id=self.goal_id);
    }
}
node Commitment(PlanningCommitment) {
    def view() -> CommitmentView {
        return CommitmentView(id=jid(self), title=self.title, day=self.day,
                              start=self.start, end=self.end, source=self.source);
    }
}
node Proposal {
    has day: str, title: str, start: int, end: int, base_version: int,
        minimal: Choice, deadline: Choice, active: bool = True;
    def view() -> ProposalView {
        return ProposalView(id=jid(self), day=self.day, title=self.title,
                            start=self.start, end=self.end, base_version=self.base_version,
                            minimal=self.minimal, deadline=self.deadline);
    }
}
node Revision {
    has day: str, version: int, title: str, before: list[Slot],
        commitment_id: str, restored: bool = False;
    def view() -> RevisionView {
        return RevisionView(id=jid(self), day=self.day, version=self.version,
                            title=self.title, restored=self.restored);
    }
}
node PlanningActivity {
    has day: str, title: str, detail: str, created_at: str;
    def view() -> ActivityView {
        return ActivityView(id=jid(self), day=self.day, title=self.title,
                            detail=self.detail, created_at=self.created_at);
    }
}
node ActionProposal {
    has kind: str, title: str, day: str, details: str, base_version: int,
        active: bool = True, task_title: str = "", task_duration: int = 0,
        task_deadline: int = 0, commitment_start: int = -1, commitment_end: int = -1,
        commitment_title: str = "", affected_tasks: list[str] = [], unplaced_count: int = 0, slack_change: int = 0,
        action_type: str = "", target_task_id: str = "", target_day: str = "",
        proposed_duration: int = 0;
    def view() -> CommandProposalView {
        return CommandProposalView(
            id=jid(self), kind=self.kind, title=self.title, day=self.day,
            details=self.details, base_version=self.base_version, active=self.active,
            task_title=self.task_title, task_duration=self.task_duration,
            task_deadline=self.task_deadline, commitment_start=self.commitment_start,
            commitment_end=self.commitment_end, commitment_title=self.commitment_title, affected_tasks=self.affected_tasks,
            unplaced_count=self.unplaced_count, slack_change=self.slack_change,
            action_type=self.action_type, target_task_id=self.target_task_id,
            target_day=self.target_day, proposed_duration=self.proposed_duration
        );
    }
}
node Goal(PlanningGoal) {
    can secretary_visit with SecretaryRun entry { visitor.inspect_goal(self); }
    def view(linked_tasks: list[TaskView] | None = None) -> GoalView {
        linked_tasks = linked_tasks if linked_tasks is not None else [];
        total = len(linked_tasks);
        done_count = len([t for t in linked_tasks if t.done]);
        return GoalView(id=jid(self), title=self.title, target_date=self.target_date,
                        importance=self.importance, completed=self.completed,
                        total_tasks=total, completed_tasks=done_count);
    }
}

def resolved_day(day: str) -> str { return day if day else account_clock().day; }
def activity_timestamp(value: str, timezone: str) -> float | None {
    try {
        created = datetime.fromisoformat(value.replace("Z", "+00:00"));
        # Legacy entries without an offset use the owner's planning timezone.
        if created.tzinfo is None { created = created.replace(tzinfo=ZoneInfo(timezone)); }
        return created.timestamp();
    } except (ValueError, OverflowError) { return None; }
}

def recent_activities(stamp: float = 0.0) -> list[ActivityView] {
    now = stamp if stamp > 0 else time.time();
    timezone = account_clock().timezone;
    retained: list[tuple[float, int, PlanningActivity]] = [];
    index = 0;
    for item in [root -->][?:PlanningActivity] {
        index += 1;
        created = activity_timestamp(item.created_at, timezone);
        if created is not None and created < now - 90 * 86400 {
            del item;
        } else {
            # An unreadable legacy timestamp must not imply that an entry is old.
            retained.append((created if created is not None else now, index, item));
        }
    }
    retained.sort(key=lambda (candidate: tuple[float, int, PlanningActivity]) { (candidate[0], candidate[1]); }, reverse=True);
    for candidate in retained[1000:] {
        expired = candidate[2];
        del expired;
    }
    return [candidate[2].view() for candidate in retained[:12]];
}

def record_activity(day: str, title: str, detail: str) -> None {
    root ++> PlanningActivity(
        day=day, title=title, detail=detail,
        created_at=account_clock().timestamp
    );
    recent_activities();
}
def advance_version(prefs: Settings) {
    prefs.version += 1;
    secretary_tick();
    notify_secretary_clients();
    for proposal in [root -->][?:Proposal] { proposal.active = False; }
    for proposal in [root -->][?:ActionProposal] { proposal.active = False; }
}
def require_account() -> None {
    if jid(root) == jid(root.shared) {
        raise PermissionError("Sign in to access your private plan.");
    }
}
def settings() -> Settings {
    found = [node for node in list([root -->]) if isinstance(node, Settings)];
    preferred = [prefs for prefs in found if prefs.migration_complete];
    legacy = [prefs for prefs in found if prefs.timezone];
    prefs = preferred[0] if preferred else legacy[0] if legacy else found[0] if found else root ++> Settings();
    if prefs.timezone { secretary_config().timezone = prefs.timezone; prefs.timezone = ""; }
    if not prefs.migration_complete { prefs.migration_complete = True; }
    return prefs;
}

def work_for(day: str, snapshot: PlanningSnapshot | None = None) -> list[Work] {
    current = snapshot if snapshot is not None else prepare_planning();
    return current.work(day);
}
def busy_for(day: str, snapshot: PlanningSnapshot | None = None) -> list[Busy] {
    if snapshot is not None { return snapshot.busy(day); }
    return [Busy(title=c.title, start=c.start, end=c.end)
            for c in [root -->][?:Commitment] if c.day == day];
}
def planning_start(day: str, prefs: Settings) -> int {
    clock = account_clock();
    if day != clock.day { return prefs.day_start; }
    current = clock.minute;
    rounded = ((current + 14) // 15) * 15;
    return max(prefs.day_start, min(rounded, prefs.day_end));
}
def apply_slots(day: str, slots: list[Slot]) -> None {
    for task in [root -->][?:Task] {
        if task.day == day and not task.done {
            task.start = -1;
            for slot in slots {
                if slot.task_id == jid(task) { task.start = slot.start; }
            }
        }
    }
}
def rebuild_day(day: str, prefs: Settings) -> Choice {
    choice = make_choice("minimal", work_for(day), busy_for(day),
                         planning_start(day, prefs), prefs.day_end);
    apply_slots(day, choice.slots);
    return choice;
}
def deactivate_proposals(day: str) -> None {
    for proposal in [root -->][?:Proposal] {
        if proposal.day == day { proposal.active = False; }
    }
}

def planning_days() -> list[str] {
    days: list[str] = [];
    for task in [root -->][?:Task] {
        if task.day not in days { days.append(task.day); }
    }
    for commitment in [root -->][?:Commitment] {
        if commitment.day not in days { days.append(commitment.day); }
    }
    return days;
}

def briefing_for(day: str, prefs: Settings, snapshot: PlanningSnapshot | None = None) -> DailyBriefing {
    clock = account_clock();
    today = clock.day;
    current_minute = prefs.day_start - 1;
    if day == today {
        current_minute = clock.minute;
    } elif day < today {
        current_minute = prefs.day_end;
    }
    completed = len([task for task in [root -->][?:Task] if task.day == day and task.done]);
    return build_briefing(work_for(day, snapshot), busy_for(day, snapshot), completed,
                          prefs.day_start, prefs.day_end, current_minute);
}

def horizon_for(start_day: str, prefs: Settings, snapshot: PlanningSnapshot | None = None) -> list[DayOutlook] {
    first = date.fromisoformat(start_day);
    outlooks: list[DayOutlook] = [];
    for offset in range(7) {
        day = (first + timedelta(days=offset)).isoformat();
        outlooks.append(build_outlook(day, work_for(day, snapshot), busy_for(day, snapshot),
                                      planning_start(day, prefs), prefs.day_end));
    }
    return outlooks;
}

def rebalance_for(outlooks: list[DayOutlook], prefs: Settings, snapshot: PlanningSnapshot | None = None) -> RebalanceCandidate {
    for source_index in range(len(outlooks)) {
        source = outlooks[source_index];
        if source.overloaded_minutes <= 0 { continue; }
        for target_index in range(source_index) {
            target = outlooks[target_index];
            if target.slack_minutes < 15 { continue; }
            candidate = suggest_rebalance(
                source.day, target.day, work_for(source.day, snapshot), work_for(target.day, snapshot),
                busy_for(target.day, snapshot), planning_start(target.day, prefs), prefs.day_end
            );
            if candidate.available { return candidate; }
        }
    }
    return RebalanceCandidate();
}

def:protect get_board(day: str = "") -> Board {
    require_account();
    snapshot = prepare_planning();
    prefs = settings();
    current_day = resolved_day(day);
    tasks = [t.view() for t in [root -->][?:Task] if t.day == current_day];
    commitments = [c.view() for c in [root -->][?:Commitment] if c.day == current_day];
    pending: ProposalView | None = None;
    for item in [root -->][?:Proposal] {
        if item.day == current_day and item.active { pending = item.view(); }
    }
    command_props = [p.view() for p in [root -->][?:ActionProposal] if p.day == current_day and p.active];
    revisions = [r.view() for r in [root -->][?:Revision] if r.day == current_day];
    briefing = briefing_for(current_day, prefs, snapshot);
    horizon = horizon_for(current_day, prefs, snapshot);
    all_tasks = [t.view() for t in [root -->][?:Task]];
    goals = [g.view([t for t in all_tasks if t.goal_id == jid(g)]) for g in [root -->][?:Goal]];
    activities = recent_activities();

    usage = usage_status(jid(root));
    connections = ServerConnectionView(
        model_label=str(usage["models"]), model_calls=int(usage["calls"]),
        model_remaining=int(usage["remaining"]), model_units=int(usage["units"]),
        model_unit_limit=int(usage["unit_limit"]), model_paused=bool(usage["paused"]),
        gemini_configured=bool(environ.get("GOOGLE_API_KEY"))
    );
    return Board(day=current_day, version=prefs.version,
                 day_start=prefs.day_start, day_end=prefs.day_end, tasks=tasks,
                 commitments=commitments, proposal=pending, revisions=revisions,
                 briefing=briefing, horizon=horizon,
                 rebalance=rebalance_for(horizon, prefs, snapshot),
                 command_proposals=command_props,
                 goals=goals, activities=activities,
                 tour_completed=prefs.tour_completed,
                 light_mode=prefs.light_mode, connections=connections);
}

def coordinate_command(query: str, day: str = "", use_model: bool = False) -> SecretaryRunView {
    require_account();
    current_day = resolved_day(day) if "move " in query.lower() else resolve_command_day(query, day, account_clock().day);
    prefs = settings();
    preference = suggest_focus(query);
    investigation = investigate(query, current_day, busy_for(current_day), planning_start(current_day, prefs), prefs.day_end, prefs.version, use_model);
    if not investigation.context.integrity_ok or not investigation.context.complete { return investigation; }
    normalized = query.lower();
    if "lighter" in normalized and "evening" not in normalized {
        candidate = RebalanceCandidate();
        for offset in range(1, 4) {
            target_day = (date.fromisoformat(current_day) - timedelta(days=offset)).isoformat();
            if target_day < account_clock().day { continue; }
            candidate = suggest_rebalance(
                current_day, target_day, work_for(current_day), work_for(target_day),
                busy_for(target_day), planning_start(target_day, prefs), prefs.day_end
            );
            if candidate.available { break; }
        }
        if candidate.available {
            reply = CommandReply(ok=True, kind="proposal", title="Lighter day proposal",
                message="Review the move and approve it before either day changes.",
                proposal=CommandProposal(
                    kind="rebalance", title="Move " + candidate.task_title,
                    day=current_day, target_day=candidate.to_day,
                    details=candidate.reason + " Suggested start: " +
                        clock_label(candidate.suggested_start) + ".",
                    base_version=prefs.version, action_type="rebalance",
                    target_task_id=candidate.task_id,
                    affected_tasks=[candidate.task_title],
                    slack_change=candidate.duration
                ));
        } else {
            reply = CommandReply(ok=False, kind="capacity", title="No safe nearby move found",
                message="There is no earlier day with enough validated space for this work. Review the seven-day outlook or adjust planning hours.");
        }
    } else {
        reply = investigation.reply;
    }
    if preference is not None {
        reply = CommandReply(ok=True, kind="preference", title="A preference to review", message=preference.message, action_target="settings", action_label="Review preference");
    }
    if reply.proposal and reply.proposal.action_type == "move_task" {
        move = reply.proposal;
        source_task: Task | None = None;
        for task in [root -->][?:Task] {
            if jid(task) == move.target_task_id and task.day == move.day and not task.done {
                source_task = task;
                break;
            }
        }
        if source_task is None {
            return finish_command(investigation, CommandReply(ok=False, kind="help", title="Task not available",
                message="Choose an unfinished task on the selected day."));
        }
        due_day = source_task.due_day if source_task.due_day else source_task.day;
        if move.target_day > due_day {
            return finish_command(investigation, CommandReply(ok=False, kind="risk", title="Move misses the due date",
                message=source_task.title + " is due on " + due_day +
                        ". Choose that day or an earlier day."));
        }
        target_work = work_for(move.target_day);
        target_work.append(Work(id=jid(source_task), title=source_task.title,
            duration=source_task.duration,
            deadline=source_task.deadline if move.target_day == due_day else 1440,
            priority=source_task.priority));
        target_start = planning_start(move.target_day, prefs);
        preview = make_choice("minimal", target_work, busy_for(move.target_day),
                              target_start, prefs.day_end);
        if jid(source_task) in preview.unplaced or not validate(
            preview.slots, target_work, busy_for(move.target_day),
            target_start, prefs.day_end
        ) {
            return finish_command(investigation, CommandReply(ok=False, kind="capacity", title="Move does not fit",
                message="The requested day has no valid space for " + source_task.title +
                        " before its deadline."));
        }
        destination = [slot for slot in preview.slots if slot.task_id == jid(source_task)][0];
        move.details = source_task.title + " stays on " + move.day +
            " until you approve. It would move to " + move.target_day +
            " at " + clock_label(destination.start) + " and remain due on " + due_day + ".";
        move.slack_change = source_task.duration;
    }
    return finish_command(investigation, reply);
}

def finish_command(run: SecretaryRunView, reply: CommandReply) -> SecretaryRunView {
    reply = persist_command_reply(reply);
    for record in [root -->][?:SecretaryRunRecord] {
        if jid(record) == run.id {
            record.reply = reply;
            record.summary = reply.message;
            record.status = "complete" if reply.ok else "needs_attention";
            return record.view();
        }
    }
    raise ValueError("The investigation is no longer available.");
}

def ask_replaniva_internal(query: str, day: str = "", use_model: bool = False) -> CommandReply {
    require_account();
    if len(query.strip()) > 300 {
        return CommandReply(ok=False, kind="help", title="Keep the command focused", message="Use 300 characters or fewer so Replaniva can identify the planning action.");
    }
    return coordinate_command(query, day, use_model).reply;
}

def persist_command_reply(reply: CommandReply) -> CommandReply {
    if reply.proposal and reply.proposal.active {
        p = reply.proposal;
        node_prop = root ++> ActionProposal(
            kind=p.kind, title=p.title, day=p.day, details=p.details,
            base_version=p.base_version, active=p.active,
            task_title=p.task_title, task_duration=p.task_duration,
            task_deadline=p.task_deadline, commitment_start=p.commitment_start,
            commitment_end=p.commitment_end, commitment_title=p.commitment_title, affected_tasks=p.affected_tasks,
            unplaced_count=p.unplaced_count, slack_change=p.slack_change,
            action_type=p.action_type, target_task_id=p.target_task_id,
            target_day=p.target_day, proposed_duration=p.proposed_duration
        );
        reply.proposal.id = jid(node_prop);
    }
    return reply;
}

def:protect ask_replaniva(query: str, day: str = "") -> CommandReply {
    return ask_replaniva_internal(query, day);
}

def apply_new_task(proposal: ActionProposal, prefs: Settings) -> Action {
    proposal_id = jid(proposal);
    clean = proposal.task_title.strip();
    if not clean or len(clean) > 120 or proposal.task_duration < 15 or
       proposal.task_duration > 600 or proposal.task_deadline < 0 or
       proposal.task_deadline > 1440 {
        return Action(ok=False, message="The proposed task is invalid. Create a fresh proposal.");
    }
    preview_id = "proposal:" + proposal_id;
    preview_work = work_for(proposal.day);
    preview_work.append(Work(id=preview_id, title=clean,
        duration=proposal.task_duration, deadline=proposal.task_deadline));
    schedule_start = planning_start(proposal.day, prefs);
    preview = make_choice("minimal", preview_work, busy_for(proposal.day),
                          schedule_start, prefs.day_end);
    if preview_id in preview.unplaced or not validate(
        preview.slots, preview_work, busy_for(proposal.day),
        schedule_start, prefs.day_end
    ) {
        return Action(ok=False, message="That task no longer fits. Review the day and create a fresh proposal.");
    }
    root ++> Task(title=clean, day=proposal.day,
                  duration=proposal.task_duration,
                  deadline=proposal.task_deadline);
    record_activity(proposal.day, "Task added", clean + " was added through Replaniva Command.");
    return Action(ok=True, message="");
}

def apply_new_commitment(proposal: ActionProposal, prefs: Settings) -> Action {
    clean_title = proposal.commitment_title.strip();
    if not clean_title { clean_title = "New commitment"; }
    if len(clean_title) > 120 or proposal.commitment_start < prefs.day_start or
       proposal.commitment_end > prefs.day_end or
       proposal.commitment_end <= proposal.commitment_start {
        return Action(ok=False, message="The proposed commitment is invalid. Create a fresh proposal.");
    }
    current_busy = busy_for(proposal.day);
    for item in current_busy {
        if overlaps(proposal.commitment_start, proposal.commitment_end, item.start, item.end) {
            return Action(ok=False, message="That time now overlaps a fixed commitment. Create a fresh proposal.");
        }
    }
    preview_busy = [item for item in current_busy];
    preview_busy.append(Busy(title=clean_title, start=proposal.commitment_start, end=proposal.commitment_end));
    preview_work = work_for(proposal.day);
    schedule_start = planning_start(proposal.day, prefs);
    preview = make_choice("minimal", preview_work, preview_busy,
                          schedule_start, prefs.day_end);
    if not validate(preview.slots, preview_work, preview_busy,
                    schedule_start, prefs.day_end) {
        return Action(ok=False, message="The proposed schedule is no longer valid. Create a fresh proposal.");
    }
    root ++> Commitment(title=clean_title, day=proposal.day,
        start=proposal.commitment_start, end=proposal.commitment_end,
        source="command");
    record_activity(
        proposal.day,
        "Availability changed" if proposal.action_type == "change_availability" else "Commitment added",
        clean_title + " now occupies " + str(proposal.commitment_start // 60).zfill(2) + ":" +
        str(proposal.commitment_start % 60).zfill(2) + " to " +
        str(proposal.commitment_end // 60).zfill(2) + ":" +
        str(proposal.commitment_end % 60).zfill(2) + "."
    );
    return Action(ok=True, message="");
}

def apply_duration_change(proposal: ActionProposal, prefs: Settings) -> Action {
    target_task: Task | None = None;
    for task in [root -->][?:Task] {
        if jid(task) == proposal.target_task_id and task.day == proposal.day and not task.done {
            target_task = task;
            break;
        }
    }
    if target_task is None or proposal.proposed_duration < 15 or proposal.proposed_duration > 600 {
        return Action(ok=False, message="That task or duration is no longer available.");
    }
    preview_work: list[Work] = [];
    for item in work_for(proposal.day) {
        preview_work.append(Work(
            id=item.id, title=item.title,
            duration=proposal.proposed_duration if item.id == proposal.target_task_id else item.duration,
            deadline=item.deadline, priority=item.priority,
            start=item.start, depends_on=item.depends_on
        ));
    }
    schedule_start = planning_start(proposal.day, prefs);
    preview = make_choice("minimal", preview_work, busy_for(proposal.day),
                          schedule_start, prefs.day_end);
    if proposal.target_task_id in preview.unplaced or not validate(
        preview.slots, preview_work, busy_for(proposal.day), schedule_start, prefs.day_end
    ) {
        return Action(ok=False, message="That duration no longer fits. Review the day and try again.");
    }
    old_duration = target_task.duration;
    target_task.duration = proposal.proposed_duration;
    record_activity(proposal.day, "Task duration changed",
        target_task.title + " changed from " + str(old_duration) + " to " +
        str(proposal.proposed_duration) + " minutes after approval.");
    return Action(ok=True, message="");
}

def apply_task_move(proposal: ActionProposal, prefs: Settings) -> Action {
    target_task: Task | None = None;
    for task in [root -->][?:Task] {
        if jid(task) == proposal.target_task_id and task.day == proposal.day and not task.done {
            target_task = task;
            break;
        }
    }
    if target_task is None or not proposal.target_day or proposal.target_day == proposal.day {
        return Action(ok=False, message="That task move is no longer available.");
    }
    due_day = target_task.due_day if target_task.due_day else target_task.day;
    if proposal.target_day > due_day {
        return Action(ok=False, message="That move would place the task after its due date.");
    }
    dependents = [task for task in [root -->][?:Task]
                  if not task.done and proposal.target_task_id in task.depends_on];
    if target_task.depends_on or dependents {
        return Action(ok=False, message="Move the linked task sequence together from Today so dependency order stays valid.");
    }
    target_work = work_for(proposal.target_day);
    target_work.append(Work(
        id=jid(target_task), title=target_task.title,
        duration=target_task.duration,
        deadline=target_task.deadline if proposal.target_day == due_day else 1440,
        priority=target_task.priority, depends_on=[]
    ));
    target_start = planning_start(proposal.target_day, prefs);
    preview = make_choice("minimal", target_work, busy_for(proposal.target_day),
                          target_start, prefs.day_end);
    if jid(target_task) in preview.unplaced or not validate(
        preview.slots, target_work, busy_for(proposal.target_day),
        target_start, prefs.day_end
    ) {
        return Action(ok=False, message="That task does not fit safely on the requested day.");
    }
    source_day = target_task.day;
    target_task.day = proposal.target_day;
    rebuild_day(source_day, prefs);
    rebuild_day(proposal.target_day, prefs);
    record_activity(proposal.target_day, "Task moved",
        target_task.title + " moved from " + source_day + " to " + proposal.target_day + " after approval.");
    return Action(ok=True, message="");
}

def apply_command_proposal_internal(proposal_id: str) -> Action {
    require_account();
    prepare_planning();
    prefs = settings();
    for proposal in [root -->][?:ActionProposal] {
        if jid(proposal) != proposal_id or not proposal.active { continue; }
        if proposal.base_version != prefs.version {
            return Action(ok=False, message="Your plan changed. Please review a fresh proposal.");
        }
        if proposal.action_type == "rebalance" {
            result = apply_rebalance_candidate(proposal.day, proposal.target_day, proposal.target_task_id);
            if result.ok { proposal.active = False; }
            return result;
        }
        if proposal.action_type in ["create_task", "protect_time"] { result = apply_new_task(proposal, prefs); }
        elif proposal.action_type in ["create_commitment", "what_if", "change_availability"] { result = apply_new_commitment(proposal, prefs); }
        elif proposal.action_type == "change_duration" { result = apply_duration_change(proposal, prefs); }
        elif proposal.action_type == "move_task" { result = apply_task_move(proposal, prefs); }
        else { return Action(ok=False, message="This proposal type is not supported."); }
        if not result.ok { return result; }
        if proposal.action_type != "move_task" { rebuild_day(proposal.day, prefs); }
        advance_version(prefs);
        proposal.active = False;
        return Action(ok=True, message="Proposal accepted and applied to your plan.");
    }
    return Action(ok=False, message="Proposal not found.");
}

def:protect apply_command_proposal(proposal_id: str) -> Action {
    return apply_command_proposal_internal(proposal_id);
}

def dismiss_command_proposal_internal(proposal_id: str) -> Action {
    require_account();
    for proposal in [root -->][?:ActionProposal] {
        if jid(proposal) == proposal_id and proposal.active {
            proposal.active = False;
            return Action(ok=True, message="Proposal dismissed. Your plan was not changed.");
        }
    }
    return Action(ok=False, message="Proposal not found.");
}

def:protect dismiss_command_proposal(proposal_id: str) -> Action {
    return dismiss_command_proposal_internal(proposal_id);
}

def:protect update_tour_state(completed: bool) -> Action {
    require_account();
    prefs = settings();
    prefs.tour_completed = completed;
    return Action(ok=True, message="Guide preference saved.");
}

def:protect update_appearance(light_mode: bool) -> Action {
    require_account();
    prefs = settings();
    prefs.light_mode = light_mode;
    return Action(ok=True, message="Appearance saved.");
}

def:protect update_planning_hours(day_start: int, day_end: int) -> Action {
    require_account();
    prepare_planning();
    day_start = int(day_start);
    day_end = int(day_end);
    if day_start < 0 or day_end > 1440 or day_end - day_start < 180 or
       day_start % 15 != 0 or day_end % 15 != 0 {
        return Action(ok=False, message="Choose a planning window of at least three hours in 15-minute steps.");
    }
    prefs = settings();
    if prefs.day_start == day_start and prefs.day_end == day_end {
        return Action(ok=True, message="Your planning window is already up to date.");
    }
    prefs.day_start = day_start;
    prefs.day_end = day_end;
    advance_version(prefs);
    for day in planning_days() { rebuild_day(day, prefs); }
    return Action(ok=True, message="Planning hours saved. Flexible work has been rearranged to fit.");
}

def:protect create_task(title: str, day: str = "", duration: int = 60,
                     deadline: int = 1320, priority: int = 2,
                     preferred_start: int = -1, depends_on: list[str] | None = None,
                     goal_id: str = "", due_day: str = "") -> Action {
    require_account();
    prepare_planning();
    duration = int(duration);
    deadline = int(deadline);
    priority = int(priority);
    preferred_start = int(preferred_start);
    # Native request schemas may coerce the legacy None default to a singleton list.
    depends_on = [] if depends_on is None or str(depends_on) == "None" or depends_on == ["None"] else depends_on;
    clean = title.strip();
    prefs = settings();
    current_day = resolved_day(day);
    actual_due_day = due_day if due_day else current_day;
    try { date.fromisoformat(actual_due_day); }
    except Exception { return Action(ok=False, message="Choose a valid due date."); }
    schedule_start = planning_start(current_day, prefs);
    if not clean or len(clean) > 120 or duration < 15 or duration > 600 or
       deadline < 0 or deadline > 1440 or priority < 1 or priority > 3 or
       actual_due_day < current_day or
       (actual_due_day == current_day and deadline < schedule_start + duration) or
       (preferred_start >= 0 and (preferred_start < schedule_start or
        preferred_start + duration > prefs.day_end or
        (actual_due_day == current_day and preferred_start + duration > deadline))) {
        return Action(ok=False, message="Check the title, duration, due date, deadline and priority.");
    }
    if len(depends_on) != len(set(depends_on)) {
        return Action(ok=False, message="Choose each prerequisite once.");
    }
    active_task_ids = [jid(t) for t in [root -->][?:Task]
                       if t.day == current_day and not t.done];
    if [dependency_id for dependency_id in depends_on if dependency_id not in active_task_ids] {
        return Action(ok=False, message="Every prerequisite must be an unfinished task on the same day.");
    }
    if goal_id and not [g for g in [root -->][?:Goal] if jid(g) == goal_id] {
        return Action(ok=False, message="Choose a goal from this account.");
    }
    root ++> Task(title=clean, day=current_day, duration=duration,
                  deadline=deadline, priority=priority, start=preferred_start,
                  depends_on=depends_on, goal_id=goal_id, due_day=actual_due_day);
    rebuild_day(current_day, prefs);
    advance_version(prefs);
    record_activity(current_day, "Task added", clean + " was added and placed by the scheduler.");
    return Action(ok=True, message="Task saved. The plan has been updated.");
}

def:protect set_task_done(task_id: str, done: bool = True) -> Action {
    require_account();
    prepare_planning();
    for task in [root -->][?:Task] {
        if jid(task) == task_id {
            task.done = done;
            if done { task.start = -1; }
            prefs = settings();
            rebuild_day(task.day, prefs);
            advance_version(prefs);
            record_activity(task.day, "Task completed" if done else "Task reopened",
                            task.title + (" was marked complete." if done else " returned to the active plan."));
            return Action(ok=True, message="Task updated.");
        }
    }
    return Action(ok=False, message="Task not found in your plan.");
}

def:protect delete_task(task_id: str) -> Action {
    require_account();
    prepare_planning();
    for task in [root -->][?:Task] {
        if jid(task) == task_id {
            dependents = [other for other in [root -->][?:Task]
                          if not other.done and task_id in other.depends_on];
            if dependents {
                return Action(ok=False, message="Complete or remove dependent work before deleting this prerequisite.");
            }
            current_day = task.day;
            removed_title = task.title;
            del task;
            prefs = settings();
            rebuild_day(current_day, prefs);
            advance_version(prefs);
            record_activity(current_day, "Task removed", removed_title + " was removed and the remaining work was rearranged.");
            return Action(ok=True, message="Task removed. The remaining work has been rearranged.");
        }
    }
    return Action(ok=False, message="Task not found in your plan.");
}

def:protect create_commitment(title: str, day: str = "", start: int = 540,
                           end: int = 600) -> Action {
    require_account();
    prepare_planning();
    start = int(start);
    end = int(end);
    current_day = resolved_day(day);
    prefs = settings();
    if not title.strip() or start < prefs.day_start or end > prefs.day_end or end <= start {
        return Action(ok=False, message="Enter a name and a valid time inside your day.");
    }
    for item in busy_for(current_day) {
        if overlaps(start, end, item.start, item.end) {
            return Action(ok=False, message="That time overlaps a fixed commitment.");
        }
    }
    root ++> Commitment(title=title.strip(), day=current_day, start=start, end=end);
    rebuild_day(current_day, prefs);
    advance_version(prefs);
    record_activity(current_day, "Commitment added", title.strip() + " was added and flexible work moved around it.");
    return Action(ok=True, message="Commitment saved. Flexible work has been arranged around it.");
}

def:protect delete_commitment(commitment_id: str) -> Action {
    require_account();
    prepare_planning();
    for commitment in [root -->][?:Commitment] {
        if jid(commitment) == commitment_id {
            current_day = commitment.day;
            removed_title = commitment.title;
            del commitment;
            prefs = settings();
            rebuild_day(current_day, prefs);
            advance_version(prefs);
            record_activity(current_day, "Commitment removed", removed_title + " was removed and the day was rearranged.");
            return Action(ok=True, message="Commitment removed. The day has been rearranged.");
        }
    }
    return Action(ok=False, message="Commitment not found in your plan.");
}

def:protect preview_recovery(title: str, day: str = "", start: int = 840,
                          end: int = 1020, use_model: bool = False) -> Action {
    require_account();
    start = int(start);
    end = int(end);
    current_day = resolved_day(day);
    prefs = settings();
    if not title.strip() or start < prefs.day_start or end > prefs.day_end or end <= start {
        return Action(ok=False, message="Enter a disruption name and a valid time.");
    }
    busy = busy_for(current_day);
    for item in busy {
        if overlaps(start, end, item.start, item.end) {
            return Action(ok=False, message="The new commitment overlaps another fixed event.");
        }
    }
    busy.append(Busy(title=title.strip(), start=start, end=end));
    work = work_for(current_day);
    schedule_start = planning_start(current_day, prefs);
    minimal = make_choice("minimal", work, busy, schedule_start, prefs.day_end);
    deadline = make_choice("deadline", work, busy, schedule_start, prefs.day_end);
    if use_model {
        model_choice = optional_model_choice(work, busy, schedule_start, prefs.day_end, jid(root));
        if model_choice is not None { deadline = model_choice; }
    }
    if not validate(minimal.slots, work, busy, schedule_start, prefs.day_end) or
       not validate(deadline.slots, work, busy, schedule_start, prefs.day_end) {
        return Action(ok=False, message="No valid recovery could be built.");
    }
    deactivate_proposals(current_day);
    root ++> Proposal(day=current_day, title=title.strip(), start=start, end=end,
                      base_version=prefs.version, minimal=minimal, deadline=deadline);
    return Action(ok=True, message="Two recovery choices are ready to review.");
}

def:protect dismiss_recovery(proposal_id: str) -> Action {
    require_account();
    for proposal in [root -->][?:Proposal] {
        if jid(proposal) == proposal_id and proposal.active {
            proposal.active = False;
            return Action(ok=True, message="Recovery preview dismissed. Your current plan was not changed.");
        }
    }
    return Action(ok=False, message="Recovery proposal not found.");
}

def:protect interpret_disruption(note: str, day: str = "") -> DisruptionDraft {
    require_account();
    if len(note.strip()) > 500 {
        return DisruptionDraft(ok=False, message="Keep your note under 500 characters.");
    }
    draft = optional_interpret_note(note, resolved_day(day), jid(root));
    if draft is None {
        return DisruptionDraft(ok=False, message="AI interpretation is unavailable. Enter the change using the time fields below.");
    }
    return DisruptionDraft(ok=True, title=draft.title, start=draft.start,
                           end=draft.end, message="Check these details, then explore recovery.");
}

def:protect accept_recovery(proposal_id: str, option: str) -> Action {
    require_account();
    prepare_planning();
    prefs = settings();
    for proposal in [root -->][?:Proposal] {
        if jid(proposal) == proposal_id and proposal.active {
            if proposal.base_version != prefs.version {
                return Action(ok=False, message="Your plan changed. Please create a fresh recovery.");
            }
            if option != "minimal" and option != "deadline" {
                return Action(ok=False, message="Choose one of the two recovery options.");
            }
            choice = proposal.minimal if option == "minimal" else proposal.deadline;
            busy = busy_for(proposal.day);
            busy.append(Busy(title=proposal.title, start=proposal.start, end=proposal.end));
            work = work_for(proposal.day);
            if not validate(choice.slots, work, busy,
                            planning_start(proposal.day, prefs), prefs.day_end) {
                return Action(ok=False, message="That recovery is no longer valid.");
            }
            before = [Slot(task_id=jid(t), start=t.start,
                           end=t.start + t.duration if t.start >= 0 else -1)
                      for t in [root -->][?:Task] if t.day == proposal.day and not t.done];
            commitment = root ++> Commitment(title=proposal.title, day=proposal.day,
                                              start=proposal.start, end=proposal.end,
                                              source="recovery");
            apply_slots(proposal.day, choice.slots);
            advance_version(prefs);
            root ++> Revision(day=proposal.day, version=prefs.version,
                              title=proposal.title, before=before,
                              commitment_id=jid(commitment));
            proposal.active = False;
            for slot in choice.slots {
                previous = [item for item in before if item.task_id == slot.task_id];
                if previous and previous[0].start >= 0 and previous[0].start != slot.start {
                    task_name = "Flexible work";
                    for task in [root -->][?:Task] {
                        if jid(task) == slot.task_id { task_name = task.title; }
                    }
                    record_activity(proposal.day, "Work moved",
                        task_name + " moved from " + clock_label(previous[0].start) +
                        " to " + clock_label(slot.start) + " because " + proposal.title +
                        " occupied " + clock_label(proposal.start) + " to " +
                        clock_label(proposal.end) + ".");
                }
            }
            moved_count = choice.moved;
            detail = proposal.title + " was accepted. " + str(moved_count) + " task" +
                     ("s" if moved_count != 1 else "") + " moved";
            if choice.unplaced { detail += " and " + str(len(choice.unplaced)) + " could not be placed"; }
            detail += ".";
            record_activity(proposal.day, "Recovery accepted", detail);
            return Action(ok=True, message="Recovery accepted. Your plan is updated.");
        }
    }
    return Action(ok=False, message="Recovery proposal not found.");
}

def:protect restore_revision(revision_id: str) -> Action {
    require_account();
    prepare_planning();
    prefs = settings();
    for revision in [root -->][?:Revision] {
        if jid(revision) == revision_id and not revision.restored {
            if revision.version != prefs.version {
                return Action(ok=False, message="Only the latest unchanged recovery can be restored.");
            }
            remaining_busy = [Busy(title=c.title, start=c.start, end=c.end)
                              for c in [root -->][?:Commitment]
                              if c.day == revision.day and jid(c) != revision.commitment_id];
            placed_before = [slot for slot in revision.before if slot.start >= 0];
            if not validate(placed_before, work_for(revision.day), remaining_busy,
                            planning_start(revision.day, prefs), prefs.day_end) {
                return Action(ok=False, message="The previous plan is no longer valid at the current time. Your current plan was not changed.");
            }
            for commitment in [root -->][?:Commitment] {
                if jid(commitment) == revision.commitment_id { del commitment; }
            }
            apply_slots(revision.day, revision.before);
            revision.restored = True;
            advance_version(prefs);
            record_activity(revision.day, "Recovery restored",
                            "The plan from before " + revision.title + " was restored.");
            return Action(ok=True, message="The previous plan has been restored.");
        }
    }
    return Action(ok=False, message="Revision not found.");
}

def:protect create_goal(title: str, target_date: str = "", importance: str = "medium") -> Action {
    require_account();
    clean = title.strip();
    if not clean or len(clean) > 120 {
        return Action(ok=False, message="Enter a goal title of 120 characters or fewer.");
    }
    if importance not in ["low", "medium", "high"] {
        return Action(ok=False, message="Choose low, medium or high importance.");
    }
    if target_date {
        try { date.fromisoformat(target_date); }
        except Exception { return Action(ok=False, message="Choose a valid target date."); }
    }
    root ++> Goal(title=clean, target_date=target_date, importance=importance);
    prefs = settings();
    advance_version(prefs);
    return Action(ok=True, message="Goal created.");
}

def:protect toggle_goal(goal_id: str) -> Action {
    require_account();
    for goal in [root -->][?:Goal] {
        if jid(goal) == goal_id {
            goal.completed = not goal.completed;
            prefs = settings();
            advance_version(prefs);
            return Action(ok=True, message="Goal updated.");
        }
    }
    return Action(ok=False, message="Goal not found.");
}

def:protect delete_goal(goal_id: str) -> Action {
    require_account();
    found = False;
    for goal in [root -->][?:Goal] {
        if jid(goal) == goal_id {
            del goal;
            found = True;
            break;
        }
    }
    if not found {
        return Action(ok=False, message="Goal not found.");
    }
    for task in [root -->][?:Task] {
        if task.goal_id == goal_id {
            task.goal_id = "";
            task.relationships_migrated = False;
        }
    }
    prefs = settings();
    advance_version(prefs);
    return Action(ok=True, message="Goal removed.");
}

def:protect link_task_to_goal(task_id: str, goal_id: str) -> Action {
    require_account();
    if goal_id and not [goal for goal in [root -->][?:Goal] if jid(goal) == goal_id] {
        return Action(ok=False, message="Goal not found in this account.");
    }
    for task in [root -->][?:Task] {
        if jid(task) == task_id {
            task.goal_id = goal_id;
            task.relationships_migrated = False;
            prefs = settings();
            advance_version(prefs);
            return Action(ok=True, message="Task linked to goal." if goal_id else "Task removed from its goal.");
        }
    }
    return Action(ok=False, message="Task not found.");
}

def:protect apply_rebalance_candidate(from_day: str, to_day: str, task_id: str) -> Action {
    require_account();
    prepare_planning();
    prefs = settings();
    candidate = suggest_rebalance(from_day, to_day, work_for(from_day),
        work_for(to_day), busy_for(to_day), planning_start(to_day, prefs), prefs.day_end);
    if not candidate.available or candidate.task_id != task_id or
       candidate.from_day != from_day or candidate.to_day != to_day {
        return Action(ok=False, message="That rebalance is no longer available. Review the latest outlook.");
    }
    for task in [root -->][?:Task] {
        if task.day == from_day and jid(task) == task_id and not task.done {
            task.day = to_day;
            target = rebuild_day(to_day, prefs);
            if task_id in target.unplaced {
                task.day = from_day;
                rebuild_day(from_day, prefs);
                rebuild_day(to_day, prefs);
                return Action(ok=False, message="That task no longer fits on the suggested day.");
            }
            rebuild_day(from_day, prefs);
            advance_version(prefs);
            record_activity(to_day, "Workload rebalanced",
                            task.title + " moved from " + from_day + " to " + to_day + " after validation.");
            return Action(ok=True, message="Task moved to " + to_day + " and schedules updated.");
        }
    }
    return Action(ok=False, message="Task not found.");
}

def:protect preview_task_breakdown(task_id: str) -> BreakdownProposal {
    require_account();
    for task in [root -->][?:Task] {
        if jid(task) == task_id and not task.done {
            subtasks = generate_subtasks(task.title, task.duration);
            return BreakdownProposal(
                ok=True,
                task_id=task_id,
                original_title=task.title,
                day=task.day,
                base_version=settings().version,
                subtasks=subtasks,
                message="Preview breakdown for " + task.title
            );
        }
    }
    return BreakdownProposal(ok=False, message="Task not found in your plan.");
}

def:protect apply_task_breakdown(task_id: str, titles: list[str], durations: list[int], expected_version: int) -> Action {
    require_account();
    prepare_planning();
    target_task: Task | None = None;
    for task in [root -->][?:Task] {
        if jid(task) == task_id and not task.done {
            target_task = task;
            break;
        }
    }
    if target_task is None {
        return Action(ok=False, message="Task not found in your plan.");
    }
    prefs = settings();
    if expected_version != prefs.version {
        return Action(ok=False, message="Your plan changed. Review a fresh breakdown.");
    }
    if len(titles) < 2 or len(titles) > 6 or len(titles) != len(durations) {
        return Action(ok=False, message="Use between two and six matching subtask titles and durations.");
    }
    clean_titles = [title.strip() for title in titles];
    clean_durations = [int(duration) for duration in durations];
    if [title for title in clean_titles if not title or len(title) > 120] {
        return Action(ok=False, message="Every subtask needs a title of 120 characters or fewer.");
    }
    if [duration for duration in clean_durations
        if duration < 15 or duration > 600 or duration % 15 != 0] {
        return Action(ok=False, message="Use 15-minute steps for every subtask.");
    }
    total_duration = sum(clean_durations);
    if total_duration < target_task.duration or total_duration > target_task.duration + 14 {
        return Action(ok=False, message="Subtasks must preserve the original task duration, rounded up to 15 minutes.");
    }
    target_day = target_task.day;
    target_deadline = target_task.deadline;
    target_due_day = target_task.due_day if target_task.due_day else target_day;
    preview_deadline = target_deadline if target_due_day == target_day else 1440;
    target_priority = target_task.priority;
    target_goal_id = target_task.goal_id;
    parent_deps = [d for d in target_task.depends_on];

    preview_ids = ["breakdown:" + task_id + ":" + str(i) for i in range(len(clean_titles))];
    preview_work: list[Work] = [];
    for existing in work_for(target_day) {
        if existing.id == task_id { continue; }
        updated_deps = [preview_ids[-1] if dependency_id == task_id else dependency_id
                        for dependency_id in existing.depends_on];
        preview_work.append(Work(id=existing.id, title=existing.title,
            duration=existing.duration, deadline=existing.deadline,
            priority=existing.priority, start=existing.start,
            depends_on=updated_deps));
    }
    for i in range(len(clean_titles)) {
        preview_deps = [preview_ids[i - 1]] if i > 0 else [d for d in parent_deps];
        preview_work.append(Work(id=preview_ids[i], title=clean_titles[i],
            duration=clean_durations[i], deadline=preview_deadline,
            priority=target_priority, depends_on=preview_deps));
    }
    schedule_start = planning_start(target_day, prefs);
    preview_choice = make_choice("minimal", preview_work, busy_for(target_day),
                                 schedule_start, prefs.day_end);
    if [preview_id for preview_id in preview_ids if preview_id in preview_choice.unplaced] or
       not validate(preview_choice.slots, preview_work, busy_for(target_day),
                    schedule_start, prefs.day_end) {
        return Action(ok=False, message="That breakdown does not fit the current plan. Adjust the steps or make space first.");
    }

    previous_jid = "";
    for i in range(len(titles)) {
        sub_title = clean_titles[i];
        sub_dur = clean_durations[i];

        deps: list[str] = [];
        if previous_jid {
            deps = [previous_jid];
        } elif len(parent_deps) > 0 {
            deps = [d for d in parent_deps];
        }

        new_task = root ++> Task(
            title=sub_title,
            day=target_day,
            duration=sub_dur,
            deadline=target_deadline,
            priority=target_priority,
            depends_on=deps,
            goal_id=target_goal_id,
            due_day=target_due_day
        );
        previous_jid = jid(new_task);
    }

    last_jid = previous_jid;
    for other in [root -->][?:Task] {
        if task_id in other.depends_on {
            other.depends_on = [last_jid if d == task_id else d for d in other.depends_on];
            other.relationships_migrated = False;
        }
    }

    original_title = target_task.title;
    del target_task;
    rebuild_day(target_day, prefs);
    advance_version(prefs);
    record_activity(target_day, "Task broken down",
                    original_title + " became " + str(len(clean_titles)) + " ordered steps after approval.");
    return Action(ok=True, message="Task broken down into sequenced subtasks.");
}
# Private Calendar proposals reuse the existing Jac planning graph.

node CalendarLink {
    has key: str, identity: str, calendar: str, commitment_id: str,
        title: str, day: str, start: int, end: int;
}
node CalendarProposal {
    has mode: str, payload: str, version: int, expires: int, active: bool = True;
}
obj CalendarPreview {
    has ok: bool, id: str = "", mode: str = "", message: str = "",
        changes: list[str] = [], effects: list[str] = [];
}

def:protect calendar_status -> dict[str, any] {
    require_account();
    return google.status(jid(root));
}
def:protect calendar_connect -> dict[str, str] {
    require_account();
    return google.begin(jid(root));
}
def:protect calendar_finish(authorization_id: str, proof: str) -> Action {
    require_account();
    try {
        connection = google.finish(jid(root), authorization_id, proof);
        if not connection["connected"] { return Action(ok=False, message=connection["message"]); }
        return Action(ok=True, message="Google Calendar connected. Choose which calendars to read.");
    } except google.CalendarError as error { return Action(ok=False, message=str(error)); }
}
def:protect calendar_select(selected: list[str]) -> Action {
    require_account();
    try {
        google.select_calendars(jid(root), selected);
        for proposal in [root -->][?:CalendarProposal] { proposal.active = False; }
        return Action(ok=True, message="Calendar selection saved. Preview synchronization before applying changes.");
    } except google.CalendarError as error { return Action(ok=False, message=str(error)); }
}
def:protect calendar_disconnect -> Action {
    require_account();
    for proposal in [root -->][?:CalendarProposal] { proposal.active = False; }
    return Action(ok=True, message=google.disconnect(jid(root)));
}
def:protect calendar_create_export_calendar -> Action {
    require_account();
    try {
        google.ensure_app_calendar(jid(root));
        return Action(ok=True, message="The dedicated Replaniva export calendar is ready.");
    } except google.CalendarError as error { return Action(ok=False, message=str(error)); }
}


def calendar_import_data(first: str, last: str) -> dict[str, any] {
    require_account();
    snapshot = google.snapshot(jid(root), first, last);
    selected = snapshot["selected"];
    if not selected { raise google.CalendarError("Choose at least one calendar to read."); }
    links = [item for item in [root -->][?:CalendarLink] if item.identity == snapshot["identity"] and item.calendar in selected and first <= item.day and item.day < last];
    changes: list[dict[str, any]] = [];
    for link in links {
        existing = [c for c in [root -->][?:Commitment] if jid(c) == link.commitment_id];
        if not existing or existing[0].source != "google_calendar" or existing[0].title != link.title or existing[0].day != link.day or existing[0].start != link.start or existing[0].end != link.end {
            raise google.CalendarError("An imported commitment was edited or removed locally. Resolve that item before synchronizing its calendar.");
        }
        matches = [e for e in snapshot["events"] if e["key"] == link.key];
        if not matches {
            changes.append({"kind": "remove", "key": link.key, "id": link.commitment_id, "title": link.title, "day": link.day});
        } elif matches[0]["title"] != link.title or matches[0]["start"] != link.start or matches[0]["end"] != link.end {
            changes.append({"kind": "update", "key": link.key, "id": link.commitment_id, "event": matches[0], "title": matches[0]["title"], "day": link.day});
        }
    }
    for event in snapshot["events"] {
        if not [l for l in links if l.key == event["key"]] {
            changes.append({"kind": "add", "key": event["key"], "id": "", "event": event, "title": event["title"], "day": event["day"]});
        }
    }
    return {"snapshot": snapshot, "changes": changes, "first": first, "last": last};
}

def calendar_choices(data: dict[str, any]) -> dict[str, any] {
    require_account();
    prefs = settings();
    days = sorted(set([item["day"] for item in data["changes"]]));
    choices: dict[str, any] = {};
    for day in days {
        removed = [item["id"] for item in data["changes"] if item["kind"] != "add"];
        busy = [Busy(title=c.title, start=c.start, end=c.end) for c in [root -->][?:Commitment] if c.day == day and jid(c) not in removed];
        for item in data["changes"] {
            if item["kind"] != "remove" and item["day"] == day {
                event = item["event"];
                busy.append(Busy(title=event["title"], start=event["start"], end=event["end"]));
            }
        }
        for (index, item) in enumerate(busy) {
            for other in busy[index + 1:] {
                if overlaps(item.start, item.end, other.start, other.end) {
                    raise google.CalendarError("Fixed commitments overlap on " + day + ". Review the source calendars or local commitments before importing.");
                }
            }
        }
        work = work_for(day);
        choice = make_choice("minimal", work, busy, planning_start(day, prefs), prefs.day_end);
        if not validate(choice.slots, work, busy, planning_start(day, prefs), prefs.day_end) {
            raise google.CalendarError("This import cannot produce a valid schedule.");
        }
        choices[day] = choice;
    }
    return choices;
}

def save_calendar_preview(mode: str, data: dict[str, any], changes: list[str], effects: list[str]) -> CalendarPreview {
    require_account();
    for proposal in [root -->][?:CalendarProposal] { proposal.active = False; }
    proposal = root ++> CalendarProposal(mode=mode, payload=json.dumps(data), version=settings().version, expires=int(time.time()) + 900);
    return CalendarPreview(ok=True, id=jid(proposal), mode=mode,
        message="Review these changes. Nothing is applied until you approve. This preview expires in 15 minutes.", changes=changes, effects=effects);
}

def:protect calendar_preview_import(first: str = "") -> CalendarPreview {
    require_account();
    try {
        first = first if first else account_clock().day;
        last = (date.fromisoformat(first) + timedelta(days=7)).isoformat();
        data = calendar_import_data(first, last);
        choices = calendar_choices(data);
        changes = [c["kind"].capitalize() + ": " + c["title"] + " on " + c["day"] +
            (" (" + str(c["event"]["start"] // 60).zfill(2) + ":" + str(c["event"]["start"] % 60).zfill(2) + " to " + str(c["event"]["end"] // 60).zfill(2) + ":" + str(c["event"]["end"] % 60).zfill(2) + ")" if c["kind"] != "remove" else " (only its imported copy)") for c in data["changes"]];
        effects: list[str] = [];
        for (day, choice) in choices.items() {
            names = [t.title for t in [root -->][?:Task] if jid(t) in choice.unplaced];
            effects.append(day + ": " + str(choice.moved) + " task(s) moved; " + str(len(choice.unplaced)) + " unplaced." + (" Unplaced: " + ", ".join(names) if names else "") + " " + choice.reason);
        }
        return save_calendar_preview("import", data, changes, effects);
    } except (google.CalendarError, ValueError) as error { return CalendarPreview(ok=False, message=str(error)); }
}

def export_tasks(task_ids: list[str]) -> list[dict[str, any]] {
    require_account();
    if not task_ids or len(task_ids) > 100 or len(set(task_ids)) != len(task_ids) {
        raise google.CalendarError("Select between one and 100 different tasks to export.");
    }
    tasks = [t for t in [root -->][?:Task] if jid(t) in task_ids];
    if len(tasks) != len(task_ids) { raise google.CalendarError("A selected task is not in this account."); }
    prefs = settings();
    for task in tasks {
        if task.done or task.start < 0 { raise google.CalendarError("Only saved, unfinished, scheduled tasks can be exported."); }
        work = work_for(task.day);
        slots = [Slot(task_id=jid(t), start=t.start, end=t.start+t.duration) for t in [root -->][?:Task] if t.day == task.day and not t.done and t.start >= 0];
        if not validate(slots, work, busy_for(task.day), prefs.day_start, prefs.day_end) {
            raise google.CalendarError("The saved schedule needs validation before it can be exported.");
        }
    }
    return [{"id": jid(t), "title": t.title, "day": t.day, "start": t.start, "duration": t.duration} for t in tasks];
}

def:protect calendar_preview_export(task_ids: list[str]) -> CalendarPreview {
    require_account();
    try {
        tasks = export_tasks(task_ids);
        data = google.export_preview(jid(root), tasks);
        data["tasks"] = tasks;
        changes = [c["kind"].capitalize() + ": " + c["label"] + ("; previously " + str(c["before"]) if c.get("before") else "") + " (" + c["body"]["start"]["dateTime"] + " to " + c["body"]["end"]["dateTime"] + ")" for c in data["changes"]];
        return save_calendar_preview("export", data, changes, ["Only the app-created Replaniva calendar can be changed. Existing personal calendar events are never edited."]);
    } except google.CalendarError as error { return CalendarPreview(ok=False, message=str(error)); }
}

def:protect calendar_dismiss(proposal_id: str) -> Action {
    require_account();
    for proposal in [root -->][?:CalendarProposal] {
        if jid(proposal) == proposal_id { proposal.active = False; return Action(ok=True, message="Calendar preview dismissed. No changes were applied."); }
    }
    return Action(ok=False, message="Preview not found in this account.");
}

def:protect calendar_approve(proposal_id: str) -> Action {
    require_account();
    prepare_planning();
    for proposal in [root -->][?:CalendarProposal] {
        if jid(proposal) != proposal_id { continue; }
        if not proposal.active or proposal.expires < int(time.time()) or proposal.version != settings().version {
            return Action(ok=False, message="This calendar preview is stale or expired. Preview again.");
        }
        try {
            data = json.loads(proposal.payload);
            if proposal.mode == "export" {
                if export_tasks([t["id"] for t in data["tasks"]]) != data["tasks"] {
                    raise google.CalendarError("The tasks changed. Preview exports again.");
                }
                google.write_export(jid(root), data);
            } else {
                current = calendar_import_data(data["first"], data["last"]);
                if google.fingerprint(current) != google.fingerprint(data) {
                    raise google.CalendarError("Google Calendar or the selected calendars changed. Preview imports again.");
                }
                choices = calendar_choices(data);
                for item in data["changes"] {
                    if item["kind"] != "add" {
                        for commitment in [root -->][?:Commitment] {
                            if jid(commitment) == item["id"] and commitment.source == "google_calendar" { del commitment; }
                        }
                        for link in [root -->][?:CalendarLink] {
                            if link.key == item["key"] and link.identity == data["snapshot"]["identity"] { del link; }
                        }
                    }
                    if item["kind"] != "remove" {
                        event = item["event"];
                        commitment = root ++> Commitment(title=event["title"], day=event["day"], start=event["start"], end=event["end"], source="google_calendar");
                        root ++> CalendarLink(key=event["key"], identity=data["snapshot"]["identity"], calendar=event["calendar"], commitment_id=jid(commitment), title=event["title"], day=event["day"], start=event["start"], end=event["end"]);
                    }
                }
                for (day, choice) in choices.items() { apply_slots(day, choice.slots); }
                if data["changes"] { advance_version(settings()); }
                google.mark_synced(jid(root));
            }
            proposal.active = False;
            record_activity(account_clock().day, "Calendar synchronization approved", "Reviewed " + proposal.mode + " changes were applied.");
            return Action(ok=True, message="Approved calendar synchronization completed.");
        } except google.CalendarError as error { return Action(ok=False, message=str(error)); }
    }
    return Action(ok=False, message="Preview not found in this account.");
}


# Calendar approval tests use synthetic events and temporary private roots.


test "calendar imports are reviewed deduplicated reconciled and isolated" {
    import from unittest.mock { patch }
    import from jaclang { JacRuntime as Jac }
    import from jaclang.runtime.archetype { Root }
    import from uuid { UUID }
    original = jid(root);
    context = Jac.get_context();
    first = root ++> Root();
    second = root ++> Root();
    Jac.save(first); Jac.save(second); Jac.commit();
    Jac.set_shared_root_resolver(lambda -> str { return original; });
    snapshot = {"generation": "test-generation", "identity": "synthetic-google", "selected": ["personal"],
        "events": [{"key": "external-event", "calendar": "personal", "event": "lab", "title": "Lab", "day": "2099-01-01", "start": 840, "end": 1020}]};
    try {
        context.set_user_root(jid(first));
        root ++> Settings();
        root ++> Task(title="Study", day="2099-01-01", duration=60, deadline=1200, start=840);
        root ++> Commitment(title="Manual class", day="2099-01-01", start=480, end=540);
        with patch.object(google, "snapshot", return_value=snapshot) {
            with patch.object(google, "mark_synced") {
                preview = calendar_preview_import("2099-01-01");
                assert preview.ok and len(preview.changes) == 1;
                assert len([root -->][?:Commitment]) == 1;
                assert calendar_dismiss(preview.id).ok;
                assert not calendar_approve(preview.id).ok;
                assert len([root -->][?:Commitment]) == 1;
                preview = calendar_preview_import("2099-01-01");
                context.set_user_root(jid(second));
                assert not calendar_approve(preview.id).ok;
                assert len([root -->][?:Commitment]) == 0;
                context.set_user_root(jid(first));
                assert calendar_approve(preview.id).ok;
                assert not calendar_approve(preview.id).ok;
                assert len([root -->][?:Commitment]) == 2;
                assert [root -->][?:Task][0].start != 840;
                repeat = calendar_preview_import("2099-01-01");
                assert repeat.ok and len(repeat.changes) == 0;
                assert calendar_approve(repeat.id).ok;
                assert len([root -->][?:Commitment]) == 2;
                stale = calendar_preview_import("2099-01-01");
                settings().version += 1;
                assert not calendar_approve(stale.id).ok;
            }
        }
        moved = {"generation": "test-generation", "identity": "synthetic-google", "selected": ["personal"],
            "events": [{"key": "external-event", "calendar": "personal", "event": "lab", "title": "Moved lab", "day": "2099-01-01", "start": 1080, "end": 1140}]};
        with patch.object(google, "snapshot", return_value=moved) {
            with patch.object(google, "mark_synced") {
                preview = calendar_preview_import("2099-01-01");
                assert preview.ok and "Update" in preview.changes[0];
                assert calendar_approve(preview.id).ok;
                assert len([root -->][?:Commitment]) == 2;
                imported = [c for c in [root -->][?:Commitment] if c.source == "google_calendar"][0];
                imported.title = "Locally edited";
                assert not calendar_preview_import("2099-01-01").ok;
                imported.title = "Moved lab";
            }
        }
        empty = {"generation": "test-generation", "identity": "synthetic-google", "selected": ["personal"], "events": []};
        with patch.object(google, "snapshot", side_effect=[moved, empty]) {
            preview = calendar_preview_import("2099-01-01");
            assert preview.ok;
            assert not calendar_approve(preview.id).ok;
            assert len([root -->][?:Commitment]) == 2;
        }
        with patch.object(google, "snapshot", return_value=empty) {
            with patch.object(google, "mark_synced") {
                preview = calendar_preview_import("2099-01-01");
                assert "Remove" in preview.changes[0];
                assert len([root -->][?:Commitment]) == 2;
                assert calendar_approve(preview.id).ok;
                assert len([root -->][?:Commitment]) == 1;
                assert [root -->][?:Commitment][0].title == "Manual class";
            }
        }
        root ++> Task(title="No room today", day="2099-01-02", duration=60, deadline=1200, start=600);
        all_day = {"generation": "test-generation", "identity": "synthetic-google", "selected": ["personal"],
            "events": [{"key": "all-day", "calendar": "personal", "event": "busy-day", "title": "Busy day", "day": "2099-01-02", "start": 0, "end": 1440}]};
        with patch.object(google, "snapshot", return_value=all_day) {
            with patch.object(google, "mark_synced") {
                preview = calendar_preview_import("2099-01-02");
                assert preview.ok and "No room today" in preview.effects[0];
                assert [t for t in [root -->][?:Task] if t.day == "2099-01-02"][0].start == 600;
                for proposal in [root -->][?:CalendarProposal] { if jid(proposal) == preview.id { proposal.expires = 0; } }
                assert not calendar_approve(preview.id).ok;
                preview = calendar_preview_import("2099-01-02");
                assert calendar_approve(preview.id).ok;
                assert [t for t in [root -->][?:Task] if t.day == "2099-01-02"][0].start == -1;
            }
        }
    } finally {
        for fixture in [first, second] {
            context.set_user_root(jid(fixture));
            for item in [root -->] { del item; }
        }
        context.set_user_root(original);
        Jac.disconnect(root, first); Jac.disconnect(root, second);
        context.mem.delete(UUID(jid(first))); context.mem.delete(UUID(jid(second)));
        Jac.commit(); Jac.set_shared_root_resolver(None);
    }
}

test "calendar exports reject unscheduled foreign stale and dismissed tasks" {
    import from unittest.mock { patch }
    import from jaclang { JacRuntime as Jac }
    import from jaclang.runtime.archetype { Root }
    import from uuid { UUID }
    original = jid(root);
    context = Jac.get_context();
    fixture = root ++> Root();
    Jac.save(fixture); Jac.commit();
    Jac.set_shared_root_resolver(lambda -> str { return original; });
    try {
        context.set_user_root(jid(fixture));
        root ++> Settings();
        task = root ++> Task(title="Study", day="2099-01-01", duration=30, deadline=1200, start=600);
        with patch.object(google, "export_preview", return_value={"generation":"test", "calendar":"app-owned", "changes":[]}) {
            with patch.object(google, "write_export") as writer {
                assert not calendar_preview_export(["foreign-task"]).ok;
                task.start = -1;
                assert not calendar_preview_export([jid(task)]).ok;
                task.start = 600;
                preview = calendar_preview_export([jid(task)]);
                assert preview.ok;
                settings().version += 1;
                assert not calendar_approve(preview.id).ok;
                writer.assert_not_called();
                preview = calendar_preview_export([jid(task)]);
                assert calendar_dismiss(preview.id).ok;
                assert not calendar_approve(preview.id).ok;
                writer.assert_not_called();
                preview = calendar_preview_export([jid(task)]);
                assert calendar_approve(preview.id).ok;
                writer.assert_called_once();
                assert not calendar_approve(preview.id).ok;
            }
        }
    } finally {
        for item in [root -->] { del item; }
        context.set_user_root(original); Jac.disconnect(root, fixture);
        context.mem.delete(UUID(jid(fixture))); Jac.commit(); Jac.set_shared_root_resolver(None);
    }
}


test "planner month handles leap days and adjacent dates without invented highlights" {
    month = build_planner_month("2024-02-14", [], []);
    assert month.label == "February 2024" and len(month.days) == 42;
    assert month.previous == "2024-01-01" and month.following == "2024-03-01";
    assert month.days[0].day == "2024-01-29" and not month.days[0].in_month;
    assert len([day for day in month.days if day.in_month]) == 29;
    assert all(day.tasks == 0 and day.deadlines == 0 and day.commitments == 0 for day in month.days);
}

test "planner calendar separates scheduled work commitments and outstanding deadlines" {
    tasks = [TaskView(id="one", title="Study", day="2026-12-30", due_day="2027-01-02",
        duration=30, deadline=1200, priority=2, start=-1, done=False),
        TaskView(id="two", title="Completed", day="2026-12-30", due_day="2026-12-31",
        duration=30, deadline=1200, priority=2, start=600, done=True)];
    commitments = [CommitmentView(id="lab", title="Lab", day="2026-12-30", start=840, end=900, source="manual")];
    month = build_planner_month("2026-12-01", tasks, commitments);
    assert month.following == "2027-01-01";
    day = [item for item in month.days if item.day == "2026-12-30"][0];
    assert day.tasks == 2 and day.commitments == 1;
    assert [item for item in month.days if item.day == "2026-12-31"][0].deadlines == 0;
    assert [item for item in month.days if item.day == "2027-01-02"][0].deadlines == 1;
    assert tasks[0].start == -1 and not tasks[0].done;
}


def:protect secretary_run(query: str = "What should I do next?", day: str = "", use_model: bool = True) -> SecretaryRunView {
    if len(query.strip()) > 300 { raise ValueError("Use 300 characters or fewer."); }
    return coordinate_command(query, day, use_model);
}

def:protect secretary_runs() -> list[SecretaryRunView] {
    require_account();
    return [item.view() for item in [root -->][?:SecretaryRunRecord]][-10:];
}


def:protect secretary_settings -> SecretaryPreferences { return secretary_config().view(); }
def:protect secretary_notifications -> list[NotificationView] { return notifications(); }
def:protect secretary_notification(notification_id: str, action: str, minutes: int = 15) -> SecretaryAction {
    result = change_notification(notification_id, action, minutes);
    if result.ok { notify_secretary_clients(); }
    return result;
}
def:protect secretary_check_now -> SecretaryAction {
    secretary_tick();
    notify_secretary_clients();
    return SecretaryAction(ok=True, message="Checked your saved plan. Quiet hours still apply.");
}
def:protect secretary_preferences -> list[PreferenceView] { return preference_suggestions(); }
def:protect secretary_propose_focus(period: str) -> SecretaryAction { return propose_focus_period(period); }
def:protect secretary_decide_preference(suggestion_id: str, accept: bool) -> SecretaryAction { return decide_preference(suggestion_id, accept); }
def:protect secretary_forget_focus -> SecretaryAction {
    secretary_config().focus_period = "";
    return SecretaryAction(ok=True, message="Focus preference forgotten. Your saved plan was not moved.");
}

def:protect secretary_update_settings(enabled: bool, timezone_name: str, morning: int = 480,
    quiet_start: int = 1320, quiet_end: int = 480, lead: int = 15) -> SecretaryAction {
    import from zoneinfo { ZoneInfo }
    import from .secretary_runtime { ensure_secretary_job }
    require_account();
    morning = int(morning);
    quiet_start = int(quiet_start);
    quiet_end = int(quiet_end);
    lead = int(lead);
    try { ZoneInfo(timezone_name); }
    except Exception { return SecretaryAction(ok=False, message="Choose a valid IANA timezone, such as Africa/Nairobi."); }
    if min(morning, quiet_start, quiet_end) < 0 or max(morning, quiet_start, quiet_end) >= 1440 or lead not in [5, 15, 30, 60] {
        return SecretaryAction(ok=False, message="Check the briefing time, quiet hours and reminder lead.");
    }
    cfg = secretary_config();
    try { job_id = ensure_secretary_job(jid(root), enabled); }
    except Exception { return SecretaryAction(ok=False, message="The Jac background job could not be configured. Your settings were not enabled. Check the server scheduler and try again."); }
    cfg.enabled = enabled;
    cfg.timezone = timezone_name;
    cfg.morning = morning;
    cfg.quiet_start = quiet_start;
    cfg.quiet_end = quiet_end;
    cfg.lead = lead;
    cfg.job_id = job_id;
    secretary_tick();
    notify_secretary_clients();
    return SecretaryAction(ok=True, message="Secretary settings saved. The service must stay running for reminders.");
}

def notify_secretary_clients() -> None {
    import from .secretary_runtime { publish_account }
    owner = jid(root);
    on_commit(lambda -> None { publish_account(owner); });
}


def:protect secretary_live_ticket -> SecretaryLiveConnection {
    import from .secretary_runtime { live_ticket, live_api_port }
    require_account();
    return SecretaryLiveConnection(ticket=live_ticket(jid(root)), api_port=live_api_port());
}


test "account preferences do not change the plan version" {
    prefs = Settings(version=7, tour_completed=False, light_mode=False);
    prefs.tour_completed = True;
    prefs.light_mode = True;
    assert prefs.tour_completed and prefs.light_mode;
    assert prefs.version == 7;
}

test "connection status exposes credential presence flags" {
    status = ServerConnectionView(gemini_configured=False);
    assert isinstance(status.gemini_configured, bool);
}

test "activity retention parses offsets and legacy timestamps" {
    assert activity_timestamp("2026-10-16T11:00:00Z", "Africa/Nairobi") == activity_timestamp("2026-10-16T14:00:00+03:00", "Africa/Nairobi");
    assert activity_timestamp("2026-10-16T14:00:00", "Africa/Nairobi") == activity_timestamp("2026-10-16T11:00:00Z", "Africa/Nairobi");
    assert activity_timestamp("invalid", "Africa/Nairobi") is None;
}

test "activity retention limits history without touching plans or other owners" {
    import from jaclang { JacRuntime as Jac }
    import from jaclang.runtime.archetype { Root }
    import from uuid { UUID }
    original = jid(root);
    context = Jac.get_context();
    first = root ++> Root(); second = root ++> Root();
    Jac.save(first); Jac.save(second); Jac.commit();
    Jac.set_shared_root_resolver(lambda -> str { return original; });
    stamp = datetime.fromisoformat("2026-10-16T12:00:00+00:00").timestamp();
    cutoff = datetime.fromtimestamp(stamp - 90 * 86400, ZoneInfo("UTC"));
    try {
        context.set_user_root(jid(second));
        root ++> PlanningActivity(day="2020-01-01", title="Other owner", detail="Keep", created_at="2020-01-01T00:00:00Z");
        context.set_user_root(jid(first));
        root ++> Task(title="Keep task", day="2026-10-16", duration=30, deadline=1200);
        root ++> Revision(day="2026-10-16", version=1, title="Keep restore", before=[], commitment_id="");
        root ++> PlanningActivity(day="2099-01-01", title="Expired", detail="Old creation despite future plan date", created_at=(cutoff - timedelta(seconds=1)).isoformat());
        root ++> PlanningActivity(day="2020-01-01", title="Boundary", detail="Recent creation despite past plan date", created_at=cutoff.isoformat());
        root ++> PlanningActivity(day="2026-10-16", title="Legacy", detail="Unknown timestamp", created_at="invalid");
        history = recent_activities(stamp);
        assert len(history) == 2;
        assert len([root -->][?:PlanningActivity]) == 2;
        assert len(recent_activities(stamp)) == 2;
        for item in [root -->][?:PlanningActivity] { del item; }
        for index in range(1005) {
            root ++> PlanningActivity(day="2026-10-16", title=str(index), detail="Cap fixture", created_at=datetime.fromtimestamp(stamp - 2000 + index, ZoneInfo("UTC")).isoformat());
        }
        history = recent_activities(stamp);
        assert len([root -->][?:PlanningActivity]) == 1000;
        assert len(history) == 12;
        assert history[0].title == "1004" and history[11].title == "993";
        assert len(recent_activities(stamp)) == 12;
        assert len([root -->][?:Task]) == 1 and len([root -->][?:Revision]) == 1;
        record_activity("2026-10-16", "Newest", "A new change enforces the cap too");
        assert len([root -->][?:PlanningActivity]) <= 1000;
        context.set_user_root(jid(second));
        assert len([root -->][?:PlanningActivity]) == 1;
    } finally {
        for fixture in [first, second] {
            context.set_user_root(jid(fixture));
            for item in [root -->] { del item; }
        }
        context.set_user_root(original);
        Jac.disconnect(root, first); Jac.disconnect(root, second);
        context.mem.delete(UUID(jid(first))); context.mem.delete(UUID(jid(second)));
        Jac.commit(); Jac.set_shared_root_resolver(None);
    }
}

test "recovery preview approval isolation and restore preserve the saved plan" {
    import from jaclang { JacRuntime as Jac }
    import from jaclang.runtime.archetype { Root }
    import from uuid { UUID }
    original = jid(root);
    context = Jac.get_context();
    first = root ++> Root(); second = root ++> Root();
    Jac.save(first); Jac.save(second); Jac.commit();
    Jac.set_shared_root_resolver(lambda -> str { return original; });
    day = "2099-01-01";
    try {
        context.set_user_root(jid(first));
        prefs = root ++> Settings();
        task = root ++> Task(title="Prepare project brief", day=day,
                            duration=60, deadline=1200, start=480);
        blocked = root ++> Task(title="Long project", day=day,
                               duration=900, deadline=1200, start=-1);
        assert preview_recovery("Team meeting", day, 480, 540).ok;
        proposal = [p for p in [root -->][?:Proposal] if p.active][0];
        assert task.start == 480 and blocked.start == -1;
        assert len([root -->][?:Commitment]) == 0 and prefs.version == 0;
        assert validate(proposal.minimal.slots, work_for(day),
                        [Busy(title="Team meeting", start=480, end=540)], 480, prefs.day_end);
        assert validate(proposal.deadline.slots, work_for(day),
                        [Busy(title="Team meeting", start=480, end=540)], 480, prefs.day_end);
        assert jid(blocked) in proposal.minimal.unplaced;
        context.set_user_root(jid(second));
        assert not accept_recovery(jid(proposal), "minimal").ok;
        assert not dismiss_recovery(jid(proposal)).ok;
        assert len([root -->][?:Commitment]) == 0;
        context.set_user_root(jid(first));
        assert not accept_recovery(jid(proposal), "unknown").ok;
        assert proposal.active and task.start == 480;
        assert dismiss_recovery(jid(proposal)).ok;
        assert not accept_recovery(jid(proposal), "minimal").ok;
        assert task.start == 480 and prefs.version == 0;
        assert preview_recovery("Team meeting", day, 480, 540).ok;
        proposal = [p for p in [root -->][?:Proposal] if p.active][0];
        assert accept_recovery(jid(proposal), "deadline").ok;
        assert task.start >= 540 and blocked.start == -1;
        assert len([root -->][?:Commitment]) == 1;
        assert not accept_recovery(jid(proposal), "deadline").ok;
        revision = [root -->][?:Revision][0];
        context.set_user_root(jid(second));
        assert not restore_revision(jid(revision)).ok;
        context.set_user_root(jid(first));
        assert restore_revision(jid(revision)).ok;
        assert task.start == 480 and blocked.start == -1;
        assert revision.restored and len([root -->][?:Commitment]) == 0;
        assert not restore_revision(jid(revision)).ok;
        assert preview_recovery("Outdated meeting", day, 480, 540).ok;
        proposal = [p for p in [root -->][?:Proposal] if p.active][0];
        prefs.version += 1;
        assert not accept_recovery(jid(proposal), "minimal").ok;
        assert task.start == 480 and len([root -->][?:Commitment]) == 0;
        assert preview_recovery("Fresh meeting", day, 480, 540).ok;
        proposal = [p for p in [root -->][?:Proposal] if p.active][0];
        assert accept_recovery(jid(proposal), "minimal").ok;
        revision = [r for r in [root -->][?:Revision] if not r.restored][0];
        prefs.version += 1;
        assert not restore_revision(jid(revision)).ok;
        assert not revision.restored and len([root -->][?:Commitment]) == 1;
    } finally {
        for fixture in [first, second] {
            context.set_user_root(jid(fixture));
            for item in [root -->] { del item; }
        }
        context.set_user_root(original);
        Jac.disconnect(root, first); Jac.disconnect(root, second);
        context.mem.delete(UUID(jid(first))); context.mem.delete(UUID(jid(second)));
        Jac.commit(); Jac.set_shared_root_resolver(None);
    }
}

test "restore rejects a now infeasible schedule before deleting its commitment" {
    import from jaclang { JacRuntime as Jac }
    import from jaclang.runtime.archetype { Root }
    import from uuid { UUID }
    original = jid(root);
    context = Jac.get_context();
    owner = root ++> Root();
    Jac.save(owner); Jac.commit();
    Jac.set_shared_root_resolver(lambda -> str { return original; });
    try {
        context.set_user_root(jid(owner));
        prefs = root ++> Settings();
        task = root ++> Task(title="Project brief", day="2099-01-01", duration=60,
                            deadline=1200, start=540);
        commitment = root ++> Commitment(title="Team meeting", day="2099-01-01", start=480, end=540);
        revision = root ++> Revision(day="2099-01-01", version=prefs.version,
            title="Team meeting", before=[Slot(task_id=jid(task), start=450, end=510)],
            commitment_id=jid(commitment));
        assert not restore_revision(jid(revision)).ok;
        assert task.start == 540 and not revision.restored and prefs.version == 0;
        assert len([root -->][?:Commitment]) == 1;
    } finally {
        context.set_user_root(jid(owner));
        for item in [root -->] { del item; }
        context.set_user_root(original);
        Jac.disconnect(root, owner); context.mem.delete(UUID(jid(owner)));
        Jac.commit(); Jac.set_shared_root_resolver(None);
    }
}
