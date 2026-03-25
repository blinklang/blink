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

// Comment before struct with field comments
type Bar {
    // Comment on first field
    name: String
    // Comment on second field
    age: Int
}

// Enum with variant comments
type Color {
    // Red variant
    Red
    // Green variant
    Green
    // Blue variant
    Blue
}

// Trait with method comments
trait Drawable {
    // Draw the shape
    fn draw(self) -> Int
    // Get the area
    fn area(self) -> Int
}

// Annotation then comment then fn
@trusted
// Comment between annotation and function
fn dangerous() -> Int {
    42
}

// EOF comment
