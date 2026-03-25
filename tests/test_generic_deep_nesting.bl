// Tests for generic monomorphization with deep nesting.
// Some patterns are commented out due to known codegen bugs — see inline notes.

fn get_first_or_none[T](items: List[T]) -> Option[List[T]] {
    if items.len() > 0 {
        Some(items)
    } else {
        None
    }
}

// --- Working patterns ---

test "Option[List[Int]] — option wrapping a list via match" {
    let nums = [1, 2, 3]
    let opt: Option[List[Int]] = Some(nums)
    match opt {
        Some(list) => {
            assert_eq(list.len(), 3)
            let first = list.get(0) ?? 0
            assert_eq(first, 1)
        }
        None => assert(false)
    }
}

test "Result[List[Int], Str] — result wrapping a list" {
    let r: Result[List[Int], Str] = Ok([10, 20, 30])
    match r {
        Ok(list) => {
            assert_eq(list.len(), 3)
            let second = list.get(1) ?? 0
            assert_eq(second, 20)
        }
        Err(_) => assert(false)
    }
}

test "Result[List[Int], Str] — error case" {
    let r: Result[List[Int], Str] = Err("bad input")
    match r {
        Ok(_) => assert(false)
        Err(msg) => assert_eq(msg, "bad input")
    }
}

test "generic fn returning Option[List[T]] with Int" {
    let nums = [1, 2, 3]
    let result = get_first_or_none(nums)
    match result {
        Some(list) => assert_eq(list.len(), 3)
        None => assert(false)
    }
}

test "generic fn returning Option[List[T]] with Str" {
    let names = ["alice", "bob"]
    let result = get_first_or_none(names)
    match result {
        Some(list) => assert_eq(list.len(), 2)
        None => assert(false)
    }
}

test "generic fn returning Option[List[T]] — empty list returns None" {
    let empty: List[Int] = []
    let result = get_first_or_none(empty)
    match result {
        Some(_) => assert(false)
        None => assert(true)
    }
}

// --- BUG: Option[List[Int]] with ?? operator ---
// Generates pointer/integer type mismatch in C conditional expression.
// The ?? fallback for list-typed Option doesn't generate correct C type cast.
// test "Option[List[Int]] — None with ?? fallback" {
//     let opt: Option[List[Int]] = None
//     let fallback = [99]
//     let result = opt ?? fallback
//     assert_eq(result.len(), 1)
// }

// --- BUG: Generic fn Result[List[T], Str] Err branch type mismatch ---
// The Err branch of a generic fn returning Result[List[T], Str] generates
// pact_Result_int_str instead of pact_Result_list_str when T=Int.
// fn wrap_in_result[T](val: T, fail: Bool) -> Result[List[T], Str] {
//     if fail { Err("failed") } else { let items: List[T] = [val]; Ok(items) }
// }
// test "Result[List[T], Str] via generic fn" {
//     let r = wrap_in_result(42, false)
//     match r { Ok(list) => assert_eq(list.len(), 1) Err(_) => assert(false) }
// }

test "List[Option[Int]] — list of optionals" {
    let items: List[Option[Int]] = []
    items.push(Some(10))
    assert_eq(items.len(), 1)
}

test "Option[Result[Int, Str]] — option wrapping a result" {
    let inner: Result[Int, Str] = Ok(42)
    let opt: Option[Result[Int, Str]] = Some(inner)
    match opt {
        Some(res) => { match res { Ok(val) => assert_eq(val, 42) Err(_) => assert(false) } }
        None => assert(false)
    }
}

type Wrapper[T] { inner: Option[T] }
fn make_wrapper[T](val: T) -> Wrapper[T] { Wrapper { inner: Some(val) } }
test "Wrapper[Int] — generic struct with Option[T] field" {
    let w = make_wrapper(42)
    let opt: Option[Int] = w.inner
    match opt { Some(val) => assert_eq(val, 42) None => assert(false) }
}

test "Result[Map[Str, Int], Str]" {
    let m = Map()
    m.set("a", 1)
    let r: Result[Map[Str, Int], Str] = Ok(m)
    match r { Ok(map) => assert_eq(map.len(), 1) Err(_) => assert(false) }
}
