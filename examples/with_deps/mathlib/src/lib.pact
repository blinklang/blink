// lib.pact — A small math utility library
//
// Demonstrates: pub/private visibility, library packaging

/// Add two integers.
pub fn add(a: Int, b: Int) -> Int {
    a + b
}

/// Multiply two integers.
pub fn multiply(a: Int, b: Int) -> Int {
    a * b
}

/// Square a number (uses private helper).
pub fn square(n: Int) -> Int {
    power(n, 2)
}

fn power(base: Int, exp: Int) -> Int {
    let mut result = 1
    let mut i = 0
    while i < exp {
        result = result * base
        i = i + 1
    }
    result
}
