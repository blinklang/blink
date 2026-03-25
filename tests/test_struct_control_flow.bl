type Point { x: Int, y: Int }
type Color { Red, Green, Blue }

fn pick_point(c: Color) -> Point {
    match c {
        Color.Red => Point { x: 1, y: 0 }
        Color.Green => Point { x: 0, y: 1 }
        Color.Blue => Point { x: 0, y: 0 }
    }
}

fn unwrap_point(r: Result[Point, Str]) -> Point {
    match r {
        Ok(p) => p
        Err(_) => Point { x: 0, y: 0 }
    }
}

fn make_ok_point(x: Int, y: Int) -> Result[Point, Str] {
    Ok(Point { x: x, y: y })
}

fn make_err_point(msg: Str) -> Result[Point, Str] {
    Err(msg)
}

test "match returning struct" {
    let p = match Color.Red {
        Color.Red => Point { x: 10, y: 20 }
        Color.Green => Point { x: 30, y: 40 }
        Color.Blue => Point { x: 50, y: 60 }
    }
    assert_eq(p.x, 10)
    assert_eq(p.y, 20)

    let q = match Color.Blue {
        Color.Red => Point { x: 10, y: 20 }
        Color.Green => Point { x: 30, y: 40 }
        Color.Blue => Point { x: 50, y: 60 }
    }
    assert_eq(q.x, 50)
    assert_eq(q.y, 60)
}

test "nested if/else returning struct" {
    let a = true
    let b = false
    let p = if a {
        if b { Point { x: 1, y: 1 } } else { Point { x: 2, y: 2 } }
    } else {
        Point { x: 3, y: 3 }
    }
    assert_eq(p.x, 2)
    assert_eq(p.y, 2)

    let q = if !a {
        Point { x: 10, y: 10 }
    } else {
        if b { Point { x: 20, y: 20 } } else { Point { x: 30, y: 30 } }
    }
    assert_eq(q.x, 30)
    assert_eq(q.y, 30)
}

test "function returning struct via match" {
    let p = pick_point(Color.Red)
    assert_eq(p.x, 1)
    assert_eq(p.y, 0)

    let q = pick_point(Color.Green)
    assert_eq(q.x, 0)
    assert_eq(q.y, 1)

    let r = pick_point(Color.Blue)
    assert_eq(r.x, 0)
    assert_eq(r.y, 0)
}

test "struct return from Result match" {
    let ok = make_ok_point(5, 7)
    let p = unwrap_point(ok)
    assert_eq(p.x, 5)
    assert_eq(p.y, 7)

    let err = make_err_point("nope")
    let q = unwrap_point(err)
    assert_eq(q.x, 0)
    assert_eq(q.y, 0)
}

test "closure returning struct via match" {
    let f = fn(c: Color) -> Point {
        match c {
            Color.Red => Point { x: 100, y: 200 }
            Color.Green => Point { x: 300, y: 400 }
            Color.Blue => Point { x: 500, y: 600 }
        }
    }
    let p = f(Color.Green)
    assert_eq(p.x, 300)
    assert_eq(p.y, 400)

    let q = f(Color.Blue)
    assert_eq(q.x, 500)
    assert_eq(q.y, 600)
}

test "struct in for loop" {
    let points: List[Point] = []
    points.push(Point { x: 1, y: 2 })
    points.push(Point { x: 3, y: 4 })
    points.push(Point { x: 5, y: 6 })

    let mut sum_x = 0
    let mut sum_y = 0
    for p in points {
        sum_x += p.x
        sum_y += p.y
    }
    assert_eq(sum_x, 9)
    assert_eq(sum_y, 12)
}
