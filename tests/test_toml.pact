import std.toml

test "basic key value" {
    toml_clear()
    toml_parse("name = \"pact\"\nversion = \"0.1.0\"\n")
    assert_eq(toml_get("name"), "pact")
    assert_eq(toml_get("version"), "0.1.0")
}

test "sections" {
    toml_clear()
    toml_parse("[package]\nname = \"mylib\"\nversion = \"1.0.0\"\n\n[dependencies]\nfoo = \"0.2\"\n")
    assert_eq(toml_get("package.name"), "mylib")
    assert_eq(toml_get("package.version"), "1.0.0")
    assert_eq(toml_get("dependencies.foo"), "0.2")
}

test "integers and bools" {
    toml_clear()
    toml_parse("count = 42\nenabled = true\ndisabled = false\nneg = -7\n")
    assert_eq(toml_get_int("count"), 42)
    assert_eq(toml_get("enabled"), "1")
    assert_eq(toml_get("disabled"), "0")
    assert_eq(toml_get_int("neg"), -7)
}

test "arrays" {
    toml_clear()
    toml_parse("tags = [\"a\", \"b\", \"c\"]\n")
    assert_eq(toml_get_array_len("tags"), 3)
    assert_eq(toml_get_array_item("tags", 0), "a")
    assert_eq(toml_get_array_item("tags", 1), "b")
    assert_eq(toml_get_array_item("tags", 2), "c")
}

test "inline table" {
    toml_clear()
    toml_parse("[dependencies]\nhttp = \{ git = \"https://example.com/http.git\", tag = \"v1.0\" \}\n")
    assert_eq(toml_get("dependencies.http.git"), "https://example.com/http.git")
    assert_eq(toml_get("dependencies.http.tag"), "v1.0")
}

test "array tables" {
    toml_clear()
    toml_parse("[[package]]\nname = \"foo\"\nversion = \"1.0.0\"\n\n[[package]]\nname = \"bar\"\nversion = \"2.0.0\"\n")
    assert_eq(toml_get("package[0].name"), "foo")
    assert_eq(toml_get("package[0].version"), "1.0.0")
    assert_eq(toml_get("package[1].name"), "bar")
    assert_eq(toml_get("package[1].version"), "2.0.0")
    assert_eq(toml_array_len("package"), 2)
}

test "comments and blanks" {
    toml_clear()
    toml_parse("# This is a comment\nfoo = \"bar\"\n\n# Another comment\nbaz = 123\n")
    assert_eq(toml_get("foo"), "bar")
    assert_eq(toml_get_int("baz"), 123)
}

test "has key" {
    toml_clear()
    toml_parse("name = \"test\"\n")
    assert_eq(toml_has("name"), 1)
    assert_eq(toml_has("missing"), 0)
}

test "dotted key" {
    toml_clear()
    toml_parse("package.name = \"dotted\"\n")
    assert_eq(toml_get("package.name"), "dotted")
}

test "escape sequences" {
    toml_clear()
    toml_parse("msg = \"hello\\nworld\"\n")
    assert_eq(toml_get("msg"), "hello\nworld")
}

test "pact toml realistic" {
    toml_clear()
    let content = "[package]\nname = \"my-project\"\nversion = \"0.1.0\"\n\n[dependencies]\nstd/http = \"1.2\"\nstd/json = \"0.3\"\n\n[dev-dependencies]\nstd/test-utils = \"1.0\"\n\n[capabilities]\nrequired = [\"net\", \"fs\"]\noptional = [\"env\"]\n"
    toml_parse(content)
    assert_eq(toml_get("package.name"), "my-project")
    assert_eq(toml_get("package.version"), "0.1.0")
    assert_eq(toml_get("dependencies.std/http"), "1.2")
    assert_eq(toml_get("dependencies.std/json"), "0.3")
    assert_eq(toml_get("dev-dependencies.std/test-utils"), "1.0")
    assert_eq(toml_get_array_len("capabilities.required"), 2)
    assert_eq(toml_get_array_item("capabilities.required", 0), "net")
    assert_eq(toml_get_array_item("capabilities.required", 1), "fs")
    assert_eq(toml_get_array_len("capabilities.optional"), 1)
    assert_eq(toml_get_array_item("capabilities.optional", 0), "env")
}
