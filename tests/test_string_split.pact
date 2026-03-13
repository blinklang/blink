test "basic split" {
    let parts = "a,b,c".split(",")
    assert_eq(parts.len(), 3)
    assert_eq(parts.get(0).unwrap(), "a")
    assert_eq(parts.get(1).unwrap(), "b")
    assert_eq(parts.get(2).unwrap(), "c")
}

test "split with space" {
    let words = "hello world foo".split(" ")
    assert_eq(words.len(), 3)
    assert_eq(words.get(0).unwrap(), "hello")
    assert_eq(words.get(2).unwrap(), "foo")
}

test "split no match" {
    let no_match = "abc".split("x")
    assert_eq(no_match.len(), 1)
    assert_eq(no_match.get(0).unwrap(), "abc")
}

test "split empty segments" {
    let empties = "a,,b".split(",")
    assert_eq(empties.len(), 3)
    assert_eq(empties.get(1).unwrap(), "")
}

test "join with comma" {
    let parts = "a,b,c".split(",")
    assert_eq(parts.join(","), "a,b,c")
}

test "join with space" {
    let words = "hello world foo".split(" ")
    assert_eq(words.join(" "), "hello world foo")
}

test "join with empty delimiter" {
    let parts = "a,b,c".split(",")
    assert_eq(parts.join(""), "abc")
}

test "empty list join" {
    let empty_list: List[Str] = []
    assert_eq(empty_list.join(","), "")
}

test "round-trip split join" {
    let csv = "x,y,z"
    assert_eq(csv.split(",").join(","), "x,y,z")
}
