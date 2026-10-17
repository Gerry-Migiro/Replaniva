"""A card-specific guided tour over real planning screens."""
import from studio { UiIcon }

obj TourStop { has title: str, copy: str, page: str, target: str, settings: str = ""; }
glob stops: list[TourStop] = [
    TourStop(title="Choose the day you are planning", copy="Use the month arrows, select a marked date, or return to today. Dots mark saved work; deadline markers show unfinished work due that day. Selecting a day never moves a task.", page="today", target=".month-panel"),
    TourStop(title="Your next step, with a reason", copy="This card chooses a useful next action from your actual schedule, capacity and deadlines. Why this step explains the decision. Open Command to ask a question or review a proposed change.", page="today", target=".assistant-overview"),
    TourStop(title="Read the saved schedule", copy="Fixed commitments keep their times. Flexible work is placed by the scheduler. Complete or reopen work here, or review smaller steps with Break down. Unplaced work remains visible.", page="today", target=".timeline-panel"),
    TourStop(title="Understand capacity before adding more", copy="Available time, remaining work and pressure are calculated from this day's saved plan and planning hours. Why this assessment explains the health result.", page="today", target=".health-panel"),
    TourStop(title="Ask in Command, even without a model", copy="Next action, risks, capacity, plan summaries and structured recovery guidance work without model assistance. Suggestions fill the input; edit and send them yourself. Use the offline help link for examples.", page="command", target=".command-suggestion-list"),
    TourStop(title="Type or speak, then review", copy="The conversation and microphone belong together. Voice writes into the message field. Check the transcript before sending. A proposal never changes your plan until you accept it.", page="command", target=".command-composer"),
    TourStop(title="Capture flexible work", copy="Confirm the planning day, enter a task, its duration and deadline, then choose a priority. Optional dates and preferred time give the planner boundaries. The summary shows exactly what you are saving.", page="capture", target="#task-capture-card"),
    TourStop(title="Protect a fixed commitment", copy="Use this form for meetings, appointments or other times that cannot move. Check both times and the weekday before saving. For a new disruption, Recovery lets you compare changes first.", page="capture", target="#fixed-capture-card"),
    TourStop(title="Preview a disruption safely", copy="Enter what changed and its start and end times. Structured fields work without a model. Interpreting a note and a model-assisted alternative are optional. Explore recovery creates a preview, not a saved commitment.", page="recovery", target="#recovery-capture-card"),
    TourStop(title="Compare, approve, or keep your plan", copy="After previewing, the comparison shows protected commitments, moved tasks and work that cannot fit. Choose an option only after reviewing it. Discard keeps the saved plan; restore is validated against the latest revision.", page="recovery", target="#recovery-comparison"),
    TourStop(title="Settings stays within reach", copy="The left menu stays in view while the right panel scrolls. Choose Workspace, Planning, Connections, Assistant or Privacy. Each action reports its result where you are working.", page="settings", target=".settings-sidebar", settings="workspace"),
    TourStop(title="Set realistic planning boundaries", copy="Day starts and Day ends define the flexible-work window. Saving validates and rebuilds the affected days. Fixed commitments stay protected and unplaceable work remains visible.", page="settings", target=".planning-window", settings="planning"),
    TourStop(title="Check and configure your secretary", copy="Save the reminder settings you want. Check my plan now evaluates the saved graph and reports its result beside the button. Notifications can be opened from the bell; remembered preferences need approval.", page="settings", target=".secretary-settings-card", settings="assistant"),
    TourStop(title="One plan across your interfaces", copy="Mobile and CLI are separate views. The mobile app uses the same private planning service. The CLI accepts real planning commands, requires approval for proposed mutations and never exposes a system shell.", page="interfaces", target=".interface-controls")
];
def:pub tour_count() -> int { return len(stops); }
def:pub tour_title(step: int) -> str { return stops[step].title; }
def:pub tour_copy(step: int) -> str { return stops[step].copy; }
def:pub tour_page(step: int) -> str { return stops[step].page; }
def:pub tour_target(step: int) -> str { return stops[step].target; }
def:pub tour_settings(step: int) -> str { return stops[step].settings; }

def:pub GuidedTour(tour_step: int, narration_supported: bool, tour_audio: bool, speaking: bool, tour_key: any, close_tour: any, speak_tour: any, previous_tour_step: any, next_tour_step: any, placement: any = None, highlight: any = None) -> JsxElement {
    return <div className="tour-layer" aria-live="polite">
        {highlight and <div className="tour-highlight" style={highlight} aria-hidden="true"></div>}
        <aside className="tour-coach" style={placement} role="dialog" aria-modal="true" aria-labelledby="tour-title" aria-describedby="tour-copy" onKeyDown={tour_key}>
            <div className="tour-top"><span className="tour-avatar" aria-hidden="true">R</span><div><span className="eyebrow">REPLANIVA GUIDE</span><small>Step {str(tour_step + 1)} of {str(tour_count())}</small></div><button className="tour-close" type="button" aria-label="Close guided tour" onClick={lambda -> None { close_tour(); return; }}>×</button></div>
            <div className="tour-progress" aria-hidden="true">{[<span className={"done" if idx <= tour_step else ""} key={str(idx)}></span> for idx in range(tour_count())]}</div>
            <h2 id="tour-title">{tour_title(tour_step)}</h2><p id="tour-copy">{tour_copy(tour_step)}</p>
            <button className="button secondary tour-speak" type="button" disabled={not narration_supported} onClick={speak_tour}><UiIcon name={"volume-x" if tour_audio and speaking else "volume-2"} />{"Stop reading" if tour_audio and speaking else "Speak this step"}</button>
            <div className="tour-actions"><button className="text-button" type="button" onClick={lambda -> None { close_tour(); return; }}>Skip tour</button><div>{tour_step > 0 and <button className="button secondary" type="button" onClick={previous_tour_step}>Back</button>}<button className="button primary" type="button" onClick={lambda -> None { next_tour_step(); return; }}>{"Finish" if tour_step == tour_count() - 1 else "Next"}<span>→</span></button></div></div>
        </aside>
    </div>;
}
