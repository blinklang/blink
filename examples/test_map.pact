fn main() {
    let m: Map[Str, Int] = Map()
    m.set("a", 1)
    m.set("b", 2)
    m.set("c", 3)

    io.println("len: {m.len()}")
    io.println("get a: {m.get("a")}")
    io.println("get b: {m.get("b")}")
    io.println("has a: {m.has("a")}")
    io.println("has z: {m.has("z")}")

    m.set("a", 42)
    io.println("get a after update: {m.get("a")}")

    let removed = m.remove("b")
    io.println("removed b: {removed}")
    io.println("len after remove: {m.len()}")
    io.println("has b: {m.has("b")}")

    let keys = m.keys()
    io.println("keys count: {keys.len()}")

    let vals = m.values()
    io.println("values count: {vals.len()}")

    let m2: Map[Str, Str] = Map()
    m2.set("hello", "world")
    m2.set("foo", "bar")
    io.println("str val: {m2.get("hello")}")
    io.println("str len: {m2.len()}")
}
