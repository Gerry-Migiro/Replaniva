"""Stage 1 web workflow: private capture and a real saved schedule."""
import from "@jac/runtime" {
    SignupResult,
    jacSignup,
    jacLogin,
    jacLogout,
    jacIsLoggedIn
}
import from endpoints {
    Board,
    Action,
    TaskView,
    CommitmentView,
    get_board,
    save_task,
    change_task,
    save_commitment,
    delete_commitment,
    update_settings
}

def clock(value: int) -> str {
    if value < 0 {
        return "Unscheduled";
    }
    if value == 1440 {
        return "24:00";
    }
    return str(value // 60).zfill(2) + ":" + str(value % 60).zfill(2);
}

def minutes(value: str) -> int {
    parts = value.split(":");
    if len(parts) != 2 {
        return -1;
    }
    return int(parts[0]) * 60 + int(parts[1]);
}

def:pub app -> JsxElement {
    has signed: bool = jacIsLoggedIn(),
        registering: bool = False,
        email: str = "",
        password: str = "",
        error: str = "",
        working: bool = False;
    async def authenticate(e: FormEvent) -> None {
        e.preventDefault();
        working = True;
        error = "";
        result: SignupResult | None = None;
        ok: bool = False;
        try {
            if registering {
                result = await jacSignup(email.strip().lower(), password);
                if not result.success {
                    error = result.error
                        if result.error
                        else "Could not create your account.";
                    working = False;
                    return;
                }
            }
            ok = await jacLogin(email.strip().lower(), password);
            if ok {
                password = "";
                signed = True;
            } else {
                error = "Sign-in failed. Check your email and password.";
            }
        } except Exception {
            error = "Could not connect. Please try again.";
        }
        working = False;
    }
    if signed {
        return
            <Planner
                onLogout={lambda -> None {
                    jacLogout();
                    signed = False;
                }}
            />;
    }
    return
        <main className="auth-layout">
            <section className="intro">
                <a className="brand" href="/">
                    Replaniva
                    <span>.</span>
                </a>
                <p className="eyebrow">A little clarity for everyday life</p>
                <h1>
                    Plans that adapt
                    <br/>
                    when life changes.
                </h1>
                <p>
                    Make room for work, home, study and everything in between. Your tasks and commitments, in one private plan.
                </p>
                <div className="intro-line">
                    Your time. Your priorities. A realistic day.
                </div>
            </section>
            <section className="panel auth-panel">
                <p className="eyebrow">Your private workspace</p>
                <h2>{"Create your account" if registering else "Welcome back"}</h2>
                <form onSubmit={authenticate}>
                    <label htmlFor="email">Email</label>
                    <input
                        id="email"
                        type="email"
                        autoComplete="email"
                        required
                        value={email}
                        onChange={lambda (e: ChangeEvent) { email = e.target.value; }}
                    />
                    <label htmlFor="password">Password</label>
                    <input
                        id="password"
                        type="password"
                        minLength={8}
                        autoComplete={"new-password"
                            if registering
                            else "current-password"}
                        required
                        value={password}
                        onChange={lambda (e: ChangeEvent) { password = e.target.value; }}
                    />
                    <p className="hint">
                        Use at least eight characters. Password managers and paste are supported.
                    </p>
                    {<p role="alert" className="error">{error}</p> if error else None}
                    <button className="primary" disabled={working} type="submit">
                        {"Please wait…"
                            if working
                            else ("Create account" if registering else "Sign in")}
                    </button>
                </form>
                <button
                    className="text-button"
                    onClick={lambda {
                        registering = not registering;
                        error = "";
                    }}
                >
                    {"Already registered? Sign in"
                        if registering
                        else "New here? Create an account"}
                </button>
            </section>
        </main>;
}

def:pub Planner(onLogout: any) -> JsxElement {
    has board: Board | None = None,
        day: str = "",
        notice: str = "",
        failed: bool = False,
        busy: bool = False,
        section: str = "task",
        title: str = "",
        duration: str = "60",
        due: str = "",
        deadline: str = "17:00",
        priority: str = "2",
        editing: str = "",
        fixedTitle: str = "",
        fixedStart: str = "09:00",
        fixedEnd: str = "10:00",
        fixedEditing: str = "",
        hoursStart: str = "08:00",
        hoursEnd: str = "20:00",
        timezone: str = "UTC";
    can with entry {
        load("");
    }
    async def load(selected: str) -> None {
        busy = True;
        result: Board | None = None;
        try {
            result = await get_board(selected);
            if result.error {
                failed = True;
                notice = result.error;
                busy = False;
                return;
            }
            board = result;
            day = result.day;
            due = result.day;
            hoursStart = clock(result.start);
            hoursEnd = clock(result.end);
            timezone = result.timezone;
        } except Exception {
            failed = True;
            notice = "Could not load your plan. Your saved data has not been cleared. Retry or sign in again.";
        }
        busy = False;
    }
    async def finish(action: Action) -> None {
        failed = not action.ok;
        notice = action.message;
        if action.ok {
            await load(day);
        }
    }
    async def submitTask(e: FormEvent) -> None {
        e.preventDefault();
        busy = True;
        result: Action | None = None;
        try {
            result = await save_task(
                day,
                title,
                int(duration),
                due,
                minutes(deadline),
                int(priority),
                editing
            );
            await finish(result);
            if result.ok {
                title = "";
                editing = "";
            }
        } except Exception {
            failed = True;
            notice = "Task was not saved. Check its title, date and values, then retry.";
        }
        busy = False;
    }
    async def submitFixed(e: FormEvent) -> None {
        e.preventDefault();
        busy = True;
        result: Action | None = None;
        try {
            result = await save_commitment(
                day, fixedTitle, minutes(fixedStart), minutes(fixedEnd), fixedEditing
            );
            await finish(result);
            if result.ok {
                fixedTitle = "";
                fixedEditing = "";
            }
        } except Exception {
            failed = True;
            notice = "Commitment was not saved. Check the date, title and times.";
        }
        busy = False;
    }
    async def submitSettings(e: FormEvent) -> None {
        e.preventDefault();
        busy = True;
        result: Action | None = None;
        try {
            result = await update_settings(
                minutes(hoursStart), minutes(hoursEnd), timezone
            );
            await finish(result);
        } except Exception {
            failed = True;
            notice = "Settings were not saved. Check the hours and timezone.";
        }
        busy = False;
    }
    async def taskAction(id: str, operation: str) -> None {
        busy = True;
        result: Action | None = None;
        try {
            result = await change_task(id, operation);
            await finish(result);
        } except Exception {
            failed = True;
            notice = "Could not update the task. Retry after reloading your plan.";
        }
        busy = False;
    }
    async def removeFixed(id: str) -> None {
        busy = True;
        result: Action | None = None;
        try {
            result = await delete_commitment(id);
            await finish(result);
        } except Exception {
            failed = True;
            notice = "Could not remove the commitment. Please retry.";
        }
        busy = False;
    }
    def editTask(t: TaskView) -> None {
        section = "task";
        editing = t.id;
        title = t.title;
        duration = str(t.duration);
        due = t.due_day;
        deadline = clock(t.deadline);
        priority = str(t.priority);
    }
    def editFixed(c: CommitmentView) -> None {
        section = "fixed";
        fixedEditing = c.id;
        fixedTitle = c.title;
        fixedStart = clock(c.start);
        fixedEnd = clock(c.end);
    }
    return
        <div className="workspace">
            <header className="topbar">
                <a className="brand" href="/">
                    Replaniva
                    <span>.</span>
                </a>
                <span className="private-label">Your private plan</span>
                <button onClick={onLogout}>Sign out</button>
            </header>
            <main>
                <div className="page-heading">
                    <div>
                        <p className="eyebrow">Make space for what matters</p>
                        <h1>Your day, realistically planned.</h1>
                    </div>
                    <label className="date-control">
                        Planning date
                        <input
                            aria-label="Planning date"
                            type="date"
                            value={day}
                            disabled={busy}
                            onChange={lambda (e: ChangeEvent) {
                                editing = "";
                                fixedEditing = "";
                                load(e.target.value);
                            }}
                        />
                    </label>
                </div>
                {<div role="status" className={"notice error" if failed else "notice"}>
                    {notice}{<button onClick={lambda { load(day); }}>
                        Reload plan
                    </button>
                        if failed
                        else None}
                </div>
                    if notice
                    else None}
                {<div className="planner-grid">
                    <section className="panel capture">
                        <nav aria-label="Planning tools" className="tabs">
                            {[
                                <button
                                    key={s}
                                    aria-pressed={section == s}
                                    onClick={lambda { section = s; }}
                                    disabled={busy}
                                >
                                    {"Task"
                                        if s == "task"
                                        else (
                                            "Commitment" if s == "fixed" else "Hours"
                                        )}
                                </button> for s in ["task", "fixed", "hours"]
                            ]}
                        </nav>
                        {<form onSubmit={submitTask}>
                            <h2>{"Edit task" if editing else "Add a task"}</h2>
                            <p className="hint">
                                Flexible work, placed around your commitments.
                            </p>
                            <label htmlFor="task-title">Task title</label>
                            <input
                                id="task-title"
                                required
                                maxLength={160}
                                value={title}
                                onChange={lambda (e: ChangeEvent) { title = e.target.value; }}
                            />
                            <div className="field-row">
                                <div>
                                    <label htmlFor="duration">Minutes needed</label>
                                    <input
                                        id="duration"
                                        type="number"
                                        min="15"
                                        max="1440"
                                        required
                                        value={duration}
                                        onChange={lambda (e: ChangeEvent) { duration = e.target.value; }}
                                    />
                                </div>
                                <div>
                                    <label htmlFor="priority">Importance</label>
                                    <select
                                        id="priority"
                                        value={priority}
                                        onChange={lambda (e: ChangeEvent) { priority = e.target.value; }}
                                    >
                                        <option value="1">Low</option>
                                        <option value="2">Medium</option>
                                        <option value="3">High</option>
                                    </select>
                                </div>
                            </div>
                            <div className="field-row due-row">
                                <div>
                                    <label htmlFor="due">Due date</label>
                                    <input
                                        id="due"
                                        type="date"
                                        min={day}
                                        required
                                        value={due}
                                        onChange={lambda (e: ChangeEvent) { due = e.target.value; }}
                                    />
                                </div>
                                <div>
                                    <label htmlFor="deadline">Due by</label>
                                    <input
                                        id="deadline"
                                        type="time"
                                        required
                                        value={deadline}
                                        onChange={lambda (e: ChangeEvent) { deadline = e.target.value; }}
                                    />
                                </div>
                            </div>
                            <button type="submit" className="primary" disabled={busy}>
                                {"Save task and schedule"
                                    if editing
                                    else "Add task and schedule"}
                            </button>
                            {<button
                                type="button"
                                onClick={lambda {
                                    editing = "";
                                    title = "";
                                }}
                            >
                                Cancel edit
                            </button>
                                if editing
                                else None}
                        </form>
                            if section == "task"
                            else None}
                        {<form onSubmit={submitFixed}>
                            <h2>
                                {"Edit commitment"
                                    if fixedEditing
                                    else "Add a commitment"}
                            </h2>
                            <p className="hint">
                                Fixed time stays fixed. Overlapping commitments are rejected.
                            </p>
                            <label htmlFor="fixed-title">Commitment title</label>
                            <input
                                id="fixed-title"
                                required
                                maxLength={160}
                                value={fixedTitle}
                                onChange={lambda (e: ChangeEvent) { fixedTitle = e.target.value; }}
                            />
                            <div className="field-row">
                                <div>
                                    <label htmlFor="fixed-start">Starts</label>
                                    <input
                                        id="fixed-start"
                                        type="time"
                                        required
                                        value={fixedStart}
                                        onChange={lambda (e: ChangeEvent) { fixedStart = e.target.value; }}
                                    />
                                </div>
                                <div>
                                    <label htmlFor="fixed-end">Ends</label>
                                    <input
                                        id="fixed-end"
                                        type="time"
                                        required
                                        value={fixedEnd}
                                        onChange={lambda (e: ChangeEvent) { fixedEnd = e.target.value; }}
                                    />
                                </div>
                            </div>
                            <button className="primary" type="submit" disabled={busy}>
                                Save commitment and schedule
                            </button>
                            {<button
                                type="button"
                                onClick={lambda {
                                    fixedEditing = "";
                                    fixedTitle = "";
                                }}
                            >
                                Cancel edit
                            </button>
                                if fixedEditing
                                else None}
                        </form>
                            if section == "fixed"
                            else None}
                        {<form onSubmit={submitSettings}>
                            <h2>Your planning hours</h2>
                            <p className="hint">
                                Saving reschedules flexible work on every saved day. Fixed commitments stay unchanged.
                            </p>
                            <div className="field-row">
                                <div>
                                    <label htmlFor="hours-start">Day starts</label>
                                    <input
                                        id="hours-start"
                                        type="time"
                                        required
                                        value={hoursStart}
                                        onChange={lambda (e: ChangeEvent) { hoursStart = e.target.value; }}
                                    />
                                </div>
                                <div>
                                    <label htmlFor="hours-end">Day ends</label>
                                    <input
                                        id="hours-end"
                                        type="time"
                                        required
                                        value={hoursEnd}
                                        onChange={lambda (e: ChangeEvent) { hoursEnd = e.target.value; }}
                                    />
                                </div>
                            </div>
                            <label htmlFor="timezone">Timezone (IANA)</label>
                            <input
                                id="timezone"
                                required
                                value={timezone}
                                onChange={lambda (e: ChangeEvent) { timezone = e.target.value; }}
                            />
                            <button
                                type="button"
                                className="text-button"
                                onClick={lambda {
                                    browser: any = window;
                                    timezone = str(
                                        browser.Intl.DateTimeFormat().resolvedOptions().timeZone
                                    );
                                }}
                            >
                                Use browser timezone
                            </button>
                            <button className="primary" type="submit" disabled={busy}>
                                Save hours and schedule
                            </button>
                        </form>
                            if section == "hours"
                            else None}
                        <p className="hint footnote">
                            Schedule changes happen when you save. Tasks that cannot fit before their deadline stay visible.
                        </p>
                    </section>
                    <section
                        className="panel schedule-panel"
                        aria-label="Saved schedule"
                    >
                        <div className="section-heading">
                            <div>
                                <p className="eyebrow">Your saved day</p>
                                <h2>Room for what matters</h2>
                            </div>
                            <span className="badge">{board.timezone}</span>
                        </div>
                        <p className="hint">
                            {clock(board.start)}–{clock(
                                board.end
                            )} planning hours · earliest deadlines first
                        </p>
                        {<div className="empty">
                            <h3>A clear day, ready for your priorities.</h3>
                            <p>Add a task or commitment to build your schedule.</p>
                        </div>
                            if not board.tasks and not board.commitments
                            else None}
                        {<h3 className="list-heading">Fixed commitments</h3>
                            if board.commitments
                            else None}
                        {[
                            <article className="plan-item fixed" key={c.id}>
                                <div className="item-time">
                                    {clock(c.start)}
                                    –
                                    {clock(c.end)}
                                    <span>Fixed</span>
                                </div>
                                <div className="item-copy">
                                    <h3>{c.title}</h3>
                                </div>
                                <div className="item-actions">
                                    <button
                                        disabled={busy}
                                        onClick={lambda { editFixed(c); }}
                                    >
                                        Edit
                                    </button>
                                    <button
                                        disabled={busy}
                                        aria-label={"Remove " + c.title}
                                        onClick={lambda { removeFixed(c.id); }}
                                    >
                                        Remove
                                    </button>
                                </div>
                            </article> for c in board.commitments
                        ]}
                        {<h3 className="list-heading">Tasks</h3>
                            if board.tasks
                            else None}
                        {[
                            <article
                                className={"plan-item completed"
                                    if t.done
                                    else "plan-item"}
                                key={t.id}
                            >
                                <div className="item-time">
                                    {"Completed" if t.done else clock(t.start)}
                                    <span>{str(t.duration) + " min"}</span>
                                    {<span>{"to " + clock(t.start + t.duration)}</span>
                                        if t.start >= 0 and not t.done
                                        else None}
                                </div>
                                <div className="item-copy">
                                    <h3>{t.title}</h3>
                                    <p>
                                        {"Due "
                                            + t.due_day
                                            + " at "
                                            + clock(t.deadline)}
                                    </p>
                                    {<p className="unplaced">
                                        No valid space before the deadline. Shorten, move or remove work to make room.
                                    </p>
                                        if t.start < 0 and not t.done
                                        else None}
                                </div>
                                <div className="item-actions">
                                    <button
                                        disabled={busy}
                                        onClick={lambda { taskAction(
                                            t.id, "reopen" if t.done else "complete"
                                        ); }}
                                    >
                                        {"Reopen" if t.done else "Complete"}
                                    </button>
                                    <button
                                        disabled={busy}
                                        onClick={lambda { editTask(t); }}
                                    >
                                        Edit
                                    </button>
                                    <button
                                        disabled={busy}
                                        aria-label={"Delete " + t.title}
                                        onClick={lambda { taskAction(t.id, "delete"); }}
                                    >
                                        Delete
                                    </button>
                                </div>
                            </article> for t in board.tasks
                        ]}
                    </section>
                </div>
                    if board is not None
                    else <div className="panel">
                        <p>Loading your private plan…</p>
                        <button onClick={lambda { load(day); }}>Retry</button>
                    </div>}
            </main>
            <footer>Replaniva · Plans that adapt when life changes.</footer>
        </div>;
}
