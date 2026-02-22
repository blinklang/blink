fn main() {
    let path = get_env("PATH") ?? "not set"
    io.println("PATH: {path}")

    let missing = get_env("__PACT_NONEXISTENT_VAR__") ?? "default"
    io.println("missing: {missing}")
}
