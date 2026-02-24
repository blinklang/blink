import std.json

@derive(Serialize, Deserialize)
type User {
    name: Str
    age: Int
    score: Float
    active: Bool
}

fn check_roundtrip(json: Str) -> Bool {
    let result = User.from_json(json)
    match result {
        Ok(u2) => {
            if u2.name != "Alice" {
                io.println("FAIL: name -- got {u2.name}")
                return false
            }
            let json2 = u2.to_json()
            if json != json2 {
                io.println("FAIL: round-trip -- got {json2}")
                return false
            }
            return true
        }
        Err(e) => {
            io.println("FAIL: from_json error -- {e}")
            return false
        }
    }
}

fn main() {
    let mut pass = true

    let u = User { name: "Alice", age: 30, score: 9.5, active: true }
    let json = u.to_json()
    if check_roundtrip(json) == false {
        pass = false
    }

    let bad = User.from_json("not json")
    match bad {
        Ok(_) => {
            io.println("FAIL: expected error for invalid JSON")
            pass = false
        }
        Err(_) => {}
    }

    if pass {
        io.println("PASS")
    }
}
