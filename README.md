# Replaniva

**Plans that adapt when life changes.**

Replaniva is a private personal planner built around recovery. When a new commitment disrupts a day, it shows what is affected, prepares validated alternatives, explains the tradeoffs, and changes the saved plan only after approval.

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
jac run --dev --host 127.0.0.1 --port 8100 --api-port 8101
```

Open **http://localhost:8100**. The API uses **8101**. Create an account or sign in with your username. Email-shaped usernames are also supported.

The web app supports private accounts, dates, planning hours, tasks, fixed commitments, Daily Briefing, Plan Health, Next Action, Risk Radar, weekly outlook, goals, Command proposals, voice controls, task breakdown, Recovery Studio, approval, dismissal, and restore.

A task is due on its planning date unless you choose a later due date in Capture. The later date lets Replaniva assess a requested move to another day without pretending that a deadline has changed.

## Terminal and mobile clients

The terminal client shares the web account and planning API:

```bash
jac run cli -- login YOUR_USERNAME
jac run cli -- today
jac run cli -- ask "What is at risk?"
jac run cli
```

The local API defaults to `http://127.0.0.1:8101`. Set `REPLANIVA_URL` to use another deployment. The guided menu supports capture, recovery review and explicit approval. Sign-in stores a private token on the device; `jac run cli -- logout` removes it.

The mobile client uses the same protected planning operations and original mobile layouts:

```bash
jac run --dev --platform web mobile
jac build mobile --platform web
```

Native Android packaging requires the Android SDK and a device or emulator. A browser build does not establish native Android verification.

## Recovery Studio

Enter a disruption and its time, then choose **Explore recovery**. Previewing does not change saved tasks or add the commitment. Compare **Move as little as possible** and **Protect deadlines**, including work that cannot fit. Each option is checked against planning hours, fixed commitments, durations, deadlines and dependencies.

Choose **Accept this plan** to apply an option, or dismiss the preview to keep the current plan. A change to the plan invalidates outstanding previews. **Restore previous plan** is available for the latest unchanged recovery and rechecks feasibility before restoring it.

Planning activity shows the twelve most recent changes in a scrollable card. Older entries are pruned when activity is read or recorded: entries older than 90 days are removed, and retained history is capped at 1,000 entries per account. Activity cleanup does not remove tasks or recovery revisions.

## Homepage planning calendar

Today uses the monthly calendar for date selection and shows the selected date in a compact header label. Browse earlier or later months, select a date to open its saved plan and timeline, or choose **Back to today**. Orange dots mark task dates, square markers show fixed commitments, and diamond markers identify outstanding deadlines. Today is underlined; the selected date has a filled background.

Browsing and selecting dates does not move tasks, approve proposals or contact Google Calendar.

## Command and voice

Replaniva Command keeps the conversation, suggested planning prompts, message field and microphone together. Suggested prompts fill the input for review before sending. Dictation uses the browser speech API: edit the transcript, then send it through the same proposal and validation flow. Browser and operating-system support determine voice availability.

Task **Break down** opens a focused popup with editable steps and a duration total. Closing it does not apply a breakdown. Only **Apply breakdown** submits the reviewed steps for validation.

## Settings and guided tour

Open **Settings** to manage appearance, planning hours, assistant preferences and integration readiness. The **Quick Guide** at the top of Today starts the written tour or browser narration. Browser narration does not use the model allowance.

No model key is required for deterministic planning or structured recovery. Optional model assistance uses bounded provider calls and application allowances. If interpretation is unavailable, use the structured time fields. Configure provider credentials through deployment secrets or an excluded local environment file. Raw provider credentials are not accepted through browser forms.

Google Calendar requires separate owner setup and consent. Live synchronization has not been verified.

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
- `frontend.jac` coordinates web navigation and shared state. The `frontend_*` modules separate Settings, conversation, dialogs, recovery views, speech, live connection, tour and formatting.

## Verification

```bash
jac check
jac test planning.jac intelligence.jac assistant.jac accounts.jac account_clock.jac secretary_tests.jac model_provider_tests.jac
jac test endpoints.jac
jac test test_model_usage.jac test_calendar_gateway.jac cli_tests.jac
```

Model and Calendar tests use synthetic replies rather than live external calls. Compiler warnings remain visible.

## Hosting

The application is hosted on [Jac Hammer](https://preview-jac-sbx-502b88fe495449528b3cd21fedf641ef.jachammer.app/). Configure production authentication and persistent storage, then verify the hosted workflows. Keep secrets, runtime storage and caches out of Git. The bundled admin portal is disabled in `jac.toml`.

## Dashboard appearance and visual assets

The dashboard uses graphite and orange, with Today, Command, Recovery Studio, Capture and Settings workspaces. The companion portrait and blink artwork are served locally. Reduced-motion preferences disable decorative animation.

The interface icon notices are included in `assets/interface-icons.LICENSE.txt`.
