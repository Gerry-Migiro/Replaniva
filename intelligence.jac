"""Deterministic plan health, briefing, and next-action intelligence."""

import from planning { Work, Busy, make_choice }

obj NextAction {
    has kind: str, title: str, start: int = -1, end: int = -1,
        task_id: str = "", reason: str = "";
}

obj PlanHealth {
    has status: str, label: str, required_minutes: int,
        available_minutes: int, slack_minutes: int, pressure_percent: int,
        unplaced_tasks: int, overdue_tasks: int, urgent_tasks: int,
        deadline_risks: int, reasons: list[str] = [];
}

obj RiskSignal {
    has code: str, severity: str, title: str, detail: str,
        action_label: str, action_target: str, task_id: str = "";
}

obj DailyBriefing {
    has headline: str, summary: str, remaining_tasks: int,
        completed_tasks: int, fixed_commitments: int,
        health: PlanHealth, next_action: NextAction,
        risks: list[RiskSignal] = [];
}

obj DayOutlook {
    has day: str, status: str, label: str, required_minutes: int,
        available_minutes: int, slack_minutes: int, overloaded_minutes: int,
        fixed_minutes: int, unplaced_tasks: int, deadline_risks: int,
        high_priority_tasks: int;
}

obj RebalanceCandidate {
    has available: bool = False, from_day: str = "", to_day: str = "",
        task_id: str = "", task_title: str = "", duration: int = 0,
        suggested_start: int = -1, reason: str = "";
}

def duration_label(minutes: int) -> str {
    safe = max(0, minutes);
    hours = safe // 60;
    remainder = safe % 60;
    if hours > 0 and remainder > 0 { return str(hours) + "h " + str(remainder) + "m"; }
    if hours > 0 { return str(hours) + "h"; }
    return str(remainder) + "m";
}

def clock_label(minutes: int) -> str {
    if minutes < 0 { return "unscheduled"; }
    hour = str(minutes // 60);
    minute = str(minutes % 60);
    if minutes // 60 < 10 { hour = "0" + hour; }
    if minutes % 60 < 10 { minute = "0" + minute; }
    return hour + ":" + minute;
}

def free_minutes(start: int, end: int, busy: list[Busy]) -> int {
    if end <= start { return 0; }
    ordered = [item for item in busy];
    ordered.sort(key=lambda (item: Busy) { (item.start, item.end); });
    cursor = start;
    free = 0;
    for item in ordered {
        blocked_start = max(start, item.start);
        blocked_end = min(end, item.end);
        if blocked_end <= cursor or blocked_end <= blocked_start { continue; }
        if blocked_start > cursor { free += blocked_start - cursor; }
        cursor = max(cursor, blocked_end);
        if cursor >= end { break; }
    }
    if cursor < end { free += end - cursor; }
    return max(0, free);
}

def deadline_risk_count(work: list[Work], busy: list[Busy],
                        anchor: int, day_end: int) -> int {
    return len(deadline_risk_ids(work, busy, anchor, day_end));
}

def deadline_risk_ids(work: list[Work], busy: list[Busy],
                      anchor: int, day_end: int) -> list[str] {
    ordered = [item for item in work];
    ordered.sort(key=lambda (item: Work) { (item.deadline, -item.priority); });
    required = 0;
    risks: list[str] = [];
    for item in ordered {
        required += item.duration;
        capacity = free_minutes(anchor, min(item.deadline, day_end), busy);
        if required > capacity { risks.append(item.id); }
    }
    return risks;
}

def build_risk_signals(work: list[Work], busy: list[Busy], anchor: int,
                       day_end: int, required: int, available: int,
                       slack: int) -> list[RiskSignal] {
    risks: list[RiskSignal] = [];
    if required > available {
        risks.append(RiskSignal(code="capacity", severity="critical",
            title="The day is over capacity",
            detail=duration_label(required) + " of work remains with only " + duration_label(available) + " available.",
            action_label="Explore recovery", action_target="recovery"));
    }
    deadline_ids = deadline_risk_ids(work, busy, anchor, day_end);
    for item in work {
        if len(risks) >= 4 { break; }
        if item.deadline < anchor {
            risks.append(RiskSignal(code="overdue", severity="critical",
                title=item.title + " is overdue",
                detail="Its deadline passed at " + clock_label(item.deadline) + " and it is still unfinished.",
                action_label="Review the day", action_target="today", task_id=item.id));
        } elif item.id in deadline_ids {
            risks.append(RiskSignal(code="deadline", severity="high",
                title=item.title + " may miss its deadline",
                detail="The remaining work cannot all fit before " + clock_label(item.deadline) + ".",
                action_label="Explore recovery", action_target="recovery", task_id=item.id));
        } elif [p for p in work if p.id in item.depends_on and p.start < 0] {
            blocked_by = [p for p in work if p.id in item.depends_on and p.start < 0][0];
            risks.append(RiskSignal(code="dependency", severity="high",
                title=item.title + " is blocked",
                detail="It is blocked by its prerequisite " + blocked_by.title + ".",
                action_label="Resolve blocker", action_target="capture", task_id=item.id));
        } elif item.start < 0 {
            risks.append(RiskSignal(code="unplaced", severity="high",
                title=item.title + " has no valid time",
                detail="Replaniva could not place it inside the current boundaries before its deadline.",
                action_label="Adjust the plan", action_target="capture", task_id=item.id));
        }
    }
    if len(risks) == 0 and required > 0 and slack <= 60 {
        risks.append(RiskSignal(code="tight", severity="medium",
            title="Very little slack remains",
            detail="Only " + duration_label(max(0, slack)) + " remains for delays or unexpected work.",
            action_label="Protect this plan", action_target="today"));
    }
    return risks;
}

def choose_next_action(work: list[Work], busy: list[Busy], current_minute: int) -> NextAction {
    active_fixed = [item for item in busy if item.start <= current_minute and current_minute < item.end];
    if active_fixed {
        active_fixed.sort(key=lambda (item: Busy) { item.end; });
        fixed_item: Busy = active_fixed[0];
        return NextAction(kind="commitment", title=fixed_item.title, start=fixed_item.start, end=fixed_item.end,
                          reason="This fixed commitment is happening now.");
    }
    active_work = [item for item in work if item.start >= 0 and
                   item.start <= current_minute and current_minute < item.start + item.duration];
    if active_work {
        active_work.sort(key=lambda (item: Work) { (item.deadline, -item.priority); });
        active_item: Work = active_work[0];
        return NextAction(kind="task", title=active_item.title, start=active_item.start,
                          end=active_item.start + active_item.duration, task_id=active_item.id,
                          reason="This is the current scheduled focus block.");
    }
    upcoming = [item for item in work if item.start >= current_minute];
    if upcoming {
        upcoming.sort(key=lambda (item: Work) { (item.start, item.deadline, -item.priority); });
        upcoming_item: Work = upcoming[0];
        due_label = "due on " + upcoming_item.due_day + " at " + clock_label(upcoming_item.due_time)
            if upcoming_item.due_day and upcoming_item.due_time >= 0 else
            "due by " + clock_label(upcoming_item.deadline);
        return NextAction(kind="task", title=upcoming_item.title, start=upcoming_item.start,
                          end=upcoming_item.start + upcoming_item.duration, task_id=upcoming_item.id,
                          reason="This is the next scheduled task and is " + due_label + ".");
    }
    pending = [item for item in work];
    if pending {
        pending.sort(key=lambda (item: Work) { (item.deadline, -item.priority); });
        pending_item: Work = pending[0];
        return NextAction(kind="task", title=pending_item.title, start=pending_item.start,
                          end=pending_item.start + pending_item.duration if pending_item.start >= 0 else -1,
                          task_id=pending_item.id,
                          reason="This has the earliest remaining deadline and still needs attention.");
    }
    upcoming_fixed = [item for item in busy if item.start >= current_minute];
    if upcoming_fixed {
        upcoming_fixed.sort(key=lambda (item: Busy) { item.start; });
        upcoming_fixed_item: Busy = upcoming_fixed[0];
        return NextAction(kind="commitment", title="Prepare for " + upcoming_fixed_item.title,
                          start=upcoming_fixed_item.start, end=upcoming_fixed_item.end,
                          reason="This is the next fixed commitment in the plan.");
    }
    return NextAction(kind="clear", title="Use the open space intentionally",
                      reason="No unfinished work or upcoming commitment needs attention.");
}

def build_briefing(work: list[Work], busy: list[Busy], completed_tasks: int,
                   day_start: int, day_end: int, current_minute: int) -> DailyBriefing {
    anchor = max(day_start, min(current_minute, day_end));
    required = 0;
    unplaced = 0;
    overdue = 0;
    urgent = 0;
    for item in work {
        required += item.duration;
        if item.start < 0 { unplaced += 1; }
        if item.deadline < current_minute { overdue += 1; }
        if item.deadline >= current_minute and item.deadline - current_minute <= 120 { urgent += 1; }
    }
    available = free_minutes(anchor, day_end, busy);
    slack = available - required;
    deadline_risks = deadline_risk_count(work, busy, anchor, day_end);
    # Pressure is a bounded gauge, not a ratio with a fabricated denominator.
    # The exact shortfall remains available in slack_minutes and the reasons.
    pressure = 0;
    if required > 0 {
        pressure = 100 if available == 0 else min(100, required * 100 // available);
    }
    reasons: list[str] = [];
    status = "HEALTHY";
    label = "Healthy";
    if required > available {
        status = "OVERLOADED";
        label = "Overloaded";
        reasons.append(duration_label(required) + " of work remains with " + duration_label(available) + " available.");
    } elif overdue > 0 or unplaced > 0 or deadline_risks > 0 {
        status = "AT_RISK";
        label = "At risk";
    } elif required > 0 and (slack <= 60 or urgent > 0) {
        status = "TIGHT";
        label = "Tight";
    }
    if overdue > 0 { reasons.append(str(overdue) + " unfinished task" + (" is" if overdue == 1 else "s are") + " overdue."); }
    if unplaced > 0 { reasons.append(str(unplaced) + " task" + (" has" if unplaced == 1 else "s have") + " no valid time yet."); }
    if deadline_risks > 0 { reasons.append(str(deadline_risks) + " task" + (" has" if deadline_risks == 1 else "s have") + " insufficient time before its deadline."); }
    if len(reasons) == 0 and required > 0 and slack <= 60 {
        reasons.append("Only " + duration_label(max(0, slack)) + " of flexible slack remains.");
    }
    if len(reasons) == 0 {
        reasons.append("The remaining work fits inside the available planning time.");
    }
    headline = "This day has breathing room.";
    if status == "TIGHT" { headline = "This day is tight but workable."; }
    if status == "AT_RISK" { headline = "This day needs attention."; }
    if status == "OVERLOADED" { headline = "This day is overloaded."; }
    summary = "No flexible tasks remain. " + duration_label(available) + " is still open.";
    if len(work) > 0 {
        summary = str(len(work)) + " task" + (" remains. " if len(work) == 1 else "s remain. ") +
                  duration_label(available) + " is available for " + duration_label(required) + " of work.";
    }
    health = PlanHealth(status=status, label=label, required_minutes=required,
                        available_minutes=available, slack_minutes=slack,
                        pressure_percent=pressure, unplaced_tasks=unplaced,
                        overdue_tasks=overdue, urgent_tasks=urgent,
                        deadline_risks=deadline_risks, reasons=reasons);
    return DailyBriefing(headline=headline, summary=summary,
                         remaining_tasks=len(work), completed_tasks=completed_tasks,
                         fixed_commitments=len(busy), health=health,
                         next_action=choose_next_action(work, busy, current_minute),
                         risks=build_risk_signals(work, busy, anchor, day_end,
                                                  required, available, slack));
}

def build_outlook(day: str, work: list[Work], busy: list[Busy],
                  day_start: int, day_end: int) -> DayOutlook {
    briefing = build_briefing(work, busy, 0, day_start, day_end, day_start);
    fixed = 0;
    high_priority = 0;
    for item in busy { fixed += max(0, min(day_end, item.end) - max(day_start, item.start)); }
    for item in work { if item.priority >= 3 { high_priority += 1; } }
    return DayOutlook(day=day, status=briefing.health.status,
        label=briefing.health.label, required_minutes=briefing.health.required_minutes,
        available_minutes=briefing.health.available_minutes,
        slack_minutes=briefing.health.slack_minutes,
        overloaded_minutes=max(0, -briefing.health.slack_minutes),
        fixed_minutes=fixed, unplaced_tasks=briefing.health.unplaced_tasks,
        deadline_risks=briefing.health.deadline_risks,
        high_priority_tasks=high_priority);
}

def suggest_rebalance(from_day: str, to_day: str,
                      source_work: list[Work], target_work: list[Work],
                      target_busy: list[Busy], day_start: int,
                      day_end: int) -> RebalanceCandidate {
    target = build_outlook(to_day, target_work, target_busy, day_start, day_end);
    if target.slack_minutes < 15 or not source_work {
        return RebalanceCandidate();
    }
    prerequisite_ids: list[str] = [];
    for item in source_work {
        for dependency_id in item.depends_on {
            if dependency_id not in prerequisite_ids { prerequisite_ids.append(dependency_id); }
        }
    }
    candidates = [item for item in source_work
                  if not item.depends_on and item.id not in prerequisite_ids];
    candidates.sort(key=lambda (item: Work) { (item.priority, -item.duration, item.deadline); });
    for source in candidates {
        if source.duration > target.slack_minutes { continue; }
        moving = Work(id=source.id, title=source.title, duration=source.duration,
                      deadline=source.deadline, priority=source.priority, start=-1);
        combined = [item for item in target_work];
        combined.append(moving);
        choice = make_choice("minimal", combined, target_busy, day_start, day_end);
        matches = [slot for slot in choice.slots if slot.task_id == source.id];
        if matches and source.id not in choice.unplaced {
            slot = matches[0];
            return RebalanceCandidate(available=True, from_day=from_day,
                to_day=to_day, task_id=source.id, task_title=source.title,
                duration=source.duration, suggested_start=slot.start,
                reason="Moving this flexible task to a nearby day uses spare capacity and reduces pressure on " + from_day + ".");
        }
    }
    return RebalanceCandidate();
}

test "healthy plan reports measurable slack" {
    work = [Work(id="read", title="Read", duration=60, deadline=1020, start=600)];
    briefing = build_briefing(work, [Busy(title="Class", start=540, end=600)], 1, 480, 1080, 480);
    assert briefing.health.status == "HEALTHY";
    assert briefing.health.available_minutes == 540;
    assert briefing.health.slack_minutes == 480;
    assert briefing.next_action.title == "Read";
}

test "capacity overflow is overloaded" {
    work = [Work(id="a", title="A", duration=180, deadline=720),
            Work(id="b", title="B", duration=180, deadline=720)];
    briefing = build_briefing(work, [Busy(title="Lab", start=540, end=660)], 0, 480, 720, 480);
    assert briefing.health.status == "OVERLOADED";
    assert briefing.health.required_minutes == 360;
    assert briefing.health.available_minutes == 120;
}

test "deadline feasibility produces a visible risk" {
    work = [Work(id="report", title="Report", duration=120, deadline=600, start=-1)];
    briefing = build_briefing(work, [Busy(title="Class", start=480, end=540)], 0, 480, 900, 480);
    assert briefing.health.status == "AT_RISK";
    assert briefing.health.deadline_risks == 1;
    assert briefing.health.unplaced_tasks == 1;
}

test "active fixed commitment becomes next action" {
    briefing = build_briefing([], [Busy(title="Laboratory", start=600, end=720)], 2, 480, 1080, 660);
    assert briefing.next_action.kind == "commitment";
    assert briefing.next_action.title == "Laboratory";
}

test "overload creates a concise proactive warning" {
    work = [Work(id="exam", title="Exam revision", duration=240, deadline=720)];
    briefing = build_briefing(work, [Busy(title="Lab", start=540, end=660)], 0, 480, 720, 480);
    assert len(briefing.risks) >= 1;
    assert briefing.risks[0].code == "capacity";
    assert briefing.risks[0].action_target == "recovery";
}

test "tight plan warns before it becomes impossible" {
    work = [Work(id="read", title="Read", duration=180, deadline=720, start=480)];
    briefing = build_briefing(work, [], 0, 480, 720, 480);
    assert briefing.health.status == "TIGHT";
    assert len(briefing.risks) == 1;
    assert briefing.risks[0].code == "tight";
}

test "day outlook reports exact overload" {
    work = [Work(id="a", title="A", duration=300, deadline=720)];
    outlook = build_outlook("2026-09-24", work,
                            [Busy(title="Lab", start=540, end=660)], 480, 720);
    assert outlook.status == "OVERLOADED";
    assert outlook.overloaded_minutes == 180;
    assert outlook.fixed_minutes == 120;
}

test "rebalance uses validated spare capacity without changing inputs" {
    source = [Work(id="signals", title="Signals revision", duration=60,
                   deadline=1200, priority=2, start=1080)];
    target = [Work(id="reading", title="Reading", duration=60,
                   deadline=1200, start=600)];
    candidate = suggest_rebalance("2026-09-24", "2026-09-23", source, target,
                                  [Busy(title="Class", start=480, end=540)], 480, 1200);
    assert candidate.available;
    assert candidate.task_id == "signals";
    assert candidate.suggested_start >= 480;
    assert source[0].start == 1080;
    assert len(target) == 1;
}

test "rebalance candidate handles task migration" {
    source = [Work(id="signals", title="Signals revision", duration=60,
                   deadline=1200, priority=2, start=1080)];
    target = [Work(id="reading", title="Reading", duration=60,
                   deadline=1200, start=600)];
    target_busy = [Busy(title="Class", start=480, end=540)];
    candidate = suggest_rebalance("2026-09-24", "2026-09-23", source, target,
                                  target_busy, 480, 1200);
    assert candidate.available;
    assert candidate.task_id == "signals";
    assert candidate.from_day == "2026-09-24";
    assert candidate.to_day == "2026-09-23";

    updated_source = [w for w in source if w.id != candidate.task_id];
    updated_target = [w for w in target];
    updated_target.append(Work(id=candidate.task_id, title=candidate.task_title,
                               duration=candidate.duration, deadline=1200, priority=2));
    target_choice = make_choice("minimal", updated_target, target_busy, 480, 1200);

    assert len(updated_source) == 0;
    assert len(target_choice.unplaced) == 0;
    placed_ids = [slot.task_id for slot in target_choice.slots];
    assert candidate.task_id in placed_ids;
}

test "dependency failure creates a visible risk" {
    work = [Work(id="a", title="A", duration=60, deadline=1200, start=-1),
            Work(id="b", title="B", duration=60, deadline=1200, start=-1, depends_on=["a"])];
    risks = build_risk_signals(work, [], 480, 1320, 120, 840, 720);
    dep_risks = [r for r in risks if r.code == "dependency"];
    assert len(dep_risks) == 1;
    assert dep_risks[0].severity == "high";
    assert dep_risks[0].task_id == "b";
}

test "next action names the saved due date instead of the scheduling cutoff" {
    work = [Work(id="paper", title="Paper", duration=30, deadline=1440,
                 start=600, due_day="2026-10-12", due_time=1200)];
    next = choose_next_action(work, [], 540);
    assert "2026-10-12 at 20:00" in next.reason;
    assert "24:00" not in next.reason;
}


test "unfinished work after planning hours has full pressure without fabricated percentage" {
    briefing = build_briefing([Work(id="late", title="Study", duration=30, deadline=1320)], [], 0, 480, 1080, 1200);
    assert briefing.health.available_minutes == 0;
    assert briefing.health.required_minutes == 30;
    assert briefing.health.slack_minutes == -30;
    assert briefing.health.pressure_percent == 100;
    assert briefing.health.status == "OVERLOADED";
}

test "fully blocked day has full pressure with unfinished work" {
    briefing = build_briefing([Work(id="work", title="Work", duration=30, deadline=720)],
        [Busy(title="Commitment", start=480, end=720)], 0, 480, 720, 480);
    assert briefing.health.available_minutes == 0;
    assert briefing.health.pressure_percent == 100;
    assert briefing.health.slack_minutes == -30;
}

test "empty closed day has no pressure" {
    briefing = build_briefing([], [], 1, 480, 1080, 1200);
    assert briefing.health.available_minutes == 0;
    assert briefing.health.slack_minutes == 0;
    assert briefing.health.pressure_percent == 0;
    assert briefing.health.status == "HEALTHY";
}

test "pressure gauge preserves ordinary load and bounds overload" {
    work = [Work(id="work", title="Work", duration=30, deadline=720)];
    assert build_briefing(work, [], 0, 480, 540, 480).health.pressure_percent == 50;
    assert build_briefing(work, [], 0, 480, 510, 480).health.pressure_percent == 100;
    overloaded = build_briefing(work, [], 0, 480, 490, 480);
    assert overloaded.health.pressure_percent == 100;
    assert overloaded.health.slack_minutes == -20;
}
