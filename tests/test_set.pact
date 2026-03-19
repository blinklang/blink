fn main() ! IO {
    let mut s = Set()

    // insert returns true if new, false if already present
    let r1 = s.insert("Alice")
    assert_eq(r1, 1)
    let r2 = s.insert("Alice")
    assert_eq(r2, 0)
    s.insert("Bob")
    s.insert("Carol")

    // len
    assert_eq(s.len(), 3)

    // is_empty
    assert_eq(s.is_empty(), 0)

    // contains
    assert_eq(s.contains("Alice"), 1)
    assert_eq(s.contains("Dave"), 0)

    // remove returns true if was present
    let r3 = s.remove("Bob")
    assert_eq(r3, 1)
    let r4 = s.remove("Bob")
    assert_eq(r4, 0)
    assert_eq(s.len(), 2)

    // union
    let mut s2 = Set()
    s2.insert("Carol")
    s2.insert("Dave")
    let merged = s.union(s2)
    assert_eq(merged.len(), 3)
    assert_eq(merged.contains("Alice"), 1)
    assert_eq(merged.contains("Carol"), 1)
    assert_eq(merged.contains("Dave"), 1)

    // empty set
    let empty = Set()
    assert_eq(empty.len(), 0)
    assert_eq(empty.is_empty(), 1)

    io.println("all set tests passed")
}
