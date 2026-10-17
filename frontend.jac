"""Replaniva's web experience."""

import from "@jac/runtime" { SignupResult, jacLogin, jacSignup, jacLogout, jacIsLoggedIn }
import from react { useEffect, useRef }
import from accounts { normalize_username }
import from endpoints { Board, Action, CommandReply, BreakdownProposal, preview_task_breakdown, apply_task_breakdown, get_board, get_planner_month, PlannerMonth, create_task, set_task_done, delete_task, create_commitment, delete_commitment, preview_recovery, dismiss_recovery, accept_recovery, restore_revision, interpret_disruption, update_planning_hours, update_tour_state, update_appearance, create_goal, toggle_goal, delete_goal, apply_command_proposal, dismiss_command_proposal, apply_rebalance_candidate, CalendarPreview, calendar_status, calendar_connect, calendar_finish, calendar_select, calendar_disconnect, calendar_create_export_calendar, calendar_preview_import, calendar_preview_export, calendar_approve, calendar_dismiss, SecretaryRunView, NotificationView, secretary_notifications, secretary_notification, secretary_run }

import from .date_labels { day_label }
import from .ui_theme { appearance_vars }
import from studio { UiIcon, CompanionVisual, CapacityOrbit }
import from .assistant { SubtaskDraft }

import from .frontend_speech { useSpeech }
import from .frontend_live { useSecretaryLive }
import from .frontend_command { CommandPanel }
import from .frontend_interfaces { InterfacesWorkspace }
import from .frontend_settings { AssistantSettings }
import from .frontend_format { clock_time, duration_label, pressure_style, workload_style, short_day, outlook_date_label, time_minutes, same_plan, timeline_for }
import from .frontend_recovery { OptionCard }
import from .frontend_tour { tour_title, tour_copy, tour_page, tour_count, tour_target, tour_settings, GuidedTour }
import from .frontend_panels { PlanningCalendar, NotificationInbox, BreakdownDialog, WorkspaceDialog }

def login_name(value: str) -> str {
    clean = value.strip().lower();
    if "@" in clean and len(clean) <= 254 and " " not in clean { return clean; }
    return normalize_username(value);
}

def:pub ClientApp -> JsxElement {
    has signed_in: bool = jacIsLoggedIn(), username: str = "", password: str = "",
        registering: bool = False, auth_error: str = "";

    useEffect(lambda {
        document.title = "Replaniva | Plans that adapt when life changes";
        icon: any = document.querySelector("link[rel='icon']");
        if icon is None {
            icon = document.createElement("link");
            icon.rel = "icon";
            head: any = document.head;
            head.appendChild(icon);
        }
        icon.type = "image/png";
        icon.href = "/static/assets/replaniva-favicon.png";
    }, []);

    async def authenticate(e: FormEvent) -> None {
        e.preventDefault();
        auth_error = "";
        if not login_name(username) or len(password) < 8 {
            auth_error = "Use a username of 3 to 32 letters, numbers, underscores or hyphens, and a password of at least eight characters.";
            return;
        }
        signup: SignupResult | None = None;
        ok: bool = False;
        identity = {"type": "username", "value": login_name(username)};
        try {
            if registering {
                signup = await jacSignup([identity], password);
                if not signup.success {
                    auth_error = signup.error if signup.error else "Account could not be created.";
                    return;
                }
            }
            ok = await jacLogin(identity, password);
            if ok { signed_in = True; }
            else { auth_error = "Those details did not work. Please try again."; }
        } except Exception {
            auth_error = "Connection failed. Please try again.";
        }
    }

    if signed_in {
        return <Planner onSignOut={lambda -> None { jacLogout(); signed_in = False; }} />;
    }
    return <div className="auth-screen">
        <div className="auth-orbit auth-orbit-one"></div>
        <div className="auth-orbit auth-orbit-two"></div>
        <div className="adaptive-mesh" aria-hidden="true">
            <div className="mesh-halo"></div>
            <div className="mesh-plane mesh-plane-back"></div>
            <div className="mesh-plane mesh-plane-front"></div>
            <div className="mesh-nodes"></div>
        </div>
        <div className="auth-shell">
            <div className="auth-story">
                <div className="brand brand-lockup" aria-label="Replaniva">
                    <img className="brand-logo-full" src="/static/assets/replaniva-logo.png" alt="" />
                </div>
                <p className="eyebrow">THE PLANNER THAT MOVES WITH YOU</p>
                <h1>Life changed.<br/><em>Your plan can too.</em></h1>
                <p className="lede">Capture what matters. See your day clearly. When plans shift, find a way forward that actually fits.</p>
                <div className="auth-preview">
                    <span className="pulse-dot"></span>
                    <span>Recovery Studio</span>
                    <span className="preview-line"></span>
                    <strong>BACK ON TRACK</strong>
                </div>
            </div>
            <div className="auth-card">
                <p className="eyebrow">WELCOME TO REPLANIVA</p>
                <h2>{"Make an account" if registering else "Good to have you back"}</h2>
                <p className="muted">Your plan stays private and ready when you return.</p>
                <form onSubmit={authenticate}>
                    <label htmlFor="username">Username</label>
                    <input id="username" type="text" autoComplete="username" required={True} value={username}
                        onChange={lambda (e: ChangeEvent) { username = e.target.value; }} placeholder="your_username" />
                    <label htmlFor="password">Password</label>
                    <input id="password" type="password" autoComplete={"new-password" if registering else "current-password"}
                        required={True} value={password}
                        onChange={lambda (e: ChangeEvent) { password = e.target.value; }} placeholder="At least 8 characters" />
                    {auth_error and <p className="form-error" role="alert">{auth_error}</p>}
                    <button className="button primary full" type="submit">{"Create account" if registering else "Sign in"}<span>→</span></button>
                </form>
                <button className="text-button" type="button" onClick={lambda -> None { registering = not registering; auth_error = ""; }}>
                    {"Already have an account? Sign in" if registering else "New here? Create an account"}
                </button>
            </div>
        </div>
    </div>;
}

def:pub Planner(onSignOut: any) -> JsxElement {
    has board: Board | None = None, notice: str = "", title: str = "",
        duration: int = 60, deadline: str = "20:00", task_due_day: str = "",
        preferred: str = "", priority: int = 2,
        fixed_title: str = "", fixed_start: str = "09:00", fixed_end: str = "10:00",
        disruption: str = "", disrupted_start: str = "14:00", disrupted_end: str = "17:00",
        change_note: str = "", selected_day: str = "", session_error: str = "",
        load_error: str = "", planning_start: str = "08:00", planning_end: str = "22:00",
        command_query: str = "", command_questions: list[str] = [], command_answers: list[CommandReply] = [],
        light: bool = False, busy: bool = False, model_schedule: bool = False,
        tour_audio: bool = False,
        planner_month: PlannerMonth | None = None, month_busy: bool = False, month_error: str = "", month_request: int = 0,
        goal_title: str = "", goal_target_date: str = "", goal_importance: str = "medium",
        breakdown_proposal: BreakdownProposal | None = None,
        breakdown_error: str = "",
        active_page: str = "today", interface_refresh: int = 0, interfaces_opened: bool = False,
        tour_step: int = -1, tour_checked: bool = False, tour_placement: any = {}, tour_highlight: any = {},
        appearance_checked: bool = False, command_focus: bool = False, jump_target: str = "",
        settings_section: str = "workspace", settings_focus: bool = False,
        calendar_state: any = None, calendar_busy: bool = False, calendar_feedback: str = "",
        calendar_selected: list[str] = [], calendar_tasks: list[str] = [],
        calendar_preview: CalendarPreview | None = None,
        secretary_last_run: SecretaryRunView | None = None,
        inbox: list[NotificationView] = [], inbox_open: bool = False, secretary_error: str = "",
        live_connected: bool = False, goal_dialog_open: bool = False, explanation_dialog: str = "",
        calendar_review_open: bool = False, planning_date_open: bool = False, planning_day_input: str = "", command_sources: list[str] = [];
    speech = useSpeech(lambda (text: str) -> None { command_query = text[:300]; });
    useEffect(lambda -> None {
        if active_page != "command" { speech.cancel(); }
    }, [active_page]);
    board_request: any = useRef(0);
    selected_day_ref: any = useRef("");
    selected_day_ref.current = selected_day;
    notification_memory: any = useRef(None);
    alerts_enabled: any = useRef(False);

    async def load_inbox() -> None {
        try {
            latest = await secretary_notifications();
            previous: any = notification_memory.current;
            new_items = [item for item in latest if not item.read and item.browser_allowed and (previous is not None and item.id not in previous)];
            inbox = latest;
            notification_memory.current = [item.id for item in latest];
            win: any = window;
            if alerts_enabled.current and new_items and win.Notification and win.Notification.permission == "granted" {
                notification_class: any = win.Notification;
                new(notification_class, "Replaniva", {"body": new_items[0].title if len(new_items) == 1 else str(len(new_items)) + " planning updates are ready in your inbox.", "tag": "replaniva-secretary"});
            }
        } except Exception { secretary_error = "Notifications could not load. Try again."; }
    }


    async def notification_action(id: str, action: str) -> None {
        try {
            result = await secretary_notification(notification_id=id, action=action);
            if not result.ok { secretary_error = result.message; }
            await load_inbox();
        } except Exception { secretary_error = "The notification could not be updated. Try again."; }
    }



    async def complete_followup(notification_id: str, task_id: str) -> None {
        if not window.confirm("Mark this task done?") { return; }
        busy = True;
        secretary_error = "";
        try {
            result = await set_task_done(task_id=task_id, done=True);
            notice = result.message;
            if result.ok {
                await refresh(selected_day);
                await notification_action(notification_id, "dismiss");
            } else { secretary_error = result.message; }
        } except Exception { secretary_error = "The task status could not be confirmed. Refresh before trying again."; }
        finally { busy = False; }
    }
    async def adjust_followup(day: str) -> None {
        inbox_open = False;
        try {
            await switch_day(day);
            ask_shortcut("What is at risk?");
        } except Exception { notice = "That task's day could not be opened. Please try again."; }
    }


    async def load_month(month: str = "") -> None {
        month_request += 1;
        request_id = month_request;
        month_busy = True;
        month_error = "";
        try {
            result: PlannerMonth = await get_planner_month(month=month);
            if request_id == month_request { planner_month = result; }
        } except Exception {
            if request_id == month_request { month_error = "Your calendar could not load. Try again."; }
        }
        if request_id == month_request { month_busy = False; }
    }

    async def refresh(day: str = "") -> None {
        board_request.current += 1;
        request_id = board_request.current;
        try {
            result: Board = await get_board(day=day if day else selected_day_ref.current);
            if request_id != board_request.current { return; }
            board = result;
            selected_day = result.day;
            planning_day_input = result.day;
            selected_day_ref.current = result.day;
            planning_start = clock_time(result.day_start);
            planning_end = clock_time(result.day_end);
            if not appearance_checked { light = result.light_mode; appearance_checked = True; }
            if not tour_checked {
                if not result.tour_completed { tour_step = 0; }
                tour_checked = True;
            }
            session_error = "";
            load_error = "";
            await load_month(result.day);
        } except Exception as error {
            if request_id != board_request.current { return; }
            failure: any = error;
            if not jacIsLoggedIn() or failure.status == 401 {
                session_error = "Sign in again to reopen your private plan.";
            } else { load_error = "Your plan could not load. Check the connection and try again."; }
        }
    }

    useSecretaryLive(lambda -> None { load_inbox(); refresh(selected_day_ref.current); return; }, lambda (connected: bool) -> None { live_connected = connected; });
    useEffect(lambda { load_inbox(); return; }, []);
    async can with entry {
        await refresh();
        if "calendar_return=1" in window.location.search {
            active_page = "settings";
            settings_section = "connections";
            try {
                win: any = window;
                stored: str = win.sessionStorage.getItem("replaniva-calendar") or "null";
                pending: any = JSON.parse(stored);
                win.sessionStorage.removeItem("replaniva-calendar");
                if pending {
                    outcome: Action = await calendar_finish(authorization_id=pending.flow, proof=pending.proof);
                    calendar_feedback = outcome.message;
                } else { calendar_feedback = "No connection was started in this browser tab. Connect Calendar again."; }
            } except Exception { calendar_feedback = "The connection could not be finished. Sign in to the account that started it and reconnect."; }
            window.history.replaceState(None, "", "/");
            await load_calendar();
        }
    }

    async def load_calendar() -> None {
        calendar_busy = True;
        if calendar_feedback == "Calendar status could not be loaded. Try again." { calendar_feedback = ""; }
        try {
            calendar_state = await calendar_status();
            calendar_selected = calendar_state.selected;
        } except Exception { calendar_feedback = "Calendar status could not be loaded. Try again."; }
        calendar_busy = False;
    }
    useEffect(lambda -> None { if active_page == "settings" and settings_section == "connections" { load_calendar(); return; } }, [active_page, settings_section]);

    async def connect_calendar() -> None {
        calendar_busy = True;
        try {
            connection: any = await calendar_connect();
            win: any = window;
            if window.location.origin != connection.origin {
                calendar_feedback = "Open Replaniva at " + connection.origin + " before connecting Calendar.";
            } else {
                win.sessionStorage.setItem("replaniva-calendar", JSON.stringify({"flow": connection.flow, "proof": connection.proof}));
                window.location.assign(connection.url);
            }
        } except Exception { calendar_feedback = "Check the server Calendar configuration and try connecting again."; }
        calendar_busy = False;
    }

    async def calendar_operation(kind: str) -> None {
        calendar_busy = True;
        calendar_feedback = "";
        try {
            if kind == "select" {
                outcome: Action = await calendar_select(selected=calendar_selected);
                calendar_feedback = outcome.message;
                calendar_preview = None;
            } elif kind == "disconnect" {
                if not window.confirm("Disconnect Google Calendar? Your saved plan and exported events will be kept.") { calendar_busy = False; return; }
                outcome = await calendar_disconnect();
                calendar_feedback = outcome.message;
                calendar_preview = None;
                calendar_tasks = [];
            } elif kind == "create" {
                outcome = await calendar_create_export_calendar();
                calendar_feedback = outcome.message;
            } elif kind == "import" {
                calendar_preview = await calendar_preview_import(first=selected_day);
                calendar_feedback = calendar_preview.message;
            } elif kind == "export" {
                calendar_preview = await calendar_preview_export(task_ids=calendar_tasks);
                calendar_feedback = calendar_preview.message;
            } elif calendar_preview and kind in ["approve", "dismiss"] {
                outcome = await calendar_approve(proposal_id=calendar_preview.id) if kind == "approve" else await calendar_dismiss(proposal_id=calendar_preview.id);
                calendar_feedback = outcome.message;
                if outcome.ok { calendar_preview = None; await refresh(); }
            }
            if kind in ["import", "export"] and calendar_preview and calendar_preview.ok { calendar_review_open = True; }
            await load_calendar();
        } except Exception { calendar_feedback = "Calendar could not complete that step. Your preview was not confirmed. Refresh the status and try again."; }
        finally { calendar_busy = False; }
    }

    useEffect(lambda {
        if tour_step < 0 { return; }
        win: any = window;
        def position_guide() -> None {
            target: any = document.querySelector(tour_target(tour_step));
            coach: any = document.querySelector(".tour-coach");
            if not target or not coach { return; }
            rect: any = target.getBoundingClientRect();
            width = min(390, win.innerWidth - 24);
            height = min(coach.offsetHeight, win.innerHeight - 24);
            top = max(100, min(rect.top, win.innerHeight - 100));
            tour_highlight = {"left": str(max(8, rect.left - 4)) + "px", "top": str(top - 4) + "px",
                "width": str(min(rect.width + 8, win.innerWidth - 16)) + "px",
                "height": str(min(rect.height + 8, 220, win.innerHeight - top - 12)) + "px"};
            left = rect.right + 18 if rect.right + width + 30 < win.innerWidth else 12 if rect.left > width + 30 else win.innerWidth - width - 12;
            coach_top = min(104 if top > win.innerHeight / 2 else max(12, win.innerHeight - height - 12), max(12, win.innerHeight - height - 12));
            tour_placement = {"left": str(left) + "px", "top": str(coach_top) + "px", "right": "auto", "bottom": "auto", "width": str(width) + "px"};
        }
        def reveal() -> None {
            target: any = document.querySelector(tour_target(tour_step));
            if target { target.scrollIntoView({"block": "start", "behavior": "instant"}); }
            position_guide();
            close_button: any = document.querySelector(".tour-close");
            if close_button { close_button.focus({"preventScroll": True}); }
        }
        timer = win.setTimeout(reveal, 120);
        win.addEventListener("resize", position_guide);
        win.addEventListener("scroll", position_guide, True);
        return lambda { win.clearTimeout(timer); win.removeEventListener("resize", position_guide); win.removeEventListener("scroll", position_guide, True); };
    }, [tour_step, active_page, settings_section]);

    def open_page(page: str) -> None {
        if page != active_page { notice = ""; }
        active_page = page;
        if page == "interfaces" { interfaces_opened = True; }
        goal_dialog_open = False;
        explanation_dialog = "";
        calendar_review_open = False;
        try { window.scrollTo({"top": 0, "behavior": "instant"}); } except Exception {}
    }

    useEffect(lambda -> None {
        try { window.scrollTo({"top": 0, "behavior": "instant"}); } except Exception {}
    }, [active_page]);

    def choose_settings(section: str) -> None {
        settings_section = section;
        settings_focus = True;
    }
    useEffect(lambda -> None {
        if active_page == "settings" and settings_focus {
            heading: any = document.getElementById("settings-view-title");
            if heading { heading.focus({"preventScroll": True}); panel: any = document.querySelector(".settings-main"); if panel { panel.scrollTop = 0; } }
            settings_focus = False;
        }
    }, [active_page, settings_section, settings_focus]);

    def ask_shortcut(query: str = "") -> None {
        if active_page != "command" { notice = ""; }
        active_page = "command";
        try { window.scrollTo({"top": 0, "behavior": "instant"}); } except Exception {}
        if query { command_query = query; }
        command_focus = True;
    }
    def open_workspace(target: str) -> None {
        if target == "command" { ask_shortcut(); return; }
        if target == "settings" { choose_settings("assistant"); open_page("settings"); return; }
        if target in ["capture", "recovery", "settings", "today", "interfaces"] { open_page(target); }
        else { open_page("today"); jump_target = "timeline" if target in ["plan", "schedule", "timeline"] else "outlook" if target in ["week", "outlook"] else "goals" if target in ["goal", "goals"] else "activity" if target == "activity" else "timeline"; }
    }
    useEffect(lambda -> None {
        if active_page == "command" and command_focus {
            field: any = document.querySelector("#plan-command");
            if field { field.focus({"preventScroll": True}); command_focus = False; }
        }
        if active_page == "today" and jump_target {
            destination: any = document.getElementById(jump_target);
            if destination { destination.scrollIntoView({"block": "start", "behavior": "auto"}); jump_target = ""; }
        }
    }, [active_page, command_focus, jump_target]);

    async def save_appearance(use_light: bool) -> None {
        previous = light;
        light = use_light;
        try {
            result: Action = await update_appearance(light_mode=use_light);
            if not result.ok {
                light = previous;
                notice = result.message;
            } else { interface_refresh += 1; await refresh(); }
        } except Exception {
            light = previous;
            notice = "Appearance could not be saved.";
        }
    }

    def speak_tour() -> None {
        if tour_audio and speech.speaking { speech.stop(); tour_audio = False; return; }
        tour_audio = True;
        speech.speak("Step " + str(tour_step + 1) + " of " + str(tour_count()) + ". " + tour_title(tour_step) + ". " + tour_copy(tour_step));
    }
    def start_tour() -> None {
        tour_step = 0;
        open_page("today");
    }

    async def close_tour() -> None {
        if tour_audio { speech.stop(); }
        tour_audio = False;
        tour_step = -1;
        main: any = document.getElementById("main");
        if main { main.focus(); }
        try { await update_tour_state(completed=True); } except Exception {}
    }

    def tour_key(e: any) -> None {
        if e.key == "Escape" { e.preventDefault(); close_tour(); return; }
        if e.key != "Tab" { return; }
        controls: any = document.querySelectorAll(".tour-coach button:not([disabled])");
        if controls.length == 0 { return; }
        if e.shiftKey and document.activeElement == controls[0] {
            e.preventDefault();
            controls[controls.length - 1].focus();
        } elif not e.shiftKey and document.activeElement == controls[controls.length - 1] {
            e.preventDefault();
            controls[0].focus();
        }
    }

    async def next_tour_step() -> None {
        if tour_step >= tour_count() - 1 {
            await close_tour();
            return;
        }
        if tour_audio { speech.stop(); }
        tour_audio = False;
        tour_step += 1;
        open_page(tour_page(tour_step));
        if tour_settings(tour_step) { settings_section = tour_settings(tour_step); }
    }

    def previous_tour_step() -> None {
        if tour_step <= 0 { return; }
        if tour_audio { speech.stop(); }
        tour_audio = False;
        tour_step -= 1;
        open_page(tour_page(tour_step));
        if tour_settings(tour_step) { settings_section = tour_settings(tour_step); }
    }

    async def perform_action(operation: any, on_success: any = None) -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await operation();
            notice = result.message;
            if result.ok and on_success { on_success(result); }
            await refresh();
        } except Exception as error {
            failure: any = error;
            if failure.status == 401 { session_error = "Sign in again to reopen your private plan."; }
            else { notice = "The result could not be confirmed. Refresh your plan before retrying."; }
        } finally { busy = False; }
    }

    async def save_goal(e: FormEvent) -> None {
        e.preventDefault();
        async def execute() -> Action { return await create_goal(title=goal_title, target_date=goal_target_date, importance=goal_importance); }
        await perform_action(execute, lambda (result: Action) -> None { goal_title = ""; goal_dialog_open = False; });
    }
    async def toggle_goal_state(goal_id: str) -> None {
        async def execute() -> Action { return await toggle_goal(goal_id=goal_id); }
        await perform_action(execute);
    }
    async def remove_goal(goal_id: str) -> None {
        async def execute() -> Action { return await delete_goal(goal_id=goal_id); }
        await perform_action(execute);
    }
    async def accept_cmd_proposal(prop_id: str) -> None {
        async def execute() -> Action { return await apply_command_proposal(proposal_id=prop_id); }
        await perform_action(execute);
    }
    async def dismiss_cmd_proposal(prop_id: str) -> None {
        async def execute() -> Action { return await dismiss_command_proposal(proposal_id=prop_id); }
        await perform_action(execute);
    }
    async def apply_rebalance() -> None {
        if board is None or not board.rebalance.available { return; }
        candidate = (board as Board).rebalance;
        async def execute() -> Action { return await apply_rebalance_candidate(from_day=candidate.from_day, to_day=candidate.to_day, task_id=candidate.task_id); }
        await perform_action(execute);
    }
    async def start_breakdown(task_id: str) -> None {
        busy = True;
        breakdown_error = "";
        try {
            prop: BreakdownProposal = await preview_task_breakdown(task_id=task_id);
            if prop.ok { breakdown_proposal = prop; }
            else { notice = prop.message; }
        } except Exception { notice = "The breakdown could not load. Your task has not changed. Try again."; }
        finally { busy = False; }
    }
    def copy_breakdown_steps() -> list[SubtaskDraft] {
        if breakdown_proposal is None { return []; }
        win: any = window;
        return win.JSON.parse(win.JSON.stringify(breakdown_proposal.subtasks));
    }
    def update_breakdown_draft(subtasks: list[SubtaskDraft]) -> None {
        if breakdown_proposal is None { return; }
        win: any = window;
        updated: any = win.Object.assign({}, breakdown_proposal, {"subtasks": subtasks});
        breakdown_proposal = updated;
    }
    def change_breakdown_title(index: int, value: str) -> None {
        if breakdown_proposal is None { return; }
        drafts = copy_breakdown_steps();
        drafts[index].title = value;
        update_breakdown_draft(drafts);
    }
    def change_breakdown_duration(index: int, value: str) -> None {
        if breakdown_proposal is None or not value { return; }
        drafts = copy_breakdown_steps();
        drafts[index].duration = int(value);
        update_breakdown_draft(drafts);
    }
    def remove_breakdown_step(index: int) -> None {
        if breakdown_proposal is None or len(breakdown_proposal.subtasks) <= 2 {
            notice = "A breakdown needs at least two steps.";
            return;
        }
        drafts = [item for item in breakdown_proposal.subtasks];
        drafts.pop(index);
        update_breakdown_draft(drafts);
    }
    async def confirm_breakdown() -> None {
        if breakdown_proposal is None or busy { return; }
        busy = True;
        breakdown_error = "";
        titles: list[str] = [s.title for s in breakdown_proposal.subtasks];
        durations: list[int] = [s.duration for s in breakdown_proposal.subtasks];
        try {
            result: Action = await apply_task_breakdown(task_id=breakdown_proposal.task_id, titles=titles, durations=durations, expected_version=breakdown_proposal.base_version);
            if result.ok {
                notice = result.message;
                breakdown_proposal = None;
                await refresh();
            } else { breakdown_error = result.message; }
        } except Exception { breakdown_error = "The result could not be confirmed. Your draft is still here. Refresh your plan before retrying if the connection was interrupted."; }
        finally { busy = False; }
    }
    def cancel_breakdown() -> None {
        if busy { return; }
        breakdown_proposal = None;
        breakdown_error = "";
    }

    async def open_day(e: FormEvent) -> None {
        e.preventDefault();
        busy = True;
        await refresh(planning_day_input);
        if not session_error and not load_error { notice = "Opened your plan for " + day_label(selected_day) + "."; planning_date_open = False; }
        busy = False;
    }

    async def switch_day(day: str) -> None {
        busy = True;
        selected_day = day;
        selected_day_ref.current = day;
        await refresh(day);
        busy = False;
    }

    async def run_command(e: FormEvent) -> None {
        e.preventDefault();
        if busy or speech.listening or not command_query.strip() { return; }
        busy = True;
        reply: CommandReply | None = None;
        submitted_query = command_query.strip();
        try {
            secretary_last_run = await secretary_run(query=submitted_query, day=selected_day, use_model=True);
            reply = secretary_last_run.reply;
            command_questions = (command_questions + [submitted_query])[-20:];
            command_answers = (command_answers + [reply])[-20:];
            command_sources = (command_sources + [secretary_last_run.source])[-20:];
        } except Exception { notice = "The secretary could not finish. Your saved plan was not changed."; busy = False; return; }
        if reply is not None and reply.proposal is not None {
            selected_day = reply.proposal.day;
            await refresh(reply.proposal.day);
        }
        busy = False;
    }

    async def save_task(e: FormEvent) -> None {
        e.preventDefault();
        async def execute() -> Action { return await create_task(title=title, day=selected_day, duration=duration, deadline=time_minutes(deadline), priority=priority, preferred_start=time_minutes(preferred), due_day=task_due_day); }
        await perform_action(execute, lambda (result: Action) -> None { title = ""; task_due_day = ""; });
    }
    async def save_fixed(e: FormEvent) -> None {
        e.preventDefault();
        async def execute() -> Action { return await create_commitment(title=fixed_title, day=selected_day, start=time_minutes(fixed_start), end=time_minutes(fixed_end)); }
        await perform_action(execute, lambda (result: Action) -> None { fixed_title = ""; });
    }
    async def save_planning_window(e: FormEvent) -> None {
        e.preventDefault();
        async def execute() -> Action { return await update_planning_hours(day_start=time_minutes(planning_start), day_end=time_minutes(planning_end)); }
        await perform_action(execute);
    }
    async def report_change(e: FormEvent) -> None {
        e.preventDefault();
        async def execute() -> Action { return await preview_recovery(title=disruption, day=selected_day, start=time_minutes(disrupted_start), end=time_minutes(disrupted_end), use_model=model_schedule); }
        await perform_action(execute);
    }
    async def interpret_change() -> None {
        if busy { return; }
        busy = True;
        try {
            draft = await interpret_disruption(note=change_note, day=selected_day);
            notice = draft.message;
            if draft.ok { disruption = draft.title; disrupted_start = clock_time(draft.start); disrupted_end = clock_time(draft.end); }
        } except Exception { notice = "The interpretation could not finish. You can enter the times yourself."; }
        finally { busy = False; }
    }
    async def choose(proposal_id: str, key: str) -> None {
        async def execute() -> Action { return await accept_recovery(proposal_id=proposal_id, option=key); }
        await perform_action(execute);
    }
    async def finish(task_id: str, done: bool) -> None {
        async def execute() -> Action { return await set_task_done(task_id=task_id, done=done); }
        await perform_action(execute);
    }
    async def remove_work(task_id: str) -> None {
        async def execute() -> Action { return await delete_task(task_id=task_id); }
        await perform_action(execute);
    }
    async def remove_fixed(commitment_id: str) -> None {
        async def execute() -> Action { return await delete_commitment(commitment_id=commitment_id); }
        await perform_action(execute);
    }
    async def dismiss(proposal_id: str) -> None {
        async def execute() -> Action { return await dismiss_recovery(proposal_id=proposal_id); }
        await perform_action(execute);
    }
    async def restore(revision_id: str) -> None {
        async def execute() -> Action { return await restore_revision(revision_id=revision_id); }
        await perform_action(execute);
    }

    if session_error {
        return <div className="session-screen" role="alert">
            <img src="/static/assets/replaniva-favicon.png" alt="" />
            <span className="eyebrow">PRIVATE PLAN LOCKED</span>
            <h1>Let’s sign you in again.</h1>
            <p>{session_error}</p>
            <button className="button primary" type="button" onClick={lambda -> None { onSignOut(); }}>Return to sign in <span>→</span></button>
        </div>;
    }
    if board is None {
        return <div className="loading-screen" role="status">{load_error or "Opening your plan…"}{load_error and <button className="button secondary" type="button" onClick={lambda -> None { refresh(); return; }}>Retry loading plan</button>}</div>;
    }
    view_board = board as Board;
    remaining = len([t for t in view_board.tasks if not t.done]);
    placed = len([t for t in view_board.tasks if not t.done and t.start >= 0]);
    proposal = view_board.proposal;
    proposal_id = proposal.id if proposal is not None else "";
    return <div className={"app-shell studio-shell light" if light else "app-shell studio-shell dark"} style={appearance_vars(light)}>
        <a className="skip-link" href="#main">Skip to plan</a>
        <main id="main" className="main-content" tabIndex={-1}>
            <div className="workspace-masthead">
                <button className="workspace-brand" type="button" aria-label="Replaniva home" onClick={lambda -> None { open_page("today"); }}><img src="/static/assets/replaniva-logo.png" alt="Replaniva" width={154} height={54} /></button>
                <nav className="workspace-navigation" aria-label="Main navigation">
                    <button type="button" title="Today" aria-current={"page" if active_page == "today" else None} onClick={lambda -> None { open_page("today"); }}><UiIcon name="house" /><span>Today</span></button>
                    <button type="button" title="Command" aria-current={"page" if active_page == "command" else None} onClick={lambda -> None { ask_shortcut(); }}><UiIcon name="message-circle" /><span>Command</span></button>
                    <button type="button" title="Recovery Studio" aria-current={"page" if active_page == "recovery" else None} onClick={lambda -> None { open_page("recovery"); }}><span className="navigation-core"><span className="recovery-glyph" aria-hidden="true">↝</span></span><span>Recover</span></button>
                    <button type="button" title="Capture" aria-current={"page" if active_page == "capture" else None} onClick={lambda -> None { open_page("capture"); }}><UiIcon name="plus" /><span>Capture</span></button>
                    <button type="button" title="Settings" aria-current={"page" if active_page == "settings" else None} onClick={lambda -> None { open_page("settings"); }}><UiIcon name="settings-2" /><span>Settings</span></button>
                    <button type="button" title="One Plan. Three Interfaces." aria-current={"page" if active_page == "interfaces" else None} onClick={lambda -> None { open_page("interfaces"); }}><UiIcon name="terminal" /><span>Interfaces</span></button>
                </nav>
                <div className="workspace-actions"><button type="button" className="icon-button notification-bell" aria-label={"Notifications, " + str(len([item for item in inbox if not item.read])) + " unread"} onClick={lambda -> None { inbox_open = True; load_inbox(); return; }}><UiIcon name="bell" />{len([item for item in inbox if not item.read]) > 0 and <span className="notification-count">{str(len([item for item in inbox if not item.read]))}</span>}</button><button type="button" className="icon-button" aria-label={"Use dark appearance" if light else "Use light appearance"} title={"Use dark appearance" if light else "Use light appearance"} onClick={lambda -> None { save_appearance(not light); return; }}><UiIcon name={"moon" if light else "sun"} /></button><button type="button" className="icon-button" aria-label="Open account settings" title="Account settings" onClick={lambda -> None { open_page("settings"); }}><UiIcon name="settings-2" /></button><button type="button" className="icon-button" aria-label="Sign out" title="Sign out" onClick={lambda -> None { onSignOut(); }}><UiIcon name="log-out" /></button></div>
            </div>
            {active_page not in ["settings", "command", "interfaces"] and <header className={"topbar topbar-today" if active_page == "today" else "topbar"}>
                {active_page == "today" and <div className="tour-launcher" role="group" aria-label="Guided tour"><UiIcon name="book-open" /><button className="tour-start" type="button" onClick={start_tour}><span>QUICK GUIDE</span>Start tour</button><button className="icon-button" type="button" aria-label="Speak guided tour" title={"Speak guided tour" if speech.narration_supported else "Read-aloud is unavailable in this browser"} disabled={not speech.narration_supported} onClick={lambda -> None { start_tour(); tour_audio = True; speech.speak("Step one of " + str(tour_count()) + ". " + tour_title(0) + ". " + tour_copy(0)); }}><UiIcon name="volume-2" /></button></div>}
                {active_page != "today" and <div>
                    <span className="eyebrow">{"RECOVERY STUDIO" if active_page == "recovery" else "CAPTURE THE PLAN" if active_page == "capture" else "COMMAND WORKSPACE"}</span>
                    <h1>{"Find the best way forward." if active_page == "recovery" else "Give every commitment a place." if active_page == "capture" else "Your planning secretary."}</h1>
                </div>}
                {active_page == "today" and <div className="selected-plan-date"><UiIcon name="calendar-days" /><div><span>VIEWING YOUR PLAN</span><time dateTime={selected_day}>{outlook_date_label(selected_day, True) + ", " + outlook_date_label(selected_day)}</time></div></div>}
                {active_page != "today" and <button type="button" className="selected-plan-date compact-plan-date" aria-label={"Change planning date, " + day_label(selected_day)} aria-haspopup="dialog" onClick={lambda -> None { planning_day_input = selected_day; planning_date_open = True; }}><UiIcon name="calendar-days" /><div><span>VIEWING YOUR PLAN</span><time dateTime={selected_day}>{day_label(selected_day)}</time></div><UiIcon name="chevron-down" /></button>}
            </header>}
            {interfaces_opened and <div hidden={active_page != "interfaces"}><InterfacesWorkspace day={selected_day} version={view_board.version} refresh_token={interface_refresh} onChanged={lambda -> None { interface_refresh += 1; refresh(); load_inbox(); }} onDayChanged={lambda (day: str) -> None { selected_day = day; refresh(day); return; }} onSignOut={onSignOut} /></div>}
            {load_error and <div className="notice" role="alert"><span>{load_error}</span><button className="button secondary" type="button" onClick={lambda -> None { refresh(); return; }}>Retry loading plan</button></div>}
            {notice and <div className="notice feedback-toast" role="region" aria-label="Action result"><span role="status" aria-live="polite">{notice}</span><button className="notice-close" type="button" aria-label="Dismiss notification" onClick={lambda -> None { notice = ""; }}>×</button></div>}
            {active_page == "command" and <div className="page-view command-workspace">
                <aside className="command-suggestions" aria-label="Planning suggestions"><div className="command-intro"><span className="eyebrow">COMMAND</span><h1>Your planning secretary.</h1><p>Choose a starting point, then make it your own.</p></div><div className="command-suggestion-list">
                    <button className="command-suggestion" type="button" onClick={lambda -> None { ask_shortcut("What should I do next?"); }}><UiIcon name="layers" /><span><strong>Find my next step</strong><small>Start with what matters now</small></span><UiIcon name="arrow-up-right" /></button>
                    <button className="command-suggestion" type="button" onClick={lambda -> None { ask_shortcut("What is at risk?"); }}><UiIcon name="shield-check" /><span><strong>Check my risks</strong><small>Review deadlines and dependencies</small></span><UiIcon name="arrow-up-right" /></button>
                    <button className="command-suggestion" type="button" onClick={lambda -> None { ask_shortcut("How much capacity do I have?"); }}><UiIcon name="chart-no-axes-combined" /><span><strong>Check my capacity</strong><small>See what fits in this day</small></span><UiIcon name="arrow-up-right" /></button>
                    <button className="command-suggestion" type="button" onClick={lambda -> None { ask_shortcut("Help me adjust my plan"); }}><UiIcon name="calendar-days" /><span><strong>Adjust my plan</strong><small>Explore a change before approving it</small></span><UiIcon name="arrow-up-right" /></button>
                </div><small className="suggestion-help">These four suggestions work without Gemini. They fill your message; you decide when to send.</small></aside>
                <CommandPanel view_board={view_board} questions={command_questions} answers={command_answers} sources={command_sources} onOfflineHelp={lambda -> None { explanation_dialog = "offline"; }} command_query={command_query} busy={busy} live_connected={live_connected} speech={speech} onQuery={lambda (query: str) -> None { command_query = query; }} run_command={run_command} open_workspace={open_workspace} accept_cmd_proposal={accept_cmd_proposal} dismiss_cmd_proposal={dismiss_cmd_proposal} />
                <aside className="command-sidebar"><section className="studio-card command-date-card"><time dateTime={selected_day}>{outlook_date_label(selected_day, True) + ", " + outlook_date_label(selected_day)}</time><form onSubmit={open_day}><label htmlFor="command-day" className="sr-only">Planning date</label><input id="command-day" type="date" required={True} value={planning_day_input} onChange={lambda (e: ChangeEvent) { planning_day_input = e.target.value; }}/><button className="button secondary" type="submit" disabled={busy}>Open day</button></form></section>
                    <section className="studio-card command-context-card"><span className="eyebrow">YOUR PLAN, CONNECTED</span><div className="command-plan-metrics"><div><strong>{remaining}</strong><span>open tasks</span></div><div><strong>{duration_label(view_board.briefing.health.available_minutes)}</strong><span>available</span></div></div><div className="command-context-next"><span>YOUR NEXT STEP</span><h2>{view_board.briefing.next_action.title}</h2><button className="explanation-link" type="button" onClick={lambda -> None { explanation_dialog = "next"; }}>Why this step?</button></div>{secretary_last_run and <button className="explanation-link" type="button" onClick={lambda -> None { explanation_dialog = "run"; }}>How your secretary checked this</button>}<button className="card-link" type="button" onClick={lambda -> None { open_page("today"); }}>Open Today<UiIcon name="arrow-right" /></button><p className="command-approval-note"><UiIcon name="shield-check" />You review and approve changes.</p></section>
                </aside>
            </div>}
            {active_page == "today" and <div className="page-view page-today">
            <div id="today" className="studio-grid">
                <div className="studio-column studio-left">
                    <PlanningCalendar planner_month={planner_month} selected_day={selected_day} busy={busy} month_busy={month_busy} month_error={month_error} load_month={load_month} switch_day={switch_day} open_page={open_page} open_workspace={open_workspace} ask_shortcut={ask_shortcut} />

                </div>
                <div className="studio-column studio-center">
                    <CompanionVisual working={busy} />
                    <section className="studio-card assistant-overview" aria-labelledby="next-step-title"><div className="card-kicker"><h2 id="next-step-title">YOUR NEXT STEP</h2><UiIcon name="layers" /></div><h3>{view_board.briefing.next_action.title}</h3><button className="explanation-link" type="button" onClick={lambda -> None { explanation_dialog = "next"; }}>Why this step?</button><button className="button primary" type="button" onClick={lambda -> None { ask_shortcut(); }}><UiIcon name="message-circle" />Open Command</button><div className="overview-shortcuts"><button type="button" onClick={lambda -> None { ask_shortcut("What is at risk?"); }}>Check risks</button><button type="button" onClick={lambda -> None { ask_shortcut("How much capacity do I have?"); }}>Check capacity</button></div>{len(view_board.command_proposals) > 0 and <button className="card-link" type="button" onClick={lambda -> None { ask_shortcut(); }}>{str(len(view_board.command_proposals)) + " proposals to review"}<UiIcon name="chevron-right" /></button>}</section>



                </div>
                <div className="studio-column studio-right">
                    <section className="studio-card health-panel" aria-labelledby="health-heading"><div className="card-kicker"><h2 id="health-heading">YOUR DAY AT A GLANCE</h2><UiIcon name="chart-no-axes-combined" /></div><div className="health-headline"><div><strong>{duration_label(-view_board.briefing.health.slack_minutes) if view_board.briefing.health.slack_minutes < 0 else duration_label(view_board.briefing.health.slack_minutes)}</strong><span>{"over available time" if view_board.briefing.health.slack_minutes < 0 else "room in your plan"}</span></div><CapacityOrbit pressure={view_board.briefing.health.pressure_percent} no_time={view_board.briefing.health.available_minutes == 0 and view_board.briefing.health.required_minutes > 0} /></div><div className="capacity-track" role="progressbar" aria-label="Planning pressure" aria-valuetext={duration_label(view_board.briefing.health.required_minutes) + " needed; " + duration_label(view_board.briefing.health.available_minutes) + " available"} aria-valuemin="0" aria-valuemax="100" aria-valuenow={min(100, view_board.briefing.health.pressure_percent)}><span style={pressure_style(view_board.briefing.health.pressure_percent)}></span></div><div className="capacity-caption"><span>{duration_label(view_board.briefing.health.required_minutes)} needed</span><span>{duration_label(view_board.briefing.health.available_minutes)} available</span></div><div className="health-counters"><div><strong>{remaining}</strong><span>open tasks</span></div><div><strong>{placed}</strong><span>scheduled</span></div><div><strong>{view_board.briefing.completed_tasks}</strong><span>completed</span></div></div><p className="health-summary-label">{view_board.briefing.health.label}</p><button className="explanation-link" type="button" onClick={lambda -> None { explanation_dialog = "health"; }}>Why this assessment?</button></section>
            <section id="timeline" className="section-grid timeline-section">
                <div className="panel timeline-panel studio-card">
                    <div className="panel-heading"><div><span className="eyebrow">TODAY’S SCHEDULE</span><h2>Room for what matters</h2></div><span className="legend">Fixed / Flexible</span></div>
                    <div className="timeline-list">
                        {[<div className={"timeline-row done" if item.done else "timeline-row " + item.kind} key={item.id}>
                            <div className="time">{clock_time(item.start)}<span>{clock_time(item.end) if item.end >= 0 else "Needs space"}</span></div>
                            <div className="timeline-card"><span className="kind">{item.detail}</span><strong>{item.title}</strong>
                                <div className="timeline-actions">
                                    {item.kind == "flexible" and <button type="button" disabled={busy} onClick={lambda -> None { finish(item.id, not item.done); return; }}>{"Undo" if item.done else "Mark done"}</button>}
                                    {item.kind == "flexible" and not item.done and <button type="button" className="breakdown-btn" id={"breakdown-open-" + item.id} disabled={busy} onClick={lambda -> None { start_breakdown(item.id); return; }}>Break down</button>}
                                    {item.kind == "flexible" and <button className="danger-link" type="button" disabled={busy} aria-label={"Remove " + item.title} onClick={lambda -> None { remove_work(item.id); return; }}>Remove</button>}
                                    {item.kind == "fixed" and <button className="danger-link" type="button" disabled={busy} aria-label={"Remove " + item.title} onClick={lambda -> None { remove_fixed(item.id); return; }}>Remove</button>}
                                </div>

                            </div>
                        </div> for item in timeline_for(view_board)]}
                        {len(view_board.tasks) == 0 and len(view_board.commitments) == 0 and <div className="empty-state">A little open space. Capture a task to give your day its first anchor.</div>}
                    </div>
                </div>
            </section>
                </div>
            </div>
            <div className="studio-support-grid">

                {len(view_board.briefing.risks) > 0 and <section className="risk-radar studio-card" aria-labelledby="risk-title">
                <div className="risk-heading"><div><span className="eyebrow">EARLY SIGNALS</span><h2 id="risk-title">Worth your attention.</h2></div><span>{str(len(view_board.briefing.risks))} signal{"s" if len(view_board.briefing.risks) != 1 else ""}</span></div>
                <div className="risk-list">{[<article className={"risk-item severity-" + risk.severity} key={risk.code + risk.task_id}>
                    <span className="risk-marker" aria-hidden="true"></span>
                    <div><strong>{risk.title}</strong><p>{risk.detail}</p></div>
                    <button type="button" className="card-link" onClick={lambda -> None { open_workspace(risk.action_target); }}>{risk.action_label}<UiIcon name="arrow-right" /></button>
                </article> for risk in view_board.briefing.risks]}</div>
            </section>}
                    {len(view_board.briefing.risks) == 0 and <section className="studio-card recovery-guide"><div className="card-kicker"><span>A WAY FORWARD</span><UiIcon name="shield-check" /></div><h2>Life changed?<br/><span>Your plan can too.</span></h2><p>Keep the commitments. Rethink the path.</p><ol><li><span>01</span>Tell us what changed</li><li><span>02</span>Compare validated alternatives</li><li><span>03</span>Choose what works for you</li></ol><button className="card-link" type="button" onClick={lambda -> None { open_page("recovery"); }}>Open Recovery Studio <UiIcon name="arrow-up-right" /></button></section>}
            </div>
            <div className="studio-bottom-grid">
                <section className="studio-card connection-panel" aria-labelledby="connections-title"><div className="card-kicker"><h2 id="connections-title">YOUR CONNECTED SPACE</h2><UiIcon name="link" /></div>
                    <div className="connection-row"><UiIcon name="calendar-days" /><span>Web planner</span><strong>Saved plan</strong></div>
                    <div className="connection-row"><UiIcon name="terminal" /><span>Terminal</span><strong>Shared account</strong></div>
                    <button type="button" className="card-link" onClick={lambda -> None { choose_settings("connections"); open_page("settings"); }}>Manage connections <UiIcon name="chevron-right" /></button>
                </section>
                <section id="goals" className="goals-section studio-card">
                    <div className="goals-heading"><div><span className="eyebrow">YOUR GOALS</span><h2>The bigger picture</h2></div></div>
                    <div className="goals-grid">
                        {[<div className="goal-item" key={goal.id}>
                            <div className="goal-info">
                                <strong>{goal.title}</strong>
                                <span className="goal-pill">{"Priority: " + str(goal.importance)}</span>
                                <span className="goal-pill">{"Target: " + day_label(goal.target_date)}</span>
                            </div>
                            <div className="goal-progress-bar">
                                <span style={{"width": str(goal.completed_tasks * 100 // max(1, goal.total_tasks)) + "%"}}></span>
                            </div>
                            <p>{str(goal.completed_tasks)} / {str(goal.total_tasks)} tasks done</p>
                            <div className="goal-actions">
                                <button type="button" onClick={lambda -> None { toggle_goal_state(goal.id); return; }}>{"Mark Incomplete" if goal.completed else "Mark Complete"}</button>
                                <button type="button" onClick={lambda -> None { remove_goal(goal.id); return; }}>Delete</button>
                            </div>
                        </div> for goal in view_board.goals]}
                    </div>
                    <button className="button secondary goal-launcher" type="button" onClick={lambda -> None { notice = ""; goal_dialog_open = True; }}><UiIcon name="plus" />Add a goal</button>
                </section>
                <section id="activity" className="activity-section studio-card" aria-labelledby="activity-title">
                    <div className="activity-heading"><div><span className="eyebrow">WHY THE PLAN CHANGED</span><h2 id="activity-title">Planning activity</h2></div><span>{str(len(view_board.activities))} recent changes</span></div>
                    <div id="planning-activity-list" className="activity-list" role="region" aria-label="Recent planning changes" tabIndex={0}>
                        {[<article className="activity-item" key={activity.id}>
                            <span className="activity-marker" aria-hidden="true"></span>
                            <div><strong>{activity.title}</strong><p>{activity.detail}</p><small>{day_label(activity.day)} | {day_label(activity.created_at[:10]) + " " + activity.created_at[11:]}</small></div>
                        </article> for activity in view_board.activities]}
                        {len(view_board.activities) == 0 and <p className="empty-state">Accepted changes will appear here with a short explanation.</p>}
                    </div>
                </section>
            </div>
            <div className="studio-details">            <section id="outlook" className="week-outlook studio-card" aria-labelledby="outlook-title">
                <div className="outlook-heading"><div><span className="eyebrow">SEVEN-DAY OUTLOOK</span><h2 id="outlook-title">A little foresight goes a long way.</h2></div><p>Open a day to inspect its full plan.</p></div>
                <div className="outlook-grid">{[<button type="button" className={"outlook-day outlook-" + outlook.status.lower()} key={outlook.day} disabled={busy} onClick={lambda -> None { switch_day(outlook.day); return; }}>
                    <time className="outlook-date" dateTime={outlook.day}><span className="outlook-weekday">{outlook_date_label(outlook.day, True)}</span><span className="outlook-date-label">{outlook_date_label(outlook.day)}</span></time><strong>{outlook.label}</strong>
                    <div className="workload-track" aria-hidden="true"><span style={workload_style(outlook.required_minutes, outlook.available_minutes)}></span></div>
                    <small>{duration_label(outlook.required_minutes)} work / {duration_label(outlook.available_minutes)} open</small>
                    <em>{"+" + duration_label(outlook.overloaded_minutes) + " over" if outlook.overloaded_minutes > 0 else duration_label(outlook.slack_minutes) + " slack"}</em>
                </button> for outlook in view_board.horizon]}</div>

                {view_board.rebalance.available and <div className="rebalance-hint">
                    <div><span className="eyebrow">SAFE MOVE FOUND</span><strong>Move {view_board.rebalance.task_title} to {short_day(view_board.rebalance.to_day)} at {clock_time(view_board.rebalance.suggested_start)}</strong><p>{view_board.rebalance.reason}</p></div>
                    <div>
                        <button type="button" onClick={lambda -> None { switch_day(view_board.rebalance.from_day); return; }}>Review overloaded day <span>→</span></button>
                        <button type="button" className="button primary" disabled={busy} onClick={apply_rebalance}>Apply Rebalance</button>
                    </div>
                </div>}

            </section>


</div>
            </div>}
            {active_page == "capture" and <section id="capture" className="page-view page-capture">
                <div className="capture-column capture-page-grid">
                    <div id="task-capture-card" className="panel form-panel"><span className="eyebrow">QUICK CAPTURE</span><h2>What needs doing?</h2>
                        <form onSubmit={save_task}>
                            <label htmlFor="task-title">Task</label><input id="task-title" required={True} value={title} placeholder="Prepare the weekly report" onChange={lambda (e: ChangeEvent) { title = e.target.value; }}/>
                            <div className="field-pair"><div><label htmlFor="duration">Duration · minutes</label><input id="duration" required={True} type="number" min="15" max="600" step="15" value={str(duration)} onChange={lambda (e: ChangeEvent) { duration = int(e.target.value) if e.target.value else 0; }}/></div>
                            <div><label htmlFor="deadline">Done by</label><input id="deadline" required={True} type="time" value={deadline} onChange={lambda (e: ChangeEvent) { deadline = e.target.value; }}/></div></div>
                            <label htmlFor="task-due-day">Due date (optional)</label><input id="task-due-day" aria-describedby="task-due-context" type="date" min={selected_day} value={task_due_day} onChange={lambda (e: ChangeEvent) { task_due_day = e.target.value; }}/>
                            <p id="task-due-context" className="date-context">Due {day_label(task_due_day or selected_day)}</p><p className="form-note">Leave this blank if the task is due on the planning date. A later due date allows a safe move to another day.</p>
                            <label htmlFor="preferred">Best time (optional)</label><input id="preferred" type="time" value={preferred} onChange={lambda (e: ChangeEvent) { preferred = e.target.value; }}/>
                            <label htmlFor="priority">Priority</label><select id="priority" value={str(priority)} onChange={lambda (e: ChangeEvent) { priority = int(e.target.value); }}><option value="1">Low</option><option value="2">Normal</option><option value="3">High</option></select>
                            <div className="capture-summary"><strong>{day_label(selected_day)}</strong><span>{str(duration)} minutes · Due {clock_time(time_minutes(deadline)) if deadline else "Choose a time"}</span></div><button className="button primary full" type="submit" disabled={busy}>Add task <span>→</span></button>
                        </form>
                    </div>
                    <div id="fixed-capture-card" className="panel form-panel"><span className="eyebrow">CAN’T MOVE</span><h2>Fixed commitment</h2>
                        <form onSubmit={save_fixed}>
                            <label htmlFor="fixed-title">Event</label><input id="fixed-title" required={True} value={fixed_title} placeholder="Meeting, appointment or family commitment" onChange={lambda (e: ChangeEvent) { fixed_title = e.target.value; }}/>
                            <div className="field-pair"><div><label htmlFor="fixed-start">Starts</label><input id="fixed-start" required={True} type="time" value={fixed_start} onChange={lambda (e: ChangeEvent) { fixed_start = e.target.value; }}/></div>
                            <div><label htmlFor="fixed-end">Ends</label><input id="fixed-end" required={True} type="time" value={fixed_end} onChange={lambda (e: ChangeEvent) { fixed_end = e.target.value; }}/></div></div>
                            <div className="capture-summary"><strong>{day_label(selected_day)}</strong><span>{fixed_start}–{fixed_end} · Fixed time</span></div><button className="button secondary full" type="submit" disabled={busy}>Add commitment</button>
                        </form>
                    </div>
                </div>
            </section>}
            {active_page == "settings" and <section id="settings" className="settings-page page-view">
                <aside className="settings-sidebar" aria-label="Settings navigation">
                    <div className="settings-sidebar-title"><UiIcon name="settings-2" /><strong>Settings</strong></div>
                    <p className="settings-sidebar-copy">A space that works for you.</p>
                    <nav className="settings-nav" aria-label="Settings sections">
                        <button type="button" aria-current={"page" if settings_section == "workspace" else None} aria-controls="settings-panel" onClick={lambda -> None { choose_settings("workspace"); }}><UiIcon name="settings-2" /><span>Workspace</span></button>
                        <button type="button" aria-current={"page" if settings_section == "planning" else None} aria-controls="settings-panel" onClick={lambda -> None { choose_settings("planning"); }}><UiIcon name="calendar-days" /><span>Planning</span></button>
                        <button type="button" aria-current={"page" if settings_section == "connections" else None} aria-controls="settings-panel" onClick={lambda -> None { choose_settings("connections"); }}><UiIcon name="link" /><span>Connections</span></button>
                        <button type="button" aria-current={"page" if settings_section == "assistant" else None} aria-controls="settings-panel" onClick={lambda -> None { choose_settings("assistant"); }}><UiIcon name="layers" /><span>Assistant</span></button>
                        <button type="button" aria-current={"page" if settings_section == "privacy" else None} aria-controls="settings-panel" onClick={lambda -> None { choose_settings("privacy"); }}><UiIcon name="shield-check" /><span>Privacy</span></button>
                    </nav>
                    <div className="settings-section-picker"><label htmlFor="settings-section">Settings section</label><select id="settings-section" value={settings_section} onChange={lambda (e: ChangeEvent) -> None { choose_settings(e.target.value); }}><option value="workspace">Workspace</option><option value="planning">Planning</option><option value="connections">Connections</option><option value="assistant">Assistant</option><option value="privacy">Privacy</option></select></div>
                    <div className="settings-sidebar-footer"><div><UiIcon name="shield-check" /><span>Preferences saved<br/>to your private account.</span></div><button type="button" onClick={lambda -> None { open_page("today"); }}><UiIcon name="house" />Back to Today</button></div>
                </aside>
                <div className="settings-main">
                    <div className="settings-breadcrumb"><div><span>Settings</span><UiIcon name="chevron-right" /><strong>{"Workspace" if settings_section == "workspace" else "Planning" if settings_section == "planning" else "Connections" if settings_section == "connections" else "Assistant" if settings_section == "assistant" else "Privacy"}</strong></div><span className="settings-private"><UiIcon name="shield-check" />Private account</span></div>
                    <div id="settings-panel" className="settings-panel" aria-labelledby="settings-view-title">
                        <header className="settings-page-heading"><h1 id="settings-view-title" tabIndex={-1}>{"Workspace settings" if settings_section == "workspace" else "Planning preferences" if settings_section == "planning" else "Your connections" if settings_section == "connections" else "Assistant & usage" if settings_section == "assistant" else "Privacy & access"}</h1><p>{"Make Replaniva feel like your own." if settings_section == "workspace" else "Set the boundaries your plan should respect." if settings_section == "planning" else "Bring your tools together, on your terms." if settings_section == "connections" else "Manage proactive reminders, remembered preferences and model allowance." if settings_section == "assistant" else "Keep control of your account and connected tools."}</p></header>
                        {settings_section == "workspace" and <div className="settings-stack">
                            <article className="settings-card"><div className="settings-card-head"><div><UiIcon name="sun" /><h2>Appearance</h2></div><span className="status-chip">Saved to your account</span></div>
                        <div className="setting-group">
                            <p>Choose the look that feels easiest to use. Your choice follows this account.</p>
                            <div className="appearance-choice" role="group" aria-label="Appearance">
                                <button className={"appearance-option selected" if not light else "appearance-option"} type="button" aria-pressed={not light} onClick={lambda -> None { save_appearance(False); return; }}><span className="theme-preview dark-preview"></span><strong>Dark</strong></button>
                                <button className={"appearance-option selected" if light else "appearance-option"} type="button" aria-pressed={light} onClick={lambda -> None { save_appearance(True); return; }}><span className="theme-preview light-preview"></span><strong>Light</strong></button>
                            </div>
                        </div>

                            </article>

                        </div>}
                        {settings_section == "planning" and <article className="settings-card"><div className="settings-card-head"><div><UiIcon name="calendar-days" /><h2>Your planning day</h2></div></div>
                        <div className="setting-group planning-window"><p>Flexible work stays inside these hours. Saving safely rearranges your saved days.</p>
                            <form onSubmit={save_planning_window}>
                                <div className="field-pair"><div><label htmlFor="planning-start">Day starts</label><input id="planning-start" type="time" step="900" required={True} value={planning_start} onChange={lambda (e: ChangeEvent) { planning_start = e.target.value; }}/></div>
                                <div><label htmlFor="planning-end">Day ends</label><input id="planning-end" type="time" step="900" required={True} value={planning_end} onChange={lambda (e: ChangeEvent) { planning_end = e.target.value; }}/></div></div>
                                <button className="button secondary" type="submit" disabled={busy}>Save planning hours</button>
                            </form>
                        </div>

                        </article>}
                        {settings_section == "connections" and <div className="settings-stack">
                            <article className="settings-card integration-card calendar-settings" aria-labelledby="calendar-heading" aria-busy={calendar_busy}>
                                <div className="settings-card-head"><div><UiIcon name="calendar-days" /><h2 id="calendar-heading">Google Calendar</h2></div><span className={"status-chip ready" if calendar_state and calendar_state.connected else "status-chip waiting"}>{"Checking connection" if calendar_busy else "Connected" if calendar_state and calendar_state.connected else "Not connected" if calendar_state else "Status unavailable" if calendar_feedback else "Not checked"}</span></div>
                                <p>Bring appointments and meetings into your plan. Export chosen tasks to a separate Replaniva calendar. Your personal Google events stay untouched.</p>
                                <div className="calendar-feedback" role="status" aria-live="polite" aria-atomic="true">{calendar_feedback if calendar_feedback else calendar_state.message if calendar_state else "Loading Calendar status..."}</div>
                                {calendar_state is None and <button className="button secondary" type="button" disabled={calendar_busy} onClick={lambda -> None { load_calendar(); return; }}>{"Checking connection..." if calendar_busy else "Retry connection status"}</button>}
                                {calendar_state and <div>
                                    {calendar_state.label and <p className="connection-help">{"Calendar account: " + calendar_state.label}</p>}
                                    <div className="calendar-actions">
                                        <button className="button secondary" type="button" disabled={calendar_busy or not calendar_state.configured} onClick={lambda -> None { connect_calendar(); return; }}>{"Reconnect" if calendar_state.connected else "Connect Google Calendar"}</button>
                                        <button className="button secondary" type="button" disabled={calendar_busy} onClick={lambda -> None { load_calendar(); return; }}>Refresh status</button>
                                    </div>
                                    {calendar_state.connected and <div className="calendar-steps">
                                        <fieldset><legend>1. Choose calendars to read</legend><p className="connection-help">We will only read these calendars. The Replaniva export calendar is excluded.</p>
                                            {calendar_state.calendars.map(lambda (item: any) -> JsxElement {
                                                return <label className="calendar-check" key={item.id}><input type="checkbox" disabled={calendar_busy or item.id == calendar_state.app_calendar} checked={item.id in calendar_selected} onChange={lambda (e: ChangeEvent) -> None { calendar_selected = calendar_selected + [item.id] if e.target.checked else [value for value in calendar_selected if value != item.id]; calendar_preview = None; }} /><span>{item.label}</span></label>;
                                            })}
                                            <button className="button secondary" type="button" disabled={calendar_busy} onClick={lambda -> None { calendar_operation("select"); return; }}>Save calendar selection</button>
                                        </fieldset>
                                        <div><h3>2. Review busy time</h3><p className="connection-help">{"Preview seven days from " + day_label(selected_day) + ". Nothing is imported without approval. Unplaced work stays saved and is shown in the review."}</p><button className="button secondary" type="button" disabled={calendar_busy or calendar_state.selected.length == 0} onClick={lambda -> None { calendar_operation("import"); return; }}>Synchronize now: preview imports</button></div>
                                        <fieldset><legend>3. Export selected tasks</legend><p className="connection-help">Only unfinished, scheduled tasks are eligible. Checked tasks are previewed first. Exported tasks are never read back as new commitments.</p>
                                            {not calendar_state.app_calendar and <button className="button secondary" type="button" disabled={calendar_busy} onClick={lambda -> None { calendar_operation("create"); return; }}>Create dedicated Replaniva calendar</button>}
                                            {calendar_state.app_calendar and <p className="connection-help">Your app-created Replaniva calendar is ready. An existing personal calendar cannot be selected as the destination.</p>}
                                            {[<label className="calendar-check" key={task.id}><input type="checkbox" checked={task.id in calendar_tasks} disabled={calendar_busy} onChange={lambda (e: ChangeEvent) -> None { calendar_tasks = calendar_tasks + [task.id] if e.target.checked else [value for value in calendar_tasks if value != task.id]; calendar_preview = None; }} /><span>{task.title + " (" + clock_time(task.start) + ", " + str(task.duration) + " min)"}</span></label>
                                             for task in view_board.tasks if not task.done and task.start >= 0]}
                                            <button className="button secondary" type="button" disabled={calendar_busy or not calendar_state.app_calendar or len(calendar_tasks) == 0} onClick={lambda -> None { calendar_operation("export"); return; }}>Preview selected exports</button>
                                        </fieldset>
                                        <p className="connection-help">{"Last successful synchronization: " + calendar_state.last_sync if calendar_state.last_sync else "No synchronization approved yet."}</p>
                                    </div>}
                                    {calendar_state.configured and <button className="button secondary" type="button" disabled={calendar_busy} onClick={lambda -> None { calendar_operation("disconnect"); return; }}>Disconnect Google Calendar</button>}
                                </div>}
                                {calendar_preview and calendar_preview.ok and <button className="button secondary" type="button" onClick={lambda -> None { calendar_review_open = True; }}>Review pending Calendar changes</button>}
                            </article>
                        </div>}
                        {settings_section == "assistant" and <AssistantSettings connections={view_board.connections} alerts_active={bool(alerts_enabled.current)} onNotice={lambda (message: str) -> None { notice = message; }} onInboxChanged={load_inbox} onAlerts={lambda (enabled: bool) -> None { alerts_enabled.current = enabled; }} />}
                        {settings_section == "privacy" and <div className="settings-stack">
                            <article className="settings-card"><div className="settings-card-head"><div><UiIcon name="shield-check" /><h2>Your private workspace</h2></div></div><div className="setting-group"><h3>One account, one saved plan</h3><p>Your tasks, preferences and linked tools belong to this account. Your private planning state is shared across the available interfaces.</p></div><div className="setting-group settings-signout"><div><h3>Sign out of this browser</h3><p>Use this when you finish on a shared computer. Your saved plan stays available when you sign in again.</p></div><button className="button secondary" type="button" onClick={lambda -> None { onSignOut(); }}><UiIcon name="log-out" />Sign out</button></div></article>
                            <article className="settings-card"><div className="settings-card-head"><div><UiIcon name="link" /><h2>Credentials & permissions</h2></div></div><div className="setting-group"><h3>Provider credentials stay on the server</h3><p>Replaniva shows connection status without displaying provider keys. Personal Google access uses your consent, and plan changes require review and approval.</p></div><div className="settings-security-note"><UiIcon name="shield-check" /><p>For public hosting, configure credentials through deployment secrets or a managed vault. Keep raw keys out of planning data and browser storage.</p></div><button className="button secondary" type="button" onClick={lambda -> None { choose_settings("connections"); }}>Manage connections<UiIcon name="arrow-right" /></button></article>
                        </div>}
                    </div>
                </div>
            </section>}
            {active_page == "recovery" and <section id="recovery" className="recovery-section page-view">
                <div className="recovery-heading"><div><span className="eyebrow">SIGNATURE WORKFLOW / SIMULATION MODE</span><h2>Recovery Studio<span className="brand-dot">.</span></h2><p>Test a disruption without changing your saved plan. See the ripple, compare valid options, then choose your next move.</p></div><span className="recovery-symbol" aria-hidden="true">↝</span></div>
                <div id="recovery-capture-card" className="recovery-capture-card"><div className="workflow-step"><span>01</span><div><h3>Describe the interruption</h3><p>{day_label(selected_day)} · Planning hours {clock_time(view_board.day_start)}–{clock_time(view_board.day_end)}</p></div></div><div className="ai-capture"><div><label htmlFor="change-note">Describe the change in your own words <span>· Model optional</span></label><input id="change-note" value={change_note} placeholder="My meeting moved to 2–3 pm" onChange={lambda (e: ChangeEvent) { change_note = e.target.value; }}/></div><button className="button secondary" type="button" disabled={busy} onClick={lambda -> None { interpret_change(); return; }}>Interpret note</button></div>
                <label className="model-opt-in"><input type="checkbox" checked={model_schedule} onChange={lambda -> None { model_schedule = not model_schedule; }}/> Include a model-assisted alternative (uses your allowance)</label>
                <form className="disruption-form" onSubmit={report_change}>
                    <div><label htmlFor="disruption">What happened?</label><input id="disruption" required={True} value={disruption} placeholder="Unexpected meeting" onChange={lambda (e: ChangeEvent) { disruption = e.target.value; }}/></div>
                    <div><label htmlFor="disrupted-start">Starts</label><input id="disrupted-start" required={True} type="time" value={disrupted_start} onChange={lambda (e: ChangeEvent) { disrupted_start = e.target.value; }}/></div>
                    <div><label htmlFor="disrupted-end">Ends</label><input id="disrupted-end" required={True} type="time" value={disrupted_end} onChange={lambda (e: ChangeEvent) { disrupted_end = e.target.value; }}/></div>
                    <button className="button primary" type="submit" disabled={busy}>Explore recovery <span>↝</span></button>
                    <p className="recovery-form-note">Preview only. Your saved plan stays unchanged until you accept a choice.</p>
                </form></div>
                <div id="recovery-comparison"><div className="workflow-step"><span>02</span><div><h3>Review your choices</h3><p>Compare the impact, then decide what to apply.</p></div></div>
                {not proposal and <div className="recovery-empty"><UiIcon name="shield-check"/><h3>Your saved plan is protected</h3><p>Complete the interruption form to compare two validated alternatives here.</p></div>}{proposal and <div className="proposal-area">
                    <div className="proposal-intro"><div><span className="eyebrow">SIMULATED PLAN / REVIEW BEFORE APPLYING</span><h3>{proposal.title} changes your day</h3><p>{day_label(selected_day)} · {clock_time(proposal.start)}–{clock_time(proposal.end)} is held for your new commitment. Your current plan stays in place until you accept a choice.</p></div><button className="dismiss-button" type="button" disabled={busy} onClick={lambda -> None { dismiss(proposal_id); return; }}>Discard simulation</button></div>
                    <div className="option-grid">
                        <article className="option-card"><div className="option-head"><span>OPTION 01</span><h3>Move as little as possible</h3></div><OptionCard choice={proposal.minimal} tasks={view_board.tasks} commitments={view_board.commitments} change_title={proposal.title} change_start={proposal.start} change_end={proposal.end} day_start={view_board.day_start} day_end={view_board.day_end}/><button className="button secondary full" type="button" disabled={busy} onClick={lambda -> None { choose(proposal_id, "minimal"); return; }}>Accept this plan</button></article>
                        <article className="option-card featured"><div className="option-head"><span>OPTION 02</span><h3>Protect deadlines</h3></div><OptionCard choice={proposal.deadline} tasks={view_board.tasks} commitments={view_board.commitments} change_title={proposal.title} change_start={proposal.start} change_end={proposal.end} day_start={view_board.day_start} day_end={view_board.day_end}/><button className="button primary full" type="button" disabled={busy} onClick={lambda -> None { choose(proposal_id, "deadline"); return; }}>Accept this plan</button></article>
                    </div>
                    {same_plan(proposal.minimal, proposal.deadline) and <p className="same-plan">Both approaches lead to the same valid schedule today.</p>}
                </div>}
                </div>
                {[<div className="restore-bar" key={revision.id}>
                    <span>{"Restored recovery: " if revision.restored else "Accepted recovery: "}<strong>{revision.title}</strong></span>
                    {not revision.restored and <button type="button" onClick={lambda -> None { restore(revision.id); return; }}>Restore previous plan</button>}
                </div> for revision in view_board.revisions]}
            </section>}
                                {inbox_open and <NotificationInbox inbox={inbox} busy={busy} secretary_error={secretary_error} load_inbox={load_inbox} notification_action={notification_action} onClose={lambda -> None { inbox_open = False; }} onViewDay={lambda (day: str) -> None { inbox_open = False; switch_day(day); return; }} adjust_followup={adjust_followup} complete_followup={complete_followup} />}
            {goal_dialog_open and <WorkspaceDialog dialog_id="goal-dialog" title="Add a goal" focus_id="goal-title" onClose={lambda -> None { goal_dialog_open = False; }}>{notice and <p className="modal-feedback" role="alert">{notice}</p>}<form className="goal-form" onSubmit={save_goal}>
                        <label htmlFor="goal-title">Title</label>
                        <input id="goal-title" value={goal_title} required={True} onChange={lambda (e: ChangeEvent) { goal_title = e.target.value; }}/>
                        <label htmlFor="goal-target">Target Date</label>
                        <input id="goal-target" type="date" value={goal_target_date} required={True} onChange={lambda (e: ChangeEvent) { goal_target_date = e.target.value; }}/>
                        <label htmlFor="goal-importance">Importance</label>
                        <select id="goal-importance" value={goal_importance} onChange={lambda (e: ChangeEvent) { goal_importance = e.target.value; }}><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option></select>
                        <div className="modal-actions"><button className="button secondary" type="button" onClick={lambda -> None { goal_dialog_open = False; }}>Cancel</button><button type="submit" className="button primary" disabled={busy}>Save goal</button></div>
                    </form></WorkspaceDialog>}
            {explanation_dialog and <WorkspaceDialog dialog_id="explanation-dialog" title={"Why this step?" if explanation_dialog == "next" else "Why this assessment?" if explanation_dialog == "health" else "Offline planning help" if explanation_dialog == "offline" else "Secretary activity"} onClose={lambda -> None { explanation_dialog = ""; }}>
                {explanation_dialog == "next" and <p>{view_board.briefing.next_action.reason}</p>}
                {explanation_dialog == "health" and <div><p>{view_board.briefing.summary}</p><ul>{[<li key={reason}>{reason}</li> for reason in view_board.briefing.health.reasons]}</ul></div>}
                {explanation_dialog == "offline" and <div className="offline-help"><p>These requests use your saved plan and work without Gemini or another model:</p><ul><li>What should I do next?</li><li>What is at risk?</li><li>How much capacity do I have?</li><li>Explain my plan</li><li>Help me adjust my plan</li><li>Show my dependencies or my goal progress</li></ul><p>Recovery time fields, capture and scheduling also work without a model. Free-form requests outside the supported patterns may need model interpretation. If it is unavailable, the secretary gives verified plan findings and asks for a clearer request. It does not pretend to understand or apply a change.</p></div>}
                {explanation_dialog == "run" and secretary_last_run and <div><p>{secretary_last_run.source}</p><ol>{[<li key={str(index)}>{secretary_last_run.steps[index]}</li> for index in range(len(secretary_last_run.steps))]}</ol></div>}
            </WorkspaceDialog>}
            {calendar_review_open and calendar_preview and calendar_preview.ok and <WorkspaceDialog dialog_id="calendar-review-dialog" title="Review Calendar changes" onClose={lambda -> None { calendar_review_open = False; }}><section className="calendar-review" aria-labelledby="calendar-review-heading">{calendar_feedback and <p className="calendar-feedback" role="status">{calendar_feedback}</p>}<h3 id="calendar-review-heading">{"Review " + calendar_preview.mode + " changes"}</h3>
                                    {len(calendar_preview.changes) == 0 and <p>Everything in this preview is already up to date.</p>}
                                    <ul>{[<li key={change}>{change}</li> for change in calendar_preview.changes]}</ul>
                                    {[<p key={effect}>{effect}</p> for effect in calendar_preview.effects]}
                                    <div className="calendar-actions"><button className="button primary" type="button" disabled={calendar_busy} onClick={lambda -> None { calendar_operation("approve"); return; }}>Approve these changes</button><button className="button secondary" type="button" disabled={calendar_busy} onClick={lambda -> None { calendar_operation("dismiss"); return; }}>Leave unchanged</button></div>
                                </section></WorkspaceDialog>}
            {breakdown_proposal is not None and <BreakdownDialog breakdown_proposal={breakdown_proposal} busy={busy} breakdown_error={breakdown_error} cancel_breakdown={cancel_breakdown} change_breakdown_title={change_breakdown_title} change_breakdown_duration={change_breakdown_duration} remove_breakdown_step={remove_breakdown_step} confirm_breakdown={confirm_breakdown} />}
            {tour_step >= 0 and <GuidedTour placement={tour_placement} highlight={tour_highlight} tour_step={tour_step} narration_supported={speech.narration_supported} tour_audio={tour_audio} speaking={speech.speaking} tour_key={tour_key} close_tour={close_tour} speak_tour={speak_tour} previous_tour_step={previous_tour_step} next_tour_step={next_tour_step} />}
            {planning_date_open and <WorkspaceDialog dialog_id="planning-date-dialog" title="Choose planning day" focus_id="planning-day" onClose={lambda -> None { if not busy { planning_date_open = False; planning_day_input = selected_day; } }}><form className="planning-date-form" onSubmit={open_day}><label htmlFor="planning-day">Planning date</label><input id="planning-day" type="date" required={True} aria-describedby="planning-day-context" value={planning_day_input} onChange={lambda (e: ChangeEvent) { planning_day_input = e.target.value; }}/><p id="planning-day-context" className="date-context" aria-live="polite">{day_label(planning_day_input) if planning_day_input else "Choose a date"}</p><div className="modal-actions"><button type="button" className="button secondary" disabled={busy} onClick={lambda -> None { planning_date_open = False; planning_day_input = selected_day; }}>Cancel</button><button type="submit" className="button primary" disabled={busy}>Open day</button></div></form></WorkspaceDialog>}
            <footer>REPLANIVA / PLANS THAT ADAPT WHEN LIFE CHANGES</footer>
        </main>
    </div>;
}
