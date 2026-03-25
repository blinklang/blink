const EMBEDDED: Str = #embed("test_embed_data.txt")

test "embedded file contains Hello" {
    assert(EMBEDDED.contains("Hello"))
}

test "embedded file contains quotes" {
    assert(EMBEDDED.contains("quotes"))
}

test "embedded file contains braces" {
    assert(EMBEDDED.contains("\{braces\}"))
}
