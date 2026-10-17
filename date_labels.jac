"""Date labels shared by Web, mobile and terminal without a platform clock."""
def:pub day_label(value: str) -> str {
    if len(value) < 10 { return value; }
    try {
        year = int(value[:4]); month = int(value[5:7]); day = int(value[8:10]);
        if month < 1 or month > 12 or day < 1 or day > 31 { return value; }
        adjusted = year - 1 if month < 3 else year;
        offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
        weekday = (adjusted + adjusted // 4 - adjusted // 100 + adjusted // 400 + offsets[month - 1] + day) % 7;
        return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][weekday] + ", " + str(day) + " " + ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][month - 1] + " " + str(year);
    } except Exception { return value; }
}

test "weekday labels preserve a date without timezone shifts" {
    assert day_label("2026-10-17") == "Saturday, 17 Oct 2026";
    assert day_label("2028-02-29") == "Tuesday, 29 Feb 2028";
    assert day_label("") == "";
}
