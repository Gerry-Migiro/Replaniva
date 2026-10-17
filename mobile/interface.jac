"""Replaniva Android client: Today, capture, disruption and approval."""

import from ..date_labels { day_label }
import from react { useRef, useEffect }

import from "@jac/mobui" { View, Text, TextInput, Pressable, ScrollView, StyleSheet, Image, KeyboardAvoidingView, Platform, Modal, Switch }
import from accounts { normalize_username }
import from "@jac/runtime" { SignupResult, jacLogin, jacSignup, jacLogout, jacIsLoggedIn }
import from endpoints {
    dismiss_recovery, get_board, create_task, set_task_done,
    preview_recovery, accept_recovery, apply_rebalance_candidate,
    apply_command_proposal, dismiss_command_proposal, toggle_goal,
    secretary_run, create_commitment, delete_task, delete_commitment, create_goal, delete_goal,
    get_planner_month, restore_revision, update_planning_hours, preview_task_breakdown, apply_task_breakdown,
    secretary_notifications, secretary_notification
}
import from endpoints { Board, TaskView, Action, PlannerMonth, BreakdownProposal }
import from secretary { SecretaryRunView, NotificationView, SecretaryAction }
import from planning { Choice }

def login_name(value: str) -> str {
    clean = value.strip().lower();
    if "@" in clean and len(clean) <= 254 and " " not in clean { return clean; }
    return normalize_username(value);
}

import from .design { mobile_styles, MobileGlyph }

def clock_time(value: int) -> str {
    if value < 0 { return "Unplaced"; }
    hour = str(value // 60);
    minute = str(value % 60);
    if value // 60 < 10 { hour = "0" + hour; }
    if value % 60 < 10 { minute = "0" + minute; }
    return hour + ":" + minute;
}

def duration_label(value: int) -> str {
    sign = "-" if value < 0 else "";
    safe = abs(value);
    hours = safe // 60;
    remainder = safe % 60;
    if hours > 0 and remainder > 0 { return sign + str(hours) + "h " + str(remainder) + "m"; }
    if hours > 0 { return sign + str(hours) + "h"; }
    return sign + str(remainder) + "m";
}

def to_minutes(value: str) -> int {
    parts = value.split(":");
    if len(parts) != 2 { return -1; }
    return int(parts[0]) * 60 + int(parts[1]);
}

def task_title(tasks: list[TaskView], id: str) -> str {
    for task in tasks { if task.id == id { return task.title; } }
    return "Task";
}

def mobile_goal_title(board: Board, id: str) -> str {
    for goal in board.goals { if goal.id == id { return goal.title; } }
    return "Linked goal";
}

def ChoiceMobile(choice: Choice, tasks: list[TaskView], light: bool = False) -> JsxElement {
    styles = mobile_styles(light);
    <View style={styles.card}>
        <Text style={styles.small}>{choice.label}</Text>
        <Text style={styles.muted}>{choice.reason}</Text>
        <Text style={styles.muted}>{str(choice.moved)} moved · {str(len(choice.unplaced))} unplaced</Text>
        {[<Text key={slot.task_id} style={styles.text}>
            {clock_time(slot.start)}–{clock_time(slot.end)}  {task_title(tasks, slot.task_id)}
        </Text> for slot in choice.slots]}
        {[<Text key={id} style={styles.orange}>Unplaced: {task_title(tasks, id)}</Text> for id in choice.unplaced]}
        <Text style={styles.small}>{choice.source}</Text>
    </View>
}

obj MobileTurn { has question: str, answer: SecretaryRunView; }

def:pub MobileApp(embedded: bool = False, initial_day: str = "", sync_version: int = 0,
                   onChanged: any = None, onSignOut: any = None, onDayChanged: any = None) -> JsxElement {
    has signed_in: bool = jacIsLoggedIn(), registering: bool = False,
        username: str = "", password: str = "", board: Board | None = None,
        tab: str = "plan", message: str = "", busy: bool = False,
        selected_day: str = "", home_day: str = "",
        task_title_input: str = "", task_minutes: str = "60", task_due: str = "20:00",
        task_due_day: str = "",
        task_at: str = "", disruption_title: str = "", disruption_start: str = "14:00",
        disruption_end: str = "17:00", model_schedule: bool = False,
        secretary_question: str = "", secretary_reply: SecretaryRunView | None = None,
        secretary_inbox: list[NotificationView] = [],
        plan_section: str = "schedule", more_section: str = "goals", capture_kind: str = "task",
        calendar: PlannerMonth | None = None, calendar_open: bool = False, date_input: str = "",
        task_priority: int = 2, task_dependencies: list[str] = [], task_goal: str = "",
        goal_title_input: str = "", goal_target: str = "", goal_importance: str = "medium",
        event_title: str = "", event_start: str = "09:00", event_end: str = "10:00",
        hours_start: str = "", hours_end: str = "", hours_dirty: bool = False, advanced_capture: bool = False,
        last_question: str = "", show_steps: bool = False, mobile_turns: list[MobileTurn] = [],
        review_operation: str = "", review_id: str = "", review_title: str = "",
        breakdown: BreakdownProposal | None = None, breakdown_titles: list[str] = [], breakdown_minutes: list[str] = [];

    board_request: any = useRef(0);
    mobile_scroll: any = useRef(None);
    composer_ref: any = useRef(None);
    async def ask_secretary() -> None {
        if not secretary_question.strip() { return; }
        if busy { return; }
        busy = True;
        try {
            query = secretary_question.strip();
            secretary_reply = await secretary_run(query=query, day=selected_day, use_model=True);
            last_question = query;
            mobile_turns = (mobile_turns + [MobileTurn(question=query, answer=secretary_reply)])[-12:];
            show_steps = False;
            secretary_question = "";
            tab = "home";
            await refresh(notify=True);
        } except Exception { message = "The secretary could not finish. Your saved plan has not been confirmed changed."; }
        finally { busy = False; }
    }
    async def dismiss_notification(id: str) -> None {
        try {
            result: SecretaryAction = await secretary_notification(notification_id=id, action="dismiss");
            message = result.message;
            secretary_inbox = await secretary_notifications();
        } except Exception { message = "The notification update could not be confirmed. Refresh before retrying."; }
    }
    async def refresh(day: str = "", notify: bool = False, today: bool = False) -> None {
        board_request["current"] += 1;
        request_id = board_request["current"];
        try {
            loaded_board: Board = await get_board(day="" if today else day if day else selected_day);
            if request_id != board_request["current"] { return; }
            board = loaded_board;
            latest: list[NotificationView] = await secretary_notifications();
            if request_id != board_request["current"] { return; }
            secretary_inbox = latest;
            selected_day = loaded_board.day;
            date_input = loaded_board.day;
            if not hours_dirty { hours_start = clock_time(loaded_board.day_start); hours_end = clock_time(loaded_board.day_end); }
            if embedded and loaded_board.day != initial_day and onDayChanged { onDayChanged(loaded_board.day); }
            if embedded and notify and onChanged { onChanged(); }
            if not home_day { home_day = loaded_board.day; }
        } except Exception as error {
            if request_id != board_request["current"] { return; }
            failure: any = error;
            if failure.status == 401 { signed_in = False; }
            signed_in = signed_in and jacIsLoggedIn();
            if embedded and not signed_in and onSignOut { onSignOut(); }
            message = "Sign in again to reopen your private plan." if not signed_in else "Could not load your plan. Check the server connection and try again.";
        }
    }
    async can with entry { if signed_in and not embedded { await refresh(); } }
    useEffect(lambda {
        if embedded and signed_in { refresh(day=initial_day); }
    }, [initial_day, sync_version, signed_in]);
    useEffect(lambda {
        if mobile_scroll.current { mobile_scroll.current.scrollTo({y: 0, animated: False}); }
    }, [tab]);
    useEffect(lambda {
        if mobile_scroll.current and mobile_turns { mobile_scroll.current.scrollToEnd({animated: False}); }
    }, [mobile_turns]);

    async def go_today() -> None {
        tab = "plan";
        await refresh(today=True);
    }

    async def open_outlook(day: str) -> None {
        tab = "plan";
        calendar_open = False;
        task_dependencies = [];
        await refresh(day=day);
    }

    async def authenticate() -> None {
        if not login_name(username) or len(password) < 8 {
            message = "Use a username of 3 to 32 letters, numbers, underscores or hyphens, and a password of at least eight characters.";
            return;
        }
        if busy { return; }
        busy = True;
        message = "";
        signup: SignupResult | None = None;
        ok: bool = False;
        identity = {"type": "username", "value": login_name(username)};
        try {
            if registering {
                signup = await jacSignup([identity], password);
                if not signup.success {
                    message = "Account could not be created.";
                    busy = False;
                    return;
                }
            }
            ok = await jacLogin(identity, password);
            if ok { signed_in = True; await refresh(notify=True); }
            else { message = "Sign-in failed. Check your details."; }
        } except Exception {
            message = "Cannot connect to Replaniva right now.";
        }
        finally { busy = False; }
    }
    async def save_task() -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await create_task(title=task_title_input, day=selected_day,
                                       duration=int(task_minutes),
                                       deadline=to_minutes(task_due), due_day=task_due_day,
                                       preferred_start=to_minutes(task_at), priority=task_priority, depends_on=task_dependencies, goal_id=task_goal);
            message = result.message;
            if result.ok { task_title_input = ""; task_due_day = ""; task_dependencies = []; task_goal = ""; await refresh(notify=True); tab = "plan"; }
        } except Exception { message = "The result could not be confirmed. Refresh your plan before retrying."; }
        finally { busy = False; }
    }
    async def complete(task_id: str, done: bool = True) -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await set_task_done(task_id=task_id, done=done);
            message = result.message;
            await refresh(notify=True);
        } except Exception { message = "The result could not be confirmed. Refresh before retrying."; }
        finally { busy = False; }
    }

    async def preview() -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await preview_recovery(title=disruption_title,
                                            day=selected_day,
                                            start=to_minutes(disruption_start),
                                            end=to_minutes(disruption_end), use_model=model_schedule);
            message = result.message;
            if result.ok { await refresh(notify=True); }
        } except Exception { message = "Could not prepare recovery. Try again."; }
        finally { busy = False; }
    }
    async def discard_recovery(id: str) -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await dismiss_recovery(proposal_id=id);
            message = result.message;
            await refresh(notify=True);
        } except Exception { message = "The preview could not be dismissed. Refresh before retrying."; }
        finally { busy = False; }
    }
    async def accept(id: str, option: str) -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await accept_recovery(proposal_id=id, option=option);
            message = result.message;
            await refresh(notify=True);
            if result.ok { tab = "plan"; }
        } except Exception { message = "The result could not be confirmed. Refresh your plan before retrying."; }
        finally { busy = False; }
    }
    async def apply_rebalance() -> None {
        if board is None or not board.rebalance.available { return; }
        if busy { return; }
        busy = True;
        try {
            res: Action = await apply_rebalance_candidate(
                from_day=board.rebalance.from_day,
                to_day=board.rebalance.to_day,
                task_id=board.rebalance.task_id
            );
            message = res.message;
            await refresh(notify=True);
        } except Exception {
            message = "The result could not be confirmed. Refresh your plan before retrying.";
        }
        finally { busy = False; }
    }
    async def accept_proposal(prop_id: str) -> None {
        if busy { return; }
        busy = True;
        try {
            res: Action = await apply_command_proposal(proposal_id=prop_id);
            message = res.message;
            await refresh(notify=True);
        } except Exception {
            message = "The result could not be confirmed. Refresh your plan before retrying.";
        }
        finally { busy = False; }
    }
    async def dismiss_proposal(prop_id: str) -> None {
        if busy { return; }
        busy = True;
        try {
            res: Action = await dismiss_command_proposal(proposal_id=prop_id);
            message = res.message;
            await refresh(notify=True);
        } except Exception {
            message = "The result could not be confirmed. Refresh your plan before retrying.";
        }
        finally { busy = False; }
    }
    async def toggle_goal_item(goal_id: str) -> None {
        if busy { return; }
        busy = True;
        try {
            res: Action = await toggle_goal(goal_id=goal_id);
            message = res.message;
            await refresh(notify=True);
        } except Exception {
            message = "The result could not be confirmed. Refresh your plan before retrying.";
        }
        finally { busy = False; }
    }


    async def load_calendar(month: str = "") -> None {
        try { calendar = await get_planner_month(month=month if month else selected_day); calendar_open = True; }
        except Exception { message = "The calendar could not load. Your selected day has not changed."; }
    }
    async def save_event() -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await create_commitment(title=event_title, day=selected_day, start=to_minutes(event_start), end=to_minutes(event_end));
            message = result.message;
            if result.ok { event_title = ""; await refresh(notify=True); tab = "plan"; }
        } except Exception { message = "The result could not be confirmed. Refresh before retrying."; }
        finally { busy = False; }
    }
    async def save_goal() -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await create_goal(title=goal_title_input, target_date=goal_target, importance=goal_importance);
            message = result.message;
            if result.ok { goal_title_input = ""; goal_target = ""; await refresh(notify=True); }
        } except Exception { message = "The result could not be confirmed. Refresh before retrying."; }
        finally { busy = False; }
    }
    async def save_hours() -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await update_planning_hours(day_start=to_minutes(hours_start), day_end=to_minutes(hours_end));
            message = result.message;
            if result.ok { hours_dirty = False; await refresh(notify=True); }
        } except Exception { message = "The update could not be confirmed. Refresh before retrying."; }
        finally { busy = False; }
    }
    def review_change(operation: str, id: str, title: str) -> None {
        review_operation = operation; review_id = id; review_title = title;
    }
    async def confirm_change() -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action | None = None;
            if review_operation == "delete_task" { result = await delete_task(task_id=review_id); }
            elif review_operation == "delete_commitment" { result = await delete_commitment(commitment_id=review_id); }
            elif review_operation == "delete_goal" { result = await delete_goal(goal_id=review_id); }
            elif review_operation == "restore" { result = await restore_revision(revision_id=review_id); }
            if result is None { message = "Choose an available action."; return; }
            message = result.message;
            review_operation = "";
            await refresh(notify=True);
        } except Exception { message = "The result could not be confirmed. Refresh before retrying."; review_operation = ""; }
        finally { busy = False; }
    }
    async def open_breakdown(id: str) -> None {
        if busy { return; }
        busy = True;
        try {
            draft: BreakdownProposal = await preview_task_breakdown(task_id=id);
            if draft.ok {
                breakdown = draft;
                breakdown_titles = [step.title for step in draft.subtasks];
                breakdown_minutes = [str(step.duration) for step in draft.subtasks];
            } else { message = draft.message; }
        } except Exception { message = "The breakdown could not load. Nothing has been applied."; }
        finally { busy = False; }
    }
    async def apply_breakdown() -> None {
        if breakdown is None or busy { return; }
        busy = True;
        try {
            result: Action = await apply_task_breakdown(task_id=breakdown.task_id, titles=breakdown_titles,
                durations=[int(value) for value in breakdown_minutes], expected_version=breakdown.base_version);
            message = result.message;
            if result.ok { breakdown = None; await refresh(notify=True); }
        } except Exception { message = "Check the step durations. Refresh before retrying an uncertain change."; }
        finally { busy = False; }
    }
    def edit_breakdown(index: int, value: str, minutes: bool = False) -> None {
        if minutes { breakdown_minutes = [value if i == index else item for (i, item) in enumerate(breakdown_minutes)]; }
        else { breakdown_titles = [value if i == index else item for (i, item) in enumerate(breakdown_titles)]; }
    }
    def pick_prompt(text: str) -> None { secretary_question = text; tab = "home"; if composer_ref.current { composer_ref.current.focus(); } }

    light_phone = board.light_mode if board is not None else False;
    styles = mobile_styles(light_phone);
    accent_color = "#a84908" if light_phone else "#f7931e";
    muted_color = "#66594b" if light_phone else "#b9afa5";
    if not signed_in {
        return <ScrollView style={styles.screen} contentContainerStyle={styles.body}>
            <View style={styles.welcomeBrand} accessibilityLabel="Replaniva">
                <Image source={{"uri": "/static/assets/replaniva-logo.png"}} style={styles.welcomeLogo}
                    resizeMode="contain" accessibilityLabel="" />
            </View>
            <Text style={styles.small}>PLANS THAT ADAPT WHEN LIFE CHANGES</Text>
            <Text style={styles.title}>{"Create your space" if registering else "Welcome back"}</Text>
            <Text style={styles.subtitle}>Your private plan, ready whenever the day changes.</Text>
            {bool(message) and <View style={styles.message}><Text style={styles.text}>{message}</Text></View>}
            <Text style={styles.label}>Username</Text>
            <TextInput style={styles.input} accessibilityLabel="Mobile username" value={username} autoCapitalize="none"
                keyboardType="default" placeholder="your_username"
                placeholderTextColor={muted_color} onChangeText={lambda (value: str) { username = value; }}/>
            <Text style={styles.label}>Password</Text>
            <TextInput style={styles.input} accessibilityLabel="Mobile password" value={password} secureTextEntry={True}
                placeholder="At least 8 characters" placeholderTextColor={muted_color}
                onChangeText={lambda (value: str) { password = value; }}/>
            <Pressable style={styles.button} disabled={busy} onPress={lambda -> None { authenticate(); return; }}>
                <Text style={styles.buttonText}>{"Create account" if registering else "Sign in"}</Text>
            </Pressable>
            <Pressable style={styles.secondary} onPress={lambda { registering = not registering; message = ""; }}>
                <Text style={styles.secondaryText}>{"Already have an account? Sign in" if registering else "New here? Create an account"}</Text>
            </Pressable>
        </ScrollView>;
    }
    current = board;
    proposal_id = current.proposal.id if current is not None and current.proposal is not None else "";
    if review_operation or breakdown is not None {
        return <KeyboardAvoidingView style={styles.screen} behavior={"padding" if Platform.OS == "ios" else "height"}>
            <View style={styles.header}><Text style={styles.brand}>Review changes</Text><Pressable accessibilityRole="button" accessibilityLabel="Close mobile review" style={styles.secondary} disabled={busy} onPress={lambda { review_operation = ""; breakdown = None; }}><Text style={styles.secondaryText}>Back</Text></Pressable></View>
            <ScrollView style={styles.scroll} contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled">
                {bool(review_operation) and <View style={styles.card}><Text style={styles.sectionTitle}>{"Restore a previous plan?" if review_operation == "restore" else "Remove this item?"}</Text><Text style={styles.strong}>{review_title}</Text><Text style={styles.muted}>{"The shared planner checks that the saved recovery is still fresh and valid." if review_operation == "restore" else "This changes your saved plan across Web, Mobile and CLI. Review the item before confirming."}</Text><Pressable accessibilityRole="button" style={styles.button} disabled={busy} onPress={lambda -> None { confirm_change(); return; }}><Text style={styles.buttonText}>Confirm change</Text></Pressable><Pressable accessibilityRole="button" style={styles.secondary} disabled={busy} onPress={lambda { review_operation = ""; }}><Text style={styles.secondaryText}>Keep current plan</Text></Pressable></View>}
                {breakdown is not None and <View style={styles.card}><Text style={styles.sectionTitle}>Smaller steps</Text><Text style={styles.strong}>{breakdown.original_title}</Text><Text style={styles.muted}>Edit each step and its minutes. The saved task remains unchanged until you apply this breakdown.</Text>{[<View key={str(index)} style={styles.nextAction}><Text style={styles.label}>Step {str(index + 1)}</Text><TextInput accessibilityLabel={"Mobile step " + str(index + 1) + " title"} style={styles.input} value={breakdown_titles[index]} onChangeText={lambda (value: str) { edit_breakdown(index, value); }}/><Text style={styles.label}>Minutes</Text><TextInput accessibilityLabel={"Mobile step " + str(index + 1) + " minutes"} style={styles.input} keyboardType="numeric" value={breakdown_minutes[index]} onChangeText={lambda (value: str) { edit_breakdown(index, value, True); }}/></View> for index in range(len(breakdown_titles))]}<Pressable accessibilityRole="button" style={styles.button} disabled={busy} onPress={lambda -> None { apply_breakdown(); return; }}><Text style={styles.buttonText}>Apply breakdown</Text></Pressable></View>}
                {bool(message) and <View style={styles.message} accessibilityRole="alert"><Text style={styles.text}>{message}</Text></View>}
            </ScrollView>
        </KeyboardAvoidingView>;
    }
    return <KeyboardAvoidingView style={styles.screen} behavior={"padding" if Platform.OS == "ios" else "height"}>
        <View style={[styles.header, {paddingTop: 24 if embedded else 36 if Platform.OS == "ios" else 20}]}>
            <View style={styles.brandRow}><Image source={{uri: "/static/assets/replaniva-favicon.png"}} style={styles.brandIcon} accessibilityLabel=""/><Text style={styles.brand}>replaniva.</Text></View>
            <Pressable accessibilityRole="button" accessibilityLabel="Mobile menu" style={styles.iconButton} onPress={lambda { tab = "more"; }}><MobileGlyph name="menu" color={accent_color}/></Pressable>
        </View>
        <ScrollView style={styles.scroll} contentContainerStyle={styles.body} keyboardShouldPersistTaps="handled" ref={mobile_scroll}>
            {bool(message) and <View style={styles.message} accessibilityRole="alert"><Text style={styles.text}>{message}</Text><Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda { message = ""; }}><Text style={styles.secondaryText}>Dismiss message</Text></Pressable></View>}
            {current is None and <View style={styles.card}><Text style={styles.strong}>Opening your private plan</Text><Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda -> None { refresh(); return; }}><Text style={styles.secondaryText}>Try loading plan</Text></Pressable></View>}
            {current is not None and tab == "home" and <View style={{gap: 20}}>
                <View style={styles.hero}><Text style={styles.muted}>A little clarity. A way forward.</Text><Text style={styles.title}>{"What is on\nyour mind?" if not mobile_turns else "Let’s find your way forward."}</Text><Pressable accessibilityRole="button" accessibilityLabel="Mobile select planning date" onPress={lambda -> None { tab = "plan"; load_calendar(); return; }} style={{minHeight: 44, justifyContent: "center"}}><Text style={styles.muted}>Your plan · {day_label(current.day)}</Text></Pressable></View>
                {not mobile_turns and <View style={styles.tabs}>
                    <Pressable accessibilityRole="button" accessibilityLabel="Find my next step" style={styles.feature} onPress={lambda { pick_prompt("What should I do next?"); }}><View style={styles.featureTop}><View style={styles.featureBadge}><MobileGlyph name="calendar" color={accent_color}/></View><MobileGlyph name="arrow" color={accent_color}/></View><View><Text style={styles.strong}>Find my{ "\n" }next step</Text><Text style={styles.muted}>A clear start from{ "\n" }your saved plan.</Text></View></Pressable>
                    <Pressable accessibilityRole="button" accessibilityLabel="Make room for change" style={[styles.feature, styles.featureWarm]} onPress={lambda { tab = "recovery"; }}><View style={styles.featureTop}><View style={styles.featureBadge}><MobileGlyph name="recover" color={accent_color}/></View><MobileGlyph name="arrow" color={accent_color}/></View><View><Text style={styles.strong}>Make room{ "\n" }for change</Text><Text style={styles.muted}>Explore alternatives.{ "\n" }You choose the plan.</Text></View></Pressable>
                </View>}
                <View style={{gap: 10}}><Text style={styles.strong}>Start with a question</Text><View style={styles.wrap}>{[<Pressable accessibilityRole="button" key={str(index)} style={styles.chip} onPress={lambda { pick_prompt(["What should I do next?", "What is at risk?", "How much capacity do I have?", "Explain my plan"][index]); }}><Text style={styles.chipText}>{label}</Text></Pressable> for (index, label) in enumerate(["What’s next?", "Check risks", "My capacity", "Explain my plan"])]}</View></View>
                {[<View key={str(index)} style={styles.conversation}><View style={styles.userBubble}><Text style={styles.text}>{turn.question}</Text></View><View style={styles.assistantBubble} testID="mobile-secretary-reply"><View style={styles.brandRow}><Image source={{uri: "/static/assets/replaniva-favicon.png"}} style={{width: 22, height: 22}} accessibilityLabel=""/><Text style={styles.small}>REPLANIVA</Text></View><Text style={styles.text}>{turn.answer.summary}</Text><Text style={styles.muted}>{turn.answer.source}</Text>{index == len(mobile_turns) - 1 and <Pressable accessibilityRole="button" accessibilityState={{expanded: show_steps}} style={styles.secondary} onPress={lambda { show_steps = not show_steps; }}><Text style={styles.secondaryText}>{"Hide reasoning" if show_steps else "Why this answer?"}</Text></Pressable>}{show_steps and index == len(mobile_turns) - 1 and [<Text key={str(i)} style={styles.muted}>{step}</Text> for (i, step) in enumerate(turn.answer.steps)]}</View></View> for (index, turn) in enumerate(mobile_turns)]}
                {current.command_proposals and <View style={styles.message}><Text style={styles.strong}>{str(len(current.command_proposals))} proposal(s) ready for review</Text><Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda { tab = "more"; more_section = "reviews"; }}><Text style={styles.secondaryText}>Review proposed changes</Text></Pressable></View>}
                {not mobile_turns and <Pressable accessibilityRole="button" style={styles.card} onPress={lambda { tab = "plan"; }}><Text style={styles.small}>YOUR NEXT STEP</Text><Text style={styles.strong}>{current.briefing.next_action.title}</Text><Text style={styles.muted}>{current.briefing.next_action.reason}</Text></Pressable>}
            </View>}
            {current is not None and tab == "plan" and <View style={{gap: 16}}>
                <View style={styles.row}><Text style={styles.sectionTitle}>Your plan</Text><Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda -> None { refresh(); return; }}><Text style={styles.secondaryText}>Refresh</Text></Pressable></View>
                <Pressable accessibilityRole="button" accessibilityLabel="Mobile select planning date" style={styles.card} onPress={lambda -> None { load_calendar(); return; }}><View style={styles.row}><View><Text style={styles.small}>PLANNING DATE</Text><Text style={styles.strong}>{day_label(current.day)}</Text></View><MobileGlyph name="calendar" color={accent_color}/></View></Pressable>
                {calendar_open and <View style={styles.card}>
                    <View style={styles.row}><Text style={styles.strong}>Choose a day</Text><Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda { calendar_open = False; }}><Text style={styles.secondaryText}>Close</Text></Pressable></View>
                    <Text style={styles.label}>Date · YYYY-MM-DD</Text><TextInput accessibilityLabel="Mobile planning date" style={styles.input} value={date_input} onChangeText={lambda (value: str) { date_input = value; }}/><Pressable accessibilityRole="button" style={styles.button} onPress={lambda -> None { open_outlook(date_input); return; }}><Text style={styles.buttonText}>Open date</Text></Pressable>
                    {calendar is not None and <View style={{gap: 8}}><View style={styles.row}><Pressable accessibilityRole="button" accessibilityLabel="Mobile previous month" style={styles.secondary} onPress={lambda -> None { if calendar is not None { load_calendar(calendar.previous); } return; }}><Text style={styles.secondaryText}>‹</Text></Pressable><Text style={styles.strong}>{calendar.label}</Text><Pressable accessibilityRole="button" accessibilityLabel="Mobile next month" style={styles.secondary} onPress={lambda -> None { if calendar is not None { load_calendar(calendar.following); } return; }}><Text style={styles.secondaryText}>›</Text></Pressable></View><View style={styles.calendarGrid}>{[<View key={str(i)} style={styles.calendarCell}><Text style={styles.muted}>{label}</Text></View> for (i, label) in enumerate(["M", "T", "W", "T", "F", "S", "S"])]}{[<Pressable accessibilityRole="button" accessibilityLabel={day_label(day.day) + ", " + str(day.tasks) + " tasks, " + str(day.commitments) + " commitments"} accessibilityState={{selected: day.day == current.day}} key={day.day} style={[styles.calendarCell, styles.calendarSelected if day.day == current.day else {}, styles.calendarOutside if not day.in_month else {}]} onPress={lambda -> None { open_outlook(day.day); return; }}><Text style={styles.text}>{str(day.number)}</Text>{(day.tasks or day.commitments or day.deadlines) and <View style={styles.calendarDot}/>}</Pressable> for day in calendar.days]}</View><Text style={styles.muted}>Dots mark tasks, commitments or deadlines.</Text></View>}
                    <Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda -> None { go_today(); calendar_open = False; return; }}><Text style={styles.secondaryText}>Back to today</Text></Pressable>
                </View>}
                <View style={styles.tabs}>{[<Pressable accessibilityRole="button" accessibilityState={{selected: plan_section == key}} key={key} style={[styles.tab, styles.activeTab if plan_section == key else {}]} onPress={lambda { plan_section = key; }}><Text style={styles.activeText if plan_section == key else styles.tabText}>{label}</Text></Pressable> for (key, label) in [("schedule", "Schedule"), ("week", "Week"), ("risks", "Health")]]}</View>
                {plan_section == "schedule" and <View style={{gap: 14}}>
                    <View style={[styles.card, styles.briefing]}><View style={styles.row}><Text style={styles.strong}>Room for what matters</Text><Text style={styles.healthPill}>{current.briefing.health.label}</Text></View><Text style={styles.title}>{duration_label(current.briefing.health.slack_minutes)}</Text><Text style={styles.muted}>{duration_label(current.briefing.health.required_minutes)} needed · {duration_label(current.briefing.health.available_minutes)} available</Text><Text style={styles.muted}>Planning hours {clock_time(current.day_start)} to {clock_time(current.day_end)}</Text></View>
                    {not current.tasks and not current.commitments and <View style={styles.card}><Text style={styles.strong}>A little room to begin</Text><Text style={styles.muted}>Your day has no saved work yet. Capture a task or a fixed commitment.</Text><Pressable accessibilityRole="button" style={styles.button} onPress={lambda { tab = "capture"; }}><Text style={styles.buttonText}>Capture something</Text></Pressable></View>}
                    {current.commitments and <Text style={styles.small}>FIXED COMMITMENTS</Text>}{[<View key={event.id} style={styles.card}><Text style={styles.small}>{clock_time(event.start)}–{clock_time(event.end)}</Text><Text style={styles.strong}>{event.title}</Text><Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda { review_change("delete_commitment", event.id, event.title); }}><Text style={styles.secondaryText}>Remove commitment</Text></Pressable></View> for event in current.commitments]}
                    {current.tasks and <Text style={styles.small}>FLEXIBLE WORK</Text>}{[<View key={task.id} style={styles.card} testID={"mobile-task-" + task.id}><View style={styles.row}><Text style={[styles.strong, {flex: 1}]}>{task.title}</Text><Text style={styles.orange}>{"Done" if task.done else clock_time(task.start)}</Text></View><Text style={styles.muted}>{str(task.duration)} min · Due {day_label(task.due_day)} at {clock_time(task.deadline)}</Text>{task.depends_on and <Text style={styles.muted}>Depends on: {", ".join([task_title(current.tasks, id) for id in task.depends_on])}</Text>}{bool(task.goal_id) and <Text style={styles.muted}>Goal: {mobile_goal_title(current, task.goal_id)}</Text>}<Pressable accessibilityRole="button" style={styles.secondary} disabled={busy} onPress={lambda -> None { complete(task.id, not task.done); return; }}><Text style={styles.secondaryText}>{"Reopen task" if task.done else "Mark done"}</Text></Pressable>{not task.done and <Pressable accessibilityRole="button" style={styles.secondary} disabled={busy} onPress={lambda -> None { open_breakdown(task.id); return; }}><Text style={styles.secondaryText}>Break into smaller steps</Text></Pressable>}<Pressable accessibilityRole="button" style={styles.secondary} disabled={busy} onPress={lambda { review_change("delete_task", task.id, task.title); }}><Text style={styles.secondaryText}>Remove task</Text></Pressable></View> for task in current.tasks]}
                </View>}
                {plan_section == "week" and <View style={{gap: 12}}><Text style={styles.strong}>Seven-day outlook</Text>{[<Pressable accessibilityRole="button" key={day_label(outlook.day)} style={styles.card} accessibilityLabel={day_label(outlook.day) + ", " + outlook.label} onPress={lambda -> None { open_outlook(outlook.day); plan_section = "schedule"; return; }}><View style={styles.row}><Text style={styles.strong}>{day_label(outlook.day)}</Text><Text style={styles.orange}>{outlook.label}</Text></View><Text style={styles.muted}>{duration_label(outlook.required_minutes)} work · {duration_label(outlook.available_minutes)} available</Text></Pressable> for outlook in current.horizon]}{current.rebalance.available and <View style={[styles.card, styles.option]}><Text style={styles.small}>SAFE MOVE FOUND</Text><Text style={styles.strong}>Move {current.rebalance.task_title} to {day_label(current.rebalance.to_day)}</Text><Text style={styles.muted}>{current.rebalance.reason}</Text><Pressable accessibilityRole="button" style={styles.button} disabled={busy} onPress={lambda -> None { apply_rebalance(); return; }}><Text style={styles.buttonText}>Apply rebalance</Text></Pressable></View>}</View>}
                {plan_section == "risks" and <View style={{gap: 12}}><View style={styles.card}><Text style={styles.strong}>{current.briefing.headline}</Text><Text style={styles.text}>{current.briefing.summary}</Text>{[<Text key={str(i)} style={styles.muted}>{reason}</Text> for (i, reason) in enumerate(current.briefing.health.reasons)]}</View><Text style={styles.strong}>Risk radar</Text>{not current.briefing.risks and <Text style={styles.muted}>No current planning risks detected.</Text>}{[<View key={str(i)} style={styles.card}><Text style={styles.strong}>{risk.title}</Text><Text style={styles.muted}>{risk.detail}</Text></View> for (i, risk) in enumerate(current.briefing.risks)]}</View>}
            </View>}
            {current is not None and tab == "capture" and <View style={{gap: 16}}>
                <Text style={styles.sectionTitle}>Make room for it.</Text><Text style={styles.muted}>Capture for {day_label(current.day)}. The shared planner checks how it fits.</Text><View style={styles.tabs}>{[<Pressable accessibilityRole="button" accessibilityState={{selected: capture_kind == key}} key={key} style={[styles.tab, styles.activeTab if capture_kind == key else {}]} onPress={lambda { capture_kind = key; }}><Text style={styles.activeText if capture_kind == key else styles.tabText}>{label}</Text></Pressable> for (key, label) in [("task", "Task"), ("event", "Commitment")]]}</View><Text style={styles.muted}>Planning date · {day_label(current.day)}</Text>
                {capture_kind == "task" and <View style={styles.card}>
                    <Text style={styles.label}>What needs doing?</Text><TextInput style={styles.input} accessibilityLabel="Mobile task title" value={task_title_input} placeholder="Prepare project brief" placeholderTextColor={muted_color} onChangeText={lambda (value: str) { task_title_input = value; }}/>
                    <Text style={styles.label}>Minutes</Text><TextInput style={styles.input} accessibilityLabel="Mobile task minutes" value={task_minutes} keyboardType="numeric" onChangeText={lambda (value: str) { task_minutes = value; }}/>
                    <Text style={styles.label}>Done by · HH:MM</Text><TextInput style={styles.input} accessibilityLabel="Mobile task deadline" value={task_due} onChangeText={lambda (value: str) { task_due = value; }}/>
                    <Text style={styles.label}>Priority</Text><View style={styles.tabs}>{[<Pressable accessibilityRole="button" accessibilityState={{selected: task_priority == value}} key={str(value)} style={[styles.tab, styles.activeTab if task_priority == value else {}]} onPress={lambda { task_priority = value; }}><Text style={styles.activeText if task_priority == value else styles.tabText}>{label}</Text></Pressable> for (value, label) in [(1, "Low"), (2, "Medium"), (3, "High")]]}</View>
                    <Pressable accessibilityRole="button" accessibilityState={{expanded: advanced_capture}} style={styles.secondary} onPress={lambda { advanced_capture = not advanced_capture; }}><Text style={styles.secondaryText}>{"Hide dates and relationships" if advanced_capture else "Dates, dependencies and goal"}</Text></Pressable>
                    {advanced_capture and <View style={{gap: 12}}><Text style={styles.label}>Due date · YYYY-MM-DD (optional)</Text><TextInput accessibilityLabel="Mobile task due date" style={styles.input} value={task_due_day} placeholder={current.day} placeholderTextColor={muted_color} onChangeText={lambda (value: str) { task_due_day = value; }}/><Text style={styles.muted}>Due {day_label(task_due_day or current.day)}</Text><Text style={styles.label}>Best time · HH:MM (optional)</Text><TextInput accessibilityLabel="Mobile task best time" style={styles.input} value={task_at} placeholder="14:00" placeholderTextColor={muted_color} onChangeText={lambda (value: str) { task_at = value; }}/><Text style={styles.label}>Prerequisites</Text>{not [task for task in current.tasks if not task.done] and <Text style={styles.muted}>Capture another task first to use it as a prerequisite.</Text>}{[<Pressable accessibilityRole="checkbox" accessibilityState={{checked: task.id in task_dependencies}} accessibilityLabel={"Prerequisite: " + task.title} key={task.id} style={[styles.secondary, styles.activeTab if task.id in task_dependencies else {}]} onPress={lambda { task_dependencies = [id for id in task_dependencies if id != task.id] if task.id in task_dependencies else task_dependencies + [task.id]; }}><Text style={styles.secondaryText}>{("Selected · " if task.id in task_dependencies else "") + task.title}</Text></Pressable> for task in current.tasks if not task.done]}<Text style={styles.label}>Supports a goal</Text><Pressable accessibilityRole="button" accessibilityState={{selected: not task_goal}} style={[styles.secondary, styles.activeTab if not task_goal else {}]} onPress={lambda { task_goal = ""; }}><Text style={styles.secondaryText}>No linked goal</Text></Pressable>{[<Pressable accessibilityRole="button" accessibilityState={{selected: task_goal == goal.id}} key={goal.id} style={[styles.secondary, styles.activeTab if task_goal == goal.id else {}]} onPress={lambda { task_goal = goal.id; }}><Text style={styles.secondaryText}>{goal.title}</Text></Pressable> for goal in current.goals]}</View>}
                    <Pressable accessibilityRole="button" style={styles.button} disabled={busy or not task_title_input.strip()} onPress={lambda -> None { save_task(); return; }}><Text style={styles.buttonText}>{"Saving…" if busy else "Add task"}</Text></Pressable>
                </View>}
                {capture_kind == "event" and <View style={styles.card}><Text style={styles.label}>Fixed commitment</Text><TextInput accessibilityLabel="Mobile commitment title" style={styles.input} value={event_title} onChangeText={lambda (value: str) { event_title = value; }}/><Text style={styles.label}>Starts · HH:MM</Text><TextInput accessibilityLabel="Mobile commitment starts" style={styles.input} value={event_start} onChangeText={lambda (value: str) { event_start = value; }}/><Text style={styles.label}>Ends · HH:MM</Text><TextInput accessibilityLabel="Mobile commitment ends" style={styles.input} value={event_end} onChangeText={lambda (value: str) { event_end = value; }}/><Pressable accessibilityRole="button" style={styles.button} disabled={busy or not event_title.strip()} onPress={lambda -> None { save_event(); return; }}><Text style={styles.buttonText}>Save commitment</Text></Pressable></View>}
            </View>}
            {current is not None and tab == "recovery" and <View style={{gap: 16}}>
                <Text style={styles.sectionTitle}>Life changed?{ "\n" }Your plan can too.</Text><Text style={styles.muted}>Preview alternatives for {day_label(current.day)}. Nothing moves until you accept a validated choice.</Text>
                <View style={styles.card}><Text style={styles.label}>What happened?</Text><TextInput style={styles.input} accessibilityLabel="Mobile disruption title" value={disruption_title} placeholder="Unexpected meeting" placeholderTextColor={muted_color} onChangeText={lambda (value: str) { disruption_title = value; }}/><Text style={styles.label}>Starts · HH:MM</Text><TextInput style={styles.input} accessibilityLabel="Mobile disruption starts" value={disruption_start} onChangeText={lambda (value: str) { disruption_start = value; }}/><Text style={styles.label}>Ends · HH:MM</Text><TextInput style={styles.input} accessibilityLabel="Mobile disruption ends" value={disruption_end} onChangeText={lambda (value: str) { disruption_end = value; }}/><View style={styles.row}><Text style={[styles.muted, {flex: 1}]}>Include a model-assisted alternative (uses allowance)</Text><Switch trackColor={{false: "#766b60", true: accent_color}} thumbColor={"#fffdf9"} style={{width: 44, height: 24}} accessibilityLabel="Mobile model-assisted recovery" value={model_schedule} disabled={busy} onValueChange={lambda (value: bool) { model_schedule = value; }}/></View><Pressable accessibilityRole="button" style={styles.button} disabled={busy or not disruption_title.strip()} onPress={lambda -> None { preview(); return; }}><Text style={styles.buttonText}>Explore recovery</Text></Pressable></View>
                {current.proposal is not None and <View style={{gap: 12}}><Text style={styles.strong}>{current.proposal.title}</Text><ChoiceMobile choice={current.proposal.minimal} tasks={current.tasks} light={current.light_mode}/><Pressable accessibilityRole="button" style={styles.secondary} disabled={busy} onPress={lambda -> None { accept(proposal_id, "minimal"); return; }}><Text style={styles.secondaryText}>Accept minimal moves</Text></Pressable><ChoiceMobile choice={current.proposal.deadline} tasks={current.tasks} light={current.light_mode}/><Pressable accessibilityRole="button" style={styles.button} disabled={busy} onPress={lambda -> None { accept(proposal_id, "deadline"); return; }}><Text style={styles.buttonText}>Accept deadline plan</Text></Pressable><Pressable accessibilityRole="button" style={styles.secondary} disabled={busy} onPress={lambda -> None { discard_recovery(proposal_id); return; }}><Text style={styles.secondaryText}>Discard simulation</Text></Pressable></View>}
                {current.revisions and <View style={styles.card}><Text style={styles.strong}>Recovery history</Text>{[<View key={revision.id} style={styles.nextAction}><Text style={styles.text}>{revision.title}</Text><Text style={styles.muted}>{"Restored" if revision.restored else "Accepted recovery"}</Text>{not revision.restored and <Pressable accessibilityRole="button" style={styles.secondary} disabled={busy} onPress={lambda { review_change("restore", revision.id, revision.title); }}><Text style={styles.secondaryText}>Review restore</Text></Pressable>}</View> for revision in current.revisions]}</View>}
            </View>}
            {current is not None and tab == "more" and <View style={{gap: 16}}>
                <Text style={styles.sectionTitle}>Your connected plan</Text><View style={styles.wrap}>{[<Pressable accessibilityRole="button" accessibilityState={{selected: more_section == key}} key={key} style={[styles.chip, styles.activeTab if more_section == key else {}]} onPress={lambda { more_section = key; }}><Text style={styles.chipText}>{label}</Text></Pressable> for (key, label) in [("goals", "Goals"), ("reviews", "Reviews"), ("inbox", "Inbox"), ("activity", "Activity"), ("settings", "Settings")]]}</View>
                {more_section == "goals" and <View style={{gap: 14}}><View style={styles.card}><Text style={styles.strong}>Keep the bigger picture</Text><Text style={styles.label}>Goal</Text><TextInput accessibilityLabel="Mobile goal title" style={styles.input} value={goal_title_input} placeholder="Make time for what matters" placeholderTextColor={muted_color} onChangeText={lambda (value: str) { goal_title_input = value; }}/><Text style={styles.label}>Target date · YYYY-MM-DD (optional)</Text><TextInput accessibilityLabel="Mobile goal target date" style={styles.input} value={goal_target} onChangeText={lambda (value: str) { goal_target = value; }}/><Text style={styles.label}>Importance</Text><View style={styles.tabs}>{[<Pressable accessibilityRole="button" accessibilityState={{selected: goal_importance == key}} key={key} style={[styles.tab, styles.activeTab if goal_importance == key else {}]} onPress={lambda { goal_importance = key; }}><Text style={styles.tabText}>{label}</Text></Pressable> for (key, label) in [("low", "Low"), ("medium", "Medium"), ("high", "High")]]}</View><Pressable accessibilityRole="button" style={styles.button} disabled={busy or not goal_title_input.strip()} onPress={lambda -> None { save_goal(); return; }}><Text style={styles.buttonText}>Add goal</Text></Pressable></View>{[<View key={goal.id} style={styles.card}><Text style={styles.strong}>{goal.title}</Text><Text style={styles.muted}>{str(goal.completed_tasks)} / {str(goal.total_tasks)} tasks complete{(" · Target " + day_label(goal.target_date)) if goal.target_date else ""}</Text><Pressable accessibilityRole="button" style={styles.secondary} disabled={busy} onPress={lambda -> None { toggle_goal_item(goal.id); return; }}><Text style={styles.secondaryText}>{"Reopen goal" if goal.completed else "Complete goal"}</Text></Pressable><Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda { review_change("delete_goal", goal.id, goal.title); }}><Text style={styles.secondaryText}>Remove goal</Text></Pressable></View> for goal in current.goals]}</View>}
                {more_section == "reviews" and <View style={{gap: 12}}><Text style={styles.strong}>Proposed changes</Text><Text style={styles.muted}>The assistant proposes; you decide what becomes part of your plan.</Text>{not current.command_proposals and <Text style={styles.muted}>No Command proposals waiting for approval.</Text>}{[<View key={prop.id} style={[styles.card, styles.option]}><Text style={styles.strong}>{prop.title}</Text><Text style={styles.text}>{prop.details}</Text><Pressable accessibilityRole="button" style={styles.button} disabled={busy} onPress={lambda -> None { accept_proposal(prop.id); return; }}><Text style={styles.buttonText}>Accept proposal</Text></Pressable><Pressable accessibilityRole="button" style={styles.secondary} disabled={busy} onPress={lambda -> None { dismiss_proposal(prop.id); return; }}><Text style={styles.secondaryText}>Dismiss proposal</Text></Pressable></View> for prop in current.command_proposals]}</View>}
                {more_section == "inbox" and <View style={{gap: 12}}><Text style={styles.strong}>Your secretary inbox</Text>{not secretary_inbox and <Text style={styles.muted}>You’re all caught up. Planning updates appear here.</Text>}{[<View key={item.id} style={styles.card}><Text style={styles.strong}>{item.title}</Text><Text style={styles.text}>{item.message}</Text><Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda -> None { dismiss_notification(item.id); return; }}><Text style={styles.secondaryText}>Dismiss notification</Text></Pressable></View> for item in secretary_inbox]}</View>}
                {more_section == "activity" and <View style={{gap: 12}}><Text style={styles.strong}>Why the plan changed</Text>{not current.activities and <Text style={styles.muted}>Accepted changes will appear here.</Text>}{[<View key={item.id} style={styles.card}><Text style={styles.strong}>{item.title}</Text><Text style={styles.text}>{item.detail}</Text><Text style={styles.muted}>{day_label(item.day)}</Text></View> for item in current.activities]}</View>}
                {more_section == "settings" and <View style={{gap: 14}}><View style={styles.card}><Text style={styles.strong}>Your planning hours</Text><Text style={styles.label}>Start · HH:MM</Text><TextInput accessibilityLabel="Mobile planning starts" style={styles.input} value={hours_start} onChangeText={lambda (value: str) { hours_start = value; hours_dirty = True; }}/><Text style={styles.label}>End · HH:MM</Text><TextInput accessibilityLabel="Mobile planning ends" style={styles.input} value={hours_end} onChangeText={lambda (value: str) { hours_end = value; hours_dirty = True; }}/><Text style={styles.muted}>Saving rebuilds your plan using the same boundaries in Web and CLI.</Text><Pressable accessibilityRole="button" style={styles.button} disabled={busy} onPress={lambda -> None { save_hours(); return; }}><Text style={styles.buttonText}>Save planning hours</Text></Pressable></View><View style={styles.card}><Text style={styles.strong}>Model allowance</Text><Text style={styles.text}>{str(current.connections.model_remaining)} calls remaining today</Text><Text style={styles.muted}>{current.connections.model_label}</Text><Text style={styles.muted}>Scheduling and structured recovery remain available without a model response. Provider keys stay on the server.</Text></View><View style={styles.card}><Text style={styles.strong}>Web and device features</Text><Text style={styles.muted}>Google Calendar connection and advanced secretary preferences are available in Web Settings. Voice dictation is in Web Command. Your private plan is shared across interfaces.</Text></View></View>}
                <Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda -> None { refresh(); return; }}><Text style={styles.secondaryText}>Refresh shared plan</Text></Pressable><Pressable accessibilityRole="button" style={styles.secondary} onPress={lambda -> None { jacLogout(); signed_in = False; board = None; mobile_turns = []; if embedded and onSignOut { onSignOut(); } }}><Text style={styles.secondaryText}>Sign out</Text></Pressable>
            </View>}
        </ScrollView>
        {tab == "home" and <View style={styles.composer}><View style={styles.composerRow}><TextInput ref={composer_ref} accessibilityLabel="Mobile secretary question" style={styles.composerInput} value={secretary_question} placeholder="Ask about your day…" placeholderTextColor={muted_color} returnKeyType="send" onSubmitEditing={lambda -> None { ask_secretary(); return; }} onChangeText={lambda (value: str) { secretary_question = value; }}/><Pressable accessibilityRole="button" accessibilityLabel={"Asking secretary" if busy else "Ask secretary"} style={[styles.send, styles.disabled if busy or not secretary_question.strip() else {}]} disabled={busy or not secretary_question.strip()} onPress={lambda -> None { ask_secretary(); return; }}><MobileGlyph name="send" color="#ffffff"/></Pressable></View></View>}
        <View style={styles.bottomNav} accessibilityLabel="Mobile navigation">{[<Pressable accessibilityRole="button" accessibilityLabel={"Mobile " + label} accessibilityState={{selected: tab == key}} key={key} style={[styles.navItem, styles.navSelected if tab == key else {}]} onPress={lambda { tab = key; }}><MobileGlyph name={icon} color={accent_color if tab == key else muted_color}/><Text style={styles.navActiveText if tab == key else styles.navText}>{label}</Text></Pressable> for (key, label, icon) in [("plan", "Today", "calendar"), ("home", "Command", "chat"), ("capture", "Capture", "plus"), ("recovery", "Recover", "recover"), ("more", "Settings", "menu")]]}</View>
    </KeyboardAvoidingView>;
}
