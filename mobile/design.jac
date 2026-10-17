"""Native-compatible mobile design tokens and small vector controls."""
import from "@jac/mobui" { View, StyleSheet }

import from ..ui_theme { Palette, DARK, LIGHT }

def make_styles(C: Palette) -> any {
    return StyleSheet.create({
    screen: {flex: 1, backgroundColor: C.canvas},
    scroll: {flex: 1}, body: {padding: 20, paddingBottom: 24, gap: 16},
    header: {paddingHorizontal: 18, paddingTop: 20, paddingBottom: 10, flexDirection: "row", alignItems: "center", justifyContent: "space-between", borderBottomWidth: 1, borderColor: C.line},
    brand: {fontSize: 17, fontWeight: "800", color: C.ink},
    brandRow: {flexDirection: "row", alignItems: "center", gap: 8},
    brandIcon: {width: 28, height: 28},
    welcomeBrand: {alignItems: "center", gap: 8, marginBottom: 8},
    welcomeLogo: {width: 220, height: 165},
    orange: {color: C.orange, fontSize: 14},
    small: {fontSize: 12, fontWeight: "700", color: C.orange, letterSpacing: 1.3},
    title: {fontSize: 29, fontWeight: "700", lineHeight: 35, color: C.ink},
    subtitle: {fontSize: 15, color: C.muted, lineHeight: 23},
    muted: {fontSize: 13, color: C.muted, lineHeight: 20},
    text: {fontSize: 15, color: C.ink, lineHeight: 22},
    strong: {fontSize: 16, fontWeight: "700", color: C.ink, lineHeight: 23},
    card: {backgroundColor: C.surface, padding: 16, borderRadius: 18, gap: 10, borderWidth: 1, borderColor: C.line},
    row: {flexDirection: "row", justifyContent: "space-between", alignItems: "center", gap: 10},
    wrap: {flexDirection: "row", flexWrap: "wrap", gap: 8},
    tabs: {flexDirection: "row", gap: 8},
    tab: {flex: 1, alignItems: "center", minHeight: 44, justifyContent: "center", padding: 8, borderRadius: 12, backgroundColor: C.soft},
    activeTab: {backgroundColor: C.peach},
    tabText: {color: C.muted, fontWeight: "600", fontSize: 13},
    activeText: {color: C.orange, fontWeight: "700", fontSize: 13},
    input: {backgroundColor: C.field, borderWidth: 1, borderColor: C.line, color: C.ink, minHeight: 48, padding: 12, borderRadius: 12, fontSize: 16},
    label: {fontSize: 14, color: C.ink, fontWeight: "600"},
    button: {minHeight: 48, padding: 13, borderRadius: 12, backgroundColor: C.orange, alignItems: "center", justifyContent: "center"},
    buttonText: {color: C.accent_ink, fontWeight: "700", fontSize: 14},
    secondary: {minHeight: 44, padding: 12, borderRadius: 12, backgroundColor: C.soft, alignItems: "center", justifyContent: "center"},
    secondaryText: {color: C.ink, fontWeight: "600", fontSize: 14},
    message: {backgroundColor: C.peach, padding: 12, borderRadius: 12, gap: 8},
    option: {borderColor: "#ce9c72"},
    briefing: {backgroundColor: C.sage, borderColor: C.sage},
    healthRow: {flexDirection: "row", justifyContent: "space-between", alignItems: "center", gap: 10},
    healthPill: {color: C.ink, backgroundColor: C.soft, paddingHorizontal: 10, paddingVertical: 6, borderRadius: 20, fontSize: 12, fontWeight: "700"},
    nextAction: {paddingTop: 12, borderTopWidth: 1, borderColor: C.line, gap: 6},
    hero: {gap: 8, paddingVertical: 5},
    feature: {flex: 1, minHeight: 157, borderRadius: 19, padding: 15, gap: 10, justifyContent: "space-between", backgroundColor: C.sage},
    featureWarm: {backgroundColor: C.peach},
    featureTop: {flexDirection: "row", alignItems: "center", justifyContent: "space-between"},
    featureBadge: {width: 36, height: 36, borderRadius: 18, backgroundColor: C.surface, alignItems: "center", justifyContent: "center"},
    chip: {minHeight: 44, paddingHorizontal: 12, paddingVertical: 11, borderRadius: 22, borderWidth: 1, borderColor: C.line, backgroundColor: C.surface, justifyContent: "center"},
    chipText: {fontSize: 13, color: C.ink},
    conversation: {gap: 12},
    userBubble: {alignSelf: "flex-end", maxWidth: "92%", backgroundColor: C.peach, borderRadius: 16, padding: 13},
    assistantBubble: {backgroundColor: C.surface, borderRadius: 16, borderWidth: 1, borderColor: C.line, padding: 15, gap: 10},
    composer: {backgroundColor: C.canvas, paddingHorizontal: 14, paddingTop: 10, paddingBottom: 8, borderTopWidth: 1, borderColor: C.line},
    composerRow: {flexDirection: "row", alignItems: "center", gap: 8, backgroundColor: C.surface, borderWidth: 1, borderColor: C.line, borderRadius: 26, padding: 5},
    composerInput: {flex: 1, width: 0, minWidth: 0, minHeight: 44, paddingHorizontal: 12, fontSize: 16, color: C.ink},
    send: {width: 44, height: 44, borderRadius: 22, backgroundColor: C.orange, alignItems: "center", justifyContent: "center"},
    disabled: {opacity: 0.45},
    bottomNav: {flexDirection: "row", paddingHorizontal: 7, paddingTop: 8, paddingBottom: 12, backgroundColor: C.canvas, borderTopWidth: 1, borderColor: C.line, gap: 3},
    navItem: {flex: 1, minHeight: 52, alignItems: "center", justifyContent: "center", gap: 5, borderRadius: 13},
    navSelected: {backgroundColor: C.peach},
    navText: {fontSize: 12, color: C.muted},
    navActiveText: {fontSize: 12, fontWeight: "700", color: C.orange},
    iconButton: {width: 44, height: 44, alignItems: "center", justifyContent: "center", borderRadius: 22, backgroundColor: C.soft},
    calendarGrid: {flexDirection: "row", flexWrap: "wrap"},
    calendarCell: {width: "14.2857%", minHeight: 44, alignItems: "center", justifyContent: "center", borderRadius: 11, gap: 2},
    calendarSelected: {backgroundColor: C.peach}, calendarOutside: {opacity: 0.45},
    calendarDot: {width: 4, height: 4, borderRadius: 2, backgroundColor: C.orange},
    separator: {height: 1, backgroundColor: C.line},
    sectionTitle: {fontSize: 23, fontWeight: "700", color: C.ink, lineHeight: 30}
    });
}
glob:pub styles = make_styles(DARK), light_styles = make_styles(LIGHT);
def:pub mobile_styles(light: bool) -> any { return light_styles if light else styles; }

def:pub MobileGlyph(name: str, color: str = "#b84c00") -> JsxElement {
    return <View accessible={False} style={{width: 22, height: 22, alignItems: "center", justifyContent: "center"}}>
        {name == "chat" and <View style={{width: 20, height: 16, borderWidth: 1.7, borderColor: color, borderRadius: 6}}><View style={{width: 5, height: 5, borderLeftWidth: 1.7, borderColor: color, position: "absolute", bottom: -4, left: 4, transform: [{rotate: "25deg"}]}}/></View>}
        {name == "calendar" and <View style={{width: 19, height: 19, borderWidth: 1.7, borderColor: color, borderRadius: 4, paddingTop: 5}}><View style={{height: 1.5, backgroundColor: color}}/><View style={{flexDirection: "row", gap: 3, padding: 3}}>{[<View key={str(i)} style={{width: 2.5, height: 3, backgroundColor: color}}/> for i in range(3)]}</View></View>}
        {name in ["plus", "send", "arrow"] and <View style={{width: 18, height: 18, transform: [{rotate: "-45deg" if name == "send" else "0deg"}]}}><View style={{position: "absolute", left: 1, top: 8, width: 16, height: 1.8, backgroundColor: color}}/>{name == "plus" and <View style={{position: "absolute", left: 8, top: 1, width: 1.8, height: 16, backgroundColor: color}}/>}{name != "plus" and <View style={{position: "absolute", right: 1, top: 3, width: 11, height: 11, borderTopWidth: 1.8, borderRightWidth: 1.8, borderColor: color, transform: [{rotate: "45deg"}]}}/>}</View>}
        {name == "recover" and <View style={{width: 18, height: 18, borderWidth: 1.7, borderColor: color, borderRightColor: "transparent", borderRadius: 10}}><View style={{position: "absolute", right: 0, top: 0, width: 7, height: 7, borderBottomWidth: 1.7, borderRightWidth: 1.7, borderColor: color}}/></View>}
        {name == "menu" and <View style={{gap: 4}}>{[<View key={str(i)} style={{width: 18, height: 1.7, backgroundColor: color, borderRadius: 1}}/> for i in range(3)]}</View>}
    </View>;
}
