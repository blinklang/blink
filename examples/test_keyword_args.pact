fn add(a: Int, b: Int) -> Int {
    a + b
}

fn transfer(amount: Int, -- from: Str, to: Str) -> Str {
    "{from} sends {amount} to {to}"
}

fn start_server(-- host: Str, port: Int) -> Str {
    "{host}:{port}"
}

fn main() {
    let r1 = add(1, 2)
    assert_eq(r1, 3)
    let r2 = transfer(100, "alice", "bob")
    assert_eq(r2, "alice sends 100 to bob")
    let r3 = transfer(100, from: "alice", to: "bob")
    assert_eq(r3, "alice sends 100 to bob")
    let r4 = transfer(100, to: "bob", from: "alice")
    assert_eq(r4, "alice sends 100 to bob")
    let r5 = start_server("0.0.0.0", 8080)
    assert_eq(r5, "0.0.0.0:8080")
    let r6 = start_server(host: "0.0.0.0", port: 8080)
    assert_eq(r6, "0.0.0.0:8080")
    let r7 = start_server(port: 8080, host: "0.0.0.0")
    assert_eq(r7, "0.0.0.0:8080")
    io.println("All keyword arg tests passed!")
}
