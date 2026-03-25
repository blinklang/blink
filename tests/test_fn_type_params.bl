// Test: Fn type annotations with parameterized return types
// Bug 6vevsc: parser Fn TypeAnn lost return type parameters

fn apply_option(f: fn(Int) -> Option[Int], x: Int) -> Option[Int] {
    f(x)
}

fn apply_result(f: fn(Int) -> Result[Int, Str], x: Int) -> Result[Int, Str] {
    f(x)
}

fn apply_list(f: fn(Int) -> List[Int], x: Int) -> List[Int] {
    f(x)
}

test "closure with Option return through fn param" {
    let result = apply_option(fn(x: Int) -> Option[Int] { Some(x * 2) }, 5)
    assert_eq(result.unwrap(), 10)
}

test "closure with Result return through fn param" {
    let result = apply_result(fn(x: Int) -> Result[Int, Str] { Ok(x + 1) }, 5)
    assert_eq(result.unwrap(), 6)
}

test "closure with List return through fn param" {
    let result = apply_list(fn(x: Int) -> List[Int] { [x, x + 1, x + 2] }, 5)
    assert_eq(result.len(), 3)
    assert_eq(result.get(0).unwrap(), 5)
}

// Bug r3bq4e: trait impl methods returning Result[Struct, Struct] produce wrong C type

type AcceptSocket {
    fd: Int
}

type AcceptListener {
    fd: Int
}

type AcceptError {
    msg: Str
}

trait Acceptor {
    fn accept(self) -> Result[AcceptSocket, AcceptError]
}

impl Acceptor for AcceptListener {
    fn accept(self) -> Result[AcceptSocket, AcceptError] {
        Ok(AcceptSocket { fd: self.fd + 1 })
    }
}

test "trait impl with Result[Struct, Struct] return" {
    let listener = AcceptListener { fd: 1 }
    let r = listener.accept()
    match r {
        Ok(sock) => assert_eq(sock.fd, 2)
        Err(_e) => assert(false)
    }
}
