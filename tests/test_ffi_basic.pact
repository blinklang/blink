@ffi("labs")
@trusted
fn c_abs(n: Int) -> Int ! FFI { }

fn main() {
    let result = c_abs(-42)
    io.println("abs(-42) = {result}")
    let result2 = c_abs(100)
    io.println("abs(100) = {result2}")
}
