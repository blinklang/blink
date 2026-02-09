fn main() {
    let mut counter = 0
    let increment = fn() {
        counter = counter + 1
    }
    increment()
    increment()
    io.println(int_to_string(counter))

    let mut total = 0
    let add = fn(n: Int) {
        total = total + n
    }
    add(10)
    add(20)
    add(30)
    io.println(int_to_string(total))

    io.println("PASS")
}
