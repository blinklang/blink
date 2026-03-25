import pub_import_facade
import pub_import_facade_all
import pub_import_outer

test "selective re-export: function accessible" {
    assert_eq(greet("world"), "hello, world")
}

test "selective re-export: type accessible" {
    let g = Greeting { message: "hi" }
    assert_eq(g.message, "hi")
}

test "selective re-export: const accessible" {
    assert_eq(GREETING_VERSION, 1)
}

test "selective re-export: qualified access" {
    assert_eq(pub_import_facade.greet("world"), "hello, world")
}

test "wildcard re-export: function accessible" {
    assert_eq(all_greet("world"), "hi, world")
}

test "wildcard re-export: type accessible" {
    let g = AllGreeting { msg: "hey" }
    assert_eq(g.msg, "hey")
}

test "wildcard re-export: qualified access" {
    assert_eq(pub_import_facade_all.all_greet("world"), "hi, world")
}

test "transitive re-export: function accessible" {
    assert_eq(pub_import_outer.greet("chain"), "hello, chain")
}
