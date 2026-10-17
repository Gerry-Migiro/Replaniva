"""Three real interfaces, one authenticated plan."""
import from .date_labels { day_label }
import from react { useRef, useEffect }
import from .mobile.interface { MobileApp }
import from console_api { ConsoleReply, console_execute }
import from studio { UiIcon }

obj ConsoleLine { has command: str, output: str, ok: bool; }

def quoted_argument(value: str) -> str { return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""; }
def guide_clock(value: str) -> int {
    parts = value.split(":");
    if len(parts) != 2 or not parts[0].isdecimal() or not parts[1].isdecimal() { return -1; }
    hour = int(parts[0]); minute = int(parts[1]);
    return hour * 60 + minute if hour < 24 and minute < 60 else -1;
}

def:pub InterfacesWorkspace(day: str, version: int, onChanged: any, onSignOut: any, refresh_token: int = 0, onDayChanged: any = None) -> JsxElement {
    has layout: str = "mobile", input: str = "", running: bool = False,
        lines: list[ConsoleLine] = [], history: list[str] = [], cursor: int = -1,
        fit_phone: bool = True, phone_scale: float = 1.0, review: str = "", review_day: str = "", failure: str = "",
        guided: bool = True, guide_kind: str = "", guide_values: list[str] = [];
    output_ref: any = useRef(None);
    input_ref: any = useRef(None);
    useEffect(lambda {
        win: any = window;
        def resize_phone() -> None {
            shell: any = document.querySelector(".phone-scale-shell");
            if not shell { return; }
            top = shell.getBoundingClientRect().top;
            available = max(280, win.innerHeight - max(0, top) - 36);
            phone_scale = min(1.0, available / 780, (win.innerWidth - 36) / 360) if fit_phone else min(1.0, (win.innerWidth - 36) / 360);
        }
        timer = win.setTimeout(resize_phone, 40);
        win.addEventListener("resize", resize_phone);
        return lambda { win.clearTimeout(timer); win.removeEventListener("resize", resize_phone); };
    }, [fit_phone, layout]);
    async def execute(value: str) -> None {
        if running or not value.strip() { return; }
        command = value.strip();
        if command == "clear" { lines = []; review = ""; failure = ""; input = ""; return; }
        running = True;
        input = "";
        cursor = -1;
        history = (history + [command])[-100:];
        failure = "";
        try {
            result: ConsoleReply = await console_execute(command=command, day=day);
            lines = (lines + [ConsoleLine(command=command, output=result.output, ok=result.ok)])[-100:];
            if result.review_id { review = result.review_id; review_day = day; }
            elif command.startswith("confirm ") or command.startswith("cancel ") { review = ""; }
            if result.changed or command.startswith("report ") or command.startswith("ask ") or command.startswith("secretary ") or command.startswith("plan dismiss") or command.startswith("proposal dismiss") { onChanged(); }
        } except Exception as error {
            fault: any = error;
            if fault.status == 401 { onSignOut(); return; }
            failure = "The result could not be confirmed. Refresh the plan before retrying a change. No command was automatically repeated.";
        } finally {
            running = False;
            win: any = window;
            win.setTimeout(lambda -> None {
                if output_ref.current { output_ref.current.scrollTop = output_ref.current.scrollHeight; }
                if input_ref.current { input_ref.current.focus(); }
            }, 0);
        }
    }
    def guide_prompt() -> str {
        if guide_kind in ["add", "report"] {
            prompts = ["What needs doing?", "How many minutes? (15 to 600)", "Due by what time? (HH:MM)"] if guide_kind == "add" else ["What changed?", "Starts at what time? (HH:MM)", "Ends at what time? (HH:MM)"];
            return "Step " + str(len(guide_values) + 1) + " of 3 · " + prompts[len(guide_values)] + "\n" + ("Entered: " + " · ".join(guide_values) + "\n" if guide_values else "") + "Type back or cancel. Your saved plan is unchanged.";
        }
        if guide_kind == "ask" { return "What would you like to ask about your plan?\nFor example: Explain my plan. Type cancel to return."; }
        if guide_kind == "done" { return "Enter a task number from the plan above.\nYou will review the change before confirming. Type cancel to return."; }
        if guide_kind in ["proposal", "proposal-dismiss"] { return "Enter the proposal number from the list above, or cancel."; }
        if guide_kind == "review" { return "REVIEW CHANGES\n1 View recovery          2 Review minimal moves\n3 Review deadline plan   4 Review restore\n5 List proposals         6 Review a proposal\n7 Dismiss a proposal     8 Discard recovery preview\n0 Back to main menu"; }
        return "WHAT WOULD HELP?\n1 Today's plan           2 Next step\n3 Add a task             4 Plans changed\n5 Review changes         6 Complete a task\n7 Ask about my plan      8 Seven-day outlook\n9 Command help          10 Notifications\n0 Command prompt\nEnter a number, or type a planning command directly.";
    }
    def change_mode(use_guided: bool) -> None {
        if guide_kind { failure = "Unsent guided input cleared. Your saved plan is unchanged."; }
        guided = use_guided; guide_kind = ""; guide_values = []; input = "";
        win: any = window;
        win.setTimeout(lambda -> None { if output_ref.current { output_ref.current.scrollTop = output_ref.current.scrollHeight; } if input_ref.current { input_ref.current.focus({"preventScroll": True}); } }, 0);
    }
    async def submit_terminal(value: str) -> None {
        if running or not value.strip() { return; }
        value = value.strip();
        if value.lower() == "menu" { change_mode(True); return; }
        if value.lower() == "commands" { change_mode(False); return; }
        if not guided { await execute(value); return; }
        input = ""; failure = "";
        if value.lower() in ["back", "cancel"] {
            if value.lower() == "back" and guide_values { guide_values = guide_values[:-1]; }
            else { guide_kind = ""; guide_values = []; }
            return;
        }
        if not guide_kind {
            if value == "0" { change_mode(False); }
            elif value in ["3", "4"] { guide_kind = "add" if value == "3" else "report"; guide_values = []; }
            elif value == "5" { guide_kind = "review"; await execute("proposals"); await execute("plan"); }
            elif value == "6" { guide_kind = "done"; await execute("today"); }
            elif value == "7" { guide_kind = "ask"; }
            else {
                commands = {"1": "today", "2": "next", "8": "week", "9": "help", "10": "notifications"};
                if value in commands { await execute(commands[value]); }
                elif value.isdecimal() { failure = "Choose a listed menu number, or enter a planning command."; }
                else { await execute(value); }
            }
        } elif guide_kind in ["add", "report"] {
            step = len(guide_values);
            if step == 0 and len(value) > 120 { failure = "Use a title of 120 characters or fewer."; return; }
            if step == 1 and guide_kind == "add" {
                if not value.isdecimal() or int(value) < 15 or int(value) > 600 { failure = "Enter 15 to 600 minutes."; return; }
            } elif step > 0 {
                if guide_clock(value) < 0 { failure = "Enter a valid 24-hour HH:MM time."; return; }
                if guide_kind == "report" and step == 2 and guide_clock(value) <= guide_clock(guide_values[1]) { failure = "The end must be after the start."; return; }
            }
            values = guide_values + [value];
            if len(values) == 3 {
                command = "add " + quoted_argument(values[0]) + " --minutes " + values[1] + " --due " + values[2] if guide_kind == "add" else "report " + quoted_argument(values[0]) + " --start " + values[1] + " --end " + values[2];
                guide_kind = ""; guide_values = []; await execute(command);
            } else { guide_values = values; }
        } elif guide_kind == "ask" { guide_kind = ""; await execute("ask " + quoted_argument(value)); }
        elif guide_kind in ["done", "proposal", "proposal-dismiss"] {
            if not value.isdecimal() or int(value) < 1 { failure = "Enter a positive item number from the list."; return; }
            command = "done " if guide_kind == "done" else "proposal accept " if guide_kind == "proposal" else "proposal dismiss ";
            guide_kind = ""; await execute(command + value);
        } elif guide_kind == "review" {
            if value == "0" { guide_kind = ""; }
            elif value in ["6", "7"] { guide_kind = "proposal" if value == "6" else "proposal-dismiss"; await execute("proposals"); }
            else {
                commands = {"1": "plan", "2": "plan accept minimal", "3": "plan accept deadline", "4": "plan restore", "5": "proposals", "8": "plan dismiss"};
                if value not in commands { failure = "Choose a listed review option."; return; }
                await execute(commands[value]);
            }
        }
    }
    def clear_terminal() -> None { lines = []; review = ""; failure = ""; guide_kind = ""; guide_values = []; }
    def history_key(event: any) -> None {
        if (event.ctrlKey or event.metaKey) and event.key.lower() == "l" {
            event.preventDefault(); clear_terminal();
        } elif event.ctrlKey and event.key.lower() == "c" {
            event.preventDefault();
            if not running { input = ""; cursor = -1; }
            else { failure = "The request has already been sent. Wait for its result, then refresh before retrying an uncertain change."; }
        } elif event.key == "Tab" and input.strip() and " " not in input.strip() {
            matches = [name for name in ["help", "today", "briefing", "next", "week", "health", "goals", "activity", "notifications", "ask", "secretary", "add", "done", "report", "plan", "goal", "rebalance", "breakdown", "proposals", "proposal", "notification", "confirm", "cancel", "clear"] if name.startswith(input.strip())];
            if len(matches) == 1 { event.preventDefault(); input = matches[0] + " "; }
        } elif event.key == "ArrowUp" and history {
            event.preventDefault(); cursor = len(history) - 1 if cursor < 0 else max(0, cursor - 1); input = history[cursor];
        } elif event.key == "ArrowDown" and cursor >= 0 {
            event.preventDefault(); cursor += 1;
            if cursor >= len(history) { cursor = -1; input = ""; } else { input = history[cursor]; }
        }
    }
    return <section className="interfaces-workspace" aria-labelledby="interfaces-title">
        <header className="interfaces-heading"><div><span className="eyebrow">YOUR SHARED WORKSPACE</span><h1 id="interfaces-title">One Plan. Three Interfaces.</h1><p>Your mobile app and planning terminal, connected to the same saved plan for <strong>{day_label(day)}</strong>.</p></div><button type="button" className="button secondary" onClick={lambda -> None { onChanged(); }}>Refresh shared plan<UiIcon name="refresh-cw" /></button></header>
        <div className="interface-controls" role="group" aria-label="Interface layout">
            <button type="button" aria-pressed={layout == "mobile"} onClick={lambda -> None { layout = "mobile"; }}>Mobile app</button>
            <button type="button" aria-pressed={layout == "cli"} onClick={lambda -> None { layout = "cli"; }}>CLI terminal</button>
            <span className="interface-version">Plan version {str(version)}</span>
        </div>
        <div className={"interface-grid layout-" + layout}>
            <section className="embedded-mobile" hidden={layout == "cli"} aria-labelledby="mobile-interface-title">
                <h2 id="mobile-interface-title" className="sr-only">Mobile app</h2>
                <div className="phone-preview-tools" role="group" aria-label="Phone preview size"><button type="button" aria-pressed={fit_phone} onClick={lambda -> None { fit_phone = True; }}>Fit screen</button><button type="button" aria-pressed={not fit_phone} onClick={lambda -> None { fit_phone = False; }}>Actual size</button></div><div className="phone-scale-shell" style={{"--phone-scale": str(phone_scale)}}><div className="phone-frame"><div className="phone-screen"><MobileApp embedded={True} initial_day={day} sync_version={version + refresh_token} onChanged={onChanged} onDayChanged={onDayChanged} onSignOut={onSignOut}/></div></div></div>
                <p className="interface-caption">Interactive browser preview · Same source as the standalone mobile app.</p>
            </section>
            <section className="embedded-console" hidden={layout == "mobile"} aria-labelledby="console-interface-title">
                <div className="terminal-titlebar"><div className="terminal-title"><UiIcon name="terminal"/><h2 id="console-interface-title">replaniva · planning CLI</h2></div><button className="console-clear" type="button" onClick={clear_terminal}>Clear</button></div>
                <div className="terminal-session"><span className="terminal-connected" aria-hidden="true"></span>Authenticated session<span className="terminal-day">{day_label(day)}</span></div>
                <div className="console-modes" role="group" aria-label="Terminal mode"><button type="button" disabled={running} aria-pressed={guided} onClick={lambda -> None { change_mode(True); }}>Guided menu</button><button type="button" disabled={running} aria-pressed={not guided} onClick={lambda -> None { change_mode(False); }}>Commands</button></div>
                <p id="console-help" className="sr-only">Type a Replaniva planning command and press Enter. Up and Down recall history, Tab completes a unique command, Control L clears output and Control C clears an unsent line. This is a planning CLI, not an operating-system shell.</p>
                <div className="console-screen" onClick={lambda (event: MouseEvent) -> None { win: any = window; if not win.getSelection().toString() and input_ref.current { input_ref.current.focus(); } }}>
                    <div className="console-output" role="log" aria-label="Planning command output" aria-live="polite" aria-relevant="additions" tabIndex={0} ref={output_ref}>
                        <div className="terminal-welcome"><p>Replaniva CLI · Your saved plan</p><p>Type <code>menu</code> for guided steps or <code>help</code> for commands. Changes require confirmation.</p></div>
                        {[<article className={"console-entry " + ("command-ok" if line.ok else "command-error")} key={str(index)}><p className="console-command"><span aria-hidden="true">replaniva ❯</span> {line.command}</p><pre>{line.output}</pre></article> for (index, line) in enumerate(lines)]}
                        {guided and <div className="console-guide" role="status" aria-live="polite"><pre>{guide_prompt()}</pre></div>}
                    </div>
                    <form className="console-form" onSubmit={lambda (event: FormEvent) -> None { event.preventDefault(); submit_terminal(input); return; }}><label htmlFor="browser-command" className="sr-only">Planning command</label><div><span className="terminal-prompt" aria-hidden="true">replaniva ❯</span><input id="browser-command" ref={input_ref} value={input} maxLength={600} autoComplete="off" spellCheck={False} autoCapitalize="none" readOnly={running} placeholder={"Working…" if running else "Enter your answer" if guided and guide_kind else "Menu number or command" if guided else "Type a command"} aria-describedby="console-help" onKeyDown={history_key} onChange={lambda (event: ChangeEvent) -> None { input = event.target.value; }}/><button type="submit" aria-label="Run command" disabled={running or not input.strip()}><UiIcon name="arrow-up-right" /></button></div></form>
                </div>
                {review and <div className="console-review" role="group" aria-label="Pending command review"><p>Pending review for {day_label(review_day)}. Read the proposed change above before confirming. The server rejects expired, stale or repeated approvals.</p><div><button className="button primary" type="button" disabled={running or review_day != day} onClick={lambda -> None { execute("confirm " + review); return; }}>Confirm change</button><button className="button secondary" type="button" disabled={running} onClick={lambda -> None { execute("cancel " + review); return; }}>Cancel review</button></div></div>}
                {failure and <p className="console-error" role="alert">{failure}</p>}
                <p className="interface-caption terminal-hints">Enter to run · ↑ ↓ history · Tab completion · Ctrl+L clear · Planning commands only</p>
            </section>
        </div>
    </section>;
}
