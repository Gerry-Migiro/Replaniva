# Replaniva

**Plans that adapt when life changes.**

Replaniva is intended to become a personal planning secretary for anyone managing tasks, commitments and disruptions: work, household responsibilities, study, caregiving and personal goals.

## Current stage

This repository currently contains the official Jac web-app starter, generated with Jac **0.37.25**. It is a small shared guestbook: Jac message nodes persist in the graph, public walkers post and list messages, and the web client renders them. It is not yet a private planner or an AI secretary. The generated application source is unchanged.

WhatsApp is outside the scope of this project. No WhatsApp code or dependencies are included.

## Setup

Install Jac 0.37.25 using the [official installation instructions](https://www.jac-lang.org/quick-guide/install/). The [official release](https://github.com/jaseci-labs/jac/releases/tag/v0.37.25) provides the native binary. The project pins that exact version in `jac.toml`. Jac is supplied by the native toolchain, not an outdated PyPI package.

```bash
jac --version
jac install
jac check
jac run --dev --host 127.0.0.1 --port 8100 --api-port 8101
```

Open http://localhost:8100. The API uses port 8101. The non-default ports let another local application keep using 8000/8001. With no conflicting service, ordinary `jac run` uses Jac's default ports.

Use only sample text in this starter: its generated public guestbook walkers share a global root and do not provide private per-account storage.

## Starter files

- `main.jac`: full-stack entry point.
- `endpoints.jac`: message node and post/list walkers.
- `frontend.jac` and `frontend.impl.jac`: guestbook UI and handlers.
- `components/MessageCard.jac`: message presentation.
- `jac.toml`: toolchain pin and generated dependencies.

## Provenance and event eligibility

An earlier Replaniva prototype exists separately and predates this repository. This repository's initial application source comes from the official Jac scaffolder, not copied prototype features. Any later reuse must be disclosed honestly; new commit timestamps do not establish when reused source was first written. Competition eligibility, including permission to reuse earlier implementation and templates, must be confirmed with the organizers. No eligibility claim is made by this setup.

## Hosting target

[Jac Hammer](https://jachammer.ai/) is the intended deployment target. Its official site supports importing a repository for deployment. This initial stage has not been deployed there, and platform compatibility remains a verification step after the repository is pushed. No deployed URL is claimed.
