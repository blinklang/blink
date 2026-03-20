type Person {
    name: Str
    age: Int
}

fn find_person(id: Int) -> Result[Person, Str] {
    if id == 1 {
        Ok(Person { name: "Alice", age: 30 })
    } else {
        Err("not found")
    }
}

fn get_person_name(id: Int) -> Result[Str, Str] {
    let r = find_person(id)
    let person = match r {
        Ok(p) => p
        Err(e) => return Err(e)
    }
    Ok(person.name)
}

test "match on Result[Struct, Str] let binding" {
    let result = get_person_name(1)
    assert_eq(result, Ok("Alice"))
}

test "match on Result[Struct, Str] error path" {
    let result = get_person_name(99)
    assert(result.is_err())
}
