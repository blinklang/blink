@module("")

pub fn int_to_str(n: Int) -> Str {
    let mut sb = StringBuilder.new()
    sb.write("{n}")
    sb.to_str()
}

pub fn float_to_str(d: Float) -> Str {
    let mut sb = StringBuilder.new()
    sb.write("{d}")
    sb.to_str()
}

pub fn parse_int(s: Str) -> Int {
    let slen = s.len()
    let mut result = 0
    let mut i = 0
    let mut negative = 0
    if slen > 0 && s.char_at(0) == 45 {
        negative = 1
        i = 1
    }
    while i < slen {
        let ch = s.char_at(i)
        if ch >= 48 && ch <= 57 {
            result = result * 10 + (ch - 48)
        } else {
            i = slen
        }
        i = i + 1
    }
    if negative == 1 {
        return 0 - result
    }
    result
}

pub fn parse_float(s: Str) -> Float {
    let slen = s.len()
    if slen == 0 {
        return 0.0
    }
    let mut i = 0
    let mut negative = 0
    if s.char_at(0) == 45 {
        negative = 1
        i = 1
    } else if s.char_at(0) == 43 {
        i = 1
    }
    let mut result = 0.0
    let mut frac_div = 1.0
    let mut in_frac = 0
    let mut in_exp = 0
    let mut exp_val = 0
    let mut exp_neg = 0
    while i < slen {
        let ch = s.char_at(i)
        if in_exp == 1 {
            if ch == 45 {
                exp_neg = 1
            } else if ch >= 48 && ch <= 57 {
                exp_val = exp_val * 10 + (ch - 48)
            }
        } else if ch == 46 {
            in_frac = 1
        } else if ch == 101 || ch == 69 {
            in_exp = 1
        } else if ch >= 48 && ch <= 57 {
            let digit = ch - 48
            if in_frac == 1 {
                frac_div = frac_div * 10.0
                result = result + digit.to_float() / frac_div
            } else {
                result = result * 10.0 + digit.to_float()
            }
        } else {
            i = slen
        }
        i = i + 1
    }
    if exp_val > 0 {
        let mut multiplier = 1.0
        let mut ei = 0
        while ei < exp_val {
            multiplier = multiplier * 10.0
            ei = ei + 1
        }
        if exp_neg == 1 {
            result = result / multiplier
        } else {
            result = result * multiplier
        }
    }
    if negative == 1 {
        return 0.0 - result
    }
    result
}
