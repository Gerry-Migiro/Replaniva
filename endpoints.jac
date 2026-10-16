"""Private Stage 1 planning operations. Every lookup stays under the caller's root."""
import from datetime { datetime, date }
import from zoneinfo { ZoneInfo }
import from planning { Work, Block, schedule }

node PlanningSettings {
    has start: int = 480,
        end: int = 1200,
        timezone: str = "UTC";
}

node Task {
    has title: str,
        day: str,
        duration: int,
        due_day: str,
        deadline: int,
        priority: int = 2,
        done: bool = False,
        start: int = -1;
}

node Commitment {
    has title: str,
        day: str,
        start: int,
        end: int;
}

obj TaskView {
    has id: str,
        title: str,
        day: str,
        duration: int,
        due_day: str,
        deadline: int,
        priority: int,
        done: bool,
        start: int;
}

obj CommitmentView {
    has id: str,
        title: str,
        start: int,
        end: int;
}

obj Board {
    has day: str,
        today: str,
        timezone: str,
        start: int,
        end: int,
        tasks: list[TaskView] = [],
        commitments: list[CommitmentView] = [],
        error: str = "";
}

obj Action {
    has ok: bool,
        message: str;
}

def settings() -> PlanningSettings {
    found = [root-->][?:PlanningSettings];
    if found {
        return found[0];
    }
    return root ++> PlanningSettings();
}

def checked_day(value: str) -> str {
    try {
        parsed = date.fromisoformat(value);
    } except ValueError {
        raise ValueError("Use a valid date in YYYY-MM-DD format.");
    }
    if parsed.isoformat() != value {
        raise ValueError("Use a date in YYYY-MM-DD format.");
    }
    return value;
}

def checked_title(value: str) -> str {
    clean = value.strip();
    if not clean or len(clean) > 160 {
        raise ValueError("Use a title of 1 to 160 characters.");
    }
    return clean;
}

def rebuild(day: str, prefs: PlanningSettings) -> None {
    tasks = [
        t
        for t in [root-->][?:Task]
        if t.day == day
    ];
    fixed = [
        Block(start=c.start, end=c.end)
        for c in [root-->][?:Commitment]
        if c.day == day
    ];
    work = [
        Work(
            id=jid(t),
            duration=t.duration,
            deadline=(t.deadline if t.due_day == day else 1440),
            priority=t.priority
        )
        for t in tasks
        if not t.done
    ];
    result = schedule(work, fixed, prefs.start, prefs.end);
    for t in tasks {
        matches = [
            s
            for s in result.slots
            if s.id == jid(t)
        ];
        t.start = matches[0].start if matches else -1;
    }
}

def:protect get_board(day: str = "") -> Board {
    prefs = settings();
    today = datetime.now(ZoneInfo(prefs.timezone)).date().isoformat();
    try {
        selected = checked_day(day) if day else today;
    } except ValueError {
        return Board(
            day="",
            today=today,
            timezone=prefs.timezone,
            start=prefs.start,
            end=prefs.end,
            error="Use a valid date in YYYY-MM-DD format."
        );
    }
    board = Board(
        day=selected,
        today=today,
        timezone=prefs.timezone,
        start=prefs.start,
        end=prefs.end
    );
    board.tasks = [
        TaskView(
            id=jid(t),
            title=t.title,
            day=t.day,
            duration=t.duration,
            due_day=t.due_day,
            deadline=t.deadline,
            priority=t.priority,
            done=t.done,
            start=t.start
        )
        for t in [root-->][?:Task]
        if t.day == selected
    ];
    board.commitments = [
        CommitmentView(id=jid(c), title=c.title, start=c.start, end=c.end)
        for c in [root-->][?:Commitment]
        if c.day == selected
    ];
    board.tasks.sort(
        key=lambda (t: TaskView) { (t.done, t.start < 0, t.start, t.title); }
    );
    board.commitments.sort(key=lambda (c: CommitmentView) { c.start; });
    return board;
}

def:protect update_settings(start: int, end: int, timezone: str) -> Action {
    if start < 0 or end > 1440 or end - start < 15 {
        return Action(
            ok=False,
            message="Planning hours must span at least 15 minutes within one day."
        );
    }
    try {
        ZoneInfo(timezone);
    } except Exception {
        return Action(
            ok=False, message="Choose a valid IANA timezone, such as Africa/Nairobi."
        );
    }
    prefs = settings();
    prefs.start = start;
    prefs.end = end;
    prefs.timezone = timezone;
    days = {t.day for t in [root-->][?:Task]};
    for day in days {
        rebuild(day, prefs);
    }
    return Action(
        ok=True,
        message="Planning hours saved. Flexible work was rescheduled within them."
    );
}

def:protect save_task(
    day: str,
    title: str,
    duration: int,
    due_day: str,
    deadline: int,
    priority: int = 2,
    task_id: str = ""
) -> Action {
    priority = int(priority);
    try {
        checked_day(day);
        checked_day(due_day);
        clean = checked_title(title);
    } except ValueError {
        return Action(
            ok=False,
            message="Use valid planning and due dates, and a title of 1 to 160 characters."
        );
    }
    if duration < 15
        or duration > 1440
        or deadline < 1
        or deadline > 1440
        or due_day < day
        or priority < 1
        or priority > 3 {
        return Action(
            ok=False,
            message="Check the duration (15 to 1440 minutes), due date, deadline and importance."
        );
    }
    if task_id {
        matches = [
            t
            for t in [root-->][?:Task]
            if jid(t) == task_id
        ];
        if not matches {
            return Action(ok=False, message="Task not found in your plan.");
        }
        t = matches[0];
        old_day = t.day;
        t.title = clean;
        t.day = day;
        t.duration = duration;
        t.due_day = due_day;
        t.deadline = deadline;
        t.priority = priority;
        rebuild(old_day, settings());
    } else {
        root ++> Task(
            title=clean,
            day=day,
            duration=duration,
            due_day=due_day,
            deadline=deadline,
            priority=priority
        );
    }
    rebuild(day, settings());
    return Action(
        ok=True,
        message="Task saved and schedule updated. Work that cannot fit remains unscheduled."
    );
}

def:protect change_task(task_id: str, operation: str) -> Action {
    for t in [root-->][?:Task] {
        if jid(t) == task_id {
            day = t.day;
            if operation == "complete" {
                t.done = True;
            } elif operation == "reopen" {
                t.done = False;
            } elif operation == "delete" {
                del t;
            } else {
                return Action(ok=False, message="Unknown task action.");
            }
            rebuild(day, settings());
            return Action(ok=True, message="Task updated.");
        }
    }
    return Action(ok=False, message="Task not found in your plan.");
}

def:protect save_commitment(
    day: str, title: str, start: int, end: int, commitment_id: str = ""
) -> Action {
    try {
        checked_day(day);
        clean = checked_title(title);
    } except ValueError {
        return Action(
            ok=False,
            message="Use a valid planning date and a title of 1 to 160 characters."
        );
    }
    if start < 0 or end > 1440 or start >= end {
        return Action(
            ok=False, message="Commitment end must be after its start, within one day."
        );
    }
    existing = [root-->][?:Commitment];
    if commitment_id
        and not [
            c
            for c in existing
            if jid(c) == commitment_id
        ] {
        return Action(ok=False, message="Commitment not found in your plan.");
    }
    if any(
        [
            c.day == day
                and jid(c) != commitment_id
                and start < c.end
                and c.start < end for c in existing
        ]
    ) {
        return Action(
            ok=False,
            message="This overlaps another fixed commitment. Adjust the times first."
        );
    }
    if commitment_id {
        c = [
            c
            for c in existing
            if jid(c) == commitment_id
        ][0];
        old_day = c.day;
        c.title = clean;
        c.day = day;
        c.start = start;
        c.end = end;
        rebuild(old_day, settings());
    } else {
        root ++> Commitment(title=clean, day=day, start=start, end=end);
    }
    rebuild(day, settings());
    return Action(
        ok=True,
        message="Fixed commitment saved. Flexible work was scheduled around it."
    );
}

def:protect delete_commitment(commitment_id: str) -> Action {
    for c in [root-->][?:Commitment] {
        if jid(c) == commitment_id {
            day = c.day;
            del c;
            rebuild(day, settings());
            return Action(ok=True, message="Commitment removed.");
        }
    }
    return Action(ok=False, message="Commitment not found in your plan.");
}
