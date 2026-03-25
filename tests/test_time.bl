test "Duration constructors" {
    let d1 = Duration.nanos(1000000)
    let d2 = Duration.ms(1)
    let d3 = Duration.seconds(1)
    let d4 = Duration.minutes(1)
    let d5 = Duration.hours(1)
    assert(d1.to_nanos() == 1000000)
    assert(d2.to_ms() == 1)
    assert(d3.to_seconds() == 1)
}

test "Duration conversions" {
    let sec = Duration.seconds(3)
    assert_eq(sec.to_ms(), 3000)
    assert_eq(sec.to_seconds(), 3)
    assert_eq(sec.to_nanos(), 3000000000)
}

test "Duration arithmetic" {
    let a = Duration.seconds(2)
    let b = Duration.seconds(3)
    assert_eq(a.add(b).to_seconds(), 5)
    assert_eq(b.sub(a).to_seconds(), 1)
    assert_eq(a.scale(5).to_seconds(), 10)
}

test "Duration is_zero" {
    let zero = Duration.nanos(0)
    let nonzero = Duration.ms(1)
    assert(zero.is_zero())
    assert(nonzero.is_zero() == false)
}

test "time.read returns Instant" {
    let now = time.read()
    assert(now.to_unix_secs() > 1000000000)
}

test "Instant to_unix_ms" {
    let now = time.read()
    assert(now.to_unix_ms() > 1000000000000)
}

test "Instant to_rfc3339" {
    let fixed = Instant.from_epoch_secs(1735689600)
    let rfc = fixed.to_rfc3339()
    assert(rfc.len() > 0)
}

test "Instant since" {
    let i1 = Instant.from_epoch_secs(100)
    let i2 = Instant.from_epoch_secs(105)
    assert_eq(i2.since(i1).to_seconds(), 5)
}

test "Instant add" {
    let base = Instant.from_epoch_secs(1000)
    let offset = Duration.seconds(500)
    assert_eq(base.add(offset).to_unix_secs(), 1500)
}

test "Instant elapsed" {
    let before = time.read()
    let el = before.elapsed()
    assert(el.to_nanos() >= 0)
}

test "Duration unit conversions" {
    assert_eq(Duration.minutes(2).to_seconds(), 120)
    assert_eq(Duration.hours(1).to_seconds(), 3600)
}
