fn dispatch(path: List[Str]) -> Str {
    match path {
        [] => "help"
        ["build"] => "building"
        ["daemon", "start"] => "starting daemon"
        ["daemon", "stop"] => "stopping daemon"
        ["daemon", sub] => "unknown daemon: {sub}"
        [cmd] => "unknown: {cmd}"
        _ => "too many"
    }
}

fn first_or_empty(items: List[Str]) -> Str {
    match items {
        [] => "empty"
        [first, ...] => "first: {first}"
    }
}

fn count_match(items: List[Int]) -> Str {
    match items {
        [] => "none"
        [x] => "one: {x}"
        [x, y] => "two: {x}, {y}"
        _ => "many"
    }
}

test "empty list pattern" {
    let empty: List[Str] = []
    assert_eq(dispatch(empty), "help")
}

test "single element list pattern" {
    assert_eq(dispatch(["build"]), "building")
}

test "two element list pattern" {
    assert_eq(dispatch(["daemon", "start"]), "starting daemon")
    assert_eq(dispatch(["daemon", "stop"]), "stopping daemon")
}

test "variable binding in list pattern" {
    assert_eq(dispatch(["daemon", "status"]), "unknown daemon: status")
    assert_eq(dispatch(["test"]), "unknown: test")
}

test "wildcard catch-all" {
    assert_eq(dispatch(["a", "b", "c"]), "too many")
}

test "rest wildcard pattern" {
    let empty: List[Str] = []
    assert_eq(first_or_empty(empty), "empty")
    assert_eq(first_or_empty(["hello"]), "first: hello")
    assert_eq(first_or_empty(["hello", "world"]), "first: hello")
    assert_eq(first_or_empty(["a", "b", "c"]), "first: a")
}

test "int list patterns" {
    let empty: List[Int] = []
    assert_eq(count_match(empty), "none")
    assert_eq(count_match([42]), "one: 42")
    assert_eq(count_match([1, 2]), "two: 1, 2")
    assert_eq(count_match([1, 2, 3]), "many")
}
