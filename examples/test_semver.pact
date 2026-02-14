import std.semver

fn check_eq(actual: Int, expected: Int, label: Str) {
    if actual == expected {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected {expected}, got {actual}")
    }
}

fn test_parse_version() {
    parse_version("1.2.3")
    check_eq(ver_major, 1, "parse 1.2.3 major")
    check_eq(ver_minor, 2, "parse 1.2.3 minor")
    check_eq(ver_patch, 3, "parse 1.2.3 patch")
    check_eq(ver_has_minor, 1, "parse 1.2.3 has_minor")
    check_eq(ver_has_patch, 1, "parse 1.2.3 has_patch")

    parse_version("0.3")
    check_eq(ver_major, 0, "parse 0.3 major")
    check_eq(ver_minor, 3, "parse 0.3 minor")
    check_eq(ver_has_minor, 1, "parse 0.3 has_minor")
    check_eq(ver_has_patch, 0, "parse 0.3 has_patch")

    parse_version("2")
    check_eq(ver_major, 2, "parse 2 major")
    check_eq(ver_has_minor, 0, "parse 2 has_minor")
}

fn test_version_compare() {
    check_eq(version_compare(1, 2, 3, 1, 2, 3), 0, "compare equal")
    check_eq(version_compare(1, 2, 3, 1, 2, 4), -1, "compare patch less")
    check_eq(version_compare(1, 2, 4, 1, 2, 3), 1, "compare patch greater")
    check_eq(version_compare(1, 3, 0, 1, 2, 9), 1, "compare minor greater")
    check_eq(version_compare(2, 0, 0, 1, 9, 9), 1, "compare major greater")
}

fn test_caret_constraint() {
    check_eq(version_matches("1.2.0", "1.2"), 1, "caret 1.2 matches 1.2.0")
    check_eq(version_matches("1.9.9", "1.2"), 1, "caret 1.2 matches 1.9.9")
    check_eq(version_matches("2.0.0", "1.2"), 0, "caret 1.2 rejects 2.0.0")
    check_eq(version_matches("1.1.9", "1.2"), 0, "caret 1.2 rejects 1.1.9")

    check_eq(version_matches("1.2.3", "1.2.3"), 1, "caret 1.2.3 matches exact")
    check_eq(version_matches("1.2.4", "1.2.3"), 1, "caret 1.2.3 matches 1.2.4")
    check_eq(version_matches("1.3.0", "1.2.3"), 1, "caret 1.2.3 matches 1.3.0")
    check_eq(version_matches("2.0.0", "1.2.3"), 0, "caret 1.2.3 rejects 2.0.0")
}

fn test_caret_pre_1() {
    check_eq(version_matches("0.2.0", "0.2"), 1, "caret 0.2 matches 0.2.0")
    check_eq(version_matches("0.2.5", "0.2"), 1, "caret 0.2 matches 0.2.5")
    check_eq(version_matches("0.3.0", "0.2"), 0, "caret 0.2 rejects 0.3.0")
    check_eq(version_matches("0.1.9", "0.2"), 0, "caret 0.2 rejects 0.1.9")
}

fn test_tilde_constraint() {
    check_eq(version_matches("1.2.0", "~1.2"), 1, "tilde ~1.2 matches 1.2.0")
    check_eq(version_matches("1.2.9", "~1.2"), 1, "tilde ~1.2 matches 1.2.9")
    check_eq(version_matches("1.3.0", "~1.2"), 0, "tilde ~1.2 rejects 1.3.0")

    check_eq(version_matches("1.2.3", "~1.2.3"), 1, "tilde ~1.2.3 matches exact")
    check_eq(version_matches("1.2.9", "~1.2.3"), 1, "tilde ~1.2.3 matches 1.2.9")
    check_eq(version_matches("1.3.0", "~1.2.3"), 0, "tilde ~1.2.3 rejects 1.3.0")
}

fn test_exact_constraint() {
    check_eq(version_matches("1.2.3", "=1.2.3"), 1, "exact =1.2.3 matches")
    check_eq(version_matches("1.2.4", "=1.2.3"), 0, "exact =1.2.3 rejects 1.2.4")
}

fn test_range_constraints() {
    check_eq(version_matches("1.5.0", ">=1.0.0, <2.0.0"), 1, "range matches 1.5.0")
    check_eq(version_matches("0.9.0", ">=1.0.0, <2.0.0"), 0, "range rejects 0.9.0")
    check_eq(version_matches("2.0.0", ">=1.0.0, <2.0.0"), 0, "range rejects 2.0.0")
}

fn test_version_to_str() {
    let s = version_to_str(1, 2, 3)
    if s == "1.2.3" {
        io.println("PASS: version_to_str")
    } else {
        io.println("FAIL: version_to_str — got {s}")
    }
}

fn main() {
    test_parse_version()
    test_version_compare()
    test_caret_constraint()
    test_caret_pre_1()
    test_tilde_constraint()
    test_exact_constraint()
    test_range_constraints()
    test_version_to_str()
    io.println("All semver tests complete")
}
