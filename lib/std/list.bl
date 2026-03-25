@module("")

pub fn list_map[T, U](ls: List[T], f: fn(T) -> U) -> List[U] {
    let mut _r: List[U] = []
    let mut _i = 0
    while _i < ls.len() {
        _r.push(f(ls.get(_i).unwrap()))
        _i = _i + 1
    }
    _r
}

pub fn list_filter[T](ls: List[T], f: fn(T) -> Bool) -> List[T] {
    let mut _r: List[T] = []
    let mut _i = 0
    while _i < ls.len() {
        let _v = ls.get(_i).unwrap()
        if f(_v) {
            _r.push(_v)
        }
        _i = _i + 1
    }
    _r
}

pub fn list_fold[T, U](ls: List[T], init: U, f: fn(U, T) -> U) -> U {
    let mut _a = init
    let mut _i = 0
    while _i < ls.len() {
        _a = f(_a, ls.get(_i).unwrap())
        _i = _i + 1
    }
    _a
}

pub fn list_any[T](ls: List[T], f: fn(T) -> Bool) -> Bool {
    let mut _i = 0
    while _i < ls.len() {
        if f(ls.get(_i).unwrap()) {
            return true
        }
        _i = _i + 1
    }
    false
}

pub fn list_all[T](ls: List[T], f: fn(T) -> Bool) -> Bool {
    let mut _i = 0
    while _i < ls.len() {
        if !f(ls.get(_i).unwrap()) {
            return false
        }
        _i = _i + 1
    }
    true
}

pub fn list_for_each[T](ls: List[T], f: fn(T) -> Void) {
    let mut _i = 0
    while _i < ls.len() {
        f(ls.get(_i).unwrap())
        _i = _i + 1
    }
}

pub fn list_concat[T](a: List[T], b: List[T]) -> List[T] {
    let mut _r: List[T] = []
    let mut _i = 0
    while _i < a.len() {
        _r.push(a.get(_i).unwrap())
        _i = _i + 1
    }
    _i = 0
    while _i < b.len() {
        _r.push(b.get(_i).unwrap())
        _i = _i + 1
    }
    _r
}

pub fn list_slice[T](ls: List[T], start: Int, end: Int) -> List[T] {
    let mut _r: List[T] = []
    let mut _i = start
    while _i < end && _i < ls.len() {
        _r.push(ls.get(_i).unwrap())
        _i = _i + 1
    }
    _r
}
