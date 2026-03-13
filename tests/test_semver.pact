import std.semver

test "parse full version" {
    parse_version("1.2.3")
    assert_eq(ver_major, 1)
    assert_eq(ver_minor, 2)
    assert_eq(ver_patch, 3)
    assert_eq(ver_has_minor, 1)
    assert_eq(ver_has_patch, 1)
}

test "parse major.minor only" {
    parse_version("0.3")
    assert_eq(ver_major, 0)
    assert_eq(ver_minor, 3)
    assert_eq(ver_has_minor, 1)
    assert_eq(ver_has_patch, 0)
}

test "parse major only" {
    parse_version("2")
    assert_eq(ver_major, 2)
    assert_eq(ver_has_minor, 0)
}

test "version compare" {
    assert_eq(version_compare(1, 2, 3, 1, 2, 3), 0)
    assert_eq(version_compare(1, 2, 3, 1, 2, 4), -1)
    assert_eq(version_compare(1, 2, 4, 1, 2, 3), 1)
    assert_eq(version_compare(1, 3, 0, 1, 2, 9), 1)
    assert_eq(version_compare(2, 0, 0, 1, 9, 9), 1)
}

test "caret constraint major >= 1" {
    assert_eq(version_matches("1.2.0", "1.2"), 1)
    assert_eq(version_matches("1.9.9", "1.2"), 1)
    assert_eq(version_matches("2.0.0", "1.2"), 0)
    assert_eq(version_matches("1.1.9", "1.2"), 0)

    assert_eq(version_matches("1.2.3", "1.2.3"), 1)
    assert_eq(version_matches("1.2.4", "1.2.3"), 1)
    assert_eq(version_matches("1.3.0", "1.2.3"), 1)
    assert_eq(version_matches("2.0.0", "1.2.3"), 0)
}

test "caret constraint pre-1.0" {
    assert_eq(version_matches("0.2.0", "0.2"), 1)
    assert_eq(version_matches("0.2.5", "0.2"), 1)
    assert_eq(version_matches("0.3.0", "0.2"), 0)
    assert_eq(version_matches("0.1.9", "0.2"), 0)
}

test "tilde constraint" {
    assert_eq(version_matches("1.2.0", "~1.2"), 1)
    assert_eq(version_matches("1.2.9", "~1.2"), 1)
    assert_eq(version_matches("1.3.0", "~1.2"), 0)

    assert_eq(version_matches("1.2.3", "~1.2.3"), 1)
    assert_eq(version_matches("1.2.9", "~1.2.3"), 1)
    assert_eq(version_matches("1.3.0", "~1.2.3"), 0)
}

test "exact constraint" {
    assert_eq(version_matches("1.2.3", "=1.2.3"), 1)
    assert_eq(version_matches("1.2.4", "=1.2.3"), 0)
}

test "range constraints" {
    assert_eq(version_matches("1.5.0", ">=1.0.0, <2.0.0"), 1)
    assert_eq(version_matches("0.9.0", ">=1.0.0, <2.0.0"), 0)
    assert_eq(version_matches("2.0.0", ">=1.0.0, <2.0.0"), 0)
}

test "version to string" {
    assert_eq(version_to_str(1, 2, 3), "1.2.3")
}
