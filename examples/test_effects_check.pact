fn pure_function() -> Int {
    let x = 1 + 2
    x
}

fn prints_stuff() ! IO {
    io.println("hello")
}

fn main() {
    pure_function()
    prints_stuff()
    io.println("effects check passed")
}
