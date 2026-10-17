"""Shared client formatting and timeline projection."""

import from .date_labels { day_label }
import from endpoints { Board, TaskView }
import from planning { Choice }

obj TimelineItem {
    has id: str, title: str, start: int, end: int,
        kind: str, detail: str, done: bool = False;
}

def:pub clock_time(minutes: int) -> str {
    if minutes < 0 { return "Unplaced"; }
    hour = str(minutes // 60);
    minute = str(minutes % 60);
    if minutes // 60 < 10 { hour = "0" + hour; }
    if minutes % 60 < 10 { minute = "0" + minute; }
    return hour + ":" + minute;
}

def:pub duration_label(minutes: int) -> str {
    safe = max(0, minutes);
    hours = safe // 60;
    remainder = safe % 60;
    if hours > 0 and remainder > 0 { return str(hours) + "h " + str(remainder) + "m"; }
    if hours > 0 { return str(hours) + "h"; }
    return str(remainder) + "m";
}

def:pub slack_label(minutes: int) -> str {
    return "-" + duration_label(-minutes) if minutes < 0 else duration_label(minutes);
}

def:pub pressure_style(percent: int) -> dict[str, str] {
    return {"width": str(min(100, max(0, percent))) + "%"};
}

def:pub workload_style(required: int, available: int) -> dict[str, str] {
    percent = 0 if required == 0 else required * 100 // max(1, available);
    return {"width": str(min(100, max(3, percent))) + "%"};
}

def:pub short_day(day: str) -> str {
    return day[5:].replace("-", "/") if len(day) >= 10 else day;
}

def:pub outlook_date_label(day: str, weekday: bool = False) -> str {
    win: any = window;
    date_class: any = win.Date;
    value: any = new(date_class, day + "T12:00:00");
    if weekday { return value.toLocaleDateString("en-GB", {"weekday": "long"}); }
    return value.toLocaleDateString("en-GB", {"day": "numeric", "month": "short"});
}

def:pub time_minutes(value: str) -> int {
    parts = value.split(":");
    if len(parts) != 2 { return -1; }
    return int(parts[0]) * 60 + int(parts[1]);
}

def:pub task_name(tasks: list[TaskView], task_id: str) -> str {
    for task in tasks {
        if task.id == task_id { return task.title; }
    }
    return "Task";
}

def:pub original_start(tasks: list[TaskView], task_id: str) -> int {
    for task in tasks {
        if task.id == task_id { return task.start; }
    }
    return -1;
}

def:pub preview_style(start: int, end: int, day_start: int, day_end: int) -> dict[str, str] {
    clipped_start = max(day_start, min(start, day_end));
    clipped_end = max(clipped_start + 1, min(end, day_end));
    span = max(1, day_end - day_start);
    return {
        "left": str((clipped_start - day_start) * 100.0 / span) + "%",
        "width": str((clipped_end - clipped_start) * 100.0 / span) + "%"
    };
}

def:pub same_plan(left: Choice, right: Choice) -> bool {
    if len(left.slots) != len(right.slots) or len(left.unplaced) != len(right.unplaced) {
        return False;
    }
    for slot in left.slots {
        if not [other for other in right.slots
                if other.task_id == slot.task_id and other.start == slot.start] {
            return False;
        }
    }
    return True;
}

def:pub timeline_for(board: Board) -> list[TimelineItem] {
    events: list[TimelineItem] = [];
    for commitment in board.commitments {
        events.append(TimelineItem(id=commitment.id, title=commitment.title,
                                   start=commitment.start, end=commitment.end,
                                   kind="fixed", detail="FIXED · " + commitment.source));
    }
    for task in board.tasks {
        events.append(TimelineItem(id=task.id, title=task.title, start=task.start,
                                   end=task.start + task.duration if task.start >= 0 else -1,
                                   kind="flexible", detail="DONE" if task.done else "FLEXIBLE · DUE " +
                                       (day_label(task.due_day) + " at " if task.due_day != board.day else "") +
                                       clock_time(task.deadline),
                                   done=task.done));
    }
    events.sort(key=lambda (item: TimelineItem) { (item.start if item.start >= 0 else 9999, item.kind != "fixed"); });
    return events;
}
