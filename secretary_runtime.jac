"""Jac scheduler identity and account-scoped live invalidations."""

import asyncio;
import secrets;
import time;
import from secretary_state { issue_ticket, consume_ticket, remember_subscription, lookup_subscription, drop_subscription, job_lock }
import from jaclang.scale.scheduler.scheduler { JacScaleScheduler, TriggerSpec }
import from jaclang.scale.runtime.context.auth_ctx { get_current_auth }
import from jaclang.scale.server.websocket_ext { WebSocketExtension }


def scheduler_owner(root_id: str) -> tuple[any, str] {
    scheduler: any = JacScaleScheduler.instance();
    server: any = scheduler._server;
    if server is None { raise RuntimeError("The Jac scheduler is not running. Start the web server first."); }
    token = get_current_auth().removeprefix("Bearer ");
    owner: str | None = server.user_manager.validate_jwt_token(token);
    if not owner or server.user_manager.get_root_id(owner) != root_id { raise PermissionError("A valid account session is required."); }
    return (scheduler, owner);
}
def ensure_secretary_job(root_id: str, enabled: bool) -> str {
    with job_lock { return _ensure_secretary_job(root_id, enabled); }
}
def _ensure_secretary_job(root_id: str, enabled: bool) -> str {
    (scheduler, owner) = scheduler_owner(root_id);
    (jobs, total) = scheduler.list_jobs(created_by=owner);
    owned = [job for job in jobs if job.get("name") == "SecretaryTick"];
    if not enabled {
        for job in owned { scheduler.delete_job(str(job["job_id"]), acting_as=owner); }
        return "";
    }
    if owned {
        for job in owned[1:] { scheduler.delete_job(str(job["job_id"]), acting_as=owner); }
        return str(owned[0]["job_id"]);
    }
    job = scheduler.create_job("SecretaryTick", TriggerSpec(trigger="interval", interval=60.0), owner);
    return str(job["job_id"]);
}
def live_ticket(root_id: str) -> str {
    (scheduler, owner) = scheduler_owner(root_id);
    return issue_ticket(root_id, owner);
}
def live_api_port() -> int {
    server: any = JacScaleScheduler.instance()._server;
    if server is None { return 0; }
    settings: any = server.resolved_settings();
    return int(settings.port) if settings.dev and not settings.no_client else 0;
}

async def subscribe_account(root_id: str, ticket: str) -> None {
    claim = consume_ticket(ticket);
    if claim is None or claim[0] != root_id or claim[2] < time.time() { raise PermissionError("Invalid subscription ticket."); }
    owner = claim[1];
    server: any = JacScaleScheduler.instance()._server;
    for extension in server.extensions {
        if isinstance(extension, WebSocketExtension) {
            remember_subscription(root_id, asyncio.get_running_loop(), extension.ws_manager(server), owner);
            return;
        }
    }
    raise RuntimeError("Native WebSocket support is unavailable.");
}
async def _send_account(manager: any, owner: str) -> None {
    connections = list(manager._by_target.get("walker:SecretaryEvents", {}).values());
    for connection in connections {
        if connection.user_id == owner and not connection.closed {
            await manager.send_to(connection, {"type": "secretary_changed"});
        }
    }
}
def publish_account(root_id: str) -> None {
    subscription = lookup_subscription(root_id);
    if subscription is None { return; }
    (loop, manager, owner) = subscription;
    if loop.is_closed() { drop_subscription(root_id); return; }
    asyncio.run_coroutine_threadsafe(_send_account(manager, owner), loop);
}

def check_owned_plan(root_id: str, job_id: str) -> None {
    import from os { environ }
    import from urllib.parse { urlsplit }
    if root_id != jid(root) or jid(root) == jid(root.shared) { raise PermissionError("An owned account context is required."); }
    scheduler: any = JacScaleScheduler.instance();
    server: any = scheduler._server;
    job = scheduler.get_job(job_id);
    if job is None or job.get("name") != "SecretaryTick" { raise PermissionError("Owned secretary job not found."); }
    owner = str(job.get("created_by", ""));
    if server.user_manager.get_root_id(owner) != root_id { raise PermissionError("The job belongs to another account."); }
    base = (environ.get("REPLANIVA_URL") or "http://127.0.0.1:" + str(server.resolved_settings().port)).rstrip("/");
    parsed = urlsplit(base);
    if parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost", "::1") or parsed.path or parsed.username or parsed.password or parsed.query or parsed.fragment {
        raise ValueError("The secretary bridge must use a local HTTP server.");
    }
    token: str = server.user_manager.create_jwt_token(owner);
    response = owned_check_request(base, token);
    if not response.get("ok") { raise RuntimeError("The owned planning check did not finish."); }
}


def owned_check_request(base: str, token: str) -> dict[str, any] {
    import json;
    import from urllib.request { Request, urlopen }
    request = Request(base + "/function/secretary_check_now", data=b"{}", headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"}, method="POST");
    with urlopen(request, timeout=20) as handle { return json.loads(handle.read()); }
}
