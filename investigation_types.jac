"""Read-only evidence gathered by a secretary graph traversal."""

obj InvestigatedTask {
    has id: str, title: str, day: str, done: bool,
        depends_on: list[str], goal_id: str;
}
obj InvestigatedGoal {
    has id: str, title: str, target_date: str, total: int = 0, completed: int = 0;
}
obj InvestigationContext {
    has tasks: list[InvestigatedTask] = [], goals: list[InvestigatedGoal] = [],
        integrity_ok: bool = True, complete: bool = True;
}
