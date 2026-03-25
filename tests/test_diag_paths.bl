fn normalize_path(path: Str) -> Str {
    let idx = path.index_of("lib/std/")
    if idx > 0 {
        return path.substring(idx, path.len() - idx)
    }
    let idx2 = path.index_of("lib/pkg/")
    if idx2 > 0 {
        return path.substring(idx2, path.len() - idx2)
    }
    path
}

test "normalize strips build/ prefix from stdlib paths" {
    assert_eq(normalize_path("build/lib/std/json.pact"), "lib/std/json.pact")
    assert_eq(normalize_path("/home/user/pact/build/lib/std/json.pact"), "lib/std/json.pact")
    assert_eq(normalize_path("build/lib/pkg/http.pact"), "lib/pkg/http.pact")
    assert_eq(normalize_path("/opt/pact/build/lib/pkg/cli.pact"), "lib/pkg/cli.pact")
}

test "normalize preserves non-stdlib paths" {
    assert_eq(normalize_path("src/compiler.pact"), "src/compiler.pact")
    assert_eq(normalize_path("tests/test_foo.pact"), "tests/test_foo.pact")
}

test "normalize preserves bare lib/ paths" {
    assert_eq(normalize_path("lib/std/json.pact"), "lib/std/json.pact")
    assert_eq(normalize_path("lib/pkg/http.pact"), "lib/pkg/http.pact")
}
