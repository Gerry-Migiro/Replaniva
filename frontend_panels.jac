"""Focused planner panels with explicit data and action callbacks."""

import from .date_labels { day_label }
import from react { useEffect }
import from endpoints { PlannerMonth, NotificationView, BreakdownProposal }
import from studio { UiIcon }


def use_modal(id: str, opener_id: str = "", focus_id: str = "") -> None {
    useEffect(lambda {
        popup: any = document.getElementById(id);
        if not popup { return; }
        opener: any = document.getElementById(opener_id) if opener_id else document.activeElement;
        previous: str = document.body.style.overflow;
        popup.showModal();
        document.body.style.overflow = "hidden";
        target: any = document.getElementById(focus_id) if focus_id else None;
        if target { target.focus(); }
        return lambda { popup.close(); document.body.style.overflow = previous; if opener and opener.isConnected { opener.focus(); } };
    }, []);
}

def:pub WorkspaceDialog(dialog_id: str, title: str, onClose: any, children: any = None, focus_id: str = "") -> JsxElement {
    use_modal(dialog_id, focus_id=focus_id);
    return <dialog id={dialog_id} className="workspace-modal" aria-labelledby={dialog_id + "-title"} onCancel={lambda (e: any) -> None { e.preventDefault(); onClose(); }}>
        <header className="workspace-modal-heading"><h2 id={dialog_id + "-title"}>{title}</h2><button className="icon-button" type="button" aria-label={"Close " + title} onClick={lambda -> None { onClose(); }}><span aria-hidden="true">×</span></button></header>
        <div className="workspace-modal-body">{children}</div>
    </dialog>;
}

def:pub PlanningCalendar(planner_month: PlannerMonth | None, selected_day: str, busy: bool, month_busy: bool, month_error: str, load_month: any, switch_day: any, open_page: any, open_workspace: any, ask_shortcut: any) -> JsxElement {
    days = planner_month.days if planner_month else [];
    # Keep every week containing this month's dates, without empty trailing weeks.
    while len(days) > 28 and not any(day.in_month for day in days[-7:]) {
        days = days[:-7];
    }
    return <section className="studio-card month-panel" aria-labelledby="month-title">
                        <div className="card-kicker"><span>YOUR PLANNING CALENDAR</span><UiIcon name="calendar-days" /></div>
                        <div className="month-heading"><h2 id="month-title">{planner_month.label if planner_month else "Your calendar"}</h2><div className="month-navigation"><button type="button" aria-label="Previous month" disabled={month_busy or not planner_month} onClick={lambda -> None { if planner_month { load_month(planner_month.previous); } return; }}>‹</button><button type="button" aria-label="Next month" disabled={month_busy or not planner_month} onClick={lambda -> None { if planner_month { load_month(planner_month.following); } return; }}>›</button></div></div>
                        {month_error and <div className="month-error" role="status"><p>{month_error}</p><button className="button secondary" type="button" disabled={month_busy} onClick={lambda -> None { load_month(selected_day); return; }}>Retry calendar</button></div>}
                        <div className="month-status" role="status">{"Loading calendar…" if month_busy else "Select a date to open its plan."}</div>
                        {planner_month and <div className="month-calendar" aria-label={planner_month.label}>
                            <div className="month-weekdays" aria-hidden="true">{[<span key={str(index)}>{["M", "T", "W", "T", "F", "S", "S"][index]}</span> for index in range(7)]}</div>
                            <div className="month-dates">{[<button type="button" key={day.day} className={"month-date " + ("other-month " if not day.in_month else "") + ("has-work " if day.tasks + day.commitments > 0 else "") + ("has-deadline " if day.deadlines > 0 else "")} aria-pressed={day.day == selected_day} aria-current={"date" if day.day == planner_month.today else None} aria-label={day_label(day.day) + ": " + str(day.tasks) + " tasks, " + str(day.commitments) + " commitments, " + str(day.deadlines) + " outstanding deadlines"} disabled={busy or month_busy} onClick={lambda -> None { switch_day(day.day); return; }}><span>{str(day.number)}</span><span className="month-markers" aria-hidden="true">{day.tasks > 0 and <i className="task-marker"></i>}{day.commitments > 0 and <i className="commitment-marker"></i>}{day.deadlines > 0 and <i className="deadline-marker"></i>}</span></button> for day in days]}</div>
                            <div className="month-footer"><button type="button" disabled={busy or month_busy} onClick={lambda -> None { if planner_month { switch_day(planner_month.today); } return; }}>Back to today</button><span>{day_label(selected_day)}</span></div>
                            <p className="month-legend"><span><i className="task-marker"></i>Tasks</span><span><i className="commitment-marker"></i>Fixed</span><span><i className="deadline-marker"></i>Due</span></p>
                        </div>}
                        <div className="planning-toolbox"><h3>Planning tools</h3><div className="tool-grid">
                            <button type="button" onClick={lambda -> None { open_page("capture"); }}><span><UiIcon name="plus" /></span>Capture</button>
                            <button type="button" onClick={lambda -> None { open_page("recovery"); }}><span><span className="recovery-glyph" aria-hidden="true">↝</span></span>Recover</button>
                            <button type="button" onClick={lambda -> None { open_workspace("goals"); }}><span><UiIcon name="target" /></span>Goals</button>
                            <button type="button" onClick={lambda -> None { open_workspace("outlook"); }}><span><UiIcon name="calendar-days" /></span>Week</button>
                            <button type="button" onClick={lambda -> None { ask_shortcut("What is at risk?"); }}><span><UiIcon name="shield-check" /></span>Risks</button>
                            <button type="button" onClick={lambda -> None { ask_shortcut("Can I finish everything today?"); }}><span><UiIcon name="chart-no-axes-combined" /></span>Capacity</button>
                        </div></div>
                    </section>;
}

def:pub NotificationInbox(inbox: list[NotificationView], busy: bool, secretary_error: str, load_inbox: any, notification_action: any, onClose: any, onViewDay: any, adjust_followup: any, complete_followup: any) -> JsxElement {
    use_modal("notification-dialog");
    return <dialog id="notification-dialog" className="breakdown-card notification-dialog" aria-labelledby="notification-title" onCancel={lambda (e: any) { e.preventDefault(); onClose(); }}><div className="breakdown-header"><div><span className="eyebrow">YOUR SECRETARY</span><h2 id="notification-title">Planning notifications</h2></div><button className="icon-button" type="button" aria-label="Close notifications" onClick={lambda -> None { onClose(); }}>×</button></div>
                {secretary_error and <p role="status">{secretary_error}</p>}
                <button className="button secondary" type="button" onClick={lambda -> None { load_inbox(); return; }}>Refresh notifications</button>
                {len(inbox) == 0 and <p className="empty-state">You are all caught up. Enable your secretary in Settings → Assistant for proactive checks.</p>}
                {[<article className="notification-item" key={item.id}><span className="eyebrow">{item.kind}</span><h3>{item.title}</h3><p>{item.message}</p><time dateTime={item.day}>{day_label(item.day)}</time><div className="notification-actions">
                    {not item.read and <button className="button secondary" type="button" onClick={lambda -> None { notification_action(item.id, "read"); return; }}>Mark read</button>}
                    <button className="button secondary" type="button" onClick={lambda -> None { notification_action(item.id, "snooze"); return; }}>Snooze 15 min</button><button className="button secondary" type="button" onClick={lambda -> None { notification_action(item.id, "dismiss"); return; }}>Dismiss</button>
                    {item.task_id and <button className="button secondary" type="button" onClick={lambda -> None { onViewDay(item.day); return; }}>View task day</button>}
                    {item.kind == "followup" and <button className="button secondary" type="button" onClick={lambda -> None { notification_action(item.id, "snooze"); return; }}>Still working</button>}
                    {item.kind == "followup" and <button className="button primary" type="button" disabled={busy} onClick={lambda -> None { adjust_followup(item.day); return; }}>Help me adjust</button>}
                    {item.kind == "followup" and <button className="button secondary" type="button" disabled={busy} onClick={lambda -> None { complete_followup(item.id, item.task_id); return; }}>Done</button>}
                </div></article> for item in inbox]}
            </dialog>;
}

def:pub BreakdownDialog(breakdown_proposal: BreakdownProposal, busy: bool, breakdown_error: str, cancel_breakdown: any, change_breakdown_title: any, change_breakdown_duration: any, remove_breakdown_step: any, confirm_breakdown: any) -> JsxElement {
    use_modal("breakdown-dialog", "breakdown-open-" + breakdown_proposal.task_id);
    return <dialog id="breakdown-dialog" className="breakdown-card" aria-labelledby="breakdown-title" aria-describedby="breakdown-description" onCancel={lambda (e: any) { e.preventDefault(); cancel_breakdown(); }}>
                                    <div className="breakdown-header"><div>
                                        <span className="eyebrow">TASK BREAKDOWN</span>
                                        <h2 id="breakdown-title">Break down your task</h2><p className="breakdown-task-name">{breakdown_proposal.original_title}</p></div><button className="icon-button" type="button" aria-label="Close task breakdown" disabled={busy} onClick={cancel_breakdown}>×</button>
                                    </div>
                                    <p id="breakdown-description" className="form-note">Review every step before applying. The total must preserve the original task time, rounded up to 15 minutes.</p>
                                    <ol className="breakdown-subtasks">
                                        {[<li key={str(idx)} className="breakdown-subtask-row">
                                            <span className="breakdown-step-num" aria-hidden="true">{str(idx + 1)}</span>
                                            <div className="breakdown-title-field">
                                                <label htmlFor={"breakdown-title-" + str(idx)}><span className="sr-only">Step {str(idx + 1)} </span>Description</label>
                                                <textarea id={"breakdown-title-" + str(idx)} className="breakdown-step-title" rows={2} value={breakdown_proposal.subtasks[idx].title} disabled={busy} maxLength={120}
                                                    onChange={lambda (e: ChangeEvent) { change_breakdown_title(idx, e.target.value); }}></textarea>
                                            </div>
                                            <div className="breakdown-duration-field">
                                                <label htmlFor={"breakdown-duration-" + str(idx)}><span className="sr-only">Step {str(idx + 1)} </span>Minutes</label>
                                                <input id={"breakdown-duration-" + str(idx)} className="breakdown-step-duration" type="number" disabled={busy} min="15" max="600" step="15" value={str(breakdown_proposal.subtasks[idx].duration)}
                                                    onChange={lambda (e: ChangeEvent) { change_breakdown_duration(idx, e.target.value); }}/>
                                            </div>
                                            <button type="button" className="danger-link" disabled={busy or len(breakdown_proposal.subtasks) <= 2}
                                                aria-label={"Remove step " + str(idx + 1)} onClick={lambda -> None { remove_breakdown_step(idx); return; }}>Remove</button>
                                        </li> for idx in range(len(breakdown_proposal.subtasks))]}
                                    </ol>
                                    {breakdown_error and <p className="breakdown-error" role="alert">{breakdown_error}</p>}
                                    <p className="breakdown-total" aria-live="polite">Total: {str(sum([item.duration for item in breakdown_proposal.subtasks]))} minutes</p>
                                    <div className="breakdown-card-actions">
                                        <button type="button" className="button primary small" disabled={busy} onClick={lambda -> None { confirm_breakdown(); return; }}>Apply breakdown</button>
                                        <button type="button" className="button secondary small" disabled={busy} onClick={lambda -> None { cancel_breakdown(); return; }}>Cancel</button>
                                    </div>
                                </dialog>;
}

def:pub VoicePanel(listening: bool, voice_supported: bool, voice_error: str, start_listening: any) -> JsxElement {
    return <section className={"voice-panel is-listening" if listening else "voice-panel"} aria-labelledby="voice-heading"><div className="voice-orbits" aria-hidden="true"></div><button className="voice-core" type="button" aria-label={"Stop voice input" if listening else "Start voice input"} aria-pressed={listening} onClick={start_listening}><UiIcon name={"square" if listening else "mic"} /></button><h2 id="voice-heading">{"I’m listening..." if listening else "A thought away."}</h2><p className={"voice-error" if voice_error else ""} role="status">{voice_error if voice_error else "Your words appear in the message above. Stop to review." if listening else "Tap to speak, or type your message above." if voice_supported else "Voice is unavailable here. Type above instead."}</p></section>;
}
