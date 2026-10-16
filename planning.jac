"""Stage 1 deterministic placement, implemented for the new Jac application."""
obj Work {
    has id: str,
        duration: int,
        deadline: int,
        priority: int = 2;
}

obj Block {
    has start: int,
        end: int;
}

obj Slot {
    has id: str,
        start: int,
        end: int;
}

obj Schedule {
    has slots: list[Slot] = [],
        unplaced: list[str] = [];
}

def overlaps(a: int, b: int, c: int, d: int) -> bool {
    return a < d and c < b;
}

def valid_schedule(
    slots: list[Slot], work: list[Work], fixed: list[Block], start: int, end: int
) -> bool {
    if start < 0 or end > 1440 or start >= end {
        return False;
    }
    seen: list[str] = [];
    for slot in slots {
        matches = [
            w
            for w in work
            if w.id == slot.id
        ];
        if len(matches) != 1 or slot.id in seen {
            return False;
        }
        w = matches[0];
        if w.duration < 15
            or slot.end - slot.start != w.duration
            or slot.start < start
            or slot.end > end
            or slot.end > w.deadline {
            return False;
        }
        if any([overlaps(slot.start, slot.end, b.start, b.end) for b in fixed]) {
            return False;
        }
        if any(
            [
                overlaps(slot.start, slot.end, s.start, s.end)
                for s in slots
                if s.id != slot.id
            ]
        ) {
            return False;
        }
        seen.append(slot.id);
    }
    return True;
}

def schedule(work: list[Work], fixed: list[Block], start: int, end: int) -> Schedule {
    result = Schedule();
    pending = [w for w in work];
    pending.sort(key=lambda (w: Work) { (w.deadline, -w.priority, w.id); });
    occupied = [Block(start=b.start, end=b.end) for b in fixed];
    for w in pending {
        candidate = start;
        occupied.sort(key=lambda (b: Block) { b.start; });
        for b in occupied {
            if b.end <= candidate {
                continue;
            }
            if candidate + w.duration <= b.start {
                break;
            }
            candidate = b.end;
        }
        if w.duration >= 15 and candidate + w.duration <= min(end, w.deadline) {
            result.slots.append(
                Slot(id=w.id, start=candidate, end=candidate + w.duration)
            );
            occupied.append(Block(start=candidate, end=candidate + w.duration));
        } else {
            result.unplaced.append(w.id);
        }
    }
    if not valid_schedule(result.slots, work, fixed, start, end) {
        raise ValueError("Schedule failed validation.");
    }
    return result;
}

test "fixed commitments and earliest deadlines bound work" {
    work = [
        Work(id="b", duration=60, deadline=720),
        Work(id="a", duration=45, deadline=600)
    ];
    fixed = [Block(start=510, end=540)];
    result = schedule(work, fixed, 480, 1020);
    assert len(result.slots) == 2;
    assert valid_schedule(result.slots, work, fixed, 480, 1020);
    assert result.slots[0].start == 540;
}

test "capacity and deadlines do not hide impossible work" {
    result = schedule([Work(id="long", duration=120, deadline=540)], [], 480, 600);
    assert result.unplaced == ["long"] and not result.slots;
}

test "overlap duplicate unknown and wrong duration fail validation" {
    work = [
        Work(id="a", duration=60, deadline=700),
        Work(id="b", duration=60, deadline=700)
    ];
    assert valid_schedule([Slot(id="a", start=480, end=540)], work, [], 480, 700);
    assert not valid_schedule(
        [Slot(id="a", start=480, end=540), Slot(id="b", start=510, end=570)],
        work,
        [],
        480,
        700
    );
    assert not valid_schedule(
        [Slot(id="a", start=480, end=540), Slot(id="a", start=540, end=600)],
        work,
        [],
        480,
        700
    );
    assert not valid_schedule(
        [Slot(id="unknown", start=480, end=540)], work, [], 480, 700
    );
    assert not valid_schedule([Slot(id="a", start=480, end=550)], work, [], 480, 700);
    assert not valid_schedule(
        [Slot(id="a", start=480, end=540)], work, [Block(start=500, end=520)], 480, 700
    );
    assert not valid_schedule([Slot(id="a", start=470, end=530)], work, [], 480, 700);
}

test "exact minute gaps outside hours and priority are handled" {
    work = [
        Work(id="a", duration=30, deadline=600, priority=1),
        Work(id="b", duration=30, deadline=600, priority=3)
    ];
    result = schedule(
        work, [Block(start=0, end=487), Block(start=547, end=1440)], 480, 600
    );
    assert result.slots[0].id == "b" and result.slots[0].start == 487;
    assert result.slots[1].end == 547;
}
