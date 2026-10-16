# Replaniva

**Plans that adapt when life changes.**

Private personal planning for work, home, study, caregiving and personal goals.

## Stage 1: private planning foundation

- Create an account, sign in and keep your planning graph private.
- Select a planning date and save your IANA timezone and daily planning hours.
- Add, edit, complete, reopen and delete tasks with duration, importance and a due date/time.
- Add, edit and remove fixed commitments. Overlapping commitments are rejected.
- Saving rebuilds flexible work within planning hours, around fixed commitments, in deadline and importance order. Every resulting placement is validated. Work that cannot fit stays visible as **Unscheduled**.

This stage plans each selected calendar day using local wall-clock minutes. It does not split work, optimize all possible schedules, account for DST transition elapsed-time differences, or automatically move unfinished work between dates. Commitments can be outside planning hours. Changing a timezone changes the interpretation of local times, not the saved clock values. Saving planning hours explicitly reschedules flexible work across saved days.

Recovery proposals, assistant chat, notifications, dependencies, goals, voice, CLI, mobile and external calendars are later stages. WhatsApp is outside this project's scope.

## Run locally

Use the [official Jac 0.37.25 release](https://github.com/jaseci-labs/jac/releases/tag/v0.37.25). The exact version is pinned in `jac.toml`.

```bash
jac --version
jac install
jac check
jac test planning.jac
jac run --dev --host 127.0.0.1 --port 8100 --api-port 8101
```

Open **http://localhost:8100**. The API uses port **8101**. These ports let another local application keep using 8000/8001. When multiple Jac installations exist, use the explicit binary path or configure PATH to select 0.37.25 first.

Create an account through the sign-in screen. In **Hours**, use the browser timezone or enter a valid IANA name, then save. Add a commitment and a task to see the saved schedule. No model key or external calendar credentials are needed.

Jac provisions local persistent graph and identity storage. Keep its runtime directory private and out of Git; preserve the database when restarting. There is no account-data import from the older prototype. Password recovery and email verification are not configured at this stage.

## Verification

`jac test planning.jac` checks constraints, impossible work, conflicts, duplicate and unknown placements, exact-minute gaps and priority ordering. `jac check` may emit generated-state-setter warnings and explicit dynamic browser-boundary warnings; a passing check is not a warning-free claim.

`tests/stage1.cjs` exercises the browser and API together: task and commitment management, settings, authentication enforcement, foreign-account IDs, invalid inputs, refresh persistence, sign-out and responsive widths. It replaces fixtures on the selected day of a **dedicated reusable QA account**, never an owner's account. Create that account once through the UI. A temporary isolation account is removed through the local admin API after its checks.

The script needs Playwright with Firefox installed, plus these environment variables:

```bash
export REPLANIVA_TEST_EMAIL='your-dedicated-qa-account@example.test'
# Configure REPLANIVA_TEST_PASSWORD and REPLANIVA_ADMIN_PASSWORD privately.
node tests/stage1.cjs
```

Optional overrides: `PLAYWRIGHT_MODULE` (module path), `FIREFOX_PATH` (browser binary), `REPLANIVA_UI`, `REPLANIVA_API` and `REPLANIVA_ADMIN_USERNAME`. Install browser dependencies through your normal Playwright setup. Do not run the fixture test against production. Browser screenshots go to `/tmp/replaniva-stage1-*.png`.

## Structure

- `main.jac`: application entry and stylesheet.
- `endpoints.jac`: typed protected operations, owned graph storage and input validation.
- `planning.jac`: deterministic scheduling, placement validation and tests.
- `frontend.jac`: authentication, capture, planning settings and saved schedule.
- `planner.css`: responsive graphite and orange interface.

CRUD uses protected functions. A traversal walker belongs in the later investigation stage, where it will follow actual planning relationships.

## Provenance and hosting

The initial commit used the official Jac web-app guestbook scaffold. Stage 1 replaces that sample with planning code written for this repository, informed by the earlier Replaniva product concepts. The earlier prototype remains separate. Its feature implementation, accounts, credentials and WhatsApp code have not been copied here. Organizer permission for reuse, template eligibility and any competition compliance claims must be established separately; commit timestamps alone do not prove eligibility.

[Jac Hammer](https://jachammer.ai/) is the intended hosting target. This stage has been tested locally, not deployed there. Before exposing a hosted instance, configure administrative credentials, production authentication and persistent storage, then verify the deployment.
