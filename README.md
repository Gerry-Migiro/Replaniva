# Replaniva

**Plans that adapt when life changes.**

Replaniva is a private personal planner built around recovery. When a new commitment disrupts a day, it shows what is affected, prepares validated alternatives, explains the tradeoffs, and changes the saved plan only after approval.

## Try Replaniva

- [Live application](https://preview-jac-sbx-f8b7149b41a44ce1b83812205a496474.jachammer.app/)
- [Watch the narrated demo](https://youtu.be/0KcTfdmqosw)
- Choose **Try the demo** on the sign-in screen to explore the shared sample account, or create your own private account. Demo changes are visible to other visitors; use your own account for personal information and Calendar connections.

## Why it stands out

- **Recovery Studio:** Compare the current day with two valid recovery choices: move as little as possible or protect deadlines.
- **Daily Briefing:** See measurable plan health, remaining capacity, slack, risks, and the recommended Next Action.
- **Seven-day outlook:** Find overloaded days and review a safe nearby-day rebalance suggestion.
- **Replaniva Command:** Ask focused planning questions or create reviewable task, commitment, and what-if proposals.
- **Planning activity:** Review recent accepted changes and the reasons shown alongside them.
- **Voice on the web:** Dictate into Replaniva Command with the browser speech API, edit the transcript, then submit through the same proposal and validation flow. Useful answers can be read aloud on supported browsers.
- **Goals and task breakdown:** Track lightweight goals and preview editable, sequenced subtasks before applying them.
- **Dependencies:** Keep prerequisite work in valid order and show blocked or unplaceable work instead of hiding it.
- **Shared core:** Planning workspaces call the same authenticated planning service and deterministic scheduler.
- **One Plan. Three Interfaces:** Use the Web dashboard, the actual mobile interface inside a phone frame, and an authenticated planning command console from the same website.

The core rule is **AI proposes; deterministic Jac code validates.** Fixed commitments, overlaps, planning hours, durations, deadlines, dependencies, available capacity, proposal freshness, and placement feasibility are checked before a schedule change is accepted. The full structured recovery path works without an AI key.

## Requirements

- Jac 0.37.25
- Node.js and npm for the web client build
- Optional provider credentials for model-assisted interpretation and suggestions

## Web

From the project directory:

```bash
jac install
jac check
jac run --dev --host 127.0.0.1 --port 8000 --api-port 8001
```

Open **http://localhost:8000**. The API uses **8001**. Create an account or sign in with your username. Email-shaped usernames are also supported.

The web app supports private accounts, dates, planning hours, tasks, fixed commitments, Daily Briefing, Plan Health, Next Action, Risk Radar, weekly outlook, goals, Command proposals, voice controls, task breakdown, Recovery Studio, approval, dismissal, and restore.

A task is due on its planning date unless you choose a later due date in Capture. The later date lets Replaniva assess a requested move to another day without pretending that a deadline has changed.

## Terminal and mobile clients

### One Plan. Three Interfaces.

Open **Interfaces** after signing in and choose **Mobile app** or **CLI terminal**. The views are separate so each has usable space. **Fit screen** scales the entire 360 × 780 phone proportionally to your viewport; **Actual size** preserves its logical dimensions where space allows. The selected planning date and saved graph are shared with the Web dashboard. Interface state and console history remain available when navigating back to Today. **Refresh shared plan** reloads changes from another client.

The phone frame renders the same `mobile/interface.jac` component as the standalone mobile app through React Native Web. Web and Mobile share the saved account data, planning operations, weekday/date formatter and appearance palette. Their screen components differ: Web uses HTML; Mobile uses native-compatible components with touch navigation. Mobile supports task capture and completion, fixed commitments, goals and dependencies, planning hours, secretary questions and notifications, and recovery approval and restore. It is an interactive browser app, not a native Android demonstration.

The planning console uses the standalone CLI's command grammar and existing authenticated Jac operations. It opens in **Guided menu** mode: choose numbered actions, answer task/recovery questions one step at a time, and use `back` or `cancel` before submission. **Commands** switches to direct entry; `menu` returns to guided selection. Both modes use the same protected operations and explicit confirmation for saved changes. Type `help`, then try:

```text
today
briefing
next
week
health
goals
activity
notifications
ask "What should I do next?"
add "Prepare the weekly plan" --minutes 30 --due 18:00
```

Task creation, completion, goal changes, recovery acceptance or restore, rebalance, proposal acceptance and applying breakdowns require a separate **Confirm change** action or `confirm REVIEW_ID`. The review is bound to your account and planning version and expires after five minutes. `cancel REVIEW_ID` discards it. Recovery previews and secretary questions do not apply their proposed schedule changes.

Use `report "Unexpected meeting" --start 14:00 --end 15:00` to preview recovery, `plan` to inspect it, and `plan accept minimal` or `plan accept deadline` to request approval. `proposals`, `proposal accept NUMBER`, `proposal dismiss NUMBER`, `goal`, `rebalance`, `breakdown NUMBER`, and `notification NUMBER read|dismiss|snooze` are also supported. `help` gives the exact syntax. Output groups next action, capacity, fixed commitments and numbered tasks instead of showing raw internal IDs. Up and Down recall commands; Tab completes a unique command prefix; Ctrl+L, `clear` or **Clear output** clears the visible transcript. Ctrl+C cancels an unsent line.

This console runs planning commands only. It does not expose a shell, filesystem, server environment or arbitrary code execution. Sign-out clears the embedded clients and their transcript. Pending console reviews are held in the serving process, so a restart or switching workers can require a fresh review; no saved change is repeated automatically after a connection failure.

### Shared state and interface coverage

All clients use the same account-owned graph. A supported change becomes visible in the other clients after their shared refresh or live update; a preview remains a preview everywhere.

| Area | Web | Mobile | CLI |
|---|---|---|---|
| Plan, health, next action, outlook, questions | Available | Available | Available |
| Tasks | Capture, complete/reopen, remove, breakdown | Capture, complete/reopen, remove, breakdown | Add, complete, breakdown |
| Fixed commitments | Capture/remove | Capture/remove | Recovery capture |
| Recovery and proposals | Preview, approve, dismiss, restore | Preview, approve, dismiss, restore | Preview, approve, dismiss, restore |
| Goals | Manage and link tasks | Manage and link tasks | Manage goals |
| Settings | Full settings | Planning hours and status | Plan/status queries |
| Voice dictation and Google Calendar setup | Browser/owner setup required | Not provided | Not provided |

### Standalone clients

The terminal client shares the web account and planning API:

```bash
jac run cli -- login YOUR_USERNAME
jac run cli -- today
jac run cli -- ask "What is at risk?"
jac run cli
```

The local API defaults to `http://127.0.0.1:8001`. Set `REPLANIVA_URL` to use another deployment. The guided menu supports capture, recovery review and explicit approval. Sign-in stores a private token on the device; `jac run cli -- logout` removes it.

The mobile client uses the same protected planning operations and the same mobile component as the embedded phone:

```bash
jac run --dev --platform web mobile
jac build mobile --platform web
```

Native Android packaging requires the Android SDK and a device or emulator. A browser build does not establish native Android verification.

Mobile is a frontend for the shared Jac service. For a separately hosted browser build, serve its generated files behind the same planning API or configure the Jac runtime API base to that service. A physical device needs a reachable HTTPS backend. Do not create a separate planning service or account for each interface.

## Recovery Studio

Enter a disruption and its time, then choose **Explore recovery**. Previewing does not change saved tasks or add the commitment. The entry panel shows the weekday, date and planning hours; the review panel shows validated alternatives. Compare **Move as little as possible** and **Protect deadlines**, including work that cannot fit. **View schedule comparison** opens the detailed before/after schedule in a popup. Each option is checked against planning hours, fixed commitments, durations, deadlines and dependencies.

Choose **Accept this plan** to apply an option, or dismiss the preview to keep the current plan. A change to the plan invalidates outstanding previews. **Restore previous plan** is available for the latest unchanged recovery and rechecks feasibility before restoring it.

Planning activity shows the twelve most recent changes in a scrollable card. Older entries are pruned when activity is read or recorded: entries older than 90 days are removed, and retained history is capped at 1,000 entries per account. Activity cleanup does not remove tasks or recovery revisions.

## Homepage planning calendar

Today uses the monthly calendar for date selection and shows the selected date in a compact header label. Browse earlier or later months, select a date to open its saved plan and timeline, or choose **Back to today**. Orange dots mark task dates, square markers show fixed commitments, and diamond markers identify outstanding deadlines. Today is underlined; the selected date has a filled background.

Browsing and selecting dates does not move tasks, approve proposals or contact Google Calendar.

## Command and voice

Replaniva Command keeps the conversation, suggested planning prompts, message field and microphone together. Suggested prompts fill the input for review before sending. Dictation uses the browser speech API: edit the transcript, then send it through the same proposal and validation flow. Browser and operating-system support determine voice availability.

All four Web suggestions work without model assistance. Deterministic questions also cover next action, risks, capacity, plan explanation, dependencies, goal progress and recovery guidance, for example `Explain my plan`, `Show my dependencies` or `Show my goal progress`. **What works without model assistance?** lists examples in Command. Replies show their actual source. Other free-form questions may need a configured model; if interpretation is unavailable, use the listed questions or structured forms. Model availability does not make a preview an approved change.

Task **Break down** opens a focused popup with editable steps and a duration total. Closing it does not apply a breakdown. Only **Apply breakdown** submits the reviewed steps for validation.

## Settings and guided tour

Open **Settings** to manage appearance, planning hours, assistant preferences and integration readiness. Its navigation stays beside an independently scrolling content panel on larger screens and becomes a section picker on phones. **Check my plan now** displays its result beside the controls; action feedback also stays visible in a viewport notification. The **Quick Guide** at the top of Today starts a 14-stop tour that highlights specific cards across Today, Command, Capture, Recovery, Settings and Interfaces, with optional browser narration. Browser narration does not use the model allowance.

No model key is required for deterministic planning or structured recovery. Optional model assistance uses bounded provider calls and application allowances. If interpretation is unavailable, use the structured time fields. Configure provider credentials through deployment secrets or an excluded local environment file. Raw provider credentials are not accepted through browser forms.

Google Calendar requires separate owner setup and consent. Real Google export and approved import have been verified locally, including imported appointments appearing in Today and the Mobile browser preview. Each hosted deployment still needs its own authorization and synchronization check.

If the Google OAuth application is in Testing mode, only Google accounts listed under **Google Auth Platform → Audience → Test users** can authorize Calendar access. Add invited testers there, or provide a dedicated Replaniva demo account connected only to a demo calendar. A Replaniva login does not bypass Google's authorization requirements for a tester's own Google account. Public Google authorization may require production publishing and sensitive-scope verification. Never share a Google account password.

Imports preview seven days from the selected planning date and require approval. Only selected calendars' busy events are imported; events marked Free, including many holiday entries, are skipped. The dedicated export calendar is excluded from import to prevent duplicate busy time.

For local Calendar authorization, register `http://localhost:8001/integrations/google-calendar/callback` as the Google web client's redirect URI and set `REPLANIVA_WEB_URL=http://localhost:8000`. Open the app at that same web origin before connecting so the private authorization proof remains in the original browser tab. On a hosted app, use its HTTPS callback URL and set `REPLANIVA_WEB_URL` to the public app origin. Keep the client secret and Calendar encryption key in server environment variables. Select calendars to read, preview imports, then approve them. Exports require a dedicated app-created Replaniva calendar and a separate preview and approval.

## Architecture

- `planning.jac` creates and validates deterministic schedules.
- `planning_context.jac` prepares an account-owned, validated snapshot and indexes work by day.
- `account_clock.jac` supplies account-local dates and times independently of the server timezone.
- `intelligence.jac` calculates briefings, health, risks, Next Action, weekly outlooks, and rebalance candidates.
- `assistant.jac` turns supported requests into structured answers or reviewable proposals.
- `endpoints.jac` owns authenticated persistent planning state and applies validated mutations.
- `secretary.jac` owns the investigation walker, typed planning relationships, notifications and approved preference memory.
- `secretary_ai.jac` provides bounded, metered read and simulation tools.
- `secretary_runtime.jac` connects account-owned native scheduling and live updates.
- `ai.jac` contains optional provider-backed recovery suggestions and disruption interpretation.
- `model_usage.jac` enforces model allowances, private caching and provider cooldowns.
- `calendar_gateway.jac` handles Calendar requests and encrypted OAuth storage.
- `cli/main.jac` and `mobile/main.jac` provide terminal and mobile interfaces to the shared planning service.
- `command_parser.jac` supplies the shared terminal grammar; `console_api.jac` exposes the protected command allowlist and account-bound approval reviews. `frontend_interfaces.jac` hosts the mobile component and browser console.
- `frontend.jac` coordinates web navigation and shared state. The `frontend_*` modules separate Settings, conversation, dialogs, recovery views, speech, live connection, tour and formatting.

## Verification

```bash
jac check
jac test planning.jac intelligence.jac assistant.jac accounts.jac account_clock.jac secretary_tests.jac model_provider_tests.jac
jac test endpoints.jac
jac test test_model_usage.jac test_calendar_gateway.jac cli_tests.jac
jac test console_tests.jac
jac build --as client Replaniva
jac build mobile --platform web
```

Automated model and Calendar regressions use synthetic replies. Separate browser checks exercised actual model responses and real Google Calendar import/export locally. Provider quotas can temporarily block optional model responses; deterministic planning remains available. Compiler warnings remain visible.

## Hosting

The current [Jac Hammer preview](https://preview-jac-sbx-f8b7149b41a44ce1b83812205a496474.jachammer.app/) is a temporary sandbox. The narrated demo shows signup, capture, planning questions, recovery approval and saved state after reload. A new sandbox can start with empty account data. Google Calendar authorization and synchronization still require configured deployment credentials and live verification. Configure production authentication and persistent storage before a production release. Keep secrets, runtime storage and caches out of Git. The bundled admin portal is disabled in `jac.toml`.

## Dashboard appearance and visual assets

The dashboard uses graphite and orange, with Today, Command, Recovery Studio, Capture and Settings workspaces. The companion portrait and blink artwork are served locally. Reduced-motion preferences disable decorative animation.

The interface icon notices are included in `assets/interface-icons.LICENSE.txt`.
