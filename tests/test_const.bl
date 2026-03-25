const MAX_RETRIES = 5
const TIMEOUT_MS = 30 * 1000
const APP_NAME = "test-app"
const ENABLED = true

test "module-level const values" {
    assert_eq(MAX_RETRIES, 5)
    assert_eq(TIMEOUT_MS, 30000)
    assert_eq(APP_NAME, "test-app")
    assert(ENABLED)
}

test "local const" {
    const LOCAL_CONST = 42
    assert_eq(LOCAL_CONST, 42)
}
