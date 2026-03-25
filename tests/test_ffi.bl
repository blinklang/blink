// FFI test suite — ffi_scope, edge cases, integration
// Basic FFI/Ptr coverage in: test_ffi_basic, test_ptr_basic, test_ptr_string

@ffi("labs")
@trusted(audit: "FFI-001", reviewer: "test", date: "2026-03-08")
fn c_abs(n: Int) -> Int ! FFI { }

// ── FFI edge cases ───────────────────────────────────────────────────

test "ffi: large values" {
    assert_eq(c_abs(-2147483647), 2147483647)
    assert_eq(c_abs(999999), 999999)
}

test "ffi: compose results" {
    let a = c_abs(-10)
    let b = c_abs(-20)
    assert_eq(a + b, 30)
    assert_eq(a * b, 200)
}

// ── Ptr edge cases ───────────────────────────────────────────────────

test "ptr: write overwrites previous value" {
    let p: Ptr[Int] = alloc_ptr()
    p.write(10)
    assert_eq(p.deref(), 10)
    p.write(20)
    assert_eq(p.deref(), 20)
}

test "ptr: null_ptr addr is zero" {
    let n: Ptr[Int] = null_ptr()
    assert_eq(n.addr(), 0)
}

test "ptr: empty string roundtrip" {
    let s = ""
    let p = s.as_cstr()
    let result = p.to_str()
    match result {
        Some(val) => assert_eq(val, "")
        None => assert(false)
    }
}

// ── ffi.scope() ──────────────────────────────────────────────────────

test "ffi_scope: basic alloc and cleanup" {
    let mut scope = ffi_scope()
    let p: Ptr[Int] = scope.alloc()
    p.write(99)
    assert_eq(p.deref(), 99)
    assert_eq(p.is_null(), false)
}

test "ffi_scope: cstr conversion" {
    let mut scope = ffi_scope()
    let p = scope.cstr("scoped string")
    assert_eq(p.is_null(), false)
}

test "ffi_scope: multiple allocs in one scope" {
    let mut scope = ffi_scope()
    let a: Ptr[Int] = scope.alloc()
    let b: Ptr[Int] = scope.alloc()
    let c: Ptr[Int] = scope.alloc()
    a.write(1)
    b.write(2)
    c.write(3)
    assert_eq(a.deref(), 1)
    assert_eq(b.deref(), 2)
    assert_eq(c.deref(), 3)
}

test "ffi_scope: take removes from scope" {
    let mut scope = ffi_scope()
    let p: Ptr[Int] = scope.alloc()
    p.write(42)
    let taken = scope.take(p)
    assert_eq(taken.is_null(), false)
}

// ── Integration ──────────────────────────────────────────────────────

test "ffi: alloc_ptr write then pass to computation" {
    let p: Ptr[Int] = alloc_ptr()
    p.write(-77)
    let val = p.deref()
    assert_eq(c_abs(val), 77)
}
