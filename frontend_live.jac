"""Authenticated native socket lifecycle and open-window refresh signals."""

import from react { useEffect }
import from "@jac/runtime" { __getApiBaseUrl }
import from endpoints { secretary_live_ticket }

def:pub useSecretaryLive(onChange: any, onConnected: any, enabled: bool = True) -> None {
    useEffect(lambda {
        if not enabled { return; }
        stopped = False;
        socket: any = None;
        retry: any = None;
        win: any = window;
        async def connect() -> None {
            if stopped { return; }
            try {
                connection = await secretary_live_ticket();
                ticket = connection.ticket;
                if stopped { return; }
                ws_class: any = win.WebSocket;
                api_base = __getApiBaseUrl().rstrip("/") or win.location.origin;
                address: any = new(win.URL, api_base + "/ws/SecretaryEvents", win.location.origin);
                if not __getApiBaseUrl() and connection.api_port > 0 { address.port = str(connection.api_port); }
                address.protocol = "wss:" if address.protocol == "https:" else "ws:";
                socket = new(ws_class, address.toString());
                socket.onopen = lambda (event: any) -> None {
                    socket.send(JSON.stringify({"token": win.localStorage.getItem("jac_token"), "ticket": ticket}));
                };
                socket.onmessage = lambda (event: any) -> None {
                    frame: any = JSON.parse(event.data);
                    if frame.type == "ping" { socket.send(JSON.stringify({"type": "pong"})); return; }
                    if frame.type == "secretary_changed" { onChange(); return; }
                    if frame.ok { onConnected(True); } elif frame.ok == False { socket.close(); }
                };
                socket.onclose = lambda (event: any) -> None {
                    onConnected(False);
                    if not stopped { retry = win.setTimeout(connect, 10000); }
                };
            } except Exception {
                onConnected(False);
                if not stopped { retry = win.setTimeout(connect, 10000); }
            }
        }
        def on_focus(event: any) -> None { onChange(); return; }
        connect();
        win.addEventListener("focus", on_focus);
        return lambda {
            stopped = True;
            if retry { win.clearTimeout(retry); }
            if socket { socket.close(); }
            win.removeEventListener("focus", on_focus);
        };
    }, [enabled]);
}
