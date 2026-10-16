"""Secretary settings form, preference review and model allowance display."""

import from react { useEffect }
import from endpoints {
    SecretaryPreferences, PreferenceView, ServerConnectionView,
    secretary_settings, secretary_update_settings, secretary_preferences,
    secretary_decide_preference, secretary_forget_focus, secretary_propose_focus,
    secretary_check_now
}
import from studio { UiIcon }
import from .frontend_format { clock_time, time_minutes }

def:pub AssistantSettings(connections: ServerConnectionView, alerts_active: bool, onNotice: any, onInboxChanged: any, onAlerts: any) -> JsxElement {
    has secretary_prefs: SecretaryPreferences | None = None, secretary_error: str = "",
        focus_suggestions: list[PreferenceView] = [], focus_choice: str = "morning", preference_busy: bool = False,
        secretary_enabled: bool = False, secretary_zone: str = "Africa/Nairobi", secretary_morning: str = "08:00",
        secretary_quiet_start: str = "22:00", secretary_quiet_end: str = "08:00", secretary_lead: int = 15,
        secretary_busy: bool = False, browser_alerts: bool = alerts_active;
    async def load_secretary() -> None {
        try {
            prefs = await secretary_settings();
            secretary_prefs = prefs;
            secretary_enabled = prefs.enabled;
            secretary_zone = prefs.timezone;
            if not prefs.enabled {
                win: any = window;
                secretary_zone = win.Intl.DateTimeFormat().resolvedOptions().timeZone or prefs.timezone;
            }
            secretary_morning = clock_time(prefs.morning);
            secretary_quiet_start = clock_time(prefs.quiet_start);
            secretary_quiet_end = clock_time(prefs.quiet_end);
            secretary_lead = prefs.lead;
            focus_choice = prefs.focus_period or "morning";
            focus_suggestions = await secretary_preferences();
        } except Exception { secretary_error = "Secretary settings could not load. Try again."; }
    }

    async def save_secretary(e: FormEvent) -> None {
        e.preventDefault();
        secretary_busy = True;
        secretary_error = "";
        try {
            result = await secretary_update_settings(enabled=secretary_enabled, timezone_name=secretary_zone,
                morning=time_minutes(secretary_morning), quiet_start=time_minutes(secretary_quiet_start),
                quiet_end=time_minutes(secretary_quiet_end), lead=secretary_lead);
            onNotice(result.message);
            if not result.ok { secretary_error = result.message; }
            await load_secretary();
            await onInboxChanged();
        } except Exception { secretary_error = "Settings could not be confirmed. Reload the status before retrying."; }
        finally { secretary_busy = False; }
    }

    async def enable_browser_alerts() -> None {
        win: any = window;
        if not win.Notification { secretary_error = "Browser alerts are unavailable here. Your inbox still works."; return; }
        permission = await win.Notification.requestPermission();
        browser_alerts = permission == "granted";
        onAlerts(browser_alerts);
        secretary_error = "" if browser_alerts else "Browser alerts were not enabled. Your inbox still works.";
    }

    async def preference_action(id: str, accept: bool) -> None {
        try {
            result = await secretary_decide_preference(suggestion_id=id, accept=accept);
            onNotice(result.message);
            await load_secretary();
        } except Exception { secretary_error = "The update could not be confirmed. Reload the status before retrying."; }
    }

    async def review_focus_change() -> None {
        preference_busy = True;
        secretary_error = "";
        try {
            result = await secretary_propose_focus(period=focus_choice);
            onNotice(result.message);
            if not result.ok { secretary_error = result.message; }
            focus_suggestions = await secretary_preferences();
        } except Exception { secretary_error = "The preference could not be prepared. Your approved preference was not changed."; }
        finally { preference_busy = False; }
    }

    async def check_secretary() -> None {
        try {
            result = await secretary_check_now();
            onNotice(result.message);
            await onInboxChanged();
        } except Exception { secretary_error = "The update could not be confirmed. Reload the status before retrying."; }
    }

    async def forget_focus() -> None {
        try {
            result = await secretary_forget_focus();
            onNotice(result.message);
            await load_secretary();
        } except Exception { secretary_error = "The update could not be confirmed. Reload the status before retrying."; }
    }
    useEffect(lambda { load_secretary(); return; }, []);
    return <div className="settings-stack">
                            <article className="settings-card"><div className="settings-card-head"><div><UiIcon name="bell" /><h2>Your planning secretary</h2></div></div>
                                <p>Briefings, reminders and follow-ups use your saved plan. Keep this service running. No model is called by scheduled checks.</p>
                                {secretary_error and <p className="calendar-feedback" role="status">{secretary_error}</p>}
                                <form className="secretary-settings-form" onSubmit={save_secretary}>
                                    <label className="calendar-check"><input type="checkbox" aria-describedby="secretary-enable-help" checked={secretary_enabled} onChange={lambda (e: ChangeEvent) { secretary_enabled = e.target.checked; }} /><span className="check-copy">Enable proactive secretary<small id="secretary-enable-help">Applied when you save settings.</small></span></label>
                                    <label htmlFor="secretary-zone">Confirm your timezone</label><input id="secretary-zone" value={secretary_zone} required={True} onChange={lambda (e: ChangeEvent) { secretary_zone = e.target.value; }} />
                                    <div className="field-pair"><div><label htmlFor="secretary-morning">Morning briefing</label><input id="secretary-morning" type="time" required={True} value={secretary_morning} onChange={lambda (e: ChangeEvent) { secretary_morning = e.target.value; }} /></div><div><label htmlFor="secretary-lead">Reminder lead</label><select id="secretary-lead" value={str(secretary_lead)} onChange={lambda (e: ChangeEvent) { secretary_lead = int(e.target.value); }}>{[<option value={str(value)} key={str(value)}>{str(value)} minutes</option> for value in [5, 15, 30, 60]]}</select></div></div>
                                    <div className="field-pair"><div><label htmlFor="secretary-quiet-start">Quiet hours start</label><input id="secretary-quiet-start" type="time" value={secretary_quiet_start} onChange={lambda (e: ChangeEvent) { secretary_quiet_start = e.target.value; }} /></div><div><label htmlFor="secretary-quiet-end">Quiet hours end</label><input id="secretary-quiet-end" type="time" value={secretary_quiet_end} onChange={lambda (e: ChangeEvent) { secretary_quiet_end = e.target.value; }} /></div></div>
                                    <button className="button primary" type="submit" disabled={secretary_busy}>Save secretary settings</button>
                                </form>
                                <p className="connection-help">{"Background job registered" if secretary_prefs and secretary_prefs.job_id else "No background job enabled"}. Browser alerts need an open supported browser; the inbox remains available without them.</p>
                                <div className="calendar-actions"><button className="button secondary" type="button" onClick={enable_browser_alerts}>{"Browser alerts enabled for this session" if browser_alerts else "Enable browser alerts"}</button><button className="button secondary" type="button" onClick={check_secretary}>Check my plan now</button></div>
                                <div className="setting-group"><h3>Approved focus preference</h3><p>{secretary_prefs.focus_period if secretary_prefs and secretary_prefs.focus_period else "Nothing remembered yet."}</p>
                                    <label htmlFor="focus-period">Preferred focus period</label><select id="focus-period" value={focus_choice} disabled={preference_busy} onChange={lambda (e: ChangeEvent) { focus_choice = e.target.value; }}><option value="morning">Morning</option><option value="afternoon">Afternoon</option><option value="evening">Evening</option></select>
                                    <p className="connection-help">Choose a period, then review and confirm the change. Remembering a preference does not move saved work.</p><div className="calendar-actions"><button className="button secondary" type="button" disabled={preference_busy} onClick={review_focus_change}>Review preference change</button>{secretary_prefs and secretary_prefs.focus_period and <button className="button secondary" type="button" onClick={forget_focus}>Forget focus preference</button>}</div></div>
                                {[<div className="preference-review" key={item.id}><p>{item.message}</p><button className="button primary" type="button" onClick={lambda -> None { preference_action(item.id, True); return; }}>Remember this</button><button className="button secondary" type="button" onClick={lambda -> None { preference_action(item.id, False); return; }}>No thanks</button></div> for item in focus_suggestions]}
                            </article>
                            <article className="settings-card integration-card">
                                <div className="settings-card-head"><div><UiIcon name="layers" /><h2>Model usage</h2></div><span className="status-chip waiting">{ "A provider paused" if connections.model_paused else "Budget protected" }</span></div>
                                <p>{connections.model_label}</p>
                                <p>{str(connections.model_calls) + " model attempts today. " + str(connections.model_remaining) + " remaining in your daily application call allowance."}</p>
                                <p>{str(connections.model_units) + " of " + str(connections.model_unit_limit) + " reserved context and response allowance units."}</p>
                                <p className="connection-help">These are Replaniva limits, not your provider's remaining quota or exact token count. They reset at midnight UTC. Repeated unchanged requests can reuse a result for five minutes.</p>
                                <div className="secret-boundary"><span>SERVER CONFIGURATION</span><code>BYLLM_DEFAULT_MODEL</code><small>Provider keys stay in the server environment. A backup provider is optional and must be explicitly configured.</small></div>
                                <p className="connection-help">Gemini, Groq, OpenRouter and local Ollama models can be selected. Scheduling and approval remain available when model access is unavailable. Restart after changing server configuration.</p>
                            </article>

                        </div>;
}
