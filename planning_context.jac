"""One validated, account-owned graph snapshot per planning operation."""

import from planning { Work, Busy }
import from .secretary {
    PlanningTask, PlanningGoal, PlanningCommitment, private_account,
    sync_planning_graph, secretary_work
}

obj PlanningSnapshot {
    has owner: str, tasks: list[PlanningTask], goals: list[PlanningGoal],
        commitments: list[PlanningCommitment], work_by_day: dict[str, list[Work]],
        busy_by_day: dict[str, list[Busy]];
    def check_owner() -> None {
        private_account();
        if self.owner != jid(root) { raise PermissionError("The planning snapshot belongs to another account."); }
    }
    def work(day: str) -> list[Work] {
        self.check_owner();
        return list(self.work_by_day.get(day, []));
    }
    def busy(day: str) -> list[Busy] {
        self.check_owner();
        return list(self.busy_by_day.get(day, []));
    }
}

def prepare_planning() -> PlanningSnapshot {
    private_account();
    errors = sync_planning_graph();
    if errors { raise ValueError("Planning relationships need attention: " + " ".join(errors)); }
    children = list([root -->]);
    tasks = [item for item in children if isinstance(item, PlanningTask)];
    commitments = [item for item in children if isinstance(item, PlanningCommitment)];
    work_by_day: dict[str, list[Work]] = {};
    busy_by_day: dict[str, list[Busy]] = {};
    for task in tasks {
        if not task.done {
            if task.day not in work_by_day { work_by_day[task.day] = []; }
            work_by_day[task.day].append(secretary_work(task, task.day));
        }
    }
    for item in commitments {
        if item.day not in busy_by_day { busy_by_day[item.day] = []; }
        busy_by_day[item.day].append(Busy(title=item.title, start=item.start, end=item.end));
    }
    return PlanningSnapshot(owner=jid(root),
        tasks=tasks,
        goals=[item for item in children if isinstance(item, PlanningGoal)],
        commitments=commitments, work_by_day=work_by_day, busy_by_day=busy_by_day);
}
