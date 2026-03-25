@capabilities(IO, FS.Read)

// -- Scoped resources via with-as --

fn make_resource(id: Int) -> Int {
    id
}

fn test_single_resource() ! IO {
    with make_resource(10) as r {
        io.println("resource bound: {r}")
    }
}

fn test_lifo_close_order() ! IO {
    with make_resource(1) as r1, make_resource(2) as r2 {
        io.println("r1={r1} r2={r2}")
    }
}

fn test_mixed_handler_and_resource() ! IO {
    with handler IO {
        fn print(msg: Str) {
            io.println("[H] {msg}")
        }
    }, make_resource(77) as res {
        io.println("inside mixed block, res={res}")
    }
}

// -- Capabilities budget --

fn within_budget_io() ! IO {
    io.println("IO is in budget")
}

fn within_budget_fs() ! FS.Read {
    io.println("FS.Read is in budget")
}

fn within_budget_both() ! IO, FS.Read {
    io.println("IO + FS.Read both in budget")
}

fn main() {
    test_single_resource()
    test_lifo_close_order()
    test_mixed_handler_and_resource()
    within_budget_io()
    within_budget_fs()
    within_budget_both()
    io.println("PASS")
}
