type Color {
    Red
    Blue
}

trait Label {
    fn label(self) -> Str
}

impl Label for Color {
    fn label(self) -> Str {
        match self {
            Red => "red"
            Blue => "blue"
        }
    }
}

type Box {
    color: Color
}

test "trait method on enum field via local" {
    let b = Box { color: Color.Red }
    let c = b.color
    assert_eq(c.label(), "red")
}

test "trait method on enum field via local blue" {
    let b = Box { color: Color.Blue }
    let c = b.color
    assert_eq(c.label(), "blue")
}
