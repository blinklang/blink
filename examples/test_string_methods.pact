fn main() {
    let mut pass = true

    // trim
    let trimmed = "  hello world  ".trim()
    if trimmed != "hello world" {
        io.println("FAIL: trim -- got '{trimmed}'")
        pass = false
    }

    let trimmed2 = "\n  indented  \n".trim()
    if trimmed2 != "indented" {
        io.println("FAIL: trim whitespace variants -- got '{trimmed2}'")
        pass = false
    }

    // to_upper
    let upper = "hello World 123".to_upper()
    if upper != "HELLO WORLD 123" {
        io.println("FAIL: to_upper -- got '{upper}'")
        pass = false
    }

    // to_lower
    let lower = "HELLO World 123".to_lower()
    if lower != "hello world 123" {
        io.println("FAIL: to_lower -- got '{lower}'")
        pass = false
    }

    // replace
    let replaced = "foo bar foo baz".replace("foo", "qux")
    if replaced != "qux bar qux baz" {
        io.println("FAIL: replace -- got '{replaced}'")
        pass = false
    }

    let no_match = "hello".replace("xyz", "abc")
    if no_match != "hello" {
        io.println("FAIL: replace no match -- got '{no_match}'")
        pass = false
    }

    // index_of
    let idx = "hello world".index_of("world")
    if idx != 6 {
        io.println("FAIL: index_of -- got {idx}")
        pass = false
    }

    let idx_none = "hello".index_of("xyz")
    if idx_none != -1 {
        io.println("FAIL: index_of not found -- got {idx_none}")
        pass = false
    }

    // lines
    let text = "line1\nline2\nline3"
    let parts = text.lines()
    if parts.len() != 3 {
        io.println("FAIL: lines count -- got {parts.len()}")
        pass = false
    }
    if parts.unsafe_get(0) != "line1" {
        io.println("FAIL: lines[0] -- got '{parts.unsafe_get(0)}'")
        pass = false
    }
    if parts.unsafe_get(2) != "line3" {
        io.println("FAIL: lines[2] -- got '{parts.unsafe_get(2)}'")
        pass = false
    }

    // is_empty
    if "".is_empty() != true {
        io.println("FAIL: is_empty on empty string")
        pass = false
    }
    if "x".is_empty() != false {
        io.println("FAIL: is_empty on non-empty")
        pass = false
    }

    // parse_float
    let f = "3.14".parse_float()
    if f > 3.15 || f < 3.13 {
        io.println("FAIL: parse_float -- got {f}")
        pass = false
    }

    // existing methods still work
    if "hello".len() != 5 {
        io.println("FAIL: len")
        pass = false
    }
    if "hello world".contains("world") != true {
        io.println("FAIL: contains")
        pass = false
    }
    if "hello".starts_with("hel") != true {
        io.println("FAIL: starts_with")
        pass = false
    }
    if "hello".ends_with("llo") != true {
        io.println("FAIL: ends_with")
        pass = false
    }

    if pass {
        io.println("PASS")
    }
}
