type Color { Red, Green, Blue }
type Direction { North, South, East, West }

type Point {
    x: Int
    y: Int
}

type User {
    name: Str
    age: Int
}

fn classify_int(n: Int) -> Str {
    match n {
        0 => "zero"
        1 => "one"
        42 => "answer"
        _ => "other"
    }
}

fn describe_bool(b: Bool) -> Str {
    match b {
        true => "yes"
        false => "no"
    }
}

fn greet(name: Str) -> Str {
    match name {
        "alice" => "hi alice!"
        "bob" => "hey bob!"
        _ => "hello stranger"
    }
}

fn age_group(age: Int) -> Str {
    match age {
        0..13 => "child"
        13..18 => "teen"
        18..=65 => "adult"
        _ => "senior"
    }
}

fn color_name(c: Color) -> Str {
    match c {
        Red => "red"
        Green => "green"
        Blue => "blue"
    }
}

fn color_name_q(c: Color) -> Str {
    match c {
        Color.Red => "RED"
        Color.Green => "GREEN"
        Color.Blue => "BLUE"
    }
}

fn is_warm(d: Direction) -> Str {
    match d {
        South | East => "warm"
        _ => "cold"
    }
}

fn is_small(n: Int) -> Str {
    match n {
        0 | 1 | 2 | 3 => "small"
        _ => "big"
    }
}

fn describe_user(u: User) -> Str {
    match u {
        User { name, .. } => "user: {name}"
    }
}

fn describe_point(p: Point) -> Str {
    match p {
        Point { x: 0, y: 0, .. } => "origin"
        Point { x: 0, .. } => "y-axis"
        Point { y: 0, .. } => "x-axis"
        _ => "other"
    }
}

fn color_as(c: Color) -> Str {
    match c {
        whole as Color.Red => "matched red"
        _ => "not red"
    }
}

fn echo_doubled(n: Int) -> Int {
    match n {
        x => x * 2
    }
}

fn first_only(n: Int) -> Str {
    match n {
        1 => "one"
        _ => "whatever"
    }
}

fn compass_axis(d: Direction) -> Str {
    match d {
        Direction.North | Direction.South => "vertical"
        Direction.East | Direction.West => "horizontal"
    }
}

test "integer literal patterns" {
    assert_eq(classify_int(0), "zero")
    assert_eq(classify_int(1), "one")
    assert_eq(classify_int(42), "answer")
    assert_eq(classify_int(99), "other")
}

test "bool literal patterns" {
    assert_eq(describe_bool(true), "yes")
    assert_eq(describe_bool(false), "no")
}

test "string literal patterns" {
    assert_eq(greet("alice"), "hi alice!")
    assert_eq(greet("bob"), "hey bob!")
    assert_eq(greet("eve"), "hello stranger")
}

test "range patterns with boundaries" {
    assert_eq(age_group(0), "child")
    assert_eq(age_group(12), "child")
    assert_eq(age_group(13), "teen")
    assert_eq(age_group(17), "teen")
    assert_eq(age_group(18), "adult")
    assert_eq(age_group(65), "adult")
    assert_eq(age_group(66), "senior")
}

test "enum patterns unqualified" {
    assert_eq(color_name(Color.Red), "red")
    assert_eq(color_name(Color.Green), "green")
    assert_eq(color_name(Color.Blue), "blue")
}

test "enum patterns qualified" {
    assert_eq(color_name_q(Color.Red), "RED")
    assert_eq(color_name_q(Color.Green), "GREEN")
    assert_eq(color_name_q(Color.Blue), "BLUE")
}

test "or-patterns with enum" {
    assert_eq(is_warm(Direction.South), "warm")
    assert_eq(is_warm(Direction.East), "warm")
    assert_eq(is_warm(Direction.North), "cold")
    assert_eq(is_warm(Direction.West), "cold")
}

test "or-patterns with int" {
    assert_eq(is_small(0), "small")
    assert_eq(is_small(3), "small")
    assert_eq(is_small(10), "big")
}

test "struct patterns with field punning" {
    let admin = User { name: "admin", age: 30 }
    let alice = User { name: "alice", age: 25 }
    assert_eq(describe_user(admin), "user: admin")
    assert_eq(describe_user(alice), "user: alice")
}

test "struct patterns with nested int match" {
    let origin = Point { x: 0, y: 0 }
    let on_y = Point { x: 0, y: 5 }
    let on_x = Point { x: 3, y: 0 }
    let diag = Point { x: 7, y: 9 }
    assert_eq(describe_point(origin), "origin")
    assert_eq(describe_point(on_y), "y-axis")
    assert_eq(describe_point(on_x), "x-axis")
    assert_eq(describe_point(diag), "other")
}

test "as-patterns" {
    assert_eq(color_as(Color.Red), "matched red")
    assert_eq(color_as(Color.Blue), "not red")
}

test "identifier binding" {
    assert_eq(echo_doubled(21), 42)
}

test "wildcard pattern" {
    assert_eq(first_only(1), "one")
    assert_eq(first_only(999), "whatever")
}

test "qualified or-patterns" {
    assert_eq(compass_axis(Direction.North), "vertical")
    assert_eq(compass_axis(Direction.South), "vertical")
    assert_eq(compass_axis(Direction.East), "horizontal")
    assert_eq(compass_axis(Direction.West), "horizontal")
}
