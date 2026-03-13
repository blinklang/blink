// Test: non-mut StringBuilder binding should not produce const warnings
// when calling mutating methods like write().
// A non-mut `let` binding of a pointer type like StringBuilder should
// NOT emit `const pact_sb*` in the generated C, because the pointer
// target is still mutable.

fn main() ! IO {
    let sb = StringBuilder.new()
    sb.write("hello")
    sb.write(" world")
    assert_eq(sb.to_str(), "hello world")
    io.println("PASS: non-mut StringBuilder write works without const warning")
}
