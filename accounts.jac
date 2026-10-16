"""Shared username rules for web, mobile and CLI."""

def normalize_username(value: str) -> str {
    clean = value.strip().lower();
    if len(clean) < 3 or len(clean) > 32 {
        return "";
    }
    for char in clean {
        if char not in "abcdefghijklmnopqrstuvwxyz0123456789_-" { return ""; }
    }
    return clean;
}

test "usernames are normalized consistently" {
    assert normalize_username("  Gerry_1  ") == "gerry_1";
    assert normalize_username("ab") == "";
    assert normalize_username("a" * 33) == "";
    assert normalize_username("person@example.com") == "";
    assert normalize_username("a b") == "";
    assert normalize_username("abé") == "";
}
