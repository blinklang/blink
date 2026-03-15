// main.pact — Example project using a path dependency
//
// Demonstrates: import, path dependencies, using pub functions from a library
//
// Run: cd examples/with_deps/app && ../../../bin/pact run src/main.pact

import mathlib

fn main() ! IO {
    let sum = add(3, 7)
    let product = multiply(4, 5)
    let sq = square(6)

    io.println("add(3, 7) = {sum}")
    io.println("multiply(4, 5) = {product}")
    io.println("square(6) = {sq}")
}
