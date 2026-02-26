fn main() {
    let s = "hello"
    io.println("len: {s.len()}")
    io.println("contains: {s.contains("ell")}")

    let parts: List[Str] = []
    parts.push("a")
    parts.push("b")
    io.println("list len: {parts.len()}")
    io.println("get 0: {parts.unsafe_get(0)}")

    let m = Map()
    m.set("key", "val")
    io.println("has: {m.has("key")}")
    io.println("map len: {m.len()}")

    io.println("all methods valid")
}
