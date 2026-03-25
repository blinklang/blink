import std.json

@derive(Serialize, Deserialize)
type Config {
    name: Str
    tags: List[Str]
    counts: List[Int]
}

test "deserialize struct with list fields" {
    let json = #"{"name":"test","tags":["a","b"],"counts":[1,2,3]}"#
    let result = Config.from_json(json)
    match result {
        Ok(c) => {
            assert_eq(c.name, "test")
            assert_eq(c.tags.len(), 2)
            assert_eq(c.tags.get(0).unwrap(), "a")
            assert_eq(c.tags.get(1).unwrap(), "b")
            assert_eq(c.counts.len(), 3)
            assert_eq(c.counts.get(0).unwrap(), 1)
            assert_eq(c.counts.get(1).unwrap(), 2)
            assert_eq(c.counts.get(2).unwrap(), 3)
        }
        Err(_) => assert(false)
    }
}

test "round-trip struct with list fields" {
    let c = Config { name: "demo", tags: ["x", "y"], counts: [10, 20] }
    let json = c.to_json()
    let result = Config.from_json(json)
    match result {
        Ok(c2) => {
            assert_eq(c2.name, "demo")
            assert_eq(c2.tags.len(), 2)
            assert_eq(c2.counts.len(), 2)
            assert_eq(c2.to_json(), json)
        }
        Err(_) => assert(false)
    }
}
