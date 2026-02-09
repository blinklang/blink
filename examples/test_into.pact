fn main() {
    let x: Int = 42
    let y: Float = x.into()
    io.println("{y}")

    let a: Float = 3.14
    let b: Int = a.into()
    io.println("{b}")

    let c: Int = 100
    let d: Str = c.into()
    io.println(d)

    io.println("PASS")
}
