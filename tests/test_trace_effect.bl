fn greet(name: Str) ! IO {
    io.println("hello {name}")
}

fn save(path: Str, data: Str) ! IO, FS.Write {
    io.println("saving to {path}")
    fs.write(path, data)
}

fn main() ! IO, FS.Write {
    greet("world")
    save(".tmp/trace_test.txt", "test data")
}
