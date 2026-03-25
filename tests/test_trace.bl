fn add(a: Int, b: Int) -> Int {
    a + b
}

fn greet(name: Str) -> Str {
    "hello {name}"
}

fn do_nothing() {
}

fn nested_call(x: Int) -> Int {
    let y = add(x, 10)
    add(y, 5)
}

fn main() {
    let result = add(1, 2)
    let msg = greet("world")
    do_nothing()
    let n = nested_call(100)
    io.println("result={result} msg={msg} n={n}")
}
