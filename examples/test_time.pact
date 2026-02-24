fn main() ! IO, Time {
    let mut tests_run = 0
    io.println("=== time type tests ===")

    // Test 1: Duration constructors
    io.println("--- test 1: Duration constructors ---")
    let d1 = Duration.nanos(1000000)
    let d2 = Duration.ms(1)
    let d3 = Duration.seconds(1)
    let d4 = Duration.minutes(1)
    let d5 = Duration.hours(1)
    tests_run = tests_run + 1
    io.println("ok: Duration constructors")

    // Test 2: Duration to_* methods
    io.println("--- test 2: Duration conversions ---")
    let sec = Duration.seconds(3)
    let ms_val = sec.to_ms()
    let ns_val = sec.to_nanos()
    let s_val = sec.to_seconds()
    if ms_val == 3000 {
        io.println("ok: to_ms = 3000")
    } else {
        io.println("FAIL: to_ms")
    }
    if s_val == 3 {
        io.println("ok: to_seconds = 3")
    } else {
        io.println("FAIL: to_seconds")
    }
    if ns_val == 3000000000 {
        io.println("ok: to_nanos = 3000000000")
    } else {
        io.println("FAIL: to_nanos")
    }
    tests_run = tests_run + 1
    io.println("ok: Duration conversions")

    // Test 3: Duration arithmetic
    io.println("--- test 3: Duration arithmetic ---")
    let a = Duration.seconds(2)
    let b = Duration.seconds(3)
    let sum = a.add(b)
    let diff = b.sub(a)
    let scaled = a.scale(5)
    if sum.to_seconds() == 5 {
        io.println("ok: add = 5s")
    } else {
        io.println("FAIL: add")
    }
    if diff.to_seconds() == 1 {
        io.println("ok: sub = 1s")
    } else {
        io.println("FAIL: sub")
    }
    if scaled.to_seconds() == 10 {
        io.println("ok: scale = 10s")
    } else {
        io.println("FAIL: scale")
    }
    tests_run = tests_run + 1
    io.println("ok: Duration arithmetic")

    // Test 4: Duration.is_zero
    io.println("--- test 4: Duration.is_zero ---")
    let zero = Duration.nanos(0)
    let nonzero = Duration.ms(1)
    if zero.is_zero() {
        io.println("ok: zero is_zero = true")
    } else {
        io.println("FAIL: zero is_zero")
    }
    if nonzero.is_zero() {
        io.println("FAIL: nonzero is_zero should be false")
    } else {
        io.println("ok: nonzero is_zero = false")
    }
    tests_run = tests_run + 1
    io.println("ok: is_zero")

    // Test 5: time.read() returns Instant
    io.println("--- test 5: time.read ---")
    let now = time.read()
    let secs = now.to_unix_secs()
    if secs > 1000000000 {
        io.println("ok: unix secs is reasonable")
    } else {
        io.println("FAIL: unix secs too small")
    }
    tests_run = tests_run + 1
    io.println("ok: time.read")

    // Test 6: Instant.to_unix_ms
    io.println("--- test 6: Instant.to_unix_ms ---")
    let now2 = time.read()
    let ms = now2.to_unix_ms()
    if ms > 1000000000000 {
        io.println("ok: unix ms is reasonable")
    } else {
        io.println("FAIL: unix ms too small")
    }
    tests_run = tests_run + 1
    io.println("ok: Instant.to_unix_ms")

    // Test 7: Instant.to_rfc3339
    io.println("--- test 7: Instant.to_rfc3339 ---")
    let fixed = Instant.from_epoch_secs(1735689600)
    let rfc = fixed.to_rfc3339()
    io.println(rfc)
    tests_run = tests_run + 1
    io.println("ok: to_rfc3339")

    // Test 8: Instant.since
    io.println("--- test 8: Instant.since ---")
    let i1 = Instant.from_epoch_secs(100)
    let i2 = Instant.from_epoch_secs(105)
    let between = i2.since(i1)
    if between.to_seconds() == 5 {
        io.println("ok: since = 5s")
    } else {
        io.println("FAIL: since")
    }
    tests_run = tests_run + 1
    io.println("ok: Instant.since")

    // Test 9: Instant.add
    io.println("--- test 9: Instant.add ---")
    let base = Instant.from_epoch_secs(1000)
    let offset = Duration.seconds(500)
    let future = base.add(offset)
    if future.to_unix_secs() == 1500 {
        io.println("ok: add = 1500s")
    } else {
        io.println("FAIL: add")
    }
    tests_run = tests_run + 1
    io.println("ok: Instant.add")

    // Test 10: Instant.elapsed (just check it doesn't crash and returns non-negative)
    io.println("--- test 10: Instant.elapsed ---")
    let before = time.read()
    let el = before.elapsed()
    let el_ns = el.to_nanos()
    if el_ns >= 0 {
        io.println("ok: elapsed >= 0")
    } else {
        io.println("FAIL: elapsed negative")
    }
    tests_run = tests_run + 1
    io.println("ok: Instant.elapsed")

    // Test 11: Duration unit conversions
    io.println("--- test 11: Duration unit conversions ---")
    let mins = Duration.minutes(2)
    if mins.to_seconds() == 120 {
        io.println("ok: 2 minutes = 120 seconds")
    } else {
        io.println("FAIL: minutes to seconds")
    }
    let hrs = Duration.hours(1)
    if hrs.to_seconds() == 3600 {
        io.println("ok: 1 hour = 3600 seconds")
    } else {
        io.println("FAIL: hours to seconds")
    }
    tests_run = tests_run + 1
    io.println("ok: Duration unit conversions")

    io.println("--- results ---")
    io.println(tests_run)
    io.println("PASS")
}
