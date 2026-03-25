fn main() {
    // Depth 1: literal quotes
    let json = #"{"key": "value"}"#
    io.println(json)
    assert(json == "\{\"key\": \"value\"\}", "json should contain literal quotes")

    // Depth 1: no escape processing (raw backslash)
    let path = #"C:\Users\test"#
    io.println(path)
    assert(path == "C:\\Users\\test", "path should have literal backslashes")

    // Depth 1: with interpolation
    let name = "Alice"
    let greeting = #"Hello, #{name}!"#
    io.println(greeting)
    assert(greeting == "Hello, Alice!", "greeting should interpolate name")

    // Depth 1: literal { without interpolation
    let braces = #"use { for blocks"#
    io.println(braces)
    assert(braces == "use \{ for blocks", "braces should be literal")

    // Depth 2: literal #" inside
    let meta = ##"she said #"hi"#"##
    io.println(meta)
    assert(meta == "she said #\"hi\"#", "meta should contain #quotes#")

    // Interpolation immediately after a literal quote
    let val = "world"
    let s1 = #"{"key": "#{val}"}"#
    io.println(s1)
    assert(s1 == "\{\"key\": \"world\"\}", "quoted interp should work")

    // Multiple quoted interpolations
    let a = "x"
    let b = "y"
    let s2 = #"{"a": "#{a}", "b": "#{b}"}"#
    io.println(s2)
    assert(s2 == "\{\"a\": \"x\", \"b\": \"y\"\}", "multi quoted interp should work")

    // Quote immediately before interpolation at end of string
    let s3 = #"val="#{val}""#
    io.println(s3)
    assert(s3 == "val=\"world\"", "trailing quoted interp should work")

    io.println("All extended string tests passed!")
}
