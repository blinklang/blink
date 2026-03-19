type Node {
    Leaf(val: Int)
    Branch(children: List[Node])
}

fn describe(n: Node) -> Str {
    match n {
        Node.Leaf(v) => "leaf({v})"
        Node.Branch(kids) => "branch({kids.len()})"
    }
}

fn main() ! IO {
    let mut nodes: List[Node] = []
    nodes.push(Node.Leaf(1))
    nodes.push(Node.Leaf(2))

    let mut inner: List[Node] = []
    inner.push(Node.Leaf(10))
    inner.push(Node.Leaf(20))
    nodes.push(Node.Branch(inner))

    let n0 = nodes.get(0).unwrap()
    io.println(describe(n0))

    let n1 = nodes.get(1).unwrap()
    io.println(describe(n1))

    let n2 = nodes.get(2).unwrap()
    io.println(describe(n2))

    io.println("len={nodes.len()}")

    match nodes.get(2).unwrap() {
        Node.Branch(kids) => {
            let k0 = kids.get(0).unwrap()
            io.println(describe(k0))
        }
        _ => io.println("not a branch")
    }
}

test "list of recursive enum" {
    let mut nodes: List[Node] = []
    nodes.push(Node.Leaf(1))
    nodes.push(Node.Leaf(2))

    let mut inner: List[Node] = []
    inner.push(Node.Leaf(10))
    inner.push(Node.Leaf(20))
    nodes.push(Node.Branch(inner))

    assert_eq(nodes.len(), 3)
    let n0 = nodes.get(0).unwrap()
    assert_eq(describe(n0), "leaf(1)")
    let n1 = nodes.get(1).unwrap()
    assert_eq(describe(n1), "leaf(2)")
    let n2 = nodes.get(2).unwrap()
    assert_eq(describe(n2), "branch(2)")
}
