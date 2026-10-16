"""Explicit account-local time, independent of the server's timezone."""

import from datetime { datetime }
import from zoneinfo { ZoneInfo }

obj AccountClock {
    has day: str, minute: int, timezone: str, timestamp: str = "";
}

def local_clock(timezone: str = "Africa/Nairobi", stamp: float | None = None) -> AccountClock {
    current = datetime.now(ZoneInfo(timezone)) if stamp is None else datetime.fromtimestamp(stamp, ZoneInfo(timezone));
    return AccountClock(day=current.date().isoformat(), minute=current.hour * 60 + current.minute,
        timezone=timezone, timestamp=current.isoformat(timespec="seconds"));
}
