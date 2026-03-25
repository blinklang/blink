test "PATH env var is set" {
    let path = get_env("PATH") ?? "not set"
    assert_ne(path, "not set")
}

test "missing env var uses default" {
    let missing = get_env("__PACT_NONEXISTENT_VAR__") ?? "default"
    assert_eq(missing, "default")
}
