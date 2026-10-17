"""The visual palette shared by Web and native-compatible mobile views."""
obj Palette {
    has canvas: str = "#171717", surface: str = "#1d1c1b", ink: str = "#f6f1ea",
        muted: str = "#b9afa5", line: str = "#3b332b", orange: str = "#f7931e",
        peach: str = "#30261b", sage: str = "#24231e", soft: str = "#262422",
        field: str = "#151413", accent_ink: str = "#171717";
}
glob:pub DARK = Palette(), LIGHT = Palette(canvas="#f7f3ed", surface="#fffdf9", ink="#241c14",
    muted="#66594b", line="#d9c9b7", orange="#a84908", peach="#f5e6d4", sage="#f1eee4",
    soft="#f2ebe2", field="#fffdf9", accent_ink="#ffffff");

def:pub appearance_vars(light: bool) -> dict[str, str] {
    colors = LIGHT if light else DARK;
    return {"--bg": colors.canvas, "--surface": colors.surface, "--surface-hi": colors.soft,
        "--field": colors.field, "--border": colors.line, "--text": colors.ink,
        "--muted": colors.muted, "--accent": colors.orange};
}
