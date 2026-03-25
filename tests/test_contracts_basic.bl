// Test that annotations inside type bodies don't cause compiler panics,
// and that [T] list type shorthand parses correctly in struct fields.

type Account {
    balance: Int
    @invariant(self.balance >= 0)
}

type Error {
    path: Str
    message: Str
}

type Context {
    errors: [Error]
}

@requires(x > 0)
fn checked_add(x: Int, y: Int) -> Int {
    x + y
}

test "contracts basic" {
    assert_eq(checked_add(1, 2), 3)
}

test "account struct" {
    let a = Account { balance: 10 }
    assert_eq(a.balance, 10)
}

test "context with list field" {
    let ctx = Context { errors: [] }
    assert_eq(ctx.errors.len(), 0)
}
