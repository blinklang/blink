@module("")

@ffi("pact_str_len")
@trusted
fn str_len(s: Str) -> Int ! FFI {}

@ffi("pact_str_char_at")
@trusted
fn str_char_at(s: Str, i: Int) -> Int ! FFI {}

@ffi("pact_str_substr")
@trusted
fn str_substr(s: Str, start: Int, length: Int) -> Str ! FFI {}

@ffi("pact_str_from_char_code")
@trusted
fn str_from_char_code(code: Int) -> Str ! FFI {}

@ffi("pact_str_concat")
@trusted
fn str_concat(a: Str, b: Str) -> Str ! FFI {}

@ffi("pact_str_eq")
@trusted
fn str_eq(a: Str, b: Str) -> Int ! FFI {}

@ffi("pact_str_contains")
@trusted
fn str_contains(s: Str, needle: Str) -> Int ! FFI {}

@ffi("pact_str_starts_with")
@trusted
fn str_starts_with(s: Str, prefix: Str) -> Int ! FFI {}

@ffi("pact_str_ends_with")
@trusted
fn str_ends_with(s: Str, suffix: Str) -> Int ! FFI {}

@ffi("pact_str_slice")
@trusted
fn str_slice(s: Str, start: Int, end: Int) -> Str ! FFI {}

@ffi("pact_str_index_of")
@trusted
fn str_index_of(s: Str, needle: Str) -> Int ! FFI {}

pub fn str_trim(s: Str) -> Str {
    let slen = s.len()
    let mut start = 0
    while start < slen {
        let c = s.char_at(start)
        if c != 32 && c != 9 && c != 10 && c != 13 {
            break
        }
        start = start + 1
    }
    let mut end = slen
    while end > start {
        let c = s.char_at(end - 1)
        if c != 32 && c != 9 && c != 10 && c != 13 {
            break
        }
        end = end - 1
    }
    s.slice(start, end)
}

pub fn str_to_upper(s: Str) -> Str {
    let slen = s.len()
    let sb = StringBuilder.new()
    let mut i = 0
    while i < slen {
        let c = s.char_at(i)
        if c >= 97 && c <= 122 {
            sb.write(Char.from_code_point(c - 32))
        } else {
            sb.write(Char.from_code_point(c))
        }
        i = i + 1
    }
    sb.to_str()
}

pub fn str_to_lower(s: Str) -> Str {
    let slen = s.len()
    let sb = StringBuilder.new()
    let mut i = 0
    while i < slen {
        let c = s.char_at(i)
        if c >= 65 && c <= 90 {
            sb.write(Char.from_code_point(c + 32))
        } else {
            sb.write(Char.from_code_point(c))
        }
        i = i + 1
    }
    sb.to_str()
}

pub fn str_split(s: Str, delim: Str) -> List[Str] {
    let mut result: List[Str] = []
    let dlen = delim.len()
    if dlen == 0 {
        result.push(s)
        return result
    }
    let slen = s.len()
    let mut pos = 0
    loop {
        let idx = s.slice(pos, slen).index_of(delim)
        if idx == -1 {
            result.push(s.slice(pos, slen))
            break
        }
        result.push(s.slice(pos, pos + idx))
        pos = pos + idx + dlen
    }
    result
}

pub fn str_join(parts: List[Str], delim: Str) -> Str {
    let plen = parts.len()
    if plen == 0 {
        return ""
    }
    let sb = StringBuilder.new()
    let mut i = 0
    while i < plen {
        if i > 0 {
            sb.write(delim)
        }
        sb.write(parts.get(i).unwrap())
        i = i + 1
    }
    sb.to_str()
}

pub fn str_replace(s: Str, needle: Str, repl: Str) -> Str {
    let nlen = needle.len()
    if nlen == 0 {
        return s
    }
    let slen = s.len()
    let sb = StringBuilder.new()
    let mut pos = 0
    loop {
        let idx = s.slice(pos, slen).index_of(needle)
        if idx == -1 {
            sb.write(s.slice(pos, slen))
            break
        }
        sb.write(s.slice(pos, pos + idx))
        sb.write(repl)
        pos = pos + idx + nlen
    }
    sb.to_str()
}

pub fn str_lines(s: Str) -> List[Str] {
    let mut result: List[Str] = []
    let slen = s.len()
    if slen == 0 {
        return result
    }
    let mut pos = 0
    let mut line_start = 0
    while pos < slen {
        let c = s.char_at(pos)
        if c == 10 {
            result.push(s.slice(line_start, pos))
            pos = pos + 1
            line_start = pos
        } else if c == 13 {
            result.push(s.slice(line_start, pos))
            pos = pos + 1
            if pos < slen && s.char_at(pos) == 10 {
                pos = pos + 1
            }
            line_start = pos
        } else {
            pos = pos + 1
        }
    }
    if line_start < slen {
        result.push(s.slice(line_start, slen))
    }
    result
}

pub fn json_escape_str(s: Str) -> Str {
    let slen = s.len()
    let sb = StringBuilder.new()
    sb.write(#"""#)
    let mut i = 0
    while i < slen {
        let c = s.char_at(i)
        if c == 34 {
            sb.write(#"\""#)
        } else if c == 92 {
            sb.write("\\\\")
        } else if c == 10 {
            sb.write("\\n")
        } else if c == 9 {
            sb.write("\\t")
        } else if c == 13 {
            sb.write("\\r")
        } else {
            sb.write(Char.from_code_point(c))
        }
        i = i + 1
    }
    sb.write(#"""#)
    sb.to_str()
}
