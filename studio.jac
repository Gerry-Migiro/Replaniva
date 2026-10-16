"""Lightweight dashboard visuals shared across Replaniva's web interface."""

def:pub UiIcon(name: str, extra: str = "") -> JsxElement {
    return <svg className={"ui-icon " + extra} width="20" height="20" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><use href={"/static/assets/interface-icons.svg#" + name}></use></svg>;
}

def:pub CompanionVisual(working: bool = False, listening: bool = False) -> JsxElement {
    return <div className={"companion-visual is-listening" if listening else "companion-visual is-working" if working else "companion-visual"}>
        <div className="companion-heading"><span className="eyebrow">REPLANIVA ASSISTANT</span><span className="companion-status"><i></i>{"Listening" if listening else "Working" if working else "Ready"}</span></div>
        <div className="portrait-frame">
            <svg className="portrait-halo" viewBox="0 0 320 320" aria-hidden="true" focusable="false" fill="none">
                <circle className="halo-guide" cx="160" cy="160" r="147" />
                <circle className="halo-ticks" cx="160" cy="160" r="142" />
                <circle className="halo-arc" cx="160" cy="160" r="136" strokeDasharray="190 34 84 41 240 266" transform="rotate(-74 160 160)" />
                <circle className="halo-inner" cx="160" cy="160" r="128" strokeDasharray="260 65 130 350" transform="rotate(19 160 160)" />
                <circle className="halo-node" cx="47" cy="84" r="2" />
                <circle className="halo-node" cx="292" cy="193" r="2" />
                <circle className="halo-node" cx="200" cy="30" r="1.5" />
            </svg>
            <img src="/static/assets/planning-companion.webp" width={720} height={900} alt="Replaniva's human-faced orange holographic planning companion" fetchPriority="high" />
            <img className="portrait-blink" src="/static/assets/planning-companion-blink.webp" width={720} height={900} alt="" aria-hidden="true" />
            <span className="portrait-platform" aria-hidden="true"></span>
        </div>
        <div className="companion-caption"><span className="companion-signal" aria-hidden="true"></span> A little clarity. A way forward.</div>
    </div>;
}

def:pub CapacityOrbit(pressure: int, no_time: bool = False) -> JsxElement {
    filled = str(max(0, min(100, pressure)) * 194.78 / 100);
    return <div className="capacity-orbit" aria-hidden="true"><svg width="80" height="80" viewBox="0 0 80 80"><circle cx="40" cy="40" r="31" fill="none" stroke="var(--border)" strokeWidth="4" /><circle cx="40" cy="40" r="31" fill="none" stroke="currentColor" strokeWidth="4" strokeLinecap="round" strokeDasharray={filled + " 194.78"} transform="rotate(-90 40 40)" /></svg><span>{"No time" if no_time else str(max(0, min(100, pressure))) + "%"}<small>{"available" if no_time else "pressure"}</small></span></div>;
}
