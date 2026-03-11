@module("")

let CH_SLASH = 47

fn find_last_slash(path: Str) -> Int {
    let mut i = path.len() - 1
    while i >= 0 {
        if path.char_at(i) == CH_SLASH {
            return i
        }
        i = i - 1
    }
    -1
}

pub fn path_join(a: Str, b: Str) -> Str {
    let la = a.len()
    if la == 0 {
        return b
    }
    if a.char_at(la - 1) == CH_SLASH {
        return a.concat(b)
    }
    a.concat("/").concat(b)
}

pub fn path_dirname(path: Str) -> Str {
    let i = find_last_slash(path)
    if i < 0 {
        return "."
    }
    if i == 0 {
        return "/"
    }
    path.substring(0, i)
}

pub fn path_basename(path: Str) -> Str {
    let i = find_last_slash(path)
    let start = i + 1
    path.substring(start, path.len() - start)
}
