fn make_resource(name: Str) -> Int {
    io.println("opening resource: {name}")
    42
}

fn use_resource(r: Int) {
    io.println("using resource: {r}")
}

fn do_setup() -> Int {
    io.println("setup handler")
    0
}

fn main() {
    io.println("=== with-as single resource ===")
    with make_resource("file1") as f {
        use_resource(f)
        io.println("inside with block, f = {f}")
    }
    io.println("after with block")

    io.println("=== with-as multiple resources ===")
    with make_resource("src") as src, make_resource("dst") as dst {
        io.println("src = {src}, dst = {dst}")
    }
    io.println("after multiple resources")

    io.println("=== plain with block (handler, no as) ===")
    with do_setup() {
        io.println("inside plain with block")
    }
    io.println("after plain with block")

    io.println("=== mixed: handler + resource ===")
    with do_setup(), make_resource("mixed_file") as mf {
        io.println("mixed block, mf = {mf}")
    }
    io.println("all tests passed")
}
