"""Recovery comparison views, without planning mutations."""

import from endpoints { TaskView, CommitmentView }
import from planning { Choice }

import from .frontend_format { clock_time, task_name, original_start, preview_style }

def:pub RecoveryMap(choice: Choice, tasks: list[TaskView], commitments: list[CommitmentView],
                    change_title: str, change_start: int, change_end: int,
                    day_start: int, day_end: int) -> JsxElement {
    interval = (day_end - day_start) // 4;
    <div className="recovery-map">
        <div className="map-title">
            <div><strong>Day shape</strong><span>Outlined work is the current plan. Solid work is the validated proposal.</span></div>
            <div className="map-legend"><span className="legend-current">Current</span><span className="legend-proposed">Proposed</span><span className="legend-fixed">Protected</span><span className="legend-change">New fixed</span></div>
        </div>
        <div className="schedule-axis" aria-hidden="true"><span></span><div><span>{clock_time(day_start)}</span><span>{clock_time(day_start + interval)}</span><span>{clock_time(day_start + interval * 2)}</span><span>{clock_time(day_start + interval * 3)}</span><span>{clock_time(day_end)}</span></div></div>
        <div className="schedule-lane">
            <span className="lane-label">Current</span>
            <div className="schedule-track" role="img" aria-label="Current saved schedule">
                {[<span className="schedule-block fixed-block" style={preview_style(item.start, item.end, day_start, day_end)} title={item.title} key={item.id}></span> for item in commitments]}
                {[<span className="schedule-block current-block" style={preview_style(task.start, task.start + task.duration, day_start, day_end)} title={task.title} key={task.id}></span> for task in tasks if task.start >= 0 and not task.done]}
            </div>
        </div>
        <div className="schedule-lane">
            <span className="lane-label">Simulation</span>
            <div className="schedule-track" role="img" aria-label="Validated simulated schedule">
                {[<span className="schedule-block fixed-block" style={preview_style(item.start, item.end, day_start, day_end)} title={item.title} key={item.id}></span> for item in commitments]}
                <span className="schedule-block change-block" style={preview_style(change_start, change_end, day_start, day_end)} title={change_title}></span>
                {[<span className="schedule-block proposed-block" style={preview_style(slot.start, slot.end, day_start, day_end)} title={task_name(tasks, slot.task_id)} key={slot.task_id}></span> for slot in choice.slots]}
            </div>
        </div>
    </div>
}

def:pub OptionCard(choice: Choice, tasks: list[TaskView], commitments: list[CommitmentView],
                   change_title: str, change_start: int, change_end: int,
                   day_start: int, day_end: int) -> JsxElement {
    <div className="option-body">
        <div className="option-stat"><strong>{len(commitments) + 1}</strong><span>fixed protected</span></div>
        <div className="option-stat"><strong>{len(choice.slots)}</strong><span>placed</span></div>
        <div className="option-stat"><strong>{choice.moved}</strong><span>moved</span></div>
        <div className="option-stat"><strong>{len(choice.unplaced)}</strong><span>deadline risks</span></div>
        <p className="option-source">{choice.source}</p>
        <p className="option-reason">{choice.reason}</p>
        <RecoveryMap choice={choice} tasks={tasks} commitments={commitments}
            change_title={change_title} change_start={change_start} change_end={change_end}
            day_start={day_start} day_end={day_end}/>
        <div className="option-slots">
            {[<div className="slot-shift" key={slot.task_id}>
                <span>{task_name(tasks, slot.task_id)}</span>
                <span className="slot-times">
                    {original_start(tasks, slot.task_id) >= 0 and original_start(tasks, slot.task_id) != slot.start and
                        <span className="ghost-time">{clock_time(original_start(tasks, slot.task_id))}</span>}
                    {original_start(tasks, slot.task_id) >= 0 and original_start(tasks, slot.task_id) != slot.start and <span className="flow-arrow">→</span>}
                    <strong>{clock_time(slot.start)}–{clock_time(slot.end)}</strong>
                </span>
            </div> for slot in choice.slots]}
            {[<div className="slot-unplaced" key={task_id}>
                <span>{task_name(tasks, task_id)}</span><strong>Needs a new day</strong>
            </div> for task_id in choice.unplaced]}
        </div>
    </div>
}
