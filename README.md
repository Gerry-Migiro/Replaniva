# Replaniva

**Plans that adapt when life changes.**

A private personal planning secretary for work, home, study, caregiving and personal goals.

## Current application

Replaniva runs on Jac **0.37.25**, with a planning dashboard, calendar, animated companion, Command workspace, voice input and account settings.

The planning core provides private accounts, tasks and fixed commitments, deterministic scheduling, a daily briefing with capacity and risk assessment, goals and sequenced task breakdown, graph dependencies and a seven-day outlook with validated rebalance suggestions. Command, Recovery and Settings provide focused workspaces for reviewing and managing the plan.

## Run

Use the [official Jac 0.37.25 release](https://github.com/jaseci-labs/jac/releases/tag/v0.37.25). Use an explicit binary path if your shell selects another version.

```bash
jac --version
jac install
jac check
jac run --dev --host 127.0.0.1 --port 8100 --api-port 8101
```

Open **http://localhost:8100**. The API uses **8101**. Create an account or sign in with your username. Email-shaped usernames are also supported. Runtime storage and credentials are private and excluded from Git.

No model key is required for deterministic planning. Configure optional provider credentials through deployment secrets or an excluded local environment file. Google Calendar live synchronization remains unverified and requires separate owner setup and consent.

## Checks

```bash
jac test planning.jac intelligence.jac assistant.jac accounts.jac account_clock.jac secretary_tests.jac model_provider_tests.jac
jac test endpoints.jac
.jac/venv/bin/python -m unittest test_model_usage test_calendar_gateway
```

Model tests use synthetic replies, not cloud calls. Compiler warnings remain visible. Browser checks use a dedicated reusable QA account with neutral fixtures. Native Android, hosted storage, live calendar operations and Jac Hammer deployment require separate verification.

## Architecture

- `planning.jac`, `intelligence.jac`: deterministic scheduling, validation, briefing and weekly outlook.
- `endpoints.jac`, `planning_context.jac`: protected shared operations and account-owned plan snapshots.
- `secretary.jac`: typed task/goal relationships and investigative traversal.
- `frontend*.jac`, `studio.jac`, `styles.css`, `studio.css`, `assets/`: web interface and visual assets.
- `ai.jac`, `secretary_ai.jac`, `model_usage.py`: optional bounded assistance and provider allowances.

## Hosting

[Jac Hammer](https://jachammer.ai/) is the intended hosting target. The application has been tested locally. Configure production authentication, administrative credentials and persistent storage before deploying, then verify the hosted workflows.
