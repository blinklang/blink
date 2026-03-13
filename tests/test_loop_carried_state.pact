// test_loop_carried_state.pact — Regression test for SetButNotRead false positive
// on loop-carried state variables (bug k084nv).
//
// Pattern: variable set in iteration N, read in iteration N+1.
// Must compile without W0601 warnings.

fn parse_state_machine(s: Str) -> Int {
    let slen = s.len()
    let mut i = 0
    let mut in_exp = 0
    let mut result = 0
    while i < slen {
        let ch = s.char_at(i)
        if in_exp == 1 {
            if ch >= 48 && ch <= 57 {
                result = result + (ch - 48)
            }
        } else if ch == 101 {
            in_exp = 1
        }
        i = i + 1
    }
    result
}

fn multi_flag_loop(s: Str) -> Int {
    let slen = s.len()
    let mut i = 0
    let mut flag_a = 0
    let mut flag_b = 0
    let mut count = 0
    while i < slen {
        let ch = s.char_at(i)
        if flag_a == 1 && flag_b == 1 {
            count = count + 1
        }
        if ch == 65 {
            flag_a = 1
        }
        if ch == 66 {
            flag_b = 1
        }
        i = i + 1
    }
    count
}

pub fn main() ! IO {
    let r1 = parse_state_machine("abc e5")
    io.println("state_machine: {r1}")

    let r2 = multi_flag_loop("xAyBzz")
    io.println("multi_flag: {r2}")

    io.println("PASS")
}
