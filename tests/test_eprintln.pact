test "eprintln and eprint do not crash" {
    io.eprintln("stderr line")
    io.eprint("stderr ")
    io.eprint("no newline")
    io.eprintln("")
    io.eprintln(42)
    io.eprintln(3.14)
    io.eprintln(true)
    assert(true)
}
