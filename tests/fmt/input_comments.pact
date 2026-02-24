// File header comment
// This is a test file

import tokens
import ast // trailing comment on import

// Comment between imports and types
type Foo {
    x: Int // trailing on field won't survive (struct internals)
}

// Inter-declaration comment
let val = 42 // trailing on let

// Comment before function
fn add(a: Int, b: Int) -> Int {
    // Comment inside body
    let result = a + b // trailing on statement
    // Comment before return
    result
}

fn sub(a: Int, b: Int) -> Int {
    a - b
    // Comment at end of block
}

// EOF comment
