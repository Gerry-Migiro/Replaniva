"""Deterministic, single-day scheduling rules shared by Replaniva interfaces."""

obj Work {
    has id: str, title: str, duration: int, deadline: int,
        priority: int = 2, start: int = -1, depends_on: list[str] = [],
        due_day: str = "", due_time: int = -1;
}

obj Busy {
    has title: str, start: int, end: int;
}

obj Slot {
    has task_id: str, start: int, end: int;
}

obj Choice {
    has key: str, label: str, slots: list[Slot] = [],
        unplaced: list[str] = [], moved: int = 0,
        reason: str = "", source: str = "Deterministic Jac plan";
}

def overlaps(start: int, end: int, other_start: int, other_end: int) -> bool {
    return start < other_end and other_start < end;
}

def available(start: int, duration: int, deadline: int, busy: list[Busy],
              slots: list[Slot], day_start: int, day_end: int) -> bool {
    end = start + duration;
    if duration < 15 or start < day_start or end > day_end or end > deadline {
        return False;
    }
    for item in busy {
        if overlaps(start, end, item.start, item.end) { return False; }
    }
    for slot in slots {
        if overlaps(start, end, slot.start, slot.end) { return False; }
    }
    return True;
}

def validate(slots: list[Slot], work: list[Work], busy: list[Busy],
             day_start: int, day_end: int) -> bool {
    work_ids = [item.id for item in work];
    checked: list[Slot] = [];
    for slot in slots {
        if [existing for existing in checked if existing.task_id == slot.task_id] {
            return False;
        }
        matching = [item for item in work if item.id == slot.task_id];
        if len(matching) != 1 { return False; }
        item = matching[0];
        if slot.end - slot.start != item.duration {
            return False;
        }
        if not available(slot.start, item.duration, item.deadline, busy,
                         checked, day_start, day_end) { return False; }
        for prereq_id in item.depends_on {
            prereq_slots = [s for s in slots if s.task_id == prereq_id];
            if prereq_id in work_ids and not prereq_slots {
                return False;
            }
            if prereq_slots and prereq_slots[0].end > slot.start {
                return False;
            }
        }
        checked.append(slot);
    }
    return True;
}

def make_choice(key: str, work: list[Work], busy: list[Busy],
                day_start: int = 480, day_end: int = 1320) -> Choice {
    label = "Move as little as possible" if key == "minimal" else "Protect deadlines";
    choice = Choice(key=key, label=label);
    pending = [item for item in work];
    if key == "deadline" {
        pending.sort(key=lambda (item: Work) { (item.deadline, -item.priority); });
    } else {
        pending.sort(key=lambda (item: Work) { (item.start < 0, item.start if item.start >= 0 else 1440, -item.priority); });
    }
    ordered: list[Work] = [];
    while len(pending) > 0 {
        progress = False;
        for item in pending {
            ready = True;
            for p in item.depends_on {
                if p in [w.id for w in pending] {
                    ready = False;
                    break;
                }
            }
            if ready {
                ordered.append(item);
                pending.remove(item);
                progress = True;
                break;
            }
        }
        if not progress {
            choice.unplaced.extend([item.id for item in pending]);
            break;
        }
    }
    pending = ordered;
    for item in pending {
        chosen = -1;
        min_start = day_start;
        prereq_unplaced = False;
        for p in item.depends_on {
            if p in choice.unplaced {
                prereq_unplaced = True;
            }
            p_slots = [s for s in choice.slots if s.task_id == p];
            if p_slots and p_slots[0].end > min_start {
                min_start = p_slots[0].end;
            }
        }
        if prereq_unplaced {
            choice.unplaced.append(item.id);
            continue;
        }
        if key == "minimal" and item.start >= 0 and item.start >= min_start and available(
            item.start, item.duration, item.deadline, busy, choice.slots,
            day_start, day_end
        ) {
            chosen = item.start;
        }
        if chosen < 0 {
            best_distance = 99999;
            for candidate in range(min_start, day_end - item.duration + 1, 15) {
                if available(candidate, item.duration, item.deadline, busy,
                             choice.slots, day_start, day_end) {
                    distance = abs(candidate - item.start) if item.start >= 0 else candidate - day_start;
                    if key == "deadline" or distance < best_distance {
                        chosen = candidate;
                        best_distance = distance;
                        if key == "deadline" { break; }
                    }
                }
            }
        }
        if chosen < 0 {
            choice.unplaced.append(item.id);
        } else {
            choice.slots.append(Slot(task_id=item.id, start=chosen, end=chosen + item.duration));
            if item.start >= 0 and item.start != chosen { choice.moved += 1; }
        }
    }
    if key == "minimal" {
        choice.reason = "Keeps existing work blocks wherever they still fit.";
    } else {
        choice.reason = "Schedules the earliest deadlines first.";
    }
    if len(choice.unplaced) > 0 {
        choice.reason += " Some work has no valid space before its deadline.";
    }
    return choice;
}

test "fixed time and deadline are respected" {
    work = [Work(id="essay", title="Essay", duration=60, deadline=1020, start=840)];
    busy = [Busy(title="Lab", start=840, end=1020)];
    choice = make_choice("minimal", work, busy);
    assert validate(choice.slots, work, busy, 480, 1320);
    assert len(choice.slots) == 1;
    assert choice.slots[0].end <= 840;
}

test "impossible work stays visible" {
    work = [Work(id="essay", title="Essay", duration=180, deadline=600)];
    choice = make_choice("deadline", work, []);
    assert len(choice.unplaced) == 1;
    assert len(choice.slots) == 0;
}

test "overlapping placements are rejected" {
    work = [Work(id="a", title="A", duration=60, deadline=1200),
            Work(id="b", title="B", duration=60, deadline=1200)];
    slots = [Slot(task_id="a", start=600, end=660), Slot(task_id="b", start=630, end=690)];
    assert not validate(slots, work, [], 480, 1320);
}

test "the same task cannot occupy two places" {
    work = [Work(id="a", title="A", duration=60, deadline=1200)];
    slots = [Slot(task_id="a", start=600, end=660), Slot(task_id="a", start=660, end=720)];
    assert not validate(slots, work, [], 480, 1320);
}

test "custom planning hours bound every flexible block" {
    work = [Work(id="morning", title="Morning work", duration=60, deadline=1200),
            Work(id="afternoon", title="Afternoon work", duration=90, deadline=1200)];
    choice = make_choice("deadline", work, [], 600, 1080);
    assert validate(choice.slots, work, [], 600, 1080);
    assert all([slot.start >= 600 and slot.end <= 1080 for slot in choice.slots]);
}

test "task dependencies enforce valid ordering" {
    work = [Work(id="part1", title="Part 1", duration=60, deadline=1200),
            Work(id="part2", title="Part 2", duration=60, deadline=1200, depends_on=["part1"])];
    choice = make_choice("deadline", work, [], 480, 1320);
    assert validate(choice.slots, work, [], 480, 1320);
    assert len(choice.slots) == 2;
    p1_end = [s.end for s in choice.slots if s.task_id == "part1"][0];
    p2_start = [s.start for s in choice.slots if s.task_id == "part2"][0];
    assert p1_end <= p2_start;
}

test "dependent work stays unplaced when its active prerequisite cannot fit" {
    work = [Work(id="part1", title="Part 1", duration=180, deadline=600),
            Work(id="part2", title="Part 2", duration=60, deadline=720, depends_on=["part1"])];
    choice = make_choice("deadline", work, [], 480, 720);
    assert "part1" in choice.unplaced;
    assert "part2" in choice.unplaced;
    assert len(choice.slots) == 0;
}

test "cyclic dependencies remain visible as unplaced work" {
    work = [Work(id="a", title="A", duration=30, deadline=720, depends_on=["b"]),
            Work(id="b", title="B", duration=30, deadline=720, depends_on=["a"])];
    choice = make_choice("deadline", work, [], 480, 720);
    assert "a" in choice.unplaced;
    assert "b" in choice.unplaced;
    assert len(choice.slots) == 0;
}

test "validation rejects a child without its active prerequisite slot" {
    work = [Work(id="a", title="A", duration=30, deadline=720),
            Work(id="b", title="B", duration=30, deadline=720, depends_on=["a"])];
    slots = [Slot(task_id="b", start=480, end=510)];
    assert not validate(slots, work, [], 480, 720);
}
