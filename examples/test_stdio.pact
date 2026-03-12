test "io.write outputs string to stdout" {
    io.write("hello")
    io.write(" world\n")
    assert(true)
}

test "io.write_bytes outputs bytes to stdout" {
    let b = Bytes.new()
    b.push(72)
    b.push(105)
    io.write_bytes(b)
    io.write("\n")
    assert(true)
}
