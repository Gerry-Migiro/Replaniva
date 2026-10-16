"""Replaniva Android client: Today, capture, disruption and approval."""

import from react { useRef }

import from "@jac/mobui" { View, Text, TextInput, Pressable, ScrollView, StyleSheet, Image }
import from accounts { normalize_username }
import from "@jac/runtime" { SignupResult, jacLogin, jacSignup, jacLogout, jacIsLoggedIn }
import from endpoints {
    get_board, create_task, set_task_done,
    preview_recovery, accept_recovery, apply_rebalance_candidate,
    apply_command_proposal, dismiss_command_proposal, toggle_goal,
    secretary_run,
    secretary_notifications, secretary_notification
}
import from endpoints { Board, TaskView, Action }
import from secretary { SecretaryRunView, NotificationView, SecretaryAction }
import from planning { Choice }

def login_name(value: str) -> str {
    clean = value.strip().lower();
    if "@" in clean and len(clean) <= 254 and " " not in clean { return clean; }
    return normalize_username(value);
}

glob styles = StyleSheet.create({
    screen: {flex: 1, backgroundColor: "#171717"},
    body: {padding: 20, paddingBottom: 55, gap: 15},
    brand: {fontSize: 25, fontWeight: "800", color: "#fafafa"},
    brandRow: {flexDirection: "row", alignItems: "center", gap: 9},
    brandIcon: {width: 38, height: 38},
    welcomeBrand: {alignItems: "center", gap: 5, marginBottom: 8},
    welcomeLogo: {width: 260, height: 195},
    orange: {color: "#F97316"},
    small: {fontSize: 11, fontWeight: "800", color: "#F97316", letterSpacing: 2},
    title: {fontSize: 32, fontWeight: "800", color: "#fafafa"},
    subtitle: {fontSize: 14, color: "#ababab", lineHeight: 22},
    muted: {fontSize: 13, color: "#ababab"},
    text: {fontSize: 15, color: "#fafafa"},
    strong: {fontSize: 16, fontWeight: "700", color: "#fafafa"},
    card: {backgroundColor: "#262626", padding: 17, borderRadius: 15, gap: 8,
           borderWidth: 1, borderColor: "#3f3f3f"},
    row: {flexDirection: "row", justifyContent: "space-between", alignItems: "center", gap: 10},
    tabs: {flexDirection: "row", gap: 8},
    tab: {flex: 1, alignItems: "center", padding: 12, borderRadius: 9, backgroundColor: "#262626"},
    activeTab: {backgroundColor: "#F97316"},
    tabText: {color: "#fafafa", fontWeight: "700", fontSize: 12},
    activeText: {color: "#171717", fontWeight: "800", fontSize: 12},
    input: {backgroundColor: "#1e1e1e", borderWidth: 1, borderColor: "#454545",
            color: "#fafafa", padding: 13, borderRadius: 9, fontSize: 15},
    label: {fontSize: 12, color: "#bcbcbc", fontWeight: "700"},
    button: {padding: 14, borderRadius: 10, backgroundColor: "#F97316", alignItems: "center"},
    buttonText: {color: "#171717", fontWeight: "800", fontSize: 14},
    secondary: {padding: 12, borderRadius: 10, backgroundColor: "#383838", alignItems: "center"},
    secondaryText: {color: "#fafafa", fontWeight: "700", fontSize: 13},
    message: {backgroundColor: "#f9731622", borderWidth: 1, borderColor: "#f9731666",
              padding: 12, borderRadius: 9},
    fixed: {borderColor: "#f9731688"},
    option: {borderColor: "#f9731677"},
    briefing: {backgroundColor: "#2b241f", borderColor: "#f9731655"},
    healthRow: {flexDirection: "row", justifyContent: "space-between", alignItems: "center", gap: 10},
    healthPill: {color: "#171717", backgroundColor: "#F7931E", paddingHorizontal: 9,
                 paddingVertical: 4, borderRadius: 20, fontSize: 11, fontWeight: "800"},
    nextAction: {backgroundColor: "#1d1d1d", padding: 13, borderRadius: 10, gap: 4,
                 borderWidth: 1, borderColor: "#f9731644"}
});

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

def ChoiceMobile(choice: Choice, tasks: list[TaskView]) -> JsxElement {
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

def:pub app -> JsxElement {
    has signed_in: bool = jacIsLoggedIn(), registering: bool = False,
        username: str = "", password: str = "", board: Board | None = None,
        tab: str = "today", message: str = "", busy: bool = False,
        selected_day: str = "", home_day: str = "",
        task_title_input: str = "", task_minutes: str = "60", task_due: str = "20:00",
        task_due_day: str = "",
        task_at: str = "", disruption_title: str = "", disruption_start: str = "14:00",
        disruption_end: str = "17:00", model_schedule: bool = False,
        secretary_question: str = "", secretary_reply: SecretaryRunView | None = None,
        secretary_inbox: list[NotificationView] = [];

    board_request: any = useRef(0);
    async def ask_secretary() -> None {
        if not secretary_question.strip() { return; }
        if busy { return; }
        busy = True;
        try {
            secretary_reply = await secretary_run(query=secretary_question, day=selected_day, use_model=True);
            await refresh();
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
    async def refresh(day: str = "") -> None {
        board_request["current"] += 1;
        request_id = board_request["current"];
        try {
            loaded_board: Board = await get_board(day=day if day else selected_day);
            if request_id != board_request["current"] { return; }
            board = loaded_board;
            latest: list[NotificationView] = await secretary_notifications();
            if request_id != board_request["current"] { return; }
            secretary_inbox = latest;
            selected_day = loaded_board.day;
            if not home_day { home_day = loaded_board.day; }
        } except Exception as error {
            if request_id != board_request["current"] { return; }
            failure: any = error;
            if failure.status == 401 { signed_in = False; }
            signed_in = signed_in and jacIsLoggedIn();
            message = "Sign in again to reopen your private plan." if not signed_in else "Could not load your plan. Check the server connection and try again.";
        }
    }
    async can with entry { if signed_in { await refresh(); } }

    async def go_today() -> None {
        tab = "today";
        await refresh(day=home_day);
    }

    async def open_outlook(day: str) -> None {
        tab = "today";
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
            if ok { signed_in = True; await refresh(); }
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
                                       preferred_start=to_minutes(task_at), priority=2);
            message = result.message;
            if result.ok { task_title_input = ""; task_due_day = ""; await refresh(); tab = "today"; }
        } except Exception { message = "The result could not be confirmed. Refresh your plan before retrying."; }
        finally { busy = False; }
    }
    async def complete(task_id: str) -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await set_task_done(task_id=task_id, done=True);
            message = result.message;
            await refresh();
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
            if result.ok { await refresh(); }
        } except Exception { message = "Could not prepare recovery. Try again."; }
        finally { busy = False; }
    }
    async def accept(id: str, option: str) -> None {
        if busy { return; }
        busy = True;
        try {
            result: Action = await accept_recovery(proposal_id=id, option=option);
            message = result.message;
            await refresh();
            if result.ok { tab = "today"; }
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
            await refresh();
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
            await refresh();
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
            await refresh();
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
            await refresh();
        } except Exception {
            message = "The result could not be confirmed. Refresh your plan before retrying.";
        }
        finally { busy = False; }
    }


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
            <TextInput style={styles.input} value={username} autoCapitalize="none"
                keyboardType="default" placeholder="your_username"
                placeholderTextColor="#888888" onChangeText={lambda (value: str) { username = value; }}/>
            <Text style={styles.label}>Password</Text>
            <TextInput style={styles.input} value={password} secureTextEntry={True}
                placeholder="At least 8 characters" placeholderTextColor="#888888"
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
    return <ScrollView style={styles.screen} contentContainerStyle={styles.body}>
        <View style={styles.row}><View style={styles.brandRow}>
            <Image source={{"uri": "/static/assets/replaniva-favicon.png"}} style={styles.brandIcon}
                resizeMode="contain" accessibilityLabel="" />
            <Text style={styles.brand}>replaniva.</Text>
        </View>
            <Pressable onPress={lambda -> None { jacLogout(); signed_in = False; board = None; message = ""; }}><Text style={styles.muted}>Sign out</Text></Pressable></View>
        <Text style={styles.small}>YOUR DAY, IN MOTION</Text>
        <Text style={styles.title}>{"Today" if tab == "today" else "Capture" if tab == "capture" else "Recovery Studio"}</Text>
        {bool(message) and <View style={styles.message}><Text style={styles.text}>{message}</Text></View>}
        <View style={styles.tabs}>
            <Pressable style={[styles.tab, styles.activeTab] if tab == "today" else styles.tab} onPress={lambda -> None { go_today(); return; }}><Text style={styles.activeText if tab == "today" else styles.tabText}>Today</Text></Pressable>
            <Pressable style={[styles.tab, styles.activeTab] if tab == "capture" else styles.tab} onPress={lambda { tab = "capture"; }}><Text style={styles.activeText if tab == "capture" else styles.tabText}>Capture</Text></Pressable>
            <Pressable style={[styles.tab, styles.activeTab] if tab == "recovery" else styles.tab} onPress={lambda { tab = "recovery"; }}><Text style={styles.activeText if tab == "recovery" else styles.tabText}>Recover</Text></Pressable>
        </View>
        {current is None and <Pressable style={styles.secondary} disabled={busy}
            onPress={lambda -> None { refresh(); return; }}>
            <Text style={styles.secondaryText}>Try loading plan</Text>
        </Pressable>}
        {current is not None and tab == "today" and <View style={styles.card}><Text style={styles.strong}>Your planning secretary</Text><TextInput style={styles.input} value={secretary_question} placeholder="Ask about your saved plan" placeholderTextColor="#888888" onChangeText={lambda (value: str) { secretary_question = value; }} /><Pressable style={styles.secondary} disabled={busy} onPress={lambda -> None { ask_secretary(); return; }}><Text style={styles.secondaryText}>Ask secretary</Text></Pressable>{secretary_reply and <View><Text style={styles.text}>{secretary_reply.summary}</Text>{[<Text style={styles.muted} key={str(index)}>{secretary_reply.steps[index]}</Text> for index in range(len(secretary_reply.steps))]}</View>}{[<View style={styles.card} key={item.id}><Text style={styles.strong}>{item.title}</Text><Text style={styles.muted}>{item.message}</Text><Pressable style={styles.secondary} onPress={lambda -> None { dismiss_notification(item.id); return; }}><Text style={styles.secondaryText}>Dismiss notification</Text></Pressable></View> for item in secretary_inbox[:5]]}</View>}
        {current is not None and tab == "today" and <View style={styles.card}>
            <View style={styles.row}><Text style={styles.strong}>{current.day}</Text><Pressable onPress={lambda -> None { refresh(); return; }}><Text style={styles.orange}>Refresh</Text></Pressable></View>
            <Text style={styles.muted}>Flexible work window: {clock_time(current.day_start)} to {clock_time(current.day_end)}</Text>
            <View style={[styles.card, styles.briefing]}>
                <View style={styles.healthRow}><Text style={styles.small}>DAILY BRIEFING</Text><Text style={styles.healthPill}>{current.briefing.health.label}</Text></View>
                <Text style={styles.strong}>{current.briefing.headline}</Text>
                <Text style={styles.muted}>{current.briefing.summary}</Text>
                <Text style={styles.muted}>Capacity: {duration_label(current.briefing.health.available_minutes)} available, {duration_label(current.briefing.health.required_minutes)} needed</Text>
                <View style={styles.nextAction}>
                    <Text style={styles.small}>NEXT ACTION</Text>
                    <Text style={styles.strong}>{current.briefing.next_action.title}</Text>
                    {current.briefing.next_action.start >= 0 and <Text style={styles.orange}>{clock_time(current.briefing.next_action.start)}{current.briefing.next_action.end >= 0 and " to " + clock_time(current.briefing.next_action.end)}</Text>}
                    <Text style={styles.muted}>{current.briefing.next_action.reason}</Text>
                </View>
                {len(current.briefing.risks) > 0 and <View style={styles.nextAction}>
                    <Text style={styles.small}>RISK RADAR</Text>
                    <Text style={styles.strong}>{current.briefing.risks[0].title}</Text>
                    <Text style={styles.muted}>{current.briefing.risks[0].detail}</Text>
                </View>}
            </View>
            <Text style={styles.small}>SEVEN-DAY OUTLOOK</Text>
            {[<Pressable key={outlook.day} style={styles.card} accessibilityLabel={outlook.day + ", " + outlook.label} onPress={lambda -> None { open_outlook(outlook.day); return; }}>
                <View style={styles.row}><Text style={styles.strong}>{outlook.day}</Text><Text style={styles.orange}>{outlook.label}</Text></View>
                <Text style={styles.muted}>{duration_label(outlook.required_minutes)} work, {duration_label(outlook.available_minutes)} available</Text>
            </Pressable> for outlook in current.horizon]}
            {current.rebalance.available and <View style={[styles.card, styles.option]}>
                <Text style={styles.small}>SAFE MOVE FOUND</Text>
                <Text style={styles.strong}>Move {current.rebalance.task_title} to {current.rebalance.to_day}</Text>
                <Text style={styles.muted}>Suggested start: {clock_time(current.rebalance.suggested_start)}</Text>
                <Text style={styles.muted}>{current.rebalance.reason}</Text>
                <Pressable style={styles.button} disabled={busy} onPress={lambda -> None { apply_rebalance(); return; }}>
                    <Text style={styles.buttonText}>Apply rebalance</Text>
                </Pressable>
            </View>}
            {len(current.command_proposals) > 0 and <View style={styles.card}>
                <Text style={styles.small}>COMMAND PROPOSALS</Text>
                {[<View key={prop.id} style={[styles.card, styles.option]}>
                    <Text style={styles.strong}>{prop.title}</Text>
                    {bool(prop.details) and <Text style={styles.muted}>{prop.details}</Text>}
                    <View style={styles.row}>
                        <Pressable style={[styles.button, {flex: 1}]} disabled={busy} onPress={lambda -> None { accept_proposal(prop.id); return; }}>
                            <Text style={styles.buttonText}>Accept</Text>
                        </Pressable>
                        <Pressable style={[styles.secondary, {flex: 1}]} disabled={busy} onPress={lambda -> None { dismiss_proposal(prop.id); return; }}>
                            <Text style={styles.secondaryText}>Dismiss</Text>
                        </Pressable>
                    </View>
                </View> for prop in current.command_proposals]}
            </View>}
            {len(current.goals) > 0 and <View style={styles.card}>
                <Text style={styles.small}>GOALS</Text>
                {[<View key={goal.id} style={[styles.card, styles.option]}>
                    <View style={styles.row}>
                        <Text style={styles.strong}>{goal.title}</Text>
                        <Text style={styles.orange}>{str(goal.completed_tasks) + "/" + str(goal.total_tasks)}</Text>
                    </View>
                    {bool(goal.target_date) and <Text style={styles.muted}>Target: {goal.target_date}</Text>}
                    <Text style={styles.muted}>Progress: {str(goal.completed_tasks)}/{str(goal.total_tasks)} tasks done</Text>
                    <Pressable style={styles.secondary} disabled={busy} onPress={lambda -> None { toggle_goal_item(goal.id); return; }}>
                        <Text style={styles.secondaryText}>{"Reopen goal" if goal.completed else "Complete goal"}</Text>
                    </Pressable>
                </View> for goal in current.goals]}
            </View>}
            {len(current.activities) > 0 and <View style={styles.card}>
                <Text style={styles.small}>PLANNING ACTIVITY</Text>
                {[<View key={item.id} style={styles.nextAction}>
                    <Text style={styles.strong}>{item.title}</Text>
                    <Text style={styles.muted}>{item.detail}</Text>
                    <Text style={styles.orange}>{item.day}</Text>
                </View> for item in current.activities]}
            </View>}
            <Text style={styles.small}>FIXED COMMITMENTS</Text>
            {[<View key={event.id} style={styles.card}><Text style={styles.small}>{clock_time(event.start)}–{clock_time(event.end)}</Text><Text style={styles.strong}>{event.title}</Text></View> for event in current.commitments]}
            <Text style={styles.small}>FLEXIBLE WORK</Text>
            {[<View key={task.id} style={styles.card}><View style={styles.row}><Text style={styles.strong}>{task.title}</Text><Text style={styles.orange}>{clock_time(task.start)}</Text></View>
                <Text style={styles.muted}>{"Done" if task.done else "Due " + task.due_day + " at " + clock_time(task.deadline)}</Text>
                {not task.done and <Pressable style={styles.secondary} onPress={lambda -> None { complete(task.id); return; }}><Text style={styles.secondaryText}>Mark done</Text></Pressable>}
            </View> for task in current.tasks]}
            {len(current.tasks) == 0 and len(current.commitments) == 0 and <Text style={styles.muted}>Your day is clear. Capture a task to begin.</Text>}

        </View>}
        {tab == "capture" and <View style={styles.card}>
            <Text style={styles.small}>QUICK CAPTURE</Text><Text style={styles.strong}>What needs doing?</Text>
            <Text style={styles.label}>Task</Text><TextInput style={styles.input} value={task_title_input} placeholder="Prepare project brief" placeholderTextColor="#888888" onChangeText={lambda (value: str) { task_title_input = value; }}/>
            <Text style={styles.label}>Minutes</Text><TextInput style={styles.input} value={task_minutes} keyboardType="numeric" onChangeText={lambda (value: str) { task_minutes = value; }}/>
            <Text style={styles.label}>Done by · HH:MM</Text><TextInput style={styles.input} value={task_due} onChangeText={lambda (value: str) { task_due = value; }}/>
            <Text style={styles.label}>Due date · YYYY-MM-DD (optional)</Text><TextInput style={styles.input} value={task_due_day} placeholder="2026-10-12" placeholderTextColor="#888888" onChangeText={lambda (value: str) { task_due_day = value; }}/>
            <Text style={styles.label}>Best time · HH:MM (optional)</Text><TextInput style={styles.input} value={task_at} placeholder="14:00" placeholderTextColor="#888888" onChangeText={lambda (value: str) { task_at = value; }}/>
            <Pressable style={styles.button} disabled={busy} onPress={lambda -> None { save_task(); return; }}><Text style={styles.buttonText}>Add task</Text></Pressable>
        </View>}
        {current is not None and tab == "recovery" and <View style={styles.card}>
            <Text style={styles.small}>WHEN PLANS CHANGE</Text>
            <Text style={styles.subtitle}>Report a new fixed commitment. Compare changes before choosing one.</Text>
            <Text style={styles.label}>What happened?</Text><TextInput style={styles.input} value={disruption_title} placeholder="Unexpected meeting" placeholderTextColor="#888888" onChangeText={lambda (value: str) { disruption_title = value; }}/>
            <Text style={styles.label}>Starts · HH:MM</Text><TextInput style={styles.input} value={disruption_start} onChangeText={lambda (value: str) { disruption_start = value; }}/>
            <Text style={styles.label}>Ends · HH:MM</Text><TextInput style={styles.input} value={disruption_end} onChangeText={lambda (value: str) { disruption_end = value; }}/>
            <Pressable accessibilityRole="checkbox" accessibilityState={{"checked": model_schedule}} disabled={busy} onPress={lambda -> None { model_schedule = not model_schedule; }}><Text style={styles.label}>{"☑" if model_schedule else "☐"} Include a model-assisted alternative (uses allowance)</Text></Pressable>
            <Pressable style={styles.button} disabled={busy} onPress={lambda -> None { preview(); return; }}><Text style={styles.buttonText}>Explore recovery</Text></Pressable>
            {current.proposal is not None and <View style={styles.card}>
                <Text style={styles.strong}>Review your choices</Text>
                <Text style={styles.muted}>Your current plan remains until you accept.</Text>
                <ChoiceMobile choice={current.proposal.minimal} tasks={current.tasks}/>
                <Pressable style={styles.secondary} disabled={busy} onPress={lambda -> None { accept(proposal_id, "minimal"); return; }}><Text style={styles.secondaryText}>Accept minimal moves</Text></Pressable>
                <ChoiceMobile choice={current.proposal.deadline} tasks={current.tasks}/>
                <Pressable style={styles.button} disabled={busy} onPress={lambda -> None { accept(proposal_id, "deadline"); return; }}><Text style={styles.buttonText}>Accept deadline plan</Text></Pressable>
            </View>}
        </View>}
    </ScrollView>;
}
