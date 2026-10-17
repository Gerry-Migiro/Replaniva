"""Replaniva web entry: private planning API and client application."""

import from http { HTTPMethod }
import json;
import html;
import calendar_gateway as google;

import ".styles.css";
import ".studio.css";
import from .frontend { ClientApp }

def:pub app -> JsxElement {
    <ClientApp />
}


@restspec(method=HTTPMethod.GET, path="/integrations/google-calendar/callback", produces="text/html", envelope=False)
def:pub google_calendar_callback(code: str = "", state: str = "", error: str = "") -> str {
    # This public facade cannot read or write the private Jac planning graph.
    connected = google.callback(code, state, error);
    target = google.callback_return_url(bool(connected));
    return "<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='referrer' content='no-referrer'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\"><title>Return to Replaniva</title></head><body><p>Return to Replaniva to finish connecting Calendar.</p><a href='" + html.escape(target, quote=True) + "'>Return to Replaniva</a><script>location.replace(" + json.dumps(target).replace("<", "\\u003c") + ");</script></body></html>";
}

# User-owned secretary runtime, shared by the existing interface modules.
import from .secretary { secretary_config, private_account }
import from .secretary_runtime { subscribe_account, check_owned_plan }

@schedule(trigger=ScheduleTrigger.DYNAMIC)
walker:protect SecretaryTick {
    can check with Root entry {
        cfg = secretary_config();
        if cfg.enabled { check_owned_plan(jid(root), cfg.job_id); }
    }
}

@restspec(protocol=APIProtocol.WEBSOCKET)
async walker:protect SecretaryEvents {
    has ticket: str;
    async can subscribe with Root entry {
        private_account();
        await subscribe_account(jid(root), self.ticket);
        report {"type": "subscribed"};
    }
}
