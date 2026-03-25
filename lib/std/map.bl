@module("")

pub fn map_for_each[V](m: Map[Str, V], f: fn(Str, V) -> Void) {
    let _ks = m.keys()
    let mut _i = 0
    while _i < _ks.len() {
        let _k = _ks.get(_i).unwrap()
        f(_k, m.get(_k))
        _i = _i + 1
    }
}

pub fn map_filter[V](m: Map[Str, V], f: fn(Str, V) -> Bool) -> Map[Str, V] {
    let _r: Map[Str, V] = Map()
    let _ks = m.keys()
    let mut _i = 0
    while _i < _ks.len() {
        let _k = _ks.get(_i).unwrap()
        let _v = m.get(_k)
        if f(_k, _v) {
            _r.set(_k, _v)
        }
        _i = _i + 1
    }
    _r
}

pub fn map_fold[V, U](m: Map[Str, V], init: U, f: fn(U, Str, V) -> U) -> U {
    let _ks = m.keys()
    let mut _a = init
    let mut _i = 0
    while _i < _ks.len() {
        let _k = _ks.get(_i).unwrap()
        _a = f(_a, _k, m.get(_k))
        _i = _i + 1
    }
    _a
}

pub fn map_map_values[V, U](m: Map[Str, V], f: fn(Str, V) -> U) -> Map[Str, U] {
    let _r: Map[Str, U] = Map()
    let _ks = m.keys()
    let mut _i = 0
    while _i < _ks.len() {
        let _k = _ks.get(_i).unwrap()
        _r.set(_k, f(_k, m.get(_k)))
        _i = _i + 1
    }
    _r
}

pub fn map_merge[V](a: Map[Str, V], b: Map[Str, V]) -> Map[Str, V] {
    let _r: Map[Str, V] = Map()
    let _ks_a = a.keys()
    let mut _i = 0
    while _i < _ks_a.len() {
        let _k = _ks_a.get(_i).unwrap()
        _r.set(_k, a.get(_k))
        _i = _i + 1
    }
    let _ks_b = b.keys()
    _i = 0
    while _i < _ks_b.len() {
        let _k = _ks_b.get(_i).unwrap()
        _r.set(_k, b.get(_k))
        _i = _i + 1
    }
    _r
}
