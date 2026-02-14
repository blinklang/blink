import std.toml

fn assert_eq_str(actual: Str, expected: Str, label: Str) {
    if actual == expected {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected \"{expected}\", got \"{actual}\"")
    }
}

fn assert_eq_int(actual: Int, expected: Int, label: Str) {
    if actual == expected {
        io.println("PASS: {label}")
    } else {
        io.println("FAIL: {label} — expected {expected}, got {actual}")
    }
}

fn test_basic_key_value() {
    toml_clear()
    toml_parse("name = \"pact\"\nversion = \"0.1.0\"\n")
    assert_eq_str(toml_get("name"), "pact", "basic key=value string")
    assert_eq_str(toml_get("version"), "0.1.0", "basic key=value version")
}

fn test_sections() {
    toml_clear()
    toml_parse("[package]\nname = \"mylib\"\nversion = \"1.0.0\"\n\n[dependencies]\nfoo = \"0.2\"\n")
    assert_eq_str(toml_get("package.name"), "mylib", "section key package.name")
    assert_eq_str(toml_get("package.version"), "1.0.0", "section key package.version")
    assert_eq_str(toml_get("dependencies.foo"), "0.2", "section key dependencies.foo")
}

fn test_integers_and_bools() {
    toml_clear()
    toml_parse("count = 42\nenabled = true\ndisabled = false\nneg = -7\n")
    assert_eq_int(toml_get_int("count"), 42, "integer value")
    assert_eq_str(toml_get("enabled"), "1", "bool true")
    assert_eq_str(toml_get("disabled"), "0", "bool false")
    assert_eq_int(toml_get_int("neg"), -7, "negative int")
}

fn test_arrays() {
    toml_clear()
    toml_parse("tags = [\"a\", \"b\", \"c\"]\n")
    assert_eq_int(toml_get_array_len("tags"), 3, "array length")
    assert_eq_str(toml_get_array_item("tags", 0), "a", "array item 0")
    assert_eq_str(toml_get_array_item("tags", 1), "b", "array item 1")
    assert_eq_str(toml_get_array_item("tags", 2), "c", "array item 2")
}

fn test_inline_table() {
    toml_clear()
    toml_parse("[dependencies]\nhttp = \{ git = \"https://example.com/http.git\", tag = \"v1.0\" \}\n")
    assert_eq_str(toml_get("dependencies.http.git"), "https://example.com/http.git", "inline table git")
    assert_eq_str(toml_get("dependencies.http.tag"), "v1.0", "inline table tag")
}

fn test_array_tables() {
    toml_clear()
    toml_parse("[[package]]\nname = \"foo\"\nversion = \"1.0.0\"\n\n[[package]]\nname = \"bar\"\nversion = \"2.0.0\"\n")
    assert_eq_str(toml_get("package[0].name"), "foo", "array table first name")
    assert_eq_str(toml_get("package[0].version"), "1.0.0", "array table first version")
    assert_eq_str(toml_get("package[1].name"), "bar", "array table second name")
    assert_eq_str(toml_get("package[1].version"), "2.0.0", "array table second version")
    assert_eq_int(toml_array_len("package"), 2, "array table count")
}

fn test_comments_and_blanks() {
    toml_clear()
    toml_parse("# This is a comment\nfoo = \"bar\"\n\n# Another comment\nbaz = 123\n")
    assert_eq_str(toml_get("foo"), "bar", "value after comment")
    assert_eq_int(toml_get_int("baz"), 123, "value after blank+comment")
}

fn test_has_key() {
    toml_clear()
    toml_parse("name = \"test\"\n")
    assert_eq_int(toml_has("name"), 1, "has existing key")
    assert_eq_int(toml_has("missing"), 0, "has missing key")
}

fn test_dotted_key() {
    toml_clear()
    toml_parse("package.name = \"dotted\"\n")
    assert_eq_str(toml_get("package.name"), "dotted", "dotted key")
}

fn test_escape_sequences() {
    toml_clear()
    toml_parse("msg = \"hello\\nworld\"\n")
    assert_eq_str(toml_get("msg"), "hello\nworld", "escape newline in string")
}

fn test_pact_toml_realistic() {
    toml_clear()
    let content = "[package]\nname = \"my-project\"\nversion = \"0.1.0\"\n\n[dependencies]\nstd/http = \"1.2\"\nstd/json = \"0.3\"\n\n[dev-dependencies]\nstd/test-utils = \"1.0\"\n\n[capabilities]\nrequired = [\"net\", \"fs\"]\noptional = [\"env\"]\n"
    toml_parse(content)
    assert_eq_str(toml_get("package.name"), "my-project", "realistic package name")
    assert_eq_str(toml_get("package.version"), "0.1.0", "realistic package version")
    assert_eq_str(toml_get("dependencies.std/http"), "1.2", "realistic dep std/http")
    assert_eq_str(toml_get("dependencies.std/json"), "0.3", "realistic dep std/json")
    assert_eq_str(toml_get("dev-dependencies.std/test-utils"), "1.0", "realistic dev-dep")
    assert_eq_int(toml_get_array_len("capabilities.required"), 2, "capabilities required len")
    assert_eq_str(toml_get_array_item("capabilities.required", 0), "net", "capabilities required[0]")
    assert_eq_str(toml_get_array_item("capabilities.required", 1), "fs", "capabilities required[1]")
    assert_eq_int(toml_get_array_len("capabilities.optional"), 1, "capabilities optional len")
    assert_eq_str(toml_get_array_item("capabilities.optional", 0), "env", "capabilities optional[0]")
}

fn main() {
    test_basic_key_value()
    test_sections()
    test_integers_and_bools()
    test_arrays()
    test_inline_table()
    test_array_tables()
    test_comments_and_blanks()
    test_has_key()
    test_dotted_key()
    test_escape_sequences()
    test_pact_toml_realistic()
    io.println("All TOML tests complete")
}
