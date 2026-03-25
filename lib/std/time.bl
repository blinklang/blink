@module("")

fn Duration_nanos(n: Int) -> Duration { Duration { nanos: n } }
fn Duration_ms(ms: Int) -> Duration { Duration { nanos: ms * 1000000 } }
fn Duration_seconds(s: Int) -> Duration { Duration { nanos: s * 1000000000 } }
fn Duration_minutes(m: Int) -> Duration { Duration { nanos: m * 60 * 1000000000 } }
fn Duration_hours(h: Int) -> Duration { Duration { nanos: h * 3600 * 1000000000 } }

fn Duration_to_nanos(d: Duration) -> Int { d.nanos }
fn Duration_to_ms(d: Duration) -> Int { d.nanos / 1000000 }
fn Duration_to_seconds(d: Duration) -> Int { d.nanos / 1000000000 }
fn Duration_add(a: Duration, b: Duration) -> Duration { Duration { nanos: a.nanos + b.nanos } }
fn Duration_sub(a: Duration, b: Duration) -> Duration { Duration { nanos: a.nanos - b.nanos } }
fn Duration_scale(d: Duration, factor: Int) -> Duration { Duration { nanos: d.nanos * factor } }
fn Duration_is_zero(d: Duration) -> Int { if d.nanos == 0 { 1 } else { 0 } }

fn Instant_from_epoch_secs(s: Int) -> Instant { Instant { nanos: s * 1000000000 } }
fn Instant_add(i: Instant, d: Duration) -> Instant { Instant { nanos: i.nanos + d.nanos } }
fn Instant_since(later: Instant, earlier: Instant) -> Duration { Duration { nanos: later.nanos - earlier.nanos } }
fn Instant_to_unix_secs(i: Instant) -> Int { i.nanos / 1000000000 }
fn Instant_to_unix_ms(i: Instant) -> Int { i.nanos / 1000000 }

pub type Duration {
    nanos: Int
}

pub type Instant {
    nanos: Int
}
