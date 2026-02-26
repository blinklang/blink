const EMBEDDED: Str = #embed("test_embed_data.txt")

fn main() {
    io.print(EMBEDDED)
    if EMBEDDED.contains("Hello") {
        io.println("PASS: contains Hello")
    } else {
        io.println("FAIL: missing Hello")
    }
    if EMBEDDED.contains("quotes") {
        io.println("PASS: contains quotes")
    } else {
        io.println("FAIL: missing quotes")
    }
    if EMBEDDED.contains("\{braces\}") {
        io.println("PASS: contains braces")
    } else {
        io.println("FAIL: missing braces")
    }
}
