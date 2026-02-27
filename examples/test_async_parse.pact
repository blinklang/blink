test "async parse constructs" {
    let result = async.scope {
        let x = 1
        x + 1
    }

    let handle = async.spawn(fn() {
        42
    })

    let value = handle.await

    let ch = channel.new[Int](10)

    assert(true)
}
