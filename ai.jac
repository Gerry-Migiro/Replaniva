"""Optional bounded model suggestions. Jac validation always decides what can be shown."""

import from jaclang.byllm.lib { Model, MockLLM }
import from model_usage { configured_models, guarded_call }
import from planning { Work, Busy, Slot, Choice, validate, overlaps }

obj SuggestedStart {
    has task_id: str, start: int;
}
sem SuggestedStart.task_id = "An exact task ID from the supplied work list.";
sem SuggestedStart.start = "Start minute after midnight, in 15-minute increments.";

obj SuggestedPlan {
    has starts: list[SuggestedStart], explanation: str;
}
sem SuggestedPlan.starts = "One valid placement for every task in the work list.";
sem SuggestedPlan.explanation = "One plain-language sentence explaining the tradeoff.";

obj InterpretedDisruption {
    has title: str, start: int, end: int;
}
sem InterpretedDisruption.title = "A short name for the unexpected fixed commitment.";
sem InterpretedDisruption.start = "Start minute after midnight in the user's local time.";
sem InterpretedDisruption.end = "End minute after midnight in the user's local time.";

obj PlanningModel {
    has model: Model | MockLLM;
    def __repr__ -> str { return "Replaniva planning model"; }
    def interpret(note: str, day: str) -> InterpretedDisruption by self.model(
        temperature=0.1, max_tokens=200, max_output_retries=0,
        timeout=20, num_retries=0
    );
    def suggest(context: str, feedback: str) -> SuggestedPlan by self.model(
        temperature=0.2, max_tokens=700, max_output_retries=0,
        timeout=20, num_retries=0
    );
}
sem PlanningModel.interpret = "Extract one unexpected fixed commitment. Do not invent a time if it is not stated.";
sem PlanningModel.interpret.note = "The user's description of what changed.";
sem PlanningModel.interpret.day = "The local calendar day.";
sem PlanningModel.suggest = "Suggest a personal day plan preserving fixed commitments, durations, deadlines, dependencies, and every task. Return a structured result.";
sem PlanningModel.suggest.context = "Exact task IDs, durations, deadlines, current positions, dependencies, fixed times and day bounds.";
sem PlanningModel.suggest.feedback = "Validation problems from the previous suggestion.";

def model_runner(name: str) -> PlanningModel {
    params: dict[str, object] = {};
    if name.startswith("gemini/gemini-2.5-flash") {
        params["reasoning_effort"] = "none";
    }
    return PlanningModel(model=Model(model_name=name, call_params=params));
}

def validation_feedback(slots: list[Slot], work: list[Work], busy: list[Busy],
                        day_start: int, day_end: int) -> str {
    errors: list[str] = [];
    for item in work {
        found = [s for s in slots if s.task_id == item.id];
        if len(found) != 1 {
            errors.append(item.id + ": missing or repeated placement");
            continue;
        }
        slot = found[0];
        if slot.start < day_start or slot.end > day_end or slot.end > item.deadline or slot.start % 15 != 0 {
            errors.append(item.id + ": outside availability, deadline or 15-minute grid");
        }
        if [b for b in busy if overlaps(slot.start, slot.end, b.start, b.end)] or
           [s for s in slots if s.task_id != slot.task_id and overlaps(slot.start, slot.end, s.start, s.end)] {
            errors.append(item.id + ": overlaps another placement or fixed commitment");
        }
        for prereq in item.depends_on {
            if [s for s in slots if s.task_id == prereq and s.end > slot.start] {
                errors.append(item.id + ": starts before prerequisite finishes");
            }
        }
    }
    return ("Revise the rejected schedule: " + "; ".join(errors))[:1200];
}

def optional_model_choice(work: list[Work], busy: list[Busy],
                           day_start: int, day_end: int, scope: str = "local") -> Choice | None {
    models = configured_models();
    if not models or not work { return None; }
    context = str({"work": [{"id": w.id, "duration": w.duration, "deadline": w.deadline,
        "start": w.start, "priority": w.priority, "depends_on": w.depends_on} for w in work],
        "fixed": [{"start": b.start, "end": b.end} for b in busy],
        "day_start": day_start, "day_end": day_end});
    feedback = "";
    for attempt in range(2) {
        try {
            name = models[min(attempt, len(models) - 1)];
            runner = model_runner(name);
            suggestion = guarded_call(scope, name, "schedule:" + context + feedback,
                lambda -> SuggestedPlan { return runner.suggest(context, feedback); });
            if not isinstance(suggestion, SuggestedPlan) { continue; }
            slots: list[Slot] = [];
            for proposed in suggestion.starts {
                matches = [item for item in work if item.id == proposed.task_id];
                if len(matches) != 1 { break; }
                item = matches[0];
                slots.append(Slot(task_id=item.id, start=proposed.start,
                                  end=proposed.start + item.duration));
            }
            if len(slots) == len(work) and len({slot.task_id for slot in slots}) == len(work) and
               validate(slots, work, busy, day_start, day_end) {
                moved = len([slot for slot in slots for item in work
                             if item.id == slot.task_id and item.start >= 0 and item.start != slot.start]);
                return Choice(key="deadline", label="Protect deadlines", slots=slots,
                              moved=moved, reason=suggestion.explanation,
                              source=name + " suggested · Jac validated");
            }
            feedback = validation_feedback(slots, work, busy, day_start, day_end);
        } except Exception {
            continue;
        }
    }
    return None;
}

def optional_interpret_note(note: str, day: str, scope: str = "local") -> InterpretedDisruption | None {
    if not note.strip() { return None; }
    for name in configured_models() {
      try {
        runner = model_runner(name);
        draft = guarded_call(scope, name, "interpret:" + day + note,
            lambda -> InterpretedDisruption { return runner.interpret(note, day); });
        if not isinstance(draft, InterpretedDisruption) { continue; }
        if draft.title.strip() and draft.start >= 480 and draft.end <= 1320 and
           draft.end > draft.start {
            return draft;
        }
      } except Exception { }
    }
    return None;
}
