const MAX_RETRIES = 5
const TIMEOUT_MS = 30 * 1000
const APP_NAME = "test-app"
const ENABLED = true

fn main() {
    io.println("max retries: {MAX_RETRIES}")
    io.println("timeout: {TIMEOUT_MS}")
    io.println("app: {APP_NAME}")
    if ENABLED {
        io.println("enabled")
    }

    const LOCAL_CONST = 42
    io.println("local: {LOCAL_CONST}")

    io.println("PASS")
}
