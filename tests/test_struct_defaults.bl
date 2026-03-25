type Config {
    host: Str = "0.0.0.0"
    port: Int = 8080
}

type Mixed {
    name: Str
    count: Int = 0
}

fn main() {
    // Both defaults
    let c = Config {  }
    io.println("host={c.host} port={c.port}")
    assert(c.host == "0.0.0.0", "host should default")
    assert(c.port == 8080, "port should default")
    // Override one default
    let c2 = Config { port: 3000 }
    io.println("host={c2.host} port={c2.port}")
    assert(c2.host == "0.0.0.0", "host should default")
    assert(c2.port == 3000, "port should be overridden")
    // Override all
    let c3 = Config { host: "localhost", port: 9090 }
    io.println("host={c3.host} port={c3.port}")
    assert(c3.host == "localhost", "host should be overridden")
    assert(c3.port == 9090, "port should be overridden")
    // Mixed: required + default
    let m = Mixed { name: "test" }
    io.println("name={m.name} count={m.count}")
    assert(m.name == "test", "name should be set")
    assert(m.count == 0, "count should default")
    io.println("All struct default tests passed!")
}
