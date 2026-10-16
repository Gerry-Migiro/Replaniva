"""Guided tour presentation and copy."""

import from studio { UiIcon }

def:pub tour_title(step: int) -> str {
    if step == 0 { return "Start with Today"; }
    if step == 1 { return "Capture the plan"; }
    if step == 2 { return "Recover when life changes"; }
    return "Make Replaniva yours";
}

def:pub tour_copy(step: int) -> str {
    if step == 0 { return "Browse your month on the homepage. Highlighted dates have saved tasks or commitments; outlined dates mark outstanding deadlines. Select a date to see its plan and timeline. Open Command to type or speak with your planning secretary and review the transcript before sending. Restart this guide from Quick Guide at the top left of Today, or use Speak to hear each step."; }
    if step == 1 { return "Add flexible tasks and fixed commitments. Replaniva places work inside your planning boundaries."; }
    if step == 2 { return "Report a disruption, compare validated choices, and approve a recovery only when it feels right."; }
    return "Choose your appearance, planning hours, and connections in Settings. Return to the homepage for the guide. Calendar imports and exports still need your review and approval.";
}

def:pub tour_page(step: int) -> str {
    if step == 1 { return "capture"; }
    if step == 2 { return "recovery"; }
    if step == 3 { return "settings"; }
    return "today";
}

def:pub GuidedTour(tour_step: int, narration_supported: bool, tour_audio: bool, speaking: bool, tour_key: any, close_tour: any, speak_tour: any, previous_tour_step: any, next_tour_step: any) -> JsxElement {
    return <div className="tour-layer" aria-live="polite">
                <aside className="tour-coach" role="dialog" aria-modal="true" aria-labelledby="tour-title" aria-describedby="tour-copy" onKeyDown={tour_key}>
                    <div className="tour-top"><span className="tour-avatar" aria-hidden="true">R</span><div><span className="eyebrow">REPLANIVA GUIDE</span><small>Step {str(tour_step + 1)} of 4</small></div><button className="tour-close" type="button" aria-label="Close guided tour" onClick={lambda -> None { close_tour(); return; }}>×</button></div>
                    <div className="tour-progress" aria-hidden="true">{[<span className={"done" if idx <= tour_step else ""} key={str(idx)}></span> for idx in range(4)]}</div>
                    <h2 id="tour-title">{tour_title(tour_step)}</h2><p id="tour-copy">{tour_copy(tour_step)}</p>
                    <button className="button secondary tour-speak" type="button" disabled={not narration_supported} onClick={speak_tour}><UiIcon name={"volume-x" if tour_audio and speaking else "volume-2"} />{"Stop reading" if tour_audio and speaking else "Speak this step"}</button>
                    <div className="tour-actions"><button className="text-button" type="button" onClick={lambda -> None { close_tour(); return; }}>Skip tour</button><div>{tour_step > 0 and <button className="button secondary" type="button" onClick={previous_tour_step}>Back</button>}<button className="button primary" type="button" onClick={lambda -> None { next_tour_step(); return; }}>{"Finish" if tour_step == 3 else "Next"} <span>→</span></button></div></div>
                </aside>
            </div>;
}
