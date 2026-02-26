fn expand(x: Int) -> List[Int] {
    let mut result: List[Int] = []
    let mut i = 0
    while i < x {
        result.push(x)
        i = i + 1
    }
    result
}

fn main() {
    let nums: List[Int] = [1, 2, 3]
    let expanded = nums.flat_map(fn(x: Int) -> List[Int] { expand(x) }).collect()
    io.println(expanded.len())
    let mut i = 0
    while i < expanded.len() {
        io.println(expanded.unsafe_get(i))
        i = i + 1
    }
}
