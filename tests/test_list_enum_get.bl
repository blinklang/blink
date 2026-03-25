type Color {
    Red
    Green(shade: Str)
    Blue(r: Int, g: Int, b: Int)
}

fn make_colors() -> List[Color] {
    let mut colors: List[Color] = []
    colors.push(Color.Red)
    colors.push(Color.Green("lime"))
    colors.push(Color.Blue(0, 128, 255))
    colors
}

test "list enum get from function return" {
    let colors = make_colors()
    let first = colors.get(0).unwrap()
    match first {
        Red => assert_eq(1, 1)
        Green(_s) => assert_eq(1, 0)
        Blue(_r, _g, _b) => assert_eq(1, 0)
    }
}

test "list enum get with data variant" {
    let colors = make_colors()
    let second = colors.get(1).unwrap()
    match second {
        Red => assert_eq(1, 0)
        Green(s) => assert_eq(s, "lime")
        Blue(_r, _g, _b) => assert_eq(1, 0)
    }
}

test "list enum get chained from return" {
    let val = make_colors().get(2).unwrap()
    match val {
        Red => assert_eq(1, 0)
        Green(_s) => assert_eq(1, 0)
        Blue(r, g, b) => {
            assert_eq(r, 0)
            assert_eq(g, 128)
            assert_eq(b, 255)
        }
    }
}
