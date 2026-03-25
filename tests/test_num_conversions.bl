test "int_to_str" {
    assert_eq(42.to_string(), "42")
    assert_eq(0.to_string(), "0")
    let neg_one = 0 - 1
    assert_eq(neg_one.to_string(), "-1")
    let neg_999 = 0 - 999
    assert_eq(neg_999.to_string(), "-999")
}

test "float_to_str" {
    assert_eq(3.14.to_string(), "3.14")
    assert_eq(0.0.to_string(), "0")
    assert_eq(1000000.0.to_string(), "1e+06")
}

test "parse_int" {
    assert_eq("123".to_int(), 123)
    assert_eq("0".to_int(), 0)
    assert_eq("-42".to_int(), -42)
    assert_eq("".to_int(), 0)
    assert_eq("abc".to_int(), 0)
    assert_eq("12abc".to_int(), 12)
}

test "parse_float" {
    let f = "3.14".parse_float()
    assert(f > 3.13)
    assert(f < 3.15)
    assert_eq("0".parse_float(), 0.0)
    let sci = "1.5e3".parse_float()
    assert(sci > 1499.0)
    assert(sci < 1501.0)
    let neg = "-2.5".parse_float()
    assert(neg < -2.4)
    assert(neg > -2.6)
}
