"""Share transient socket state across Jac's isolated application namespaces."""

import secrets
import sys
import time
from threading import RLock
from types import ModuleType
from typing import Any

_candidate = ModuleType('_replaniva_secretary_transport')
_candidate.tickets = {}
_candidate.subscriptions = {}
_candidate.job_lock = RLock()
_state = sys.modules.setdefault(_candidate.__name__, _candidate)
job_lock = _state.job_lock


def issue_ticket(root_id: str, owner: str) -> str:
    with job_lock:
        for key, claim in list(_state.tickets.items()):
            if claim[2] < time.time():
                _state.tickets.pop(key, None)
        if len(_state.tickets) >= 500:
            raise RuntimeError('Too many pending subscriptions.')
        ticket = secrets.token_urlsafe(24)
        _state.tickets[ticket] = (root_id, owner, time.time() + 30)
        return ticket


def consume_ticket(ticket: str) -> tuple[str, str, float] | None:
    with job_lock:
        return _state.tickets.pop(ticket, None)


def remember_subscription(root_id: str, loop: Any, manager: Any, owner: str) -> None:
    with job_lock:
        _state.subscriptions[root_id] = (loop, manager, owner)


def lookup_subscription(root_id: str) -> tuple[Any, Any, str] | None:
    with job_lock:
        return _state.subscriptions.get(root_id)


def drop_subscription(root_id: str) -> None:
    with job_lock:
        _state.subscriptions.pop(root_id, None)
