import std.traits

type Resource {
    name: Str
}

fn make_resource(name: Str) -> Resource {
    Resource { name: name }
}

impl Closeable for Resource {
    fn close(self) {
        io.println("closing: {self.name}")
    }
}

fn main() {
    with make_resource("file1") as f {
        io.println("using: {f.name}")
    }
    io.println("done")

    with make_resource("a") as a, make_resource("b") as b {
        io.println("using: {a.name} and {b.name}")
    }
    io.println("multi done")
}
