test "doc comment on first function is attached to function not header" {
    write_file(".tmp/test_doc_first.pact", "/// Greets the user\nfn greet(name: Str) -> Str \{\n    \"hello\"\n\}\n")
    let result = process_run("bin/pact", ["query", ".tmp/test_doc_first.pact", "--fn", "greet", "-j"])
    assert_eq(result.exit_code, 0)
    assert(result.out.contains("Greets the user"))
}

test "doc comment on first pub function is attached to function" {
    write_file(".tmp/test_doc_first_pub.pact", "/// Public greeter\npub fn greet(name: Str) -> Str \{\n    \"hello\"\n\}\n")
    let result = process_run("bin/pact", ["query", ".tmp/test_doc_first_pub.pact", "--fn", "greet", "-j"])
    assert_eq(result.exit_code, 0)
    assert(result.out.contains("Public greeter"))
}

test "doc comment on second function still works" {
    write_file(".tmp/test_doc_second.pact", "fn main() \{\n    greet(\"world\")\n\}\n\n/// Greets the user\nfn greet(name: Str) -> Str \{\n    \"hello\"\n\}\n")
    let result = process_run("bin/pact", ["query", ".tmp/test_doc_second.pact", "--fn", "greet", "-j"])
    assert_eq(result.exit_code, 0)
    assert(result.out.contains("Greets the user"))
}

test "regular comment before first fn is not treated as doc" {
    write_file(".tmp/test_comment_first.pact", "// Just a comment\nfn greet() -> Str \{\n    \"hello\"\n\}\n")
    let result = process_run("bin/pact", ["query", ".tmp/test_comment_first.pact", "--fn", "greet", "-j"])
    assert_eq(result.exit_code, 0)
    assert(result.out.contains("\"doc\":") == false)
}
