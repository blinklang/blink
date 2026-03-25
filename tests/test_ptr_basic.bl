@ffi("labs")
@trusted
fn c_labs(n: Int) -> Int ! FFI { }

fn main() {
    let p: Ptr[Int] = alloc_ptr()
    p.write(42)
    let val = p.deref()
    io.println("deref: {val}")

    let is_null = p.is_null()
    io.println("is_null(p): {is_null}")

    let n: Ptr[Int] = null_ptr()
    let n_null = n.is_null()
    io.println("is_null(n): {n_null}")

    let addr = p.addr()
    io.println("addr > 0: {addr > 0}")
}
