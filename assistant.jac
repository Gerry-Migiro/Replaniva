import from .account_clock { local_clock }
import from intelligence { DailyBriefing, NextAction, PlanHealth, duration_label, clock_label }
import from planning { Work, Busy, make_choice, Choice, Slot }
obj SubtaskDraft {
    has title: str, duration: int = 30;
}

def generate_subtasks(title: str, total_duration: int) -> list[SubtaskDraft] {
    t_lower = title.lower();
    titles: list[str] = [];
    if "presentation" in t_lower or "talk" in t_lower or "slides" in t_lower {
        titles = ["Create outline", "Prepare slides", "Prepare demo", "Rehearse"];
    } elif "paper" in t_lower or "essay" in t_lower or "report" in t_lower or "write" in t_lower {
        titles = ["Research sources", "Structure outline", "Draft content", "Edit and proofread"];
    } elif "exam" in t_lower or "quiz" in t_lower or "test" in t_lower or "study" in t_lower {
        titles = ["Review lecture notes", "Practice exercises", "Formula sheet", "Timed mock test"];
    } elif "project" in t_lower or "code" in t_lower or "build" in t_lower or "dev" in t_lower {
        titles = ["Architecture design", "Core implementation", "Testing and debugging", "Documentation"];
    } else {
        titles = [title + " - Part 1", title + " - Part 2", title + " - Review"];
    }
    n = len(titles);
    num_blocks = max(n, int(round(total_duration / 15.0)));
    base_blocks = num_blocks // n;
    extra_blocks = num_blocks % n;
    subtasks: list[SubtaskDraft] = [];
    for i in range(n) {
        blocks = base_blocks + (1 if i < extra_blocks else 0);
        dur = max(15, blocks * 15);
        subtasks.append(SubtaskDraft(title=titles[i], duration=dur));
    }
    return subtasks;
}
import re;
import from datetime { date, timedelta }

obj CommandProposal {
    has kind: str,
        title: str,
        day: str,
        details: str,
        id: str = "",
        base_version: int = 0,
        active: bool = True,
        task_title: str = "",
        task_duration: int = 0,
        task_deadline: int = 0,
        commitment_start: int = -1,
        commitment_end: int = -1,
        commitment_title: str = "",
        affected_tasks: list[str] = [],
        unplaced_count: int = 0,
        slack_change: int = 0,
        action_type: str = "",
        target_task_id: str = "",
        target_day: str = "",
        proposed_duration: int = 0;
}

obj CommandReply {
    has ok: bool, kind: str, title: str, message: str,
        action_label: str = "", action_target: str = "",
        proposal: CommandProposal | None = None;
}

def simulate_what_if_event(title: str, start: int, end: int, work: list[Work], busy: list[Busy], day_start: int, day_end: int) -> CommandProposal {
    original_choice = make_choice("minimal", work, busy, day_start, day_end);
    new_busy = [b for b in busy];
    new_busy.append(Busy(title=title, start=start, end=end));
    new_choice = make_choice("minimal", work, new_busy, day_start, day_end);

    affected_tasks: list[str] = [];
    for new_slot in new_choice.slots {
        original_slots = [s for s in original_choice.slots if s.task_id == new_slot.task_id];
        if not original_slots or original_slots[0].start != new_slot.start {
            matching_work = [w for w in work if w.id == new_slot.task_id];
            if matching_work and matching_work[0].title not in affected_tasks {
                affected_tasks.append(matching_work[0].title);
            }
        }
    }
    for unplaced_id in new_choice.unplaced {
        if unplaced_id not in original_choice.unplaced {
            matching_work = [w for w in work if w.id == unplaced_id];
            if matching_work and matching_work[0].title not in affected_tasks {
                affected_tasks.append(matching_work[0].title);
            }
        }
    }

    slack_change = -(end - start);
    unplaced_count = len(new_choice.unplaced) - len(original_choice.unplaced);

    return CommandProposal(
        kind="what_if",
        title="What if: " + title,
        day="",
        details="Simulation results for " + title,
        commitment_start=start,
        commitment_end=end,
        commitment_title=title,
        affected_tasks=affected_tasks,
        unplaced_count=unplaced_count,
        slack_change=slack_change,
        action_type="what_if"
    );
}

def extract_duration(query: str) -> int {
    normalized = query.lower();
    m = re.search(r"(\d+)\s*(hour|min|hr|minutes|minute|hours)", normalized);
    if m {
        val = int(m.group(1));
        unit = m.group(2);
        if "hour" in unit or "hr" in unit { return val * 60; }
        return val;
    }
    number_words = {"one": 1, "two": 2, "three": 3, "four": 4,
                    "five": 5, "six": 6, "seven": 7, "eight": 8};
    for word in number_words {
        if re.search(r"\b" + word + r"\s+(hour|hours|hr)\b", normalized) {
            return number_words[word] * 60;
        }
    }
    return 60;
}

def extract_time_range(query: str) -> list[int] {
    matches = re.findall(r"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", query.lower());
    if len(matches) < 2 { return [-1, -1]; }

    def parse_t(parts: tuple[str, str, str]) -> int {
        hour = int(parts[0]);
        minute = int(parts[1]) if parts[1] else 0;
        meridiem = parts[2];
        if minute > 59 or hour > 23 { return -1; }
        if meridiem {
            if hour < 1 or hour > 12 { return -1; }
            hour = hour % 12;
            if meridiem == "pm" { hour += 12; }
        } elif hour <= 7 {
            hour += 12;
        }
        return hour * 60 + minute;
    }

    return [parse_t(matches[0]), parse_t(matches[1])];
}

def extract_single_time(query: str) -> int {
    found = re.findall(r"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", query.lower());
    if not found { return -1; }
    parts = found[0];
    hour = int(parts[0]);
    minute = int(parts[1]) if parts[1] else 0;
    meridiem = parts[2];
    if minute > 59 or hour > 23 { return -1; }
    if meridiem {
        if hour < 1 or hour > 12 { return -1; }
        hour = hour % 12;
        if meridiem == "pm" { hour += 12; }
    } elif hour <= 7 { hour += 12; }
    return hour * 60 + minute;
}

def infer_commitment_title(query: str, fallback: str = "New commitment") -> str {
    normalized = query.lower();
    if "lab" in normalized { return "Lab"; }
    if "meeting" in normalized { return "Meeting"; }
    if "appointment" in normalized { return "Appointment"; }
    if "class" in normalized or "lecture" in normalized { return "Class"; }
    return fallback;
}

def resolve_command_day(query: str, requested_day: str = "", today: str = "") -> str {
    base = date.fromisoformat(today if today else local_clock().day);
    normalized = query.lower();
    if "tomorrow" in normalized { return (base + timedelta(days=1)).isoformat(); }
    if "today" in normalized { return base.isoformat(); }
    weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
    for index in range(len(weekdays)) {
        if weekdays[index] in normalized {
            offset = (index - base.weekday()) % 7;
            if offset == 0 { offset = 7; }
            if "before " + weekdays[index] in normalized { offset -= 1; }
            return (base + timedelta(days=offset)).isoformat();
        }
    }
    return requested_day if requested_day else base.isoformat();
}

def matching_task(query: str, work: list[Work]) -> Work | None {
    normalized = query.lower();
    matches = [item for item in work if item.title.lower() in normalized];
    if len(matches) == 1 { return matches[0]; }
    words = [word for word in re.findall(r"[a-z0-9]+", normalized)
             if len(word) > 3 and word not in ["what", "assignment", "task", "takes", "hours", "hour", "minutes", "minute", "move", "this", "tomorrow", "today"]];
    best: Work | None = None;
    best_score = 0;
    tied = False;
    for item in work {
        score = len([word for word in words if word in item.title.lower()]);
        if score > best_score {
            best = item;
            best_score = score;
            tied = False;
        } elif score > 0 and score == best_score {
            tied = True;
        }
    }
    return None if tied else best;
}

def simulate_duration_change(task: Work, duration: int, work: list[Work], busy: list[Busy],
                             day_start: int, day_end: int, day: str, version: int) -> CommandProposal {
    preview_work: list[Work] = [];
    for item in work {
        preview_work.append(Work(
            id=item.id, title=item.title,
            duration=duration if item.id == task.id else item.duration,
            deadline=item.deadline, priority=item.priority,
            start=item.start, depends_on=item.depends_on
        ));
    }
    choice = make_choice("minimal", preview_work, busy, day_start, day_end);
    affected = [task.title];
    return CommandProposal(
        kind="what_if", title="What if " + task.title + " takes " + duration_label(duration),
        day=day, details="The saved task stays unchanged until you accept. " +
            (str(len(choice.unplaced)) + " task(s) would need space." if choice.unplaced else "The revised duration still fits."),
        base_version=version, affected_tasks=affected,
        unplaced_count=len(choice.unplaced), slack_change=task.duration - duration,
        action_type="change_duration", target_task_id=task.id,
        proposed_duration=duration
    );
}

def simulate_availability(title: str, start: int, end: int, work: list[Work], busy: list[Busy],
                          day_start: int, day_end: int, day: str, version: int) -> CommandProposal {
    proposal = simulate_what_if_event(title, start, end, work, busy, day_start, day_end);
    proposal.day = day;
    proposal.base_version = version;
    proposal.kind = "change_availability";
    proposal.title = title;
    proposal.details = "This time becomes unavailable only after approval. " +
        str(len(proposal.affected_tasks)) + " task(s) would move and " +
        str(max(0, proposal.unplaced_count)) + " would become unplaced.";
    proposal.action_type = "change_availability";
    return proposal;
}

obj CommandContext {
    has clean: str, normalized: str, briefing: DailyBriefing, work: list[Work], busy: list[Busy], day_start: int, day_end: int, version: int, day: str;
}

def duration_command(context: CommandContext) -> CommandReply | None {
    clean = context.clean;
    normalized = context.normalized;
    work = context.work;
    busy = context.busy;
    day_start = context.day_start;
    day_end = context.day_end;
    version = context.version;
    day = context.day;
    if "what if" in normalized and ("takes" in normalized or "lasts" in normalized) {
        target = matching_task(clean, work);
        duration = extract_duration(normalized);
        if target is None {
            return CommandReply(ok=False, kind="help", title="Name the task to simulate",
                message="Include the task name so Replaniva can test a different duration without changing it.");
        }
        proposal = simulate_duration_change(target, duration, work, busy, day_start, day_end, day, version);
        return CommandReply(ok=True, kind="proposal", title="Duration Simulation",
            message="Review how the longer or shorter task changes the day.", proposal=proposal);
    }
    return None;
}

def move_command(context: CommandContext) -> CommandReply | None {
    clean = context.clean;
    normalized = context.normalized;
    work = context.work;
    version = context.version;
    day = context.day;
    if "move " in normalized and ("tomorrow" in normalized or
       [name for name in ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"] if name in normalized]) {
        target = matching_task(clean, work);
        if target is None {
            return CommandReply(ok=False, kind="help", title="Name the task to move",
                message="Include one saved task name so Replaniva can prepare a safe move.");
        }
        proposal = CommandProposal(
            kind="move_task", title="Move " + target.title,
            day=day, target_day=resolve_command_day(clean, day, day),
            details="The task stays on its current day until the move is validated and approved.",
            base_version=version, action_type="move_task",
            target_task_id=target.id, affected_tasks=[target.title]
        );
        return CommandReply(ok=True, kind="proposal", title="Task Move Proposal",
            message="Review the proposed destination before applying.", proposal=proposal);
    }
    return None;
}

def later_start_command(context: CommandContext) -> CommandReply | None {
    normalized = context.normalized;
    work = context.work;
    busy = context.busy;
    day_start = context.day_start;
    day_end = context.day_end;
    version = context.version;
    day = context.day;
    if "start my day at" in normalized {
        start = extract_single_time(normalized.split("start my day at", 1)[1]);
        if start >= day_start and start < day_end {
            proposal = simulate_availability("Later start", day_start, start, work, busy,
                day_start, day_end, day, version);
            return CommandReply(ok=True, kind="proposal", title="Availability Simulation",
                message="Review what changes when the day starts later.", proposal=proposal);
        }
    }
    return None;
}

def availability_command(context: CommandContext) -> CommandReply | None {
    normalized = context.normalized;
    work = context.work;
    busy = context.busy;
    day_start = context.day_start;
    day_end = context.day_end;
    version = context.version;
    day = context.day;
    if ("lost" in normalized or "take" in normalized or "off" in normalized or
        "lighter evening" in normalized or "move flexible work after" in normalized) {
        times = extract_time_range(normalized);
        start = times[0];
        end = times[1];
        if "afternoon" in normalized and start < 0 { start = 720; end = 1020; }
        if "evening" in normalized and start < 0 { start = 1080; end = day_end; }
        if "move flexible work after" in normalized {
            end = extract_single_time(normalized.split("after", 1)[1]);
            start = day_start;
        }
        if start >= day_start and end > start and end <= day_end {
            if [item for item in busy if start < item.end and item.start < end] {
                return CommandReply(ok=False, kind="help", title="That time is already fixed",
                    message="The requested unavailable period overlaps a fixed commitment. Adjust its hours before simulating.");
            }
            proposal = simulate_availability("Unavailable time", start, end, work, busy,
                day_start, day_end, day, version);
            return CommandReply(ok=True, kind="proposal", title="Availability Simulation",
                message="Review the affected work before changing availability.", proposal=proposal);
        }
    }
    return None;
}

def protect_command(context: CommandContext) -> CommandReply | None {
    normalized = context.normalized;
    work = context.work;
    busy = context.busy;
    day_start = context.day_start;
    day_end = context.day_end;
    version = context.version;
    day = context.day;
    if "protect" in normalized {
        duration = extract_duration(normalized);
        title = "Protected focus time";
        if "exam" in normalized { title = "Exam revision"; }
        elif "revision" in normalized { title = "Revision"; }
        preview_id = "protect-preview";
        preview_work = [item for item in work];
        preview_work.append(Work(id=preview_id, title=title, duration=duration, deadline=day_end));
        preview = make_choice("minimal", preview_work, busy, day_start, day_end);
        if preview_id in preview.unplaced {
            return CommandReply(ok=False, kind="capacity", title="Protected time does not fit yet",
                message="The requested focus block needs more free time before it can be added.");
        }
        proposal = CommandProposal(
            kind="protect_time", title="Protect " + duration_label(duration) + " for " + title,
            day=day, details="Adds focused flexible work after approval. The block fits the current planning window.",
            base_version=version, task_title=title, task_duration=duration,
            task_deadline=day_end, action_type="protect_time",
            slack_change=-duration
        );
        return CommandReply(ok=True, kind="proposal", title="Protected Time Proposal",
            message="Review the protected work before adding it.", proposal=proposal);
    }
    return None;
}

def capture_command(context: CommandContext) -> CommandReply | None {
    clean = context.clean;
    normalized = context.normalized;
    day_end = context.day_end;
    version = context.version;
    day = context.day;
    if ("schedule" in normalized or "add task" in normalized or "find me" in normalized or "find time" in normalized) and "what if" not in normalized {
        dur = extract_duration(normalized);
        title = "New Task";
        words = clean.split();
        for i in range(len(words)) {
            w = words[i];
            if w.lower() in ["find", "me", "add", "schedule", "for", "task", "hours", "hour", "min", "mins", "minutes", "minute", "time"] { continue; }
            if w.istitle() and not w.isdigit() { title = w; break; }
        }

        prop = CommandProposal(
            kind="create_task",
            title="Create Task: " + title,
            day=day,
            details="Adds a new task to your plan.",
            base_version=version,
            task_title=title,
            task_duration=dur,
            task_deadline=day_end,
            action_type="create_task"
        );
        return CommandReply(ok=True, kind="proposal", title="Task Proposal",
            message="Review the new task.", proposal=prop);
    }
    return None;
}

def what_if_command(context: CommandContext) -> CommandReply | None {
    clean = context.clean;
    normalized = context.normalized;
    work = context.work;
    busy = context.busy;
    day_start = context.day_start;
    day_end = context.day_end;
    version = context.version;
    day = context.day;
    if "what if" in normalized {
        times = extract_time_range(normalized);
        if times[0] >= 0 and times[1] > times[0] {
            if times[0] < day_start or times[1] > day_end {
                return CommandReply(ok=False, kind="help", title="Choose time inside your planning day",
                    message="The event must fit inside the planning hours saved in Settings.");
            }
            if [item for item in busy if times[0] < item.end and item.start < times[1]] {
                return CommandReply(ok=False, kind="help", title="That time is already fixed",
                    message="The event overlaps a saved fixed commitment. Adjust its hours before simulating.");
            }
            title = infer_commitment_title(clean, "Hypothetical event");
            prop = simulate_what_if_event(title, times[0], times[1], work, busy, day_start, day_end);
            prop.day = day;
            prop.base_version = version;
            return CommandReply(ok=True, kind="proposal", title="Simulation Result",
                message="Review the what-if simulation.", proposal=prop);
        }
        return CommandReply(ok=False, kind="help", title="Add the event hours",
            message="Include a start and end time, such as 'from 2 to 5', so the simulation uses the right hours.");
    }
    return None;
}

def commitment_command(context: CommandContext) -> CommandReply | None {
    clean = context.clean;
    normalized = context.normalized;
    version = context.version;
    day = context.day;
    if "meeting" in normalized or "event" in normalized or "lab" in normalized {
        times = extract_time_range(normalized);
        if times[0] >= 0 and times[1] > times[0] {
            title = infer_commitment_title(clean);
            prop = CommandProposal(
                kind="create_commitment",
                title="Create Commitment: " + title,
                day=day,
                details="Adds a new commitment to your plan.",
                base_version=version,
                commitment_start=times[0],
                commitment_end=times[1],
                commitment_title=title,
                action_type="create_commitment"
            );
            return CommandReply(ok=True, kind="proposal", title="Commitment Proposal",
                message="Review the new commitment.", proposal=prop);
        }
    }
    return None;
}

def next_command(context: CommandContext) -> CommandReply | None {
    normalized = context.normalized;
    briefing = context.briefing;
    if "next" in normalized or "right now" in normalized or "do now" in normalized {
        action = briefing.next_action;
        timing = "";
        if action.start >= 0 {
            timing = " Start at " + clock_label(action.start);
            if action.end >= 0 { timing += " and finish by " + clock_label(action.end) + "."; }
        }
        return CommandReply(ok=True, kind="next", title=action.title,
            message=action.reason + timing,
            action_label="Open today's plan", action_target="today");
    }
    return None;
}

def risk_command(context: CommandContext) -> CommandReply | None {
    normalized = context.normalized;
    briefing = context.briefing;
    if "risk" in normalized or "deadline" in normalized or "health" in normalized or "problem" in normalized {
        if briefing.risks {
            risk = briefing.risks[0];
            return CommandReply(ok=True, kind="risk", title=risk.title,
                message=risk.detail, action_label=risk.action_label,
                action_target=risk.action_target);
        }
        return CommandReply(ok=True, kind="risk", title="No immediate risk detected",
            message=briefing.health.reasons[0], action_label="Review today's plan",
            action_target="today");
    }
    return None;
}

def capacity_command(context: CommandContext) -> CommandReply | None {
    normalized = context.normalized;
    briefing = context.briefing;
    if "fit" in normalized or "finish" in normalized or "capacity" in normalized or
       "free time" in normalized or "workload" in normalized or "lighter" in normalized {
        health = briefing.health;
        return CommandReply(ok=True, kind="capacity", title=health.label + " capacity",
            message=duration_label(health.available_minutes) + " is available for " +
                    duration_label(health.required_minutes) + " of remaining work. " +
                    "Plan slack is " + ("-" + duration_label(-health.slack_minutes) if health.slack_minutes < 0 else duration_label(health.slack_minutes)) + ".",
            action_label="Review the timeline", action_target="today");
    }
    return None;
}

def recovery_command(context: CommandContext) -> CommandReply | None {
    normalized = context.normalized;
    if "lost" in normalized or "changed" in normalized or "disruption" in normalized or
       "adjust my plan" in normalized or "replan" in normalized {
        return CommandReply(ok=True, kind="recovery", title="Let's protect the rest of the day",
            message="Open Recovery Studio to enter the time you lost. Replaniva will simulate valid choices before changing the saved plan.",
            action_label="Open Recovery Studio", action_target="recovery");
    }
    return None;
}

def briefing_command(context: CommandContext) -> CommandReply | None {
    normalized = context.normalized;
    briefing = context.briefing;
    if "brief" in normalized or "summary" in normalized or "today" in normalized or
       "explain my plan" in normalized or "explain the plan" in normalized or
       "how does my day look" in normalized {
        return CommandReply(ok=True, kind="briefing", title=briefing.headline,
            message=briefing.summary, action_label="Review today's plan",
            action_target="today");
    }
    return None;
}

def goals_command(context: CommandContext) -> CommandReply | None {
    normalized = context.normalized;
    if "goal" in normalized {
        return CommandReply(ok=True, kind="goals", title="Active Goals",
            message="Check your active goals and linked task progress.");
    }
    return None;
}

def breakdown_command(context: CommandContext) -> CommandReply | None {
    clean = context.clean;
    normalized = context.normalized;
    work = context.work;
    if "break down" in normalized or "decompose" in normalized or "steps for" in normalized {
        target_name = "";
        if "steps for " in normalized {
            idx = normalized.find("steps for ") + 10;
            target_name = clean[idx:].strip();
        } elif "break down " in normalized {
            idx = normalized.find("break down ") + 11;
            target_name = clean[idx:].strip();
        } elif "decompose " in normalized {
            idx = normalized.find("decompose ") + 10;
            target_name = clean[idx:].strip();
        }

        matching: Work | None = None;
        if target_name {
            target_lower = target_name.lower();
            for w in work {
                if target_lower in w.title.lower() or w.title.lower() in target_lower {
                    matching = w;
                    break;
                }
            }
        }
        if matching is None {
            for w in work {
                if w.title.lower() in normalized {
                    matching = w;
                    break;
                }
            }
        }
        if matching is None and len(work) > 0 {
            matching = work[0];
        }

        if matching is not None {
            subtasks = generate_subtasks(matching.title, matching.duration);
            summary = ", ".join([s.title + " (" + str(s.duration) + "m)" for s in subtasks]);
            return CommandReply(
                ok=True,
                kind="breakdown",
                title="Break down " + matching.title,
                message="Decomposed into " + str(len(subtasks)) + " sequenced steps: " + summary + ".",
                action_label="Review in Today",
                action_target="today"
            );
        } elif target_name {
            dur = extract_duration(normalized);
            subtasks = generate_subtasks(target_name, dur);
            summary = ", ".join([s.title + " (" + str(s.duration) + "m)" for s in subtasks]);
            return CommandReply(
                ok=True,
                kind="breakdown",
                title="Break down " + target_name,
                message="Suggested " + str(len(subtasks)) + " steps: " + summary + ".",
                action_label="Capture task",
                action_target="capture"
            );
        }
        return CommandReply(
            ok=True,
            kind="breakdown",
            title="Break down a task",
            message="Specify which task you want to break down into sequenced subtasks.",
            action_label="Review tasks",
            action_target="today"
        );
    }
    return None;
}

def answer_command(query: str, briefing: DailyBriefing, work: list[Work] | None = None, busy: list[Busy] | None = None, day_start: int = 480, day_end: int = 1320, version: int = 0, day: str = "") -> CommandReply {
    clean = query.strip();
    if not clean { return CommandReply(ok=False, kind="help", title="Ask about the plan", message="Try asking what to do next, what is at risk, or whether the day can fit."); }
    context = CommandContext(clean=clean, normalized=clean.lower(), briefing=briefing,
        work=work if work is not None else [], busy=busy if busy is not None else [],
        day_start=day_start, day_end=day_end, version=version, day=day);
    # The ordered handlers preserve the existing interpretation precedence.
    for handler in [duration_command, move_command, later_start_command, availability_command, protect_command, capture_command, what_if_command, commitment_command, next_command, risk_command, capacity_command, recovery_command, briefing_command, goals_command, breakdown_command] {
        reply = handler(context);
        if reply is not None { return reply; }
    }
    return CommandReply(ok=False, kind="help", title="I can act on your plan",
        message="Ask what to do next, what is at risk, whether today's work fits, or how to recover after a change.");
}

test "command parses task creation proposal" {
    briefing = DailyBriefing(headline="Clear", summary="Clear", remaining_tasks=0, completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=0, available_minutes=300, slack_minutes=300, pressure_percent=0,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0, deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="clear", title="Open space", reason="Nothing is due."));
    reply = answer_command("Find me 2 hours for Signals", briefing);
    assert reply.ok;
    assert reply.proposal is not None;
    assert reply.proposal.action_type == "create_task";
    assert reply.proposal.task_duration == 120;
    assert "Signals" in reply.proposal.task_title;
}

test "command parses commitment proposal with valid time range" {
    briefing = DailyBriefing(headline="Clear", summary="Clear", remaining_tasks=0, completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=0, available_minutes=300, slack_minutes=300, pressure_percent=0,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0, deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="clear", title="Open space", reason="Nothing is due."));
    reply = answer_command("I have a lab tomorrow from 14:00 to 15:30", briefing);
    assert reply.ok;
    assert reply.proposal is not None;
    assert reply.proposal.action_type == "create_commitment";
    assert reply.proposal.commitment_start == 840;
    assert reply.proposal.commitment_end == 930;
}

test "what-if simulation calculates affected tasks non-destructively" {
    work = [Work(id="t1", title="Task 1", duration=60, deadline=1320, start=840)];
    busy = [Busy(title="Class", start=600, end=660)];
    prop = simulate_what_if_event("Surprise Meeting", 840, 900, work, busy, 480, 1320);
    assert prop.action_type == "what_if";
    assert "Task 1" in prop.affected_tasks;
    assert prop.unplaced_count == 0;
}

test "what-if simulation flags unplaced tasks when time is constrained" {
    work = [Work(id="t1", title="Task 1", duration=120, deadline=720, start=600)];
    busy = [Busy(title="Class", start=480, end=600)];
    prop = simulate_what_if_event("Extra Class", 600, 660, work, busy, 480, 1320);
    assert prop.action_type == "what_if";
    assert "Task 1" in prop.affected_tasks;
    assert prop.unplaced_count == 1;
}

test "next command uses the computed next action" {
    briefing = DailyBriefing(headline="Ready", summary="One task", remaining_tasks=1,
        completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=60,
                          available_minutes=180, slack_minutes=120, pressure_percent=33,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0,
                          deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="task", title="Read", start=600, end=660,
                               reason="This is next."));
    reply = answer_command("What should I do next?", briefing);
    assert reply.kind == "next";
    assert reply.title == "Read";
    assert "10:00" in reply.message;
}

test "command proposal captures base version for stale detection" {
    briefing = DailyBriefing(headline="Clear", summary="Clear", remaining_tasks=0, completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=0, available_minutes=300, slack_minutes=300, pressure_percent=0,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0, deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="clear", title="Open space", reason="Nothing is due."));
    reply = answer_command("Schedule 45 min for Quiz", briefing, version=4, day="2026-09-24");
    assert reply.ok;
    assert reply.proposal is not None;
    assert reply.proposal.base_version == 4;
    assert reply.proposal.day == "2026-09-24";
}

test "unknown command explains the supported planning questions" {
    briefing = DailyBriefing(headline="Clear", summary="Clear", remaining_tasks=0,
        completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=0,
                          available_minutes=300, slack_minutes=300, pressure_percent=0,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0,
                          deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="clear", title="Open space", reason="Nothing is due."));
    reply = answer_command("Tell me a joke", briefing);
    assert not reply.ok;
    assert reply.kind == "help";
}

test "command recognizes goals query" {
    briefing = DailyBriefing(headline="Clear", summary="Clear", remaining_tasks=0,
        completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=0,
                          available_minutes=300, slack_minutes=300, pressure_percent=0,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0,
                          deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="clear", title="Open space", reason="Nothing is due."));
    reply = answer_command("goals", briefing);
    assert reply.ok;
    assert reply.kind == "goals";
    assert reply.title == "Active Goals";
    assert reply.message == "Check your active goals and linked task progress.";

    reply2 = answer_command("What are my goal progress?", briefing);
    assert reply2.ok;
    assert reply2.kind == "goals";
}

test "task breakdown generates sequenced subtasks deterministically" {
    talk_subs = generate_subtasks("Conference Presentation", 120);
    assert len(talk_subs) == 4;
    assert talk_subs[0].title == "Create outline";
    assert talk_subs[1].title == "Prepare slides";
    assert talk_subs[2].title == "Prepare demo";
    assert talk_subs[3].title == "Rehearse";
    assert talk_subs[0].duration == 30;
    assert talk_subs[1].duration == 30;
    assert talk_subs[2].duration == 30;
    assert talk_subs[3].duration == 30;

    paper_subs = generate_subtasks("Term Paper Draft", 60);
    assert len(paper_subs) == 4;
    assert paper_subs[0].title == "Research sources";
    assert paper_subs[1].title == "Structure outline";
    assert paper_subs[2].title == "Draft content";
    assert paper_subs[3].title == "Edit and proofread";
    assert paper_subs[0].duration == 15;
    assert paper_subs[1].duration == 15;
    assert paper_subs[2].duration == 15;
    assert paper_subs[3].duration == 15;

    exam_subs = generate_subtasks("Final Exam", 90);
    assert len(exam_subs) == 4;
    assert exam_subs[0].title == "Review lecture notes";
    assert exam_subs[1].title == "Practice exercises";
    assert exam_subs[2].title == "Formula sheet";
    assert exam_subs[3].title == "Timed mock test";
    assert exam_subs[0].duration == 30;
    assert exam_subs[1].duration == 30;
    assert exam_subs[2].duration == 15;
    assert exam_subs[3].duration == 15;
    total_exam = 0;
    for s in exam_subs { total_exam += s.duration; }
    assert total_exam == 90;

    proj_subs = generate_subtasks("Build New Feature", 120);
    assert len(proj_subs) == 4;
    assert proj_subs[0].title == "Architecture design";
    assert proj_subs[1].title == "Core implementation";
    assert proj_subs[2].title == "Testing and debugging";
    assert proj_subs[3].title == "Documentation";

    fallback_subs = generate_subtasks("Deep Work", 60);
    assert len(fallback_subs) == 3;
    assert fallback_subs[0].title == "Deep Work - Part 1";
    assert fallback_subs[1].title == "Deep Work - Part 2";
    assert fallback_subs[2].title == "Deep Work - Review";
    assert fallback_subs[0].duration == 30;
    assert fallback_subs[1].duration == 15;
    assert fallback_subs[2].duration == 15;

    briefing = DailyBriefing(
        headline="Clear", summary="Clear", remaining_tasks=1, completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=60, available_minutes=300,
                          slack_minutes=240, pressure_percent=20, unplaced_tasks=0, overdue_tasks=0,
                          urgent_tasks=0, deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="task", title="Team Presentation", start=600, end=720, reason="Next up")
    );
    work = [Work(id="w1", title="Team Presentation", duration=120, deadline=1320, start=600)];

    reply1 = answer_command("break down Team Presentation", briefing, work=work);
    assert reply1.ok;
    assert reply1.kind == "breakdown";
    assert "outline" in reply1.message.lower();

    reply2 = answer_command("decompose Research Paper", briefing, work=[]);
    assert reply2.ok;
    assert reply2.kind == "breakdown";
    assert "sources" in reply2.message.lower();

    reply3 = answer_command("steps for Biology Quiz", briefing, work=[]);
    assert reply3.ok;
    assert reply3.kind == "breakdown";
    assert "lecture notes" in reply3.message.lower();

    # 7. Test sequenced subtasks through the dependency scheduler
    scheduled_work: list[Work] = [];
    prev_id = "";
    for i in range(len(talk_subs)) {
        sub = talk_subs[i];
        sid = "sub_" + str(i);
        deps = [prev_id] if prev_id else [];
        scheduled_work.append(Work(id=sid, title=sub.title, duration=sub.duration, deadline=1320, depends_on=deps));
        prev_id = sid;
    }
    choice = make_choice("minimal", scheduled_work, [], 480, 1320);
    assert len(choice.slots) == 4;
    s0 = [s for s in choice.slots if s.task_id == "sub_0"][0];
    s1 = [s for s in choice.slots if s.task_id == "sub_1"][0];
    s2 = [s for s in choice.slots if s.task_id == "sub_2"][0];
    s3 = [s for s in choice.slots if s.task_id == "sub_3"][0];
    assert s0.end <= s1.start;
    assert s1.end <= s2.start;
    assert s2.end <= s3.start;
}

test "command proposes named task duration simulation" {
    briefing = DailyBriefing(headline="Clear", summary="Clear", remaining_tasks=1, completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=60, available_minutes=300, slack_minutes=240, pressure_percent=20,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0, deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="task", title="Signals assignment", reason="Next."));
    work = [Work(id="signals", title="Signals assignment", duration=60, deadline=1200)];
    reply = answer_command("What if the Signals assignment takes 3 hours?", briefing, work=work,
                           version=7, day="2026-09-28");
    assert reply.ok and reply.proposal is not None;
    assert reply.proposal.action_type == "change_duration";
    assert reply.proposal.target_task_id == "signals";
    assert reply.proposal.proposed_duration == 180;
    assert reply.proposal.base_version == 7;
}

test "command proposes unavailable afternoon without mutation" {
    briefing = DailyBriefing(headline="Clear", summary="Clear", remaining_tasks=1, completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=60, available_minutes=300, slack_minutes=240, pressure_percent=20,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0, deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="task", title="Read", reason="Next."));
    work = [Work(id="read", title="Read", duration=60, deadline=1200, start=720)];
    reply = answer_command("I lost tomorrow afternoon", briefing, work=work,
                           version=4, day="2026-09-29");
    assert reply.ok and reply.proposal is not None;
    assert reply.proposal.action_type == "change_availability";
    assert reply.proposal.commitment_start == 720;
    assert reply.proposal.commitment_end == 1020;
    assert work[0].start == 720;
}

test "command proposes a named task move" {
    briefing = DailyBriefing(headline="Clear", summary="Clear", remaining_tasks=1, completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=60, available_minutes=300, slack_minutes=240, pressure_percent=20,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0, deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="task", title="Signals revision", reason="Next."));
    work = [Work(id="signals", title="Signals revision", duration=60, deadline=1200)];
    reply = answer_command("Move Signals revision to Friday", briefing, work=work,
                           version=2, day="2026-09-28");
    assert reply.ok and reply.proposal is not None;
    assert reply.proposal.action_type == "move_task";
    assert reply.proposal.target_task_id == "signals";
    assert reply.proposal.target_day == "2026-10-02";
}

test "command proposes protected study time" {
    briefing = DailyBriefing(headline="Clear", summary="Clear", remaining_tasks=0, completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=0, available_minutes=600, slack_minutes=600, pressure_percent=0,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0, deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="clear", title="Open", reason="Clear."));
    reply = answer_command("Protect four hours for exam revision before Friday", briefing,
                           version=3, day="2026-10-02");
    assert reply.ok and reply.proposal is not None;
    assert reply.proposal.action_type == "protect_time";
    assert reply.proposal.task_duration == 240;
}

test "availability commands use a single time and never invent event hours" {
    briefing = DailyBriefing(headline="Clear", summary="Clear", remaining_tasks=0, completed_tasks=0, fixed_commitments=0,
        health=PlanHealth(status="HEALTHY", label="Healthy", required_minutes=0, available_minutes=600, slack_minutes=600, pressure_percent=0,
                          unplaced_tasks=0, overdue_tasks=0, urgent_tasks=0, deadline_risks=0, reasons=["The plan fits."]),
        next_action=NextAction(kind="clear", title="Open", reason="Clear."));
    later = answer_command("What if I start my day at 10 tomorrow?", briefing,
                           day="2026-10-12");
    assert later.proposal is not None;
    assert later.proposal.commitment_start == 480;
    assert later.proposal.commitment_end == 600;
    after = answer_command("Move flexible work after 6", briefing, day="2026-10-12");
    assert after.proposal is not None;
    assert after.proposal.commitment_end == 1080;
    unclear = answer_command("What if I attend an event Saturday?", briefing,
                             day="2026-10-17");
    assert not unclear.ok;
    assert unclear.proposal is None;
}

test "command times distinguish morning afternoon and explicit meridiem" {
    assert extract_time_range("meeting from 10 to 11") == [600, 660];
    assert extract_time_range("lab from 2 to 5") == [840, 1020];
    assert extract_time_range("office hours 9:30 am to 1:15 pm") == [570, 795];
}

test "tomorrow commands resolve against the calendar" {
    assert resolve_command_day("add a lab tomorrow", "2026-09-20", "2026-09-24") == "2026-09-25";
    assert resolve_command_day("add a lab today", "2026-09-20", "2026-09-24") == "2026-09-24";
    assert resolve_command_day("add a lab", "2026-09-20", "2026-09-24") == "2026-09-20";
    assert resolve_command_day("Protect study time before Friday", "2026-09-28", "2026-09-28") == "2026-10-01";
}

test "command infers a meaningful commitment label" {
    assert infer_commitment_title("What if I get a lab tomorrow?") == "Lab";
    assert infer_commitment_title("Add a meeting from 2 to 3") == "Meeting";
    assert infer_commitment_title("Block some time") == "New commitment";
}
